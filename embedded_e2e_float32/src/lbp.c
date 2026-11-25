/* S4: Causal Long-term Bayesian Prior (LBP) reliability temperature update */
#include <string.h>
#include "dspit_e2e.h"

void lbp_init(lbp_state_t *st)
{
    memset(st, 0, sizeof(*st));
    st->r_rel = R_LIT(0.5);
}

static real_t median5(real_t a[5])
{
    for (uint8_t i = 0u; i < 4u; i++) {
        for (uint8_t j = (uint8_t)(i + 1u); j < 5u; j++) {
            if (a[j] < a[i]) {
                real_t t = a[i]; a[i] = a[j]; a[j] = t;
            }
        }
    }
    return a[2];
}

real_t lbp_update_tau(lbp_state_t *st, const real_t obv[E2E_NB], real_t logL[E2E_K])
{
    if (st->hist_cnt < E2E_HIST_LEN) {
        return R_LIT(1.0);
    }

    /* Causal trend vhat from last 6 decoder outputs */
    real_t vhat = R_LIT(0.0);
    if (st->veh_cnt >= (E2E_VEL_L + 1u)) {
        const uint8_t cap = (uint8_t)(E2E_VEL_L + 1u);
        real_t ordered[6];
        for (uint8_t i = 0u; i < cap; i++) {
            ordered[i] = st->veh[(st->veh_pos + i) % cap];
        }
        real_t dv[5];
        for (uint8_t i = 0u; i < 5u; i++) {
            dv[i] = ordered[i + 1u] - ordered[i];
        }
        real_t med = median5(dv);
        if (med < R_LIT(-2.0)) { med = R_LIT(-2.0); }
        if (med > R_LIT(2.0))  { med = R_LIT(2.0); }
        vhat = R_ROUND(med);
    }

    real_t sum_h = R_LIT(0.0);
    for (uint8_t i = 0u; i < E2E_HIST_LEN; i++) {
        sum_h += st->hist_g[i];
    }
    const real_t a_lb = sum_h / R_LIT(15.0) + vhat;

    /* Dominant spectral peak frequency in BPM: 60 * (BIN_START + imo) * 25 / 1024 */
    uint32_t imo = 0u;
    real_t best_v = obv[0];
    for (uint32_t b = 1u; b < E2E_NB; b++) {
        if (obv[b] > best_v) {
            best_v = obv[b];
            imo = b;
        }
    }
    const real_t pk_bpm = (real_t)(E2E_BIN_START + imo) * R_LIT(1500.0) / R_LIT(1024.0);
    const real_t d_obs = R_FABS(pk_bpm - a_lb);
    const real_t rel = R_EXP(-(d_obs * d_obs) / R_LIT(400.0));

    st->r_rel = (R_LIT(29.0) / R_LIT(30.0)) * st->r_rel + (R_LIT(1.0) / R_LIT(30.0)) * rel;
    const real_t tau = R_LIT(0.7) + R_LIT(0.6) * st->r_rel;
    for (uint32_t j = 0u; j < E2E_K; j++) {
        logL[j] *= tau;
    }
    return tau;
}

void lbp_push_est(lbp_state_t *st, real_t rb)
{
    st->hist_g[st->hist_pos] = rb;
    st->hist_pos = (uint8_t)((st->hist_pos + 1u) % E2E_HIST_LEN);
    if (st->hist_cnt < E2E_HIST_LEN) { st->hist_cnt++; }

    const uint8_t cap = (uint8_t)(E2E_VEL_L + 1u);
    st->veh[st->veh_pos] = rb;
    st->veh_pos = (uint8_t)((st->veh_pos + 1u) % cap);
    if (st->veh_cnt < cap) { st->veh_cnt++; }
}
