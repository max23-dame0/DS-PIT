/* S1b optimized (f32-algo-opt): linear-phase symmetric zero-skipped FIR resampler */
#include <string.h>
#include "dspit_opt.h"
#include "e2e_f32opt_tables.h"

void fe_resamp_init(fe_resamp_t *st, uint8_t mode)
{
    memset(st, 0, sizeof(*st));
    const uint32_t init_imax = (mode == E2E_MODE_DALIA) ? 50u : 25u;
    for (uint8_t ch = 0u; ch < 4u; ch++) {
        st->next_imax[ch] = init_imax;
    }
}

uint8_t fe_resamp_push(fe_resamp_t *st, uint8_t ch, uint8_t mode, float x, float *y_out)
{
    const uint32_t idx = st->in_cnt[ch];
    float *ring = st->ring[ch];
    ring[idx & 127u] = x;
    st->in_cnt[ch] = idx + 1u;

    if (idx != st->next_imax[ch]) {
        return 0u;
    }

    float acc = 0.0f;
    if (mode == E2E_MODE_DALIA) {
        if (idx >= 100u) {
            /* 101-tap Nyquist-5 symmetric FIR: 40 pairs + 1 center = 41 muls */
            acc = DALIA_SYM_H[40] * ring[(idx - 50u) & 127u];
            for (uint32_t p = 0u; p < 40u; p++) {
                const uint32_t r = DALIA_SYM_OFF[p];
                acc += DALIA_SYM_H[p] * (ring[(idx - r) & 127u] + ring[(idx - (100u - r)) & 127u]);
            }
        } else {
            const uint32_t n_avail = idx + 1u;
            for (uint32_t r = 0u; r < n_avail; r++) {
                acc += RESAMP_H_DALIA[r] * ring[(idx - r) & 127u];
            }
        }
        st->out_m[ch]++;
        st->next_imax[ch] = 5u * st->out_m[ch] + 50u;
    } else {
        const uint32_t qpos = 640u + 64u * st->out_m[ch];
        const uint32_t imin = (qpos > 1280u) ? ((qpos - 1280u + 24u) / 25u) : 0u;
        uint32_t r = qpos - 25u * imin;
        for (uint32_t i = imin; i <= idx; i++) {
            acc += RESAMP_H_WESAD[r] * ring[i & 127u];
            r -= 25u;
        }
        st->out_m[ch]++;
        st->next_imax[ch] = (640u + 64u * st->out_m[ch]) / 25u;
    }
    *y_out = acc;
    return 1u;
}
