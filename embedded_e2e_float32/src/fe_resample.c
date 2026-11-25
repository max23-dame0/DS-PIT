/* S1b: Streaming polyphase FIR resampler (25 Hz target) */
#include <string.h>
#include "dspit_e2e.h"
#include "e2e_tables.h"

void fe_resamp_init(fe_resamp_t *st, uint8_t mode)
{
    memset(st, 0, sizeof(*st));
    const uint32_t init_imax = (mode == E2E_MODE_DALIA) ? 50u : 25u;
    for (uint8_t ch = 0u; ch < 4u; ch++) {
        st->next_imax[ch] = init_imax;
    }
}

uint8_t fe_resamp_push(fe_resamp_t *st, uint8_t ch, uint8_t mode, real_t x, real_t *y_out)
{
    const uint32_t idx = st->in_cnt[ch];
    st->ring[ch][idx & 127u] = x;
    st->in_cnt[ch] = idx + 1u;

    if (idx != st->next_imax[ch]) {
        return 0u;
    }

    real_t acc = R_LIT(0.0);
    if (mode == E2E_MODE_DALIA) {
        const uint32_t n_avail = (idx < 100u) ? (idx + 1u) : 101u;
        for (uint32_t r = 0u; r < n_avail; r++) {
            acc += RESAMP_H_DALIA[r] * st->ring[ch][(idx - r) & 127u];
        }
        st->out_m[ch]++;
        st->next_imax[ch] = 5u * st->out_m[ch] + 50u;
    } else {
        const uint32_t qpos = 640u + 64u * st->out_m[ch];
        const uint32_t imin = (qpos > 1280u) ? ((qpos - 1280u + 24u) / 25u) : 0u;
        uint32_t r = qpos - 25u * imin;
        for (uint32_t i = imin; i <= idx; i++) {
            acc += RESAMP_H_WESAD[r] * st->ring[ch][i & 127u];
            r -= 25u;
        }
        st->out_m[ch]++;
        st->next_imax[ch] = (640u + 64u * st->out_m[ch]) / 25u;
    }
    *y_out = acc;
    return 1u;
}
