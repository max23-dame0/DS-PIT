/* Top-level streaming DS-PIT E2E coordinator (q31-full-opt) */
#include <string.h>
#include "dspit_opt.h"

#define HOOK_BEGIN(hooks, st_id) \
    do { if ((hooks) && (hooks)->on_stage_begin) { (hooks)->on_stage_begin((st_id), (hooks)->user); } } while (0)
#define HOOK_END(hooks, st_id) \
    do { if ((hooks) && (hooks)->on_stage_end) { (hooks)->on_stage_end((st_id), (hooks)->user); } } while (0)

#define INV_Q16_F (1.0f / 65536.0f)
#define Q20_SCALE (1048576.0f)
#define Q28_SCALE (268435456.0f)
#define INV_Q20_D (1.0 / 1048576.0)
#define INV_Q28_D (1.0 / 268435456.0)
#define INV_Q21_D (1.0 / 2097152.0)
#define INV_Q30_D (1.0 / 1073741824.0)
#define INV_Q16_D (1.0 / 65536.0)

static inline int32_t f32_to_q20(float x)
{
    const float scaled = x * Q20_SCALE;
    return (int32_t)((scaled >= 0.0f) ? (scaled + 0.5f) : (scaled - 0.5f));
}

static inline int32_t f32_to_q28(float x)
{
    const float scaled = x * Q28_SCALE;
    return (int32_t)((scaled >= 0.0f) ? (scaled + 0.5f) : (scaled - 0.5f));
}

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

static void push_25hz_q20(dspit_e2e_t *st, uint8_t ch, int32_t y_q, const dspit_trace_cb_t *tcb)
{
    const uint32_t idx = st->out_cnt[ch];
    st->win_buf[ch][idx & 255u] = y_q;
    st->out_cnt[ch] = idx + 1u;
    if (tcb && tcb->on_x25) {
        const double inv = (ch > 0u && st->mode == E2E_MODE_DALIA) ? INV_Q28_D : INV_Q20_D;
        tcb->on_x25(ch, idx, (double)y_q * inv, tcb->user);
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

    /* ---- S1: Convert incoming float block -> Q11.20 + SOS filter + polyphase resample ---- */
    HOOK_BEGIN(hooks, DSPIT_STAGE_S1_FRONTEND);
    for (uint32_t i = 0u; i < n_ppg; i++) {
        const int32_t pf = fe_filter_sample_q20(&st->fe_filt, 0u, st->mode, f32_to_q20(ppg[i]));
        int32_t y = 0;
        if (fe_resamp_push_q20(&st->fe_res, 0u, st->mode, pf, &y)) {
            push_25hz_q20(st, 0u, y, trace_cb);
        }
    }

    const float *acc_ptrs[3] = { ax, ay, az };
    if (st->mode == E2E_MODE_DALIA) {
        for (uint8_t a = 0u; a < 3u; a++) {
            const uint8_t ch = (uint8_t)(a + 1u);
            const float *ap = acc_ptrs[a];
            for (uint32_t i = 0u; i < n_acc; i++) {
                const int32_t af = fe_filter_sample_q20(&st->fe_filt, ch, st->mode, f32_to_q28(ap[i]));
                int32_t y = 0;
                if (fe_resamp_push_q20(&st->fe_res, ch, st->mode, af, &y)) {
                    push_25hz_q20(st, ch, y, trace_cb);
                }
            }
        }
    } else {
        for (uint8_t a = 0u; a < 3u; a++) {
            const uint8_t ch = (uint8_t)(a + 1u);
            const float *ap = acc_ptrs[a];
            for (uint32_t i = 0u; i < n_acc; i++) {
                const int32_t x_cur = f32_to_q20(ap[i]);
                if (st->fe_res.wesad_acc_has_prev[a]) {
                    const int32_t x_mid = (st->fe_res.wesad_acc_prev[a] + x_cur) >> 1;
                    const int32_t af_mid = fe_filter_sample_q20(&st->fe_filt, ch, st->mode, x_mid);
                    int32_t y_mid = 0;
                    if (fe_resamp_push_q20(&st->fe_res, ch, st->mode, af_mid, &y_mid)) {
                        push_25hz_q20(st, ch, y_mid, trace_cb);
                    }
                }
                const int32_t af_cur = fe_filter_sample_q20(&st->fe_filt, ch, st->mode, x_cur);
                int32_t y_cur = 0;
                if (fe_resamp_push_q20(&st->fe_res, ch, st->mode, af_cur, &y_cur)) {
                    push_25hz_q20(st, ch, y_cur, trace_cb);
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
        spec_compute_window_q21(&st->spec, st->win_buf, start_idx, st->sp_mag, st->ap_mag);
        HOOK_END(hooks, DSPIT_STAGE_S2_SPECTRAL);

        HOOK_BEGIN(hooks, DSPIT_STAGE_S3_ENHANCE);
        enhance_window_q(&st->enh, st->sp_mag, st->ap_mag, st->obv_q16, st->psp_q30, st->logL_q16);
        HOOK_END(hooks, DSPIT_STAGE_S3_ENHANCE);

#ifdef DSPIT_ENABLE_TRACE
        double logL_pre_d[E2E_K];
        if (trace_cb && trace_cb->on_window) {
            for (uint32_t j = 0u; j < E2E_K; j++) {
                logL_pre_d[j] = (double)st->logL_q16[j] * INV_Q16_D;
            }
        }
#endif

        HOOK_BEGIN(hooks, DSPIT_STAGE_S4_LBP);
        const int32_t tau_q16 = lbp_update_tau_q16(&st->lbp, st->obv_q16, st->logL_q16);
        HOOK_END(hooks, DSPIT_STAGE_S4_LBP);
        out->tau = (float)tau_q16 * INV_Q16_F;

#ifdef DSPIT_ENABLE_TRACE
        if (trace_cb && trace_cb->on_window) {
            double sp_d[E2E_NB], ap_d[3][E2E_NB], obv_d[E2E_NB], psp_d[E2E_K], logL_post_d[E2E_K];
            for (uint32_t b = 0u; b < E2E_NB; b++) {
                sp_d[b]    = (double)st->sp_mag[b] * INV_Q21_D;
                ap_d[0][b] = (double)st->ap_mag[0][b] * INV_Q21_D;
                ap_d[1][b] = (double)st->ap_mag[1][b] * INV_Q21_D;
                ap_d[2][b] = (double)st->ap_mag[2][b] * INV_Q21_D;
                obv_d[b]   = (double)st->obv_q16[b] * INV_Q16_D;
            }
            for (uint32_t j = 0u; j < E2E_K; j++) {
                psp_d[j]       = (double)st->psp_q30[j] * INV_Q30_D;
                logL_post_d[j] = (double)st->logL_q16[j] * INV_Q16_D;
            }
            trace_cb->on_window(st->win_idx, sp_d, ap_d, obv_d, psp_d, logL_pre_d,
                                (double)tau_q16 * INV_Q16_D, logL_post_d, trace_cb->user);
        }
#endif

        int32_t rb_q16 = 0;
        HOOK_BEGIN(hooks, DSPIT_STAGE_S5_VITERBI);
        const uint8_t got_est = decode_step_q16(&st->dec, st->logL_q16, &rb_q16);
        if (got_est) {
            lbp_push_est_q16(&st->lbp, rb_q16);
        }
        HOOK_END(hooks, DSPIT_STAGE_S5_VITERBI);

        if (got_est) {
            out->has_est = 1u;
            out->est_index = st->est_idx++;
            out->est_bpm = (float)rb_q16 * INV_Q16_F;

            int32_t es_q16 = 0;
            HOOK_BEGIN(hooks, DSPIT_STAGE_S6_SMOOTH);
            const uint8_t got_es = smooth_push_q16(&st->sm, rb_q16, &es_q16);
            HOOK_END(hooks, DSPIT_STAGE_S6_SMOOTH);

            if (got_es) {
                out->has_es = 1u;
                out->es_index = st->es_idx++;
                out->es_bpm = (float)es_q16 * INV_Q16_F;
            }
        }

        st->win_idx++;
        st->next_win_end += E2E_HS;
    }
}
