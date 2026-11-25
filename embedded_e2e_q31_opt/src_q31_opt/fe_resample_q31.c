/* S1b fixed-point (q31-full-opt): Q11.20 symmetric zero-skipped polyphase FIR */
#include <string.h>
#include "dspit_opt.h"
#include "e2e_opt_tables.h"

void fe_resamp_init(fe_resamp_t *st, uint8_t mode)
{
    memset(st, 0, sizeof(*st));
    const uint32_t init_imax = (mode == E2E_MODE_DALIA) ? 50u : 25u;
    for (uint8_t ch = 0u; ch < 4u; ch++) {
        st->next_imax[ch] = init_imax;
    }
}

uint8_t fe_resamp_push_q20(fe_resamp_t *st, uint8_t ch, uint8_t mode, int32_t x_q20, int32_t *y_q20)
{
    const uint32_t idx = st->in_cnt[ch];
    int32_t *ring = st->ring[ch];
    ring[idx & 127u] = x_q20;
    st->in_cnt[ch] = idx + 1u;

    if (idx != st->next_imax[ch]) {
        return 0u;
    }

    int64_t acc = 0;
    if (mode == E2E_MODE_DALIA) {
        if (idx >= 100u) {
            acc = (int64_t)DALIA_SYM_H_Q31[40] * (int64_t)ring[(idx - 50u) & 127u];
            for (uint32_t p = 0u; p < 40u; p++) {
                const uint32_t r = DALIA_SYM_OFF[p];
                const int32_t s = ring[(idx - r) & 127u] + ring[(idx - (100u - r)) & 127u];
                acc += (int64_t)DALIA_SYM_H_Q31[p] * (int64_t)s;
            }
        } else {
            const uint32_t n_avail = idx + 1u;
            for (uint32_t r = 0u; r < n_avail; r++) {
                acc += (int64_t)RESAMP_H_DALIA_Q31[r] * (int64_t)ring[(idx - r) & 127u];
            }
        }
        st->out_m[ch]++;
        st->next_imax[ch] = 5u * st->out_m[ch] + 50u;
    } else {
        const uint32_t qpos = 640u + 64u * st->out_m[ch];
        const uint32_t imin = (qpos > 1280u) ? ((qpos - 1280u + 24u) / 25u) : 0u;
        uint32_t r = qpos - 25u * imin;
        for (uint32_t i = imin; i <= idx; i++) {
            acc += (int64_t)RESAMP_H_WESAD_Q31[r] * (int64_t)ring[i & 127u];
            r -= 25u;
        }
        st->out_m[ch]++;
        st->next_imax[ch] = (640u + 64u * st->out_m[ch]) / 25u;
    }
    *y_q20 = (int32_t)((acc + (1LL << 30)) >> 31);
    return 1u;
}
