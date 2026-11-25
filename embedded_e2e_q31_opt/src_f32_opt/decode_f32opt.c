/* S5 (f32-algo-opt): Fixed-lag Viterbi decoder */
#include <string.h>
#include "dspit_opt.h"
#include "e2e_f32opt_tables.h"

void decode_init(decode_state_t *st, uint8_t banded)
{
    memset(st, 0, sizeof(*st));
    st->banded = banded;
}

uint8_t decode_step(decode_state_t *st, const float logL[E2E_K], float *rb_out)
{
    const uint32_t t = st->step;
    if (t == 0u) {
        for (uint32_t j = 0u; j < E2E_K; j++) {
            st->v_new[j] = logL[j] + MCU_A[j];
            st->pring[0][j] = 0;
        }
    } else {
        for (uint32_t k = 0u; k < E2E_K; k++) {
            st->u_vec[k] = st->v_old[k] + MCU_A[k];
        }
        if (st->banded) {
            for (int32_t j = 0; j < (int32_t)E2E_K; j++) {
                int32_t k0 = j - E2E_BAND_HW;
                if (k0 < 0) { k0 = 0; }
                int32_t k1 = j + E2E_BAND_HW;
                if (k1 > (int32_t)E2E_K - 1) { k1 = (int32_t)E2E_K - 1; }
                float best = R_NEG_INF_F32;
                int32_t bi = k0;
                for (int32_t k = k0; k <= k1; k++) {
                    int32_t d = k - j;
                    if (d < 0) { d = -d; }
                    const float tmp = st->u_vec[k] + MCU_G[d];
                    if (tmp > best) {
                        best = tmp;
                        bi = k;
                    }
                }
                st->v_new[j] = logL[j] + best;
                st->pring[st->cur][j] = (int16_t)bi;
            }
        } else {
            for (int32_t j = 0; j < (int32_t)E2E_K; j++) {
                float best = R_NEG_INF_F32;
                int32_t bi = 0;
                for (int32_t k = 0; k < (int32_t)E2E_K; k++) {
                    int32_t d = k - j;
                    if (d < 0) { d = -d; }
                    const float tmp = st->u_vec[k] + MCU_G[d];
                    if (tmp > best) {
                        best = tmp;
                        bi = k;
                    }
                }
                st->v_new[j] = logL[j] + best;
                st->pring[st->cur][j] = (int16_t)bi;
            }
        }
    }

    uint8_t emitted = 0u;
    if (t >= (E2E_D - 1u)) {
        float best = R_NEG_INF_F32;
        int16_t s = 0;
        for (int16_t j = 0; j < (int16_t)E2E_K; j++) {
            if (st->v_new[j] > best) {
                best = st->v_new[j];
                s = j;
            }
        }
        s = st->pring[st->cur][s];
        s = st->pring[st->cur ^ 1u][s];
        *rb_out = (float)(E2E_BPM_MIN + (int32_t)s);
        emitted = 1u;
    }

    st->cur ^= 1u;
    memcpy(st->v_old, st->v_new, sizeof(st->v_old));
    st->step = t + 1u;
    return emitted;
}
