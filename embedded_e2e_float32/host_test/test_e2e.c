/* Host verification harness for DS-PIT E2E pipeline (REAL_DOUBLE + float32) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "../src/dspit_e2e.h"

typedef struct {
    const double *p25;
    const double *a25[3];
    const double *sp_mag;
    const double *ap_mag[3];
    const double *obv;
    const double *psp;
    const double *lvec;
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

static void on_x25_cb(uint32_t ch, uint32_t idx, real_t val, void *user)
{
    trace_check_t *tc = (trace_check_t *)user;
    if (idx >= tc->n_x25) { return; }
    const double ref = (ch == 0u) ? tc->p25[idx] : tc->a25[ch - 1u][idx];
    const double err = fabs((double)val - ref);
    if (err > tc->max_err_x25) { tc->max_err_x25 = err; }
}

static void on_win_cb(uint32_t w,
                      const real_t *sp_mag,
                      const real_t ap_mag[3][E2E_NB],
                      const real_t *obv,
                      const real_t *psp,
                      const real_t *lvec,
                      const real_t *logL_pre,
                      real_t tau,
                      const real_t *logL_post,
                      void *user)
{
    (void)lvec;
    trace_check_t *tc = (trace_check_t *)user;
    const uint32_t nb = tc->nb;
    const uint32_t K = tc->k_dim;

    for (uint32_t b = 0u; b < nb; b++) {
        const double ref_s = tc->sp_mag[w * nb + b];
        const double es = fabs((double)sp_mag[b] - ref_s) / (fabs(ref_s) + 1.0);
        if (es > tc->max_rel_spec) { tc->max_rel_spec = es; }
        for (uint8_t j = 0u; j < 3u; j++) {
            const double ref_a = tc->ap_mag[j][w * nb + b];
            const double ea = fabs((double)ap_mag[j][b] - ref_a) / (fabs(ref_a) + 1.0);
            if (ea > tc->max_rel_spec) { tc->max_rel_spec = ea; }
        }
        const double eo = fabs((double)obv[b] - tc->obv[w * nb + b]);
        if (eo > tc->max_err_obv) { tc->max_err_obv = eo; }
    }
    for (uint32_t j = 0u; j < K; j++) {
        const double ep = fabs((double)psp[j] - tc->psp[w * K + j]);
        if (ep > tc->max_err_psp) { tc->max_err_psp = ep; }
        const double el1 = fabs((double)logL_pre[j] - tc->logL_pre[w * K + j]);
        if (el1 > tc->max_err_logL_pre) { tc->max_err_logL_pre = el1; }
        const double el2 = fabs((double)logL_post[j] - tc->logL_post[w * K + j]);
        if (el2 > tc->max_err_logL_post) { tc->max_err_logL_post = el2; }
    }
    const double et = fabs((double)tau - tc->tau_eff[w]);
    if (et > tc->max_err_tau) { tc->max_err_tau = et; }
}

#ifdef REAL_DOUBLE
static int verify_isolated_modules(const char *tag, const trace_check_t *tc,
                                   const double *est_b, const double *es_b,
                                   uint32_t n_win, uint32_t n_eval)
{
    const uint32_t nb = tc->nb;
    const uint32_t K = tc->k_dim;
    int ok = 1;

    /* S2 isolated: feed exact golden x25 */
    static real_t wbuf[4][256];
    static spec_state_t sp_st;
    spec_init(&sp_st);
    double s2_max_rel = 0.0;
    for (uint32_t w = 0u; w < n_win; w++) {
        for (uint32_t k = 0u; k < E2E_WS; k++) {
            const uint32_t idx = w * E2E_HS + k;
            wbuf[0][k] = tc->p25[idx];
            wbuf[1][k] = tc->a25[0][idx];
            wbuf[2][k] = tc->a25[1][idx];
            wbuf[3][k] = tc->a25[2][idx];
        }
        real_t sp_out[E2E_NB], ap_out[3][E2E_NB];
        spec_compute_window(&sp_st, wbuf, 0u, sp_out, ap_out);
        for (uint32_t b = 0u; b < nb; b++) {
            const double r0 = tc->sp_mag[w * nb + b];
            const double e0 = fabs(sp_out[b] - r0) / (fabs(r0) + 1.0);
            if (e0 > s2_max_rel) { s2_max_rel = e0; }
            for (int j = 0; j < 3; j++) {
                const double rj = tc->ap_mag[j][w * nb + b];
                const double ej = fabs(ap_out[j][b] - rj) / (fabs(rj) + 1.0);
                if (ej > s2_max_rel) { s2_max_rel = ej; }
            }
        }
    }
    if (s2_max_rel > 1e-12) { ok = 0; }

    /* S3 isolated: feed exact golden sp_mag / ap_mag */
    static enhance_state_t enh_st;
    enhance_init(&enh_st);
    double s3_max_obv = 0.0, s3_max_logL = 0.0;
    uint32_t s3_step_jumps = 0u;
    for (uint32_t w = 0u; w < n_win; w++) {
        real_t sp_in[E2E_NB], ap_in[3][E2E_NB];
        real_t obv_out[E2E_NB], psp_out[E2E_K], lv_out[E2E_K], logL_out[E2E_K];
        for (uint32_t b = 0u; b < nb; b++) {
            sp_in[b] = tc->sp_mag[w * nb + b];
            for (int j = 0; j < 3; j++) { ap_in[j][b] = tc->ap_mag[j][w * nb + b]; }
        }
        enhance_window(&enh_st, sp_in, ap_in, obv_out, psp_out, lv_out, logL_out);
        int win_jump = 0;
        for (uint32_t b = 0u; b < nb; b++) {
            const double eo = fabs(obv_out[b] - tc->obv[w * nb + b]);
            if (eo > 1e-9) { win_jump = 1; }
            if (eo > s3_max_obv) { s3_max_obv = eo; }
        }
        if (win_jump) { s3_step_jumps++; }
        for (uint32_t j = 0u; j < K; j++) {
            const double el = fabs(logL_out[j] - tc->logL_pre[w * K + j]);
            if (el > s3_max_logL) { s3_max_logL = el; }
        }
    }
    if (s3_step_jumps == 0u && (s3_max_obv > 1e-11 || s3_max_logL > 1e-8)) { ok = 0; }

    /* S4 isolated: feed exact golden obv & logL_pre + golden est */
    static lbp_state_t lbp_st;
    lbp_init(&lbp_st);
    double s4_max_tau = 0.0, s4_max_logL = 0.0;
    for (uint32_t w = 0u; w < n_win; w++) {
        real_t obv_in[E2E_NB], logL_in[E2E_K];
        for (uint32_t b = 0u; b < nb; b++) { obv_in[b] = tc->obv[w * nb + b]; }
        for (uint32_t j = 0u; j < K; j++)  { logL_in[j] = tc->logL_pre[w * K + j]; }
        const real_t tau = lbp_update_tau(&lbp_st, obv_in, logL_in);
        const double et = fabs(tau - tc->tau_eff[w]);
        if (et > s4_max_tau) { s4_max_tau = et; }
        for (uint32_t j = 0u; j < K; j++) {
            const double el = fabs(logL_in[j] - tc->logL_post[w * K + j]);
            if (el > s4_max_logL) { s4_max_logL = el; }
        }
        if (w >= 2u && (w - 2u) < n_eval) {
            lbp_push_est(&lbp_st, est_b[w - 2u]);
        }
    }
    if (s4_max_tau > 1e-12 || s4_max_logL > 1e-12) { ok = 0; }

    /* S5+S6 isolated: feed exact golden logL_post into dense decode -> smooth */
    static decode_state_t dec_st;
    static smooth_state_t sm_st;
    decode_init(&dec_st, 0u);
    smooth_init(&sm_st);
    int s5_ok = 0, s6_ok = 0;
    uint32_t est_idx = 0u, es_idx = 0u;
    for (uint32_t w = 0u; w < n_win; w++) {
        real_t rb = 0.0, es = 0.0;
        if (decode_step(&dec_st, tc->logL_post + w * K, &rb)) {
            if (est_idx < n_eval && rb == est_b[est_idx]) { s5_ok++; }
            est_idx++;
            if (smooth_push(&sm_st, rb, &es)) {
                if (es_idx < n_eval && es == es_b[es_idx]) { s6_ok++; }
                es_idx++;
            }
        }
    }
    if (s5_ok != (int)n_eval || s6_ok != (int)n_eval) { ok = 0; }

    printf("   [Isolated f64] %s: S1_x25=%.2e S2_rel=%.2e S3_jumps=%u(obv=%.2e,logL=%.2e) S4_tau=%.2e S4_logL=%.2e S5=%d/254 S6=%d/254 -> %s\n",
           tag, tc->max_err_x25, s2_max_rel, s3_step_jumps, s3_max_obv, s3_max_logL,
           s4_max_tau, s4_max_logL, s5_ok, s6_ok, ok ? "PASS" : "FAIL");
    return ok;
}
#endif

static int run_record(const char *tag, uint8_t banded, int *all_ok)
{
    char raw_path[256], tr_path[256];
    snprintf(raw_path, sizeof(raw_path), "../golden/%s_raw_f32.bin", tag);
    snprintf(tr_path, sizeof(tr_path), "../golden/%s_trace_f64.bin", tag);

    FILE *fr = fopen(raw_path, "rb");
    FILE *ft = fopen(tr_path, "rb");
    if (!fr || !ft) {
        fprintf(stderr, "Failed to open golden files for %s\n", tag);
        if (fr) fclose(fr);
        if (ft) fclose(ft);
        return -1;
    }

    uint32_t hdr_r[6], hdr_t[6];
    if (fread(hdr_r, sizeof(uint32_t), 6, fr) != 6 ||
        fread(hdr_t, sizeof(uint32_t), 6, ft) != 6) {
        fprintf(stderr, "Header read error for %s\n", tag);
        fclose(fr); fclose(ft);
        return -1;
    }
    if (hdr_r[0] != 0x45324552u || hdr_t[0] != 0x45324554u) {
        fprintf(stderr, "Bad magic for %s\n", tag);
        fclose(fr); fclose(ft);
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
    size_t got = fread(tr_buf, sizeof(double), n_dbl, ft);
    fclose(ft);
    if (got != n_dbl) {
        fprintf(stderr, "Short trace read for %s: %zu vs %zu\n", tag, got, n_dbl);
        return -1;
    }

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
    tc.lvec      = tr_buf + off; off += n_win * K;
    tc.logL_pre  = tr_buf + off; off += n_win * K;
    tc.tau_eff   = tr_buf + off; off += n_win;
    tc.logL_post = tr_buf + off; off += n_win * K;
    const double *est_b  = tr_buf + off; off += n_eval;
    const double *es_b   = tr_buf + off; off += n_eval;
    const double *est_c2 = tr_buf + off; off += n_eval;
    const double *es_c2  = tr_buf + off; off += n_eval;
    const double *gt     = tr_buf + off; off += n_eval;
    const double *msk    = tr_buf + off; off += n_eval;

    static dspit_e2e_t st;
    dspit_init(&st, (uint8_t)ds_id, banded);

    dspit_trace_cb_t tcb;
    tcb.on_x25 = on_x25_cb;
    tcb.on_window = on_win_cb;
    tcb.user = &tc;

    const uint32_t blk_ppg = (ds_id == E2E_MODE_DALIA) ? E2E_DALIA_BLK : E2E_WESAD_BLK;
    const uint32_t blk_acc = (ds_id == E2E_MODE_DALIA) ? E2E_DALIA_BLK : E2E_WESAD_ABLK;
    const uint32_t n_blocks = n_ppg / blk_ppg;

    real_t *p_blk  = (real_t *)malloc(sizeof(real_t) * blk_ppg);
    real_t *ax_blk = (real_t *)malloc(sizeof(real_t) * blk_acc);
    real_t *ay_blk = (real_t *)malloc(sizeof(real_t) * blk_acc);
    real_t *az_blk = (real_t *)malloc(sizeof(real_t) * blk_acc);

    float est_out[300], es_out[300], tau_out[300];
    memset(est_out, 0, sizeof(est_out));
    memset(es_out,  0, sizeof(es_out));
    memset(tau_out, 0, sizeof(tau_out));
    uint32_t n_est_got = 0, n_es_got = 0;

    for (uint32_t b = 0u; b < n_blocks; b++) {
        for (uint32_t i = 0u; i < blk_ppg; i++) {
            p_blk[i] = (real_t)ppg_f32[b * blk_ppg + i];
        }
        for (uint32_t i = 0u; i < blk_acc; i++) {
            ax_blk[i] = (real_t)ax_f32[b * blk_acc + i];
            ay_blk[i] = (real_t)ay_f32[b * blk_acc + i];
            az_blk[i] = (real_t)az_f32[b * blk_acc + i];
        }
        dspit_block_out_t bout;
        dspit_push_block(&st, p_blk, blk_ppg, ax_blk, ay_blk, az_blk, blk_acc, &bout, NULL, &tcb);
        if (bout.win_ran && (st.win_idx - 1u) < n_win) {
            tau_out[st.win_idx - 1u] = (float)bout.tau;
        }
        if (bout.has_est && bout.est_index < n_eval) {
            est_out[bout.est_index] = (float)bout.est_bpm;
            if (bout.est_index >= n_est_got) { n_est_got = bout.est_index + 1u; }
        }
        if (bout.has_es && bout.es_index < n_eval) {
            es_out[bout.es_index] = (float)bout.es_bpm;
            if (bout.es_index >= n_es_got) { n_es_got = bout.es_index + 1u; }
        }
    }

    int eq_est_b = 0, eq_es_b = 0, eq_est_c2 = 0, eq_es_c2 = 0;
    double max_d_es_b = 0.0, max_d_es_c2 = 0.0;
    double mae_c = 0.0, mae_b = 0.0, mae_c2 = 0.0;
    int m_cnt = 0;
    for (uint32_t i = 0u; i < n_eval; i++) {
        if ((double)est_out[i] == est_b[i])  { eq_est_b++; }
        if ((double)es_out[i]  == es_b[i])   { eq_es_b++; }
        if ((double)est_out[i] == est_c2[i]) { eq_est_c2++; }
        if ((double)es_out[i]  == es_c2[i])  { eq_es_c2++; }
        const double db = fabs((double)es_out[i] - es_b[i]);
        const double dc = fabs((double)es_out[i] - es_c2[i]);
        if (db > max_d_es_b)  { max_d_es_b = db; }
        if (dc > max_d_es_c2) { max_d_es_c2 = dc; }
        if (msk[i] > 0.5) {
            mae_c  += fabs(gt[i] - (double)es_out[i]);
            mae_b  += fabs(gt[i] - es_b[i]);
            mae_c2 += fabs(gt[i] - es_c2[i]);
            m_cnt++;
        }
    }
    mae_c /= m_cnt; mae_b /= m_cnt; mae_c2 /= m_cnt;

    printf("[%s | %s] got=(%u,%u) | S1_x25=%.2e S2_rel=%.2e S3_obv=%.2e S3_psp=%.2e S3_logL=%.2e S4_tau=%.2e S4_logL=%.2e\n",
           tag, banded ? "banded" : "dense ", n_est_got, n_es_got,
           tc.max_err_x25, tc.max_rel_spec, tc.max_err_obv, tc.max_err_psp,
           tc.max_err_logL_pre, tc.max_err_tau, tc.max_err_logL_post);
    printf("   vs CheckB(SOS-f64): est=%d/254 es=%d/254 max|d_es|=%.3f MAE=%.4f vs %.4f (|diff|=%.4f)\n",
           eq_est_b, eq_es_b, max_d_es_b, mae_c, mae_b, fabs(mae_c - mae_b));
    printf("   vs CheckC(cache2):  est=%d/254 es=%d/254 max|d_es|=%.3f MAE=%.4f vs %.4f (|diff|=%.4f)\n",
           eq_est_c2, eq_es_c2, max_d_es_c2, mae_c, mae_c2, fabs(mae_c - mae_c2));

#ifdef REAL_DOUBLE
    if (!banded) {
        if (!verify_isolated_modules(tag, &tc, est_b, es_b, n_win, n_eval)) {
            *all_ok = 0;
        }
        if (tc.max_err_x25 > 1e-10) { *all_ok = 0; }
    }
#else
    if (banded) {
        char out_path[256];
        snprintf(out_path, sizeof(out_path), "../results/host_f32_%s.bin", tag);
        FILE *fo = fopen(out_path, "wb");
        if (fo) {
            fwrite(est_out, sizeof(float), n_eval, fo);
            fwrite(es_out,  sizeof(float), n_eval, fo);
            fwrite(tau_out, sizeof(float), n_win,  fo);
            fclose(fo);
        }
    }
    if (n_est_got != n_eval || n_es_got != n_eval) { *all_ok = 0; }
#endif

    free(p_blk); free(ax_blk); free(ay_blk); free(az_blk);
    free(ppg_f32); free(ax_f32); free(ay_f32); free(az_f32);
    free(tr_buf);
    return 0;
}

int main(void)
{
    const char *tags[5] = { "s1", "s2", "s3", "ws1", "ws2" };
    int all_ok = 1;
#ifdef REAL_DOUBLE
    printf("=== Host Verification: REAL_DOUBLE (E2E + Isolated S1..S6) ===\n");
    for (int i = 0; i < 5; i++) {
        if (run_record(tags[i], 0u, &all_ok) != 0) { return 2; }
    }
#else
    printf("=== Host Verification: float32 (dense + banded W=13) ===\n");
    for (int i = 0; i < 5; i++) {
        if (run_record(tags[i], 0u, &all_ok) != 0) { return 2; }
        if (run_record(tags[i], 1u, &all_ok) != 0) { return 2; }
    }
#endif
    printf("OVERALL STATUS: %s\n", all_ok ? "PASS" : "FAIL");
    return all_ok ? 0 : 1;
}
