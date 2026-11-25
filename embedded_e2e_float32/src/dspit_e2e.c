/* Top-level streaming DS-PIT E2E pipeline coordinator */
#include <string.h>
#include "dspit_e2e.h"

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

static void push_25hz(dspit_e2e_t *st, uint8_t ch, real_t y, const dspit_trace_cb_t *tcb)
{
    const uint32_t idx = st->out_cnt[ch];
    st->win_buf[ch][idx & 255u] = y;
    st->out_cnt[ch] = idx + 1u;
    if (tcb && tcb->on_x25) {
        tcb->on_x25(ch, idx, y, tcb->user);
    }
}

void dspit_push_block(dspit_e2e_t *st,
                      const real_t *ppg, uint32_t n_ppg,
                      const real_t *ax, const real_t *ay, const real_t *az, uint32_t n_acc,
                      dspit_block_out_t *out,
                      const dspit_hooks_t *hooks,
                      const dspit_trace_cb_t *trace_cb)
{
    memset(out, 0, sizeof(*out));
    out->tau = R_LIT(1.0);

    /* ---- S1: Front-end bandpass + polyphase resampling (+ WESAD ACC 32->64) ---- */
    HOOK_BEGIN(hooks, DSPIT_STAGE_S1_FRONTEND);
    for (uint32_t i = 0u; i < n_ppg; i++) {
        const real_t pf = fe_filter_sample(&st->fe_filt, 0u, st->mode, ppg[i]);
        real_t y = R_LIT(0.0);
        if (fe_resamp_push(&st->fe_res, 0u, st->mode, pf, &y)) {
            push_25hz(st, 0u, y, trace_cb);
        }
    }

    const real_t *acc_ptrs[3] = { ax, ay, az };
    if (st->mode == E2E_MODE_DALIA) {
        for (uint8_t a = 0u; a < 3u; a++) {
            const uint8_t ch = (uint8_t)(a + 1u);
            for (uint32_t i = 0u; i < n_acc; i++) {
                const real_t af = fe_filter_sample(&st->fe_filt, ch, st->mode, acc_ptrs[a][i]);
                real_t y = R_LIT(0.0);
                if (fe_resamp_push(&st->fe_res, ch, st->mode, af, &y)) {
                    push_25hz(st, ch, y, trace_cb);
                }
            }
        }
    } else {
        /* WESAD: ACC arrives at 32 Hz; linearly interpolate to 64 Hz matching interp1 */
        for (uint8_t a = 0u; a < 3u; a++) {
            const uint8_t ch = (uint8_t)(a + 1u);
            for (uint32_t i = 0u; i < n_acc; i++) {
                const real_t x_cur = acc_ptrs[a][i];
                if (st->fe_res.wesad_acc_has_prev[a]) {
                    const real_t x_mid = R_LIT(0.5) * (st->fe_res.wesad_acc_prev[a] + x_cur);
                    const real_t af_mid = fe_filter_sample(&st->fe_filt, ch, st->mode, x_mid);
                    real_t y_mid = R_LIT(0.0);
                    if (fe_resamp_push(&st->fe_res, ch, st->mode, af_mid, &y_mid)) {
                        push_25hz(st, ch, y_mid, trace_cb);
                    }
                }
                const real_t af_cur = fe_filter_sample(&st->fe_filt, ch, st->mode, x_cur);
                real_t y_cur = R_LIT(0.0);
                if (fe_resamp_push(&st->fe_res, ch, st->mode, af_cur, &y_cur)) {
                    push_25hz(st, ch, y_cur, trace_cb);
                }
                st->fe_res.wesad_acc_prev[a] = x_cur;
                st->fe_res.wesad_acc_has_prev[a] = 1u;
            }
        }
    }
    HOOK_END(hooks, DSPIT_STAGE_S1_FRONTEND);

    /* ---- Check if a new 8-s window is complete across all 4 channels ---- */
    while (st->out_cnt[0] >= st->next_win_end &&
           st->out_cnt[1] >= st->next_win_end &&
           st->out_cnt[2] >= st->next_win_end &&
           st->out_cnt[3] >= st->next_win_end) {
        const uint32_t start_idx = st->next_win_end - E2E_WS;
        out->win_ran = 1u;

        /* S2: Spectral z-score + real-packed 1024-pt FFT */
        HOOK_BEGIN(hooks, DSPIT_STAGE_S2_SPECTRAL);
        spec_compute_window(&st->spec, st->win_buf, start_idx, st->sp_mag, st->ap_mag);
        HOOK_END(hooks, DSPIT_STAGE_S2_SPECTRAL);

        /* S3: Two-branch enhancement + interp + taper + logL */
        HOOK_BEGIN(hooks, DSPIT_STAGE_S3_ENHANCE);
        enhance_window(&st->enh, st->sp_mag, st->ap_mag, st->obv, st->psp, st->lvec, st->logL);
        HOOK_END(hooks, DSPIT_STAGE_S3_ENHANCE);

        real_t logL_pre_copy[E2E_K];
        if (trace_cb && trace_cb->on_window) {
            memcpy(logL_pre_copy, st->logL, sizeof(logL_pre_copy));
        }

        /* S4: Causal LBP reliability temperature modulation */
        HOOK_BEGIN(hooks, DSPIT_STAGE_S4_LBP);
        const real_t tau = lbp_update_tau(&st->lbp, st->obv, st->logL);
        HOOK_END(hooks, DSPIT_STAGE_S4_LBP);
        out->tau = tau;

        if (trace_cb && trace_cb->on_window) {
            trace_cb->on_window(st->win_idx, st->sp_mag, st->ap_mag, st->obv,
                                st->psp, st->lvec, logL_pre_copy, tau, st->logL, trace_cb->user);
        }

        /* S5: Fixed-lag Viterbi decoding + history update */
        real_t rb = R_LIT(0.0);
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

            /* S6: 3-point median output smoothing */
            real_t es = R_LIT(0.0);
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
