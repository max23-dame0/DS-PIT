/* S4 (f32-algo-opt): Causal LBP reliability temperature update */
#include <string.h>
#include "dspit_opt.h"

void lbp_init(lbp_state_t *st)
{
    memset(st, 0, sizeof(*st));
    st->r_rel = 0.5f;
}

static float median5(float a[5])
{
    for (uint8_t i = 0u; i < 4u; i++) {
        for (uint8_t j = (uint8_t)(i + 1u); j < 5u; j++) {
            if (a[j] < a[i]) {
                float t = a[i]; a[i] = a[j]; a[j] = t;
            }
        }
    }
    return a[2];
}

float lbp_update_tau(lbp_state_t *st, const float obv[E2E_NB], float logL[E2E_K])
{
    if (st->hist_cnt < E2E_HIST_LEN) {
        return 1.0f;
    }

    float vhat = 0.0f;
    if (st->veh_cnt >= (E2E_VEL_L + 1u)) {
        const uint8_t cap = (uint8_t)(E2E_VEL_L + 1u);
        float ordered[6];
        for (uint8_t i = 0u; i < cap; i++) {
            ordered[i] = st->veh[(st->veh_pos + i) % cap];
        }
        float dv[5];
        for (uint8_t i = 0u; i < 5u; i++) {
            dv[i] = ordered[i + 1u] - ordered[i];
        }
        float med = median5(dv);
        if (med < -2.0f) { med = -2.0f; }
        if (med > 2.0f)  { med = 2.0f; }
        vhat = roundf(med);
    }

    float sum_h = 0.0f;
    for (uint8_t i = 0u; i < E2E_HIST_LEN; i++) {
        sum_h += st->hist_g[i];
    }
    const float a_lb = sum_h * (1.0f / 15.0f) + vhat;

    uint32_t imo = 0u;
    float best_v = obv[0];
    for (uint32_t b = 1u; b < E2E_NB; b++) {
        if (obv[b] > best_v) {
            best_v = obv[b];
            imo = b;
        }
    }
    const float pk_bpm = (float)(E2E_BIN_START + imo) * (1500.0f / 1024.0f);
    const float d_obs = fabsf(pk_bpm - a_lb);
    const float rel = expf(-(d_obs * d_obs) * (1.0f / 400.0f));

    st->r_rel = (29.0f / 30.0f) * st->r_rel + (1.0f / 30.0f) * rel;
    const float tau = 0.7f + 0.6f * st->r_rel;
    for (uint32_t j = 0u; j < E2E_K; j++) {
        logL[j] *= tau;
    }
    return tau;
}

void lbp_push_est(lbp_state_t *st, float rb)
{
    st->hist_g[st->hist_pos] = rb;
    uint8_t nh = (uint8_t)(st->hist_pos + 1u);
    if (nh >= E2E_HIST_LEN) { nh = 0u; }
    st->hist_pos = nh;
    if (st->hist_cnt < E2E_HIST_LEN) { st->hist_cnt++; }

    const uint8_t cap = (uint8_t)(E2E_VEL_L + 1u);
    st->veh[st->veh_pos] = rb;
    uint8_t nv = (uint8_t)(st->veh_pos + 1u);
    if (nv >= cap) { nv = 0u; }
    st->veh_pos = nv;
    if (st->veh_cnt < cap) { st->veh_cnt++; }
}
