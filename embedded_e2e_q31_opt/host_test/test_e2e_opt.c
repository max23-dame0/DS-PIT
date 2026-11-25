/* Host verification & accuracy gate for E2E-02 (f32-algo-opt & q31-full-opt) */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "dspit_opt.h"

#ifndef VARIANT_NAME
#define VARIANT_NAME DSPIT_VARIANT_NAME
#endif

typedef struct {
    const double *p25;
    const double *a25[3];
    const double *sp_mag;
    const double *ap_mag[3];
    const double *obv;
    const double *psp;
    const double *logL_pre;
    const double *tau_eff;
    const double *logL_post;
    uint32_t nb;
    uint32_t k_dim;
    uint32_t n_x25;

    double max_err_x25;
    double max_rel_spec;
    double max_err_obv;
    double max_err_psp;
    double max_err_logL_pre;
    double max_err_tau;
    double max_err_logL_post;
} trace_check_t;

static void on_x25_cb(uint32_t ch, uint32_t idx, double val, void *user)
{
    trace_check_t *tc = (trace_check_t *)user;
    if (idx >= tc->n_x25) { return; }
    const double ref = (ch == 0u) ? tc->p25[idx] : tc->a25[ch - 1u][idx];
    const double err = fabs(val - ref);
    if (err > tc->max_err_x25) { tc->max_err_x25 = err; }
}

static void on_win_cb(uint32_t w,
                      const double *sp_mag,
                      const double ap_mag[3][E2E_NB],
                      const double *obv,
                      const double *psp,
                      const double *logL_pre,
                      double tau,
                      const double *logL_post,
                      void *user)
{
    trace_check_t *tc = (trace_check_t *)user;
    const uint32_t nb = tc->nb;
    const uint32_t K = tc->k_dim;

    for (uint32_t b = 0u; b < nb; b++) {
        const double ref_s = tc->sp_mag[w * nb + b];
        const double es = fabs(sp_mag[b] - ref_s) / (fabs(ref_s) + 1.0);
        if (es > tc->max_rel_spec) { tc->max_rel_spec = es; }
        for (uint8_t j = 0u; j < 3u; j++) {
            const double ref_a = tc->ap_mag[j][w * nb + b];
            const double ea = fabs(ap_mag[j][b] - ref_a) / (fabs(ref_a) + 1.0);
            if (ea > tc->max_rel_spec) { tc->max_rel_spec = ea; }
        }
        const double eo = fabs(obv[b] - tc->obv[w * nb + b]);
        if (eo > tc->max_err_obv) { tc->max_err_obv = eo; }
    }
    for (uint32_t j = 0u; j < K; j++) {
        const double ep = fabs(psp[j] - tc->psp[w * K + j]);
        if (ep > tc->max_err_psp) { tc->max_err_psp = ep; }
        const double el1 = fabs(logL_pre[j] - tc->logL_pre[w * K + j]);
        if (el1 > tc->max_err_logL_pre) { tc->max_err_logL_pre = el1; }
        const double el2 = fabs(logL_post[j] - tc->logL_post[w * K + j]);
        if (el2 > tc->max_err_logL_post) { tc->max_err_logL_post = el2; }
    }
    const double et = fabs(tau - tc->tau_eff[w]);
    if (et > tc->max_err_tau) { tc->max_err_tau = et; }
}

static int run_record(const char *tag, uint8_t banded,
                      int *tot_eq_f32, int *tot_eq_c2, int *tot_wins,
                      double *sum_mae_opt, double *sum_mae_c2)
{
    char raw_path[256], tr_path[256], f32_path[256];
    snprintf(raw_path, sizeof(raw_path), "../../embedded_e2e_20261124/golden/%s_raw_f32.bin", tag);
    snprintf(tr_path,  sizeof(tr_path),  "../../embedded_e2e_20261124/golden/%s_trace_f64.bin", tag);
    snprintf(f32_path, sizeof(f32_path), "../../embedded_e2e_20261124/results/host_f32_%s.bin", tag);

    FILE *fr = fopen(raw_path, "rb");
    FILE *ft = fopen(tr_path, "rb");
    FILE *ff = fopen(f32_path, "rb");
    if (!fr || !ft || !ff) {
        fprintf(stderr, "Failed to open inputs for %s\n", tag);
        if (fr) { fclose(fr); }
        if (ft) { fclose(ft); }
        if (ff) { fclose(ff); }
        return -1;
    }

    uint32_t hdr_r[6], hdr_t[6];
    if (fread(hdr_r, sizeof(uint32_t), 6, fr) != 6 ||
        fread(hdr_t, sizeof(uint32_t), 6, ft) != 6) {
        fprintf(stderr, "Header read error for %s\n", tag);
        fclose(fr); fclose(ft); fclose(ff);
        return -1;
    }
    const uint32_t ds_id  = hdr_r[1];
    const uint32_t n_ppg  = hdr_r[2];
    const uint32_t n_acc  = hdr_r[3];
    const uint32_t n_win  = hdr_t[2];
    const uint32_t n_eval = hdr_t[3];
    const uint32_t nb     = hdr_t[4];
    const uint32_t K      = hdr_t[5];
    const uint32_t n_x25  = 13000u;

    float *ppg_f32 = (float *)malloc(sizeof(float) * n_ppg);
    float *ax_f32  = (float *)malloc(sizeof(float) * n_acc);
    float *ay_f32  = (float *)malloc(sizeof(float) * n_acc);
    float *az_f32  = (float *)malloc(sizeof(float) * n_acc);
    if (fread(ppg_f32, sizeof(float), n_ppg, fr) != n_ppg ||
        fread(ax_f32,  sizeof(float), n_acc, fr) != n_acc ||
        fread(ay_f32,  sizeof(float), n_acc, fr) != n_acc ||
        fread(az_f32,  sizeof(float), n_acc, fr) != n_acc) {
        fprintf(stderr, "Short raw read for %s\n", tag);
        return -1;
    }
    fclose(fr);

    const size_t n_dbl = (size_t)4 * n_x25 +
                         (size_t)5 * n_win * nb +
                         (size_t)4 * n_win * K +
                         (size_t)n_win +
                         (size_t)6 * n_eval;
    double *tr_buf = (double *)malloc(sizeof(double) * n_dbl);
    if (fread(tr_buf, sizeof(double), n_dbl, ft) != n_dbl) {
        fprintf(stderr, "Short trace read for %s\n", tag);
        return -1;
    }
    fclose(ft);

    float *e2e01_est = (float *)malloc(sizeof(float) * n_eval);
    float *e2e01_es  = (float *)malloc(sizeof(float) * n_eval);
    if (fread(e2e01_est, sizeof(float), n_eval, ff) != n_eval ||
        fread(e2e01_es,  sizeof(float), n_eval, ff) != n_eval) {
        fprintf(stderr, "Short e2e01 bin read for %s\n", tag);
        return -1;
    }
    fclose(ff);

    size_t off = 0;
    trace_check_t tc;
    memset(&tc, 0, sizeof(tc));
    tc.nb = nb; tc.k_dim = K; tc.n_x25 = n_x25;
    tc.p25       = tr_buf + off; off += n_x25;
    tc.a25[0]    = tr_buf + off; off += n_x25;
    tc.a25[1]    = tr_buf + off; off += n_x25;
    tc.a25[2]    = tr_buf + off; off += n_x25;
    tc.sp_mag    = tr_buf + off; off += n_win * nb;
    tc.ap_mag[0] = tr_buf + off; off += n_win * nb;
    tc.ap_mag[1] = tr_buf + off; off += n_win * nb;
    tc.ap_mag[2] = tr_buf + off; off += n_win * nb;
    tc.obv       = tr_buf + off; off += n_win * nb;
    tc.psp       = tr_buf + off; off += n_win * K;
    off += n_win * K; /* skip lvec */
    tc.logL_pre  = tr_buf + off; off += n_win * K;
    tc.tau_eff   = tr_buf + off; off += n_win;
    tc.logL_post = tr_buf + off; off += n_win * K;
    off += 2u * n_eval; /* skip est_b, es_b */
    const double *est_c2 = tr_buf + off; off += n_eval;
    const double *es_c2  = tr_buf + off; off += n_eval;
    const double *gt     = tr_buf + off; off += n_eval;
    const double *msk    = tr_buf + off; off += n_eval;

    static dspit_e2e_t st;
    dspit_init(&st, (uint8_t)ds_id, banded);

    dspit_trace_cb_t tcb = { on_x25_cb, on_win_cb, &tc };

    const uint32_t blk_ppg = (ds_id == E2E_MODE_DALIA) ? E2E_DALIA_BLK : E2E_WESAD_BLK;
    const uint32_t blk_acc = (ds_id == E2E_MODE_DALIA) ? E2E_DALIA_BLK : E2E_WESAD_ABLK;
    const uint32_t n_blocks = n_ppg / blk_ppg;

    float est_out[300], es_out[300], tau_out[300];
    memset(est_out, 0, sizeof(est_out));
    memset(es_out,  0, sizeof(es_out));
    memset(tau_out, 0, sizeof(tau_out));

    for (uint32_t b = 0u; b < n_blocks; b++) {
        dspit_block_out_t bout;
        dspit_push_block(&st,
                         ppg_f32 + b * blk_ppg, blk_ppg,
                         ax_f32 + b * blk_acc, ay_f32 + b * blk_acc, az_f32 + b * blk_acc, blk_acc,
                         &bout, NULL, &tcb);
        if (bout.win_ran && (st.win_idx - 1u) < n_win) {
            tau_out[st.win_idx - 1u] = bout.tau;
        }
        if (bout.has_est && bout.est_index < n_eval) {
            est_out[bout.est_index] = bout.est_bpm;
        }
        if (bout.has_es && bout.es_index < n_eval) {
            es_out[bout.es_index] = bout.es_bpm;
        }
    }

    int eq_es_f32 = 0, eq_est_c2 = 0, eq_es_c2 = 0;
    double mae_c = 0.0, mae_c2 = 0.0, max_d_c2 = 0.0;
    int m_cnt = 0;
    for (uint32_t i = 0u; i < n_eval; i++) {
        if (es_out[i] == e2e01_es[i])         { eq_es_f32++; }
        if ((double)est_out[i] == est_c2[i])  { eq_est_c2++; }
        if ((double)es_out[i]  == es_c2[i])   { eq_es_c2++; }
        const double dc = fabs((double)es_out[i] - es_c2[i]);
        if (dc > max_d_c2) { max_d_c2 = dc; }
        if (msk[i] > 0.5) {
            mae_c  += fabs(gt[i] - (double)es_out[i]);
            mae_c2 += fabs(gt[i] - es_c2[i]);
            m_cnt++;
        }
    }
    mae_c /= m_cnt;
    mae_c2 /= m_cnt;

    if (banded) {
        *tot_eq_f32 += eq_es_f32;
        *tot_eq_c2  += eq_es_c2;
        *tot_wins   += (int)n_eval;
        *sum_mae_opt += mae_c;
        *sum_mae_c2  += mae_c2;

        char out_path[256];
        snprintf(out_path, sizeof(out_path), "../results/host_%s_%s.bin", VARIANT_NAME, tag);
        FILE *fo = fopen(out_path, "wb");
        if (fo) {
            fwrite(est_out, sizeof(float), n_eval, fo);
            fwrite(es_out,  sizeof(float), n_eval, fo);
            fwrite(tau_out, sizeof(float), n_win,  fo);
            fclose(fo);
        }
    }

    printf("[%s | %-3s | %s] S1_x25=%.2e S2_rel=%.2e S3_obv=%.2e S3_logL=%.2e S4_tau=%.2e | vsE2E01=%d/254 vsF64=%d/254 maxd=%.2f MAE=%.4f vs %.4f\n",
           VARIANT_NAME, tag, banded ? "band" : "dens",
           tc.max_err_x25, tc.max_rel_spec, tc.max_err_obv, tc.max_err_logL_pre, tc.max_err_tau,
           eq_es_f32, eq_es_c2, max_d_c2, mae_c, mae_c2);

    free(e2e01_est); free(e2e01_es);
    free(ppg_f32); free(ax_f32); free(ay_f32); free(az_f32);
    free(tr_buf);
    return 0;
}

int main(void)
{
    const char *tags[5] = { "s1", "s2", "s3", "ws1", "ws2" };
    int tot_f32 = 0, tot_c2 = 0, tot_w = 0;
    double sum_mae_opt = 0.0, sum_mae_c2 = 0.0;

    printf("=== E2E-02 Host Verification: %s (sizeof algo=%u B) ===\n",
           VARIANT_NAME, (unsigned)sizeof(dspit_e2e_t));
    for (int i = 0; i < 5; i++) {
        if (run_record(tags[i], 1u, &tot_f32, &tot_c2, &tot_w, &sum_mae_opt, &sum_mae_c2) != 0) {
            return 2;
        }
    }
    /* Check dense vs banded equality on s1 */
    int d_f32 = 0, d_c2 = 0, d_w = 0;
    double dm1 = 0.0, dm2 = 0.0;
    if (run_record("s1", 0u, &d_f32, &d_c2, &d_w, &dm1, &dm2) != 0) { return 2; }

    const double pct_f32 = 100.0 * tot_f32 / tot_w;
    const double pct_c2  = 100.0 * tot_c2  / tot_w;
    const double mean_opt = sum_mae_opt / 5.0;
    const double mean_c2  = sum_mae_c2  / 5.0;
    printf("SUMMARY [%s]: vsE2E01=%d/%d (%.2f%%) | vsMATLAB-f64=%d/%d (%.2f%%) | 5-rec MAE=%.4f vs %.4f (diff=%+.4f)\n",
           VARIANT_NAME, tot_f32, tot_w, pct_f32, tot_c2, tot_w, pct_c2,
           mean_opt, mean_c2, mean_opt - mean_c2);

    const int gate_ok = (pct_c2 >= 95.0) && (mean_opt <= 7.5312 + 0.15);
    printf("ACCURACY GATE: %s\n", gate_ok ? "PASS" : "FAIL");
    return gate_ok ? 0 : 1;
}
