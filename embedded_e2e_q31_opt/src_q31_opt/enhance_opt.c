/* S3 fixed-point (q31-full-opt): O(NB) history sum + fast integer log_q16 */
#include <string.h>
#include "dspit_opt.h"
#include "e2e_opt_tables.h"

void enhance_init(enhance_state_t *st)
{
    memset(st, 0, sizeof(*st));
}

static uint32_t isqrt64(uint64_t n)
{
    if (n == 0u) { return 0u; }
    uint64_t res = 0u;
    const uint32_t shift = (63u - (uint32_t)__builtin_clzll(n)) & ~1u;
    uint64_t bit = 1ULL << shift;
    while (bit != 0u) {
        if (n >= res + bit) {
            n -= res + bit;
            res = (res >> 1u) + bit;
        } else {
            res >>= 1u;
        }
        bit >>= 2u;
    }
    return (uint32_t)res;
}

static int32_t vec_std_q21(const int32_t *v)
{
    int64_t sum = 0;
    for (uint32_t b = 0u; b < E2E_NB; b++) { sum += (int64_t)v[b]; }
    const int32_t mean = (int32_t)(sum / 92);
    uint64_t vs = 0u;
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const int64_t d = (int64_t)v[b] - (int64_t)mean;
        vs += (uint64_t)(d * d);
    }
    return (int32_t)isqrt64(vs / 91u);
}

/* Compute ln(v) in Q15.16 for v in Q1.30 (v_q30 > 0), accuracy ~1.2e-6 */
static int32_t log_q16(uint32_t v_q30)
{
    if (v_q30 == 0u) { v_q30 = 1u; }
    const uint32_t lz = (uint32_t)__builtin_clz(v_q30);
    uint32_t m_q30 = (v_q30 << lz) >> 1u; /* [1.0, 2.0) * 2^30 */
    int32_t e = 1 - (int32_t)lz;
    if (m_q30 >= 1518500250u) {           /* sqrt(2) * 2^30 */
        m_q30 >>= 1u;
        e += 1;
    }
    const int64_t diff = (int64_t)m_q30 - (int64_t)(1u << 30);
    const int64_t sum  = (int64_t)m_q30 + (int64_t)(1u << 30);
    const int32_t u    = (int32_t)((diff << 30) / sum);
    const int32_t u2   = (int32_t)(((int64_t)u * u) >> 30);
    const int32_t u3   = (int32_t)(((int64_t)u2 * u) >> 30);
    const int32_t u5   = (int32_t)(((int64_t)u3 * u2) >> 30);
    /* ln(m) = 2*(u + u^3/3 + u^5/5) in Q30; 2^31/3 = 715827883, 2^31/5 = 429496730 */
    const int64_t term = (int64_t)u + (((int64_t)u3 * 715827883LL) >> 31)
                                    + (((int64_t)u5 * 429496730LL) >> 31);
    const int64_t lnm_q30 = term << 1;
    /* ln(2) * 2^30 = 744261118 */
    const int64_t ln_q30 = (int64_t)e * 744261118LL + lnm_q30;
    return (int32_t)((ln_q30 + (ln_q30 >= 0 ? (1LL << 13) : -(1LL << 13))) >> 14);
}

void enhance_window_q(enhance_state_t *st,
                      const int32_t sp_mag_q21[E2E_NB],
                      const int32_t ap_mag_q21[3][E2E_NB],
                      int32_t obv_q16[E2E_NB],
                      int32_t psp_q30[E2E_K],
                      int32_t logL_q16[E2E_K])
{
    int32_t sp_max = 0;
    int32_t a0_max = 0, a1_max = 0, a2_max = 0;
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        if (sp_mag_q21[b] > sp_max)     { sp_max = sp_mag_q21[b]; }
        if (ap_mag_q21[0][b] > a0_max)  { a0_max = ap_mag_q21[0][b]; }
        if (ap_mag_q21[1][b] > a1_max)  { a1_max = ap_mag_q21[1][b]; }
        if (ap_mag_q21[2][b] > a2_max)  { a2_max = ap_mag_q21[2][b]; }
    }
    if (sp_max <= 0) { sp_max = 1; }
    if (a0_max <= 0) { a0_max = 1; }
    if (a1_max <= 0) { a1_max = 1; }
    if (a2_max <= 0) { a2_max = 1; }

    /* Normalize sp_mag / sp_max -> Q5.26 with 1 division */
    const uint64_t inv_sp = (1ULL << 56) / (uint64_t)sp_max;
    int32_t *slot = st->w_hist[st->hist_pos];
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const int32_t next_q26 = (int32_t)(((uint64_t)sp_mag_q21[b] * inv_sp) >> 30);
        st->w_sum[b] += next_q26 - slot[b];
        slot[b] = next_q26;
    }
    uint8_t next_pos = (uint8_t)(st->hist_pos + 1u);
    if (next_pos >= E2E_WF_LEN) { next_pos = 0u; }
    st->hist_pos = next_pos;
    if (st->hist_cnt < E2E_WF_LEN) { st->hist_cnt++; }

    int32_t w1n[E2E_NB];
    int32_t w1n_max = 0;
    const uint32_t cnt = (uint32_t)st->hist_cnt;
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const int32_t v = (int32_t)(st->w_sum[b] / (int32_t)cnt);
        w1n[b] = v;
        if (v > w1n_max) { w1n_max = v; }
    }
    if (w1n_max <= 0) { w1n_max = 1; }

    /* Map w1n and ap_mag ratios onto common Q1.30 using 1 division per vector */
    const uint64_t inv_w1n = (1ULL << 60) / (uint64_t)w1n_max;
    const uint64_t inv_a0  = (1ULL << 60) / (uint64_t)a0_max;
    const uint64_t inv_a1  = (1ULL << 60) / (uint64_t)a1_max;
    const uint64_t inv_a2  = (1ULL << 60) / (uint64_t)a2_max;

    int32_t c1[E2E_NB];
    int32_t c2[E2E_NB];
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const uint32_t a0n = (uint32_t)(((uint64_t)ap_mag_q21[0][b] * inv_a0) >> 30);
        const uint32_t a1n = (uint32_t)(((uint64_t)ap_mag_q21[1][b] * inv_a1) >> 30);
        const uint32_t a2n = (uint32_t)(((uint64_t)ap_mag_q21[2][b] * inv_a2) >> 30);
        const uint32_t accn = (uint32_t)((((uint64_t)a0n + a1n + a2n) * 1431655766ULL) >> 32);
        const uint32_t wn   = (uint32_t)(((uint64_t)w1n[b] * inv_w1n) >> 30);

        if (accn >= wn) {
            c1[b] = -sp_mag_q21[b];
        } else {
            const uint32_t base = (uint32_t)(((uint64_t)accn << 30) / wn);
            const int32_t wf1   = (int32_t)((1u << 30) - base);
            c1[b] = (int32_t)(((int64_t)sp_mag_q21[b] * wf1) >> 30);
        }

        const uint64_t den = (uint64_t)accn + (uint64_t)wn;
        if (den == 0u) {
            c2[b] = 0;
        } else {
            const int32_t wf2 = (int32_t)(((uint64_t)wn << 30) / den);
            c2[b] = (int32_t)(((int64_t)sp_mag_q21[b] * wf2) >> 30);
        }
    }

    int32_t s1 = vec_std_q21(c1);
    int32_t s2 = vec_std_q21(c2);
    if (s1 <= 0) { s1 = 1; }
    if (s2 <= 0) { s2 = 1; }
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const int32_t n1 = (int32_t)(((int64_t)c1[b] << 16) / (int64_t)s1);
        const int32_t n2 = (int32_t)(((int64_t)c2[b] << 16) / (int64_t)s2);
        obv_q16[b] = n1 + n2;
    }

    int32_t p_min =  0x7FFFFFFF;
    int32_t p_max = -0x7FFFFFFF;
    for (uint32_t j = 0u; j < E2E_K; j++) {
        const int16_t idx = INTERP_IDX[j];
        int32_t v_q16 = 0;
        if (idx >= 0) {
            const int32_t o0 = obv_q16[idx];
            const int32_t o1 = obv_q16[idx + 1];
            v_q16 = o0 + (int32_t)(((int64_t)INTERP_W_Q30[j] * (int64_t)(o1 - o0) + (1LL << 29)) >> 30);
        }
        v_q16 = (int32_t)(((int64_t)v_q16 * (int64_t)TAPER_Q30[j] + (1LL << 29)) >> 30);
        psp_q30[j] = v_q16; /* temporarily hold Q15.16 */
        if (v_q16 < p_min) { p_min = v_q16; }
        if (v_q16 > p_max) { p_max = v_q16; }
    }

    const int64_t span = (int64_t)p_max - (int64_t)p_min;
    const uint64_t u_span = (span > 0) ? (uint64_t)span : 1ULL;
    const uint64_t inv_span = (1ULL << 60) / u_span;
    for (uint32_t j = 0u; j < E2E_K; j++) {
        const uint64_t d = (uint64_t)((int64_t)psp_q30[j] - (int64_t)p_min);
        const uint32_t pn_q30 = (uint32_t)((d * inv_span) >> 30);
        psp_q30[j] = (int32_t)pn_q30;
        /* +1e-6 * 2^30 = 1074 */
        logL_q16[j] = log_q16(pn_q30 + 1074u);
    }
}
