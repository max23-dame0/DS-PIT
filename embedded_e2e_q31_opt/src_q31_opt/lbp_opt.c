/* S4 fixed-point (q31-full-opt): Q15.16 causal LBP with integer exp(-d^2/400) */
#include <string.h>
#include "dspit_opt.h"

void lbp_init(lbp_state_t *st)
{
    memset(st, 0, sizeof(*st));
    st->r_rel_q16 = Q16_ONE >> 1; /* 0.5 */
}

static int32_t median5_i32(int32_t a[5])
{
    for (uint8_t i = 0u; i < 4u; i++) {
        for (uint8_t j = (uint8_t)(i + 1u); j < 5u; j++) {
            if (a[j] < a[i]) {
                int32_t t = a[i]; a[i] = a[j]; a[j] = t;
            }
        }
    }
    return a[2];
}

/* exp(-x) in Q15.16 for x_q16 >= 0 (accuracy < 1.5e-5, zero floats) */
static int32_t exp_neg_q16(uint32_t x_q16)
{
    if (x_q16 >= (16u << 16)) { return 0; }
    /* t = x / ln(2) in Q30; round(2^30 / ln(2)) = 1549082005 */
    const uint64_t t_q30 = ((uint64_t)x_q16 * 1549082005ULL) >> 16;
    const uint32_t k = (uint32_t)(t_q30 >> 30);
    if (k >= 17u) { return 0; }
    const uint32_t f_q30 = (uint32_t)(t_q30 & 0x3FFFFFFFULL);
    /* u = f * ln(2) in [0, ln(2)), Q30 */
    const int64_t u = (int64_t)(((uint64_t)f_q30 * 744261118ULL) >> 30);

    /* Horner: 1 - u*(1 - u*(1/2 - u*(1/6 - u*(1/24 - u*(1/120 - u/720))))) */
    /* Constants in Q30: 1/720=1491308, 1/120=8947849, 1/24=44739243, 1/6=178956971, 1/2=536870912 */
    int64_t p = 8947849LL - ((u * 1491308LL) >> 30);
    p = 44739243LL  - ((u * p) >> 30);
    p = 178956971LL - ((u * p) >> 30);
    p = 536870912LL - ((u * p) >> 30);
    p = (1LL << 30) - ((u * p) >> 30);
    const int64_t val_q30 = (1LL << 30) - ((u * p) >> 30);
    const int64_t shifted = val_q30 >> k;
    return (int32_t)((shifted + (1LL << 13)) >> 14);
}

int32_t lbp_update_tau_q16(lbp_state_t *st, const int32_t obv_q16[E2E_NB], int32_t logL_q16[E2E_K])
{
    if (st->hist_cnt < E2E_HIST_LEN) {
        return Q16_ONE;
    }

    int32_t vhat_q16 = 0;
    if (st->veh_cnt >= (E2E_VEL_L + 1u)) {
        const uint8_t cap = (uint8_t)(E2E_VEL_L + 1u);
        int32_t ordered[6];
        for (uint8_t i = 0u; i < cap; i++) {
            ordered[i] = st->veh[(st->veh_pos + i) % cap];
        }
        int32_t dv[5];
        for (uint8_t i = 0u; i < 5u; i++) {
            dv[i] = ordered[i + 1u] - ordered[i];
        }
        int32_t med = median5_i32(dv);
        if (med < (-2 * Q16_ONE)) { med = -2 * Q16_ONE; }
        if (med > ( 2 * Q16_ONE)) { med =  2 * Q16_ONE; }
        /* round to nearest integer BPM in Q15.16 */
        vhat_q16 = ((med >= 0) ? ((med + 32768) & ~0xFFFF) : -((-med + 32768) & ~0xFFFF));
    }

    int64_t sum_h = 0;
    for (uint8_t i = 0u; i < E2E_HIST_LEN; i++) {
        sum_h += (int64_t)st->hist_g[i];
    }
    const int32_t a_lb_q16 = (int32_t)(sum_h / 15) + vhat_q16;

    uint32_t imo = 0u;
    int32_t best_v = obv_q16[0];
    for (uint32_t b = 1u; b < E2E_NB; b++) {
        if (obv_q16[b] > best_v) {
            best_v = obv_q16[b];
            imo = b;
        }
    }
    /* pk_bpm = (31 + imo) * 1500 / 1024 in Q15.16 = ((31 + imo) * 1500) << 6 */
    const int32_t pk_bpm_q16 = (int32_t)((E2E_BIN_START + imo) * 1500u * 64u);
    int32_t d_obs_q16 = pk_bpm_q16 - a_lb_q16;
    if (d_obs_q16 < 0) { d_obs_q16 = -d_obs_q16; }

    /* d^2 / 400 in Q15.16 */
    const uint64_t d2_q16 = ((uint64_t)d_obs_q16 * (uint64_t)d_obs_q16) >> 16;
    const uint32_t x_q16  = (uint32_t)(d2_q16 / 400ULL);
    const int32_t rel_q16 = exp_neg_q16(x_q16);

    /* r_rel = (29/30)*r_rel + (1/30)*rel; round(2^30/30) = 35791394 */
    st->r_rel_q16 = (int32_t)((29LL * (int64_t)st->r_rel_q16 + (int64_t)rel_q16 + 15LL) / 30LL);
    /* tau = 0.7 + 0.6 * r_rel in Q15.16; 0.7*65536=45875.2, 0.6*65536=39321.6 */
    const int32_t tau_q16 = (int32_t)(45875LL + ((39322LL * (int64_t)st->r_rel_q16 + 32768LL) >> 16));

    for (uint32_t j = 0u; j < E2E_K; j++) {
        logL_q16[j] = (int32_t)(((int64_t)logL_q16[j] * (int64_t)tau_q16 + 32768LL) >> 16);
    }
    return tau_q16;
}

void lbp_push_est_q16(lbp_state_t *st, int32_t rb_q16)
{
    st->hist_g[st->hist_pos] = rb_q16;
    uint8_t nh = (uint8_t)(st->hist_pos + 1u);
    if (nh >= E2E_HIST_LEN) { nh = 0u; }
    st->hist_pos = nh;
    if (st->hist_cnt < E2E_HIST_LEN) { st->hist_cnt++; }

    const uint8_t cap = (uint8_t)(E2E_VEL_L + 1u);
    st->veh[st->veh_pos] = rb_q16;
    uint8_t nv = (uint8_t)(st->veh_pos + 1u);
    if (nv >= cap) { nv = 0u; }
    st->veh_pos = nv;
    if (st->veh_cnt < cap) { st->veh_cnt++; }
}
