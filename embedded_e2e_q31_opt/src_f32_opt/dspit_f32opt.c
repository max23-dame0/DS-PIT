/* Top-level streaming DS-PIT E2E coordinator (f32-algo-opt) */
#include <string.h>
#include "dspit_opt.h"

#define HOOK_BEGIN(hooks, st_id) \
    do { if ((hooks) && (hooks)->on_stage_begin) { (hooks)->on_stage_begin((st_id), (hooks)->user); } } while (0)
#define HOOK_END(hooks, st_id) \
    do { if ((hooks) && (hooks)->on_stage_end) { (hooks)->on_stage_end((st_id), (hooks)->user); } } while (0)

void dspit_init(dspit_e2e_t *st, uint8_t mode, uint8_t banded)
{
    memset(st, 0, sizeof(*st));
    st->mode = mode;
    st->banded = banded;
    fe_filter_init(&st->fe_filt);
    fe_resamp_init(&st->fe_res, mode);
    spec_init(&st->spec);
    enhance_init(&st->enh);
    lbp_init(&st->lbp);
    decode_init(&st->dec, banded);
    smooth_init(&st->sm);
    st->next_win_end = E2E_WS;
}

static void push_25hz(dspit_e2e_t *st, uint8_t ch, float y, const dspit_trace_cb_t *tcb)
{
    const uint32_t idx = st->out_cnt[ch];
    st->win_buf[ch][idx & 255u] = y;
    st->out_cnt[ch] = idx + 1u;
    if (tcb && tcb->on_x25) {
        tcb->on_x25(ch, idx, (double)y, tcb->user);
    }
}

void dspit_push_block(dspit_e2e_t *st,
                      const float *ppg, uint32_t n_ppg,
                      const float *ax, const float *ay, const float *az, uint32_t n_acc,
                      dspit_block_out_t *out,
                      const dspit_hooks_t *hooks,
                      const dspit_trace_cb_t *trace_cb)
{
    memset(out, 0, sizeof(*out));
    out->tau = 1.0f;

    HOOK_BEGIN(hooks, DSPIT_STAGE_S1_FRONTEND);
    for (uint32_t i = 0u; i < n_ppg; i++) {
        const float pf = fe_filter_sample(&st->fe_filt, 0u, st->mode, ppg[i]);
        float y = 0.0f;
        if (fe_resamp_push(&st->fe_res, 0u, st->mode, pf, &y)) {
            push_25hz(st, 0u, y, trace_cb);
        }
    }

    const float *acc_ptrs[3] = { ax, ay, az };
    if (st->mode == E2E_MODE_DALIA) {
        for (uint8_t a = 0u; a < 3u; a++) {
            const uint8_t ch = (uint8_t)(a + 1u);
            const float *ap = acc_ptrs[a];
            for (uint32_t i = 0u; i < n_acc; i++) {
                const float af = fe_filter_sample(&st->fe_filt, ch, st->mode, ap[i]);
                float y = 0.0f;
                if (fe_resamp_push(&st->fe_res, ch, st->mode, af, &y)) {
                    push_25hz(st, ch, y, trace_cb);
                }
            }
        }
    } else {
        for (uint8_t a = 0u; a < 3u; a++) {
            const uint8_t ch = (uint8_t)(a + 1u);
            const float *ap = acc_ptrs[a];
            for (uint32_t i = 0u; i < n_acc; i++) {
                const float x_cur = ap[i];
                if (st->fe_res.wesad_acc_has_prev[a]) {
                    const float x_mid = 0.5f * (st->fe_res.wesad_acc_prev[a] + x_cur);
                    const float af_mid = fe_filter_sample(&st->fe_filt, ch, st->mode, x_mid);
                    float y_mid = 0.0f;
                    if (fe_resamp_push(&st->fe_res, ch, st->mode, af_mid, &y_mid)) {
                        push_25hz(st, ch, y_mid, trace_cb);
                    }
                }
                const float af_cur = fe_filter_sample(&st->fe_filt, ch, st->mode, x_cur);
                float y_cur = 0.0f;
                if (fe_resamp_push(&st->fe_res, ch, st->mode, af_cur, &y_cur)) {
                    push_25hz(st, ch, y_cur, trace_cb);
                }
                st->fe_res.wesad_acc_prev[a] = x_cur;
                st->fe_res.wesad_acc_has_prev[a] = 1u;
            }
        }
    }
    HOOK_END(hooks, DSPIT_STAGE_S1_FRONTEND);

    while (st->out_cnt[0] >= st->next_win_end &&
           st->out_cnt[1] >= st->next_win_end &&
           st->out_cnt[2] >= st->next_win_end &&
           st->out_cnt[3] >= st->next_win_end) {
        const uint32_t start_idx = st->next_win_end - E2E_WS;
        out->win_ran = 1u;

        HOOK_BEGIN(hooks, DSPIT_STAGE_S2_SPECTRAL);
        spec_compute_window(&st->spec, st->win_buf, start_idx, st->sp_mag, st->ap_mag);
        HOOK_END(hooks, DSPIT_STAGE_S2_SPECTRAL);

        HOOK_BEGIN(hooks, DSPIT_STAGE_S3_ENHANCE);
        enhance_window(&st->enh, st->sp_mag, st->ap_mag, st->obv, st->psp, st->logL);
        HOOK_END(hooks, DSPIT_STAGE_S3_ENHANCE);

        double logL_pre_d[E2E_K];
        if (trace_cb && trace_cb->on_window) {
            for (uint32_t j = 0u; j < E2E_K; j++) { logL_pre_d[j] = (double)st->logL[j]; }
        }

        HOOK_BEGIN(hooks, DSPIT_STAGE_S4_LBP);
        const float tau = lbp_update_tau(&st->lbp, st->obv, st->logL);
        HOOK_END(hooks, DSPIT_STAGE_S4_LBP);
        out->tau = tau;

        if (trace_cb && trace_cb->on_window) {
            double sp_d[E2E_NB], ap_d[3][E2E_NB], obv_d[E2E_NB], psp_d[E2E_K], logL_post_d[E2E_K];
            for (uint32_t b = 0u; b < E2E_NB; b++) {
                sp_d[b] = (double)st->sp_mag[b];
                ap_d[0][b] = (double)st->ap_mag[0][b];
                ap_d[1][b] = (double)st->ap_mag[1][b];
                ap_d[2][b] = (double)st->ap_mag[2][b];
                obv_d[b] = (double)st->obv[b];
            }
            for (uint32_t j = 0u; j < E2E_K; j++) {
                psp_d[j] = (double)st->psp[j];
                logL_post_d[j] = (double)st->logL[j];
            }
            trace_cb->on_window(st->win_idx, sp_d, ap_d, obv_d, psp_d, logL_pre_d,
                                (double)tau, logL_post_d, trace_cb->user);
        }

        float rb = 0.0f;
        HOOK_BEGIN(hooks, DSPIT_STAGE_S5_VITERBI);
        const uint8_t got_est = decode_step(&st->dec, st->logL, &rb);
        if (got_est) {
            lbp_push_est(&st->lbp, rb);
        }
        HOOK_END(hooks, DSPIT_STAGE_S5_VITERBI);

        if (got_est) {
            out->has_est = 1u;
            out->est_index = st->est_idx++;
            out->est_bpm = rb;

            float es = 0.0f;
            HOOK_BEGIN(hooks, DSPIT_STAGE_S6_SMOOTH);
            const uint8_t got_es = smooth_push(&st->sm, rb, &es);
            HOOK_END(hooks, DSPIT_STAGE_S6_SMOOTH);

            if (got_es) {
                out->has_es = 1u;
                out->es_index = st->es_idx++;
                out->es_bpm = es;
            }
        }

        st->win_idx++;
        st->next_win_end += E2E_HS;
    }
}
