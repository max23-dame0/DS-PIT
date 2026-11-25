/* S3: Two-branch amplitude-ratio enhancement + interpolation + taper + logL */
#include <string.h>
#include "dspit_e2e.h"
#include "e2e_tables.h"

void enhance_init(enhance_state_t *st)
{
    memset(st, 0, sizeof(*st));
}

static real_t vec_std_nb(const real_t *v)
{
    real_t sum = R_LIT(0.0);
    for (uint32_t b = 0u; b < E2E_NB; b++) { sum += v[b]; }
    const real_t mean = sum / R_LIT(92.0);
    real_t vs = R_LIT(0.0);
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const real_t d = v[b] - mean;
        vs += d * d;
    }
    return R_SQRT(vs / R_LIT(91.0));
}

void enhance_window(enhance_state_t *st,
                    const real_t sp_mag[E2E_NB],
                    const real_t ap_mag[3][E2E_NB],
                    real_t obv_out[E2E_NB],
                    real_t psp_out[E2E_K],
                    real_t l_out[E2E_K],
                    real_t logL_out[E2E_K])
{
    real_t sp_max = R_LIT(0.0);
    real_t a_max[3] = { R_LIT(0.0), R_LIT(0.0), R_LIT(0.0) };
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        if (sp_mag[b] > sp_max) { sp_max = sp_mag[b]; }
        for (uint8_t j = 0u; j < 3u; j++) {
            if (ap_mag[j][b] > a_max[j]) { a_max[j] = ap_mag[j][b]; }
        }
    }

    const real_t inv_sp_max = R_LIT(1.0) / (sp_max + R_EPS);
    real_t *slot = st->w_hist[st->hist_pos];
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        slot[b] = sp_mag[b] * inv_sp_max;
    }
    st->hist_pos = (uint8_t)((st->hist_pos + 1u) % E2E_WF_LEN);
    if (st->hist_cnt < E2E_WF_LEN) { st->hist_cnt++; }

    real_t w1n[E2E_NB];
    real_t w1n_max = R_LIT(0.0);
    const real_t inv_cnt = R_LIT(1.0) / (real_t)st->hist_cnt;
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        real_t s = R_LIT(0.0);
        for (uint8_t r = 0u; r < st->hist_cnt; r++) {
            s += st->w_hist[r][b];
        }
        w1n[b] = s * inv_cnt;
        if (w1n[b] > w1n_max) { w1n_max = w1n[b]; }
    }
    const real_t inv_w1n_max = R_LIT(1.0) / (w1n_max + R_EPS);
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        w1n[b] *= inv_w1n_max;
    }

    const real_t inv_a0 = R_LIT(1.0) / (a_max[0] + R_EPS);
    const real_t inv_a1 = R_LIT(1.0) / (a_max[1] + R_EPS);
    const real_t inv_a2 = R_LIT(1.0) / (a_max[2] + R_EPS);

    real_t c1[E2E_NB];
    real_t c2[E2E_NB];
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const real_t accn = (ap_mag[0][b] * inv_a0 +
                             ap_mag[1][b] * inv_a1 +
                             ap_mag[2][b] * inv_a2) / R_LIT(3.0);
        const real_t wn = w1n[b];
        const real_t base = accn / (wn + R_EPS);
        real_t wf1 = R_LIT(1.0) - base;
        if (wf1 < R_LIT(0.0)) { wf1 = R_LIT(-1.0); }
        c1[b] = sp_mag[b] * wf1;
        c2[b] = sp_mag[b] * (wn / (accn + wn + R_EPS));
    }

    const real_t inv_s1 = R_LIT(1.0) / (vec_std_nb(c1) + R_EPS);
    const real_t inv_s2 = R_LIT(1.0) / (vec_std_nb(c2) + R_EPS);
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        obv_out[b] = c1[b] * inv_s1 + c2[b] * inv_s2;
    }

    /* Interpolate onto K=161 BPM states + 30-BPM edge taper */
    real_t p_min = R_LIT(1e30);
    real_t p_max = R_LIT(-1e30);
    for (uint32_t j = 0u; j < E2E_K; j++) {
        const int16_t idx = INTERP_IDX[j];
        real_t v = R_LIT(0.0);
        if (idx >= 0) {
            v = obv_out[idx] + INTERP_W[j] * (obv_out[idx + 1] - obv_out[idx]);
        }
        v *= TAPER[j];
        psp_out[j] = v;
        if (v < p_min) { p_min = v; }
        if (v > p_max) { p_max = v; }
    }

    /* Normalize Psp and L (= Psp norm + 1e-6) */
    const real_t inv_span1 = R_LIT(1.0) / (p_max - p_min + R_EPS);
    real_t l_min = R_LIT(1e30);
    real_t l_max = R_LIT(-1e30);
    for (uint32_t j = 0u; j < E2E_K; j++) {
        const real_t pn = (psp_out[j] - p_min) * inv_span1;
        psp_out[j] = pn;
        if (pn < l_min) { l_min = pn; }
        if (pn > l_max) { l_max = pn; }
    }

    const real_t inv_span2 = R_LIT(1.0) / (l_max - l_min + R_EPS);
    for (uint32_t j = 0u; j < E2E_K; j++) {
        const real_t lv = (psp_out[j] - l_min) * inv_span2 + R_LIT(1e-6);
        l_out[j] = lv;
        logL_out[j] = R_LOG(lv);
    }
}
