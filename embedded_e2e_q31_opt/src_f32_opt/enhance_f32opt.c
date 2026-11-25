/* S3 optimized (f32-algo-opt): O(NB) incremental history sum */
#include <string.h>
#include "dspit_opt.h"
#include "e2e_f32opt_tables.h"

void enhance_init(enhance_state_t *st)
{
    memset(st, 0, sizeof(*st));
}

static float vec_std_nb(const float *v)
{
    float sum = 0.0f;
    for (uint32_t b = 0u; b < E2E_NB; b++) { sum += v[b]; }
    const float mean = sum * (1.0f / 92.0f);
    float vs = 0.0f;
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const float d = v[b] - mean;
        vs += d * d;
    }
    return sqrtf(vs * (1.0f / 91.0f));
}

void enhance_window(enhance_state_t *st,
                    const float sp_mag[E2E_NB],
                    const float ap_mag[3][E2E_NB],
                    float obv_out[E2E_NB],
                    float psp_out[E2E_K],
                    float logL_out[E2E_K])
{
    float sp_max = 0.0f;
    float a0_max = 0.0f, a1_max = 0.0f, a2_max = 0.0f;
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        if (sp_mag[b] > sp_max)     { sp_max = sp_mag[b]; }
        if (ap_mag[0][b] > a0_max)  { a0_max = ap_mag[0][b]; }
        if (ap_mag[1][b] > a1_max)  { a1_max = ap_mag[1][b]; }
        if (ap_mag[2][b] > a2_max)  { a2_max = ap_mag[2][b]; }
    }

    const float inv_sp_max = 1.0f / (sp_max + R_EPS_F32);
    float *slot = st->w_hist[st->hist_pos];
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const float next_val = sp_mag[b] * inv_sp_max;
        st->w_sum[b] += next_val - slot[b];
        slot[b] = next_val;
    }
    uint8_t next_pos = (uint8_t)(st->hist_pos + 1u);
    if (next_pos >= E2E_WF_LEN) { next_pos = 0u; }
    st->hist_pos = next_pos;
    if (st->hist_cnt < E2E_WF_LEN) { st->hist_cnt++; }

    float w1n[E2E_NB];
    float w1n_max = 0.0f;
    const float inv_cnt = 1.0f / (float)st->hist_cnt;
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const float v = st->w_sum[b] * inv_cnt;
        w1n[b] = v;
        if (v > w1n_max) { w1n_max = v; }
    }
    const float inv_w1n_max = 1.0f / (w1n_max + R_EPS_F32);
    const float inv_a0 = 1.0f / (a0_max + R_EPS_F32);
    const float inv_a1 = 1.0f / (a1_max + R_EPS_F32);
    const float inv_a2 = 1.0f / (a2_max + R_EPS_F32);
    const float inv3 = 1.0f / 3.0f;

    float c1[E2E_NB];
    float c2[E2E_NB];
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const float accn = (ap_mag[0][b] * inv_a0 +
                            ap_mag[1][b] * inv_a1 +
                            ap_mag[2][b] * inv_a2) * inv3;
        const float wn = w1n[b] * inv_w1n_max;
        const float base = accn / (wn + R_EPS_F32);
        float wf1 = 1.0f - base;
        if (wf1 < 0.0f) { wf1 = -1.0f; }
        c1[b] = sp_mag[b] * wf1;
        c2[b] = sp_mag[b] * (wn / (accn + wn + R_EPS_F32));
    }

    const float inv_s1 = 1.0f / (vec_std_nb(c1) + R_EPS_F32);
    const float inv_s2 = 1.0f / (vec_std_nb(c2) + R_EPS_F32);
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        obv_out[b] = c1[b] * inv_s1 + c2[b] * inv_s2;
    }

    float p_min = 1e30f;
    float p_max = -1e30f;
    for (uint32_t j = 0u; j < E2E_K; j++) {
        const int16_t idx = INTERP_IDX[j];
        float v = 0.0f;
        if (idx >= 0) {
            v = obv_out[idx] + INTERP_W[j] * (obv_out[idx + 1] - obv_out[idx]);
        }
        v *= TAPER[j];
        psp_out[j] = v;
        if (v < p_min) { p_min = v; }
        if (v > p_max) { p_max = v; }
    }

    const float inv_span = 1.0f / (p_max - p_min + R_EPS_F32);
    for (uint32_t j = 0u; j < E2E_K; j++) {
        const float pn = (psp_out[j] - p_min) * inv_span;
        psp_out[j] = pn;
        logL_out[j] = logf(pn + 1e-6f);
    }
}
