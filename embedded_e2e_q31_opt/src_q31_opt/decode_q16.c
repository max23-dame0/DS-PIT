/* S5 fixed-point (q31-full-opt): Pure int32 Q15.16 fixed-lag Viterbi decoder */
#include <string.h>
#include "dspit_opt.h"
#include "e2e_opt_tables.h"

void decode_init(decode_state_t *st, uint8_t banded)
{
    memset(st, 0, sizeof(*st));
    st->banded = banded;
}

uint8_t decode_step_q16(decode_state_t *st, const int32_t logL_q16[E2E_K], int32_t *rb_q16_out)
{
    const uint32_t t = st->step;
    if (t == 0u) {
        for (uint32_t j = 0u; j < E2E_K; j++) {
            st->v_new[j] = logL_q16[j] + MCU_A_Q16[j];
            st->pring[0][j] = 0;
        }
    } else {
        for (uint32_t k = 0u; k < E2E_K; k++) {
            st->u_vec[k] = st->v_old[k] + MCU_A_Q16[k];
        }
        if (st->banded) {
            for (int32_t j = 0; j < (int32_t)E2E_K; j++) {
                int32_t k0 = j - E2E_BAND_HW;
                if (k0 < 0) { k0 = 0; }
                int32_t k1 = j + E2E_BAND_HW;
                if (k1 > (int32_t)E2E_K - 1) { k1 = (int32_t)E2E_K - 1; }
                int32_t best = Q16_NEG_INF;
                int32_t bi = k0;
                for (int32_t k = k0; k <= k1; k++) {
                    int32_t d = k - j;
                    if (d < 0) { d = -d; }
                    const int32_t tmp = st->u_vec[k] + MCU_G_Q16[d];
                    if (tmp > best) {
                        best = tmp;
                        bi = k;
                    }
                }
                st->v_new[j] = logL_q16[j] + best;
                st->pring[st->cur][j] = (int16_t)bi;
            }
        } else {
            for (int32_t j = 0; j < (int32_t)E2E_K; j++) {
                int32_t best = Q16_NEG_INF;
                int32_t bi = 0;
                for (int32_t k = 0; k < (int32_t)E2E_K; k++) {
                    int32_t d = k - j;
                    if (d < 0) { d = -d; }
                    const int32_t tmp = st->u_vec[k] + MCU_G_Q16[d];
                    if (tmp > best) {
                        best = tmp;
                        bi = k;
                    }
                }
                st->v_new[j] = logL_q16[j] + best;
                st->pring[st->cur][j] = (int16_t)bi;
            }
        }
    }

    int32_t vmax = st->v_new[0];
    int16_t best_s = 0;
    for (int16_t j = 1; j < (int16_t)E2E_K; j++) {
        if (st->v_new[j] > vmax) {
            vmax = st->v_new[j];
            best_s = j;
        }
    }

    uint8_t emitted = 0u;
    if (t >= (E2E_D - 1u)) {
        int16_t s = best_s;
        s = st->pring[st->cur][s];
        s = st->pring[st->cur ^ 1u][s];
        *rb_q16_out = (E2E_BPM_MIN + (int32_t)s) << 16;
        emitted = 1u;
    }

    st->cur ^= 1u;
    /* Max-subtraction shift invariance prevents int32 overflow over unbounded streams */
    for (uint32_t j = 0u; j < E2E_K; j++) {
        st->v_old[j] = st->v_new[j] - vmax;
    }
    st->step = t + 1u;
    return emitted;
}
