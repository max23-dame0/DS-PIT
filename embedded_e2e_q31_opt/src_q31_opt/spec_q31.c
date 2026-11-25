/* S2 fixed-point (q31-full-opt): integer z-score + pruned 1024->4x256 Radix-4 DIF FFT */
#include <string.h>
#include "dspit_opt.h"
#include "e2e_opt_tables.h"

void spec_init(spec_state_t *st)
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

static void zscore_200_q21(const int32_t *ring, uint32_t start_idx, int32_t *dst_q21)
{
    int64_t sum = 0;
    for (uint32_t i = 0u; i < E2E_WS; i++) {
        sum += (int64_t)ring[(start_idx + i) & 255u];
    }
    const int32_t mean_q = (int32_t)((sum + (sum >= 0 ? 100 : -100)) / 200);

    uint32_t max_abs = 0u;
    for (uint32_t i = 0u; i < E2E_WS; i++) {
        const int32_t d = ring[(start_idx + i) & 255u] - mean_q;
        dst_q21[i] = d;
        const uint32_t ad = (d >= 0) ? (uint32_t)d : (uint32_t)(-d);
        if (ad > max_abs) { max_abs = ad; }
    }
    if (max_abs == 0u) {
        memset(dst_q21, 0, E2E_WS * sizeof(int32_t));
        return;
    }

    /* Auto-normalize d so max(|d_norm|) sits in [2^23, 2^24) -> exact sum(d_norm^2) < 2^56 << 2^64 */
    const uint32_t lz = (uint32_t)__builtin_clz(max_abs); /* bit_len = 32 - lz */
    const int32_t adj = (int32_t)lz - 8;                  /* shift to map max_abs near 2^23..2^24 */
    uint64_t var_sum = 0u;
    for (uint32_t i = 0u; i < E2E_WS; i++) {
        const int64_t dn = (adj >= 0) ? ((int64_t)dst_q21[i] << adj) : ((int64_t)dst_q21[i] >> (-adj));
        var_sum += (uint64_t)(dn * dn);
    }
    const uint32_t sd_norm = isqrt64(var_sum / 199u);
    if (sd_norm == 0u) {
        memset(dst_q21, 0, E2E_WS * sizeof(int32_t));
        return;
    }
    /* dn = d * 2^adj, sd_norm ~ std(d) * 2^adj -> (dn * (2^45 / sd_norm)) >> 24 = (d / std) * 2^21 */
    const uint64_t inv_sd = (1ULL << 45) / (uint64_t)sd_norm;
    for (uint32_t i = 0u; i < E2E_WS; i++) {
        const int64_t dn = (adj >= 0) ? ((int64_t)dst_q21[i] << adj) : ((int64_t)dst_q21[i] >> (-adj));
        dst_q21[i] = (int32_t)((dn * (int64_t)inv_sd) >> 24);
    }
}

static inline int32_t qmul31(int32_t a, int32_t b)
{
    return (int32_t)(((int64_t)a * (int64_t)b + (1LL << 30)) >> 31);
}

static inline void w1024_q31(uint32_t idx, int32_t *wr, int32_t *wi)
{
    idx &= 1023u;
    if (idx < 512u) {
        *wr = TWID_RE_Q31[idx];
        *wi = TWID_IM_Q31[idx];
    } else {
        *wr = -TWID_RE_Q31[idx - 512u];
        *wi = -TWID_IM_Q31[idx - 512u];
    }
}

static inline uint32_t digitrev4(uint32_t m)
{
    return ((m & 3u) << 6) | ((m & 0xCu) << 2) | ((m & 0x30u) >> 2) | ((m & 0xC0u) >> 6);
}

static void fft256_radix4_dif_q21(int32_t *re, int32_t *im)
{
    uint32_t n_sub = 256u;
    uint32_t step = 4u;
    while (n_sub > 4u) {
        const uint32_t quarter = n_sub >> 2u;
        for (uint32_t start = 0u; start < 256u; start += n_sub) {
            {
                const uint32_t i0 = start;
                const uint32_t i1 = i0 + quarter;
                const uint32_t i2 = i1 + quarter;
                const uint32_t i3 = i2 + quarter;
                const int32_t ar = re[i0], ai = im[i0];
                const int32_t br = re[i1], bi = im[i1];
                const int32_t cr = re[i2], ci = im[i2];
                const int32_t dr = re[i3], di = im[i3];
                const int32_t s0r = ar + cr, s0i = ai + ci;
                const int32_t s1r = ar - cr, s1i = ai - ci;
                const int32_t d0r = br + dr, d0i = bi + di;
                const int32_t d1r = br - dr, d1i = bi - di;
                re[i0] = s0r + d0r; im[i0] = s0i + d0i;
                re[i1] = s1r + d1i; im[i1] = s1i - d1r;
                re[i2] = s0r - d0r; im[i2] = s0i - d0i;
                re[i3] = s1r - d1i; im[i3] = s1i + d1r;
            }
            for (uint32_t k = 1u; k < quarter; k++) {
                const uint32_t i0 = start + k;
                const uint32_t i1 = i0 + quarter;
                const uint32_t i2 = i1 + quarter;
                const uint32_t i3 = i2 + quarter;
                const int32_t ar = re[i0], ai = im[i0];
                const int32_t br = re[i1], bi = im[i1];
                const int32_t cr = re[i2], ci = im[i2];
                const int32_t dr = re[i3], di = im[i3];
                const int32_t s0r = ar + cr, s0i = ai + ci;
                const int32_t s1r = ar - cr, s1i = ai - ci;
                const int32_t d0r = br + dr, d0i = bi + di;
                const int32_t d1r = br - dr, d1i = bi - di;
                re[i0] = s0r + d0r; im[i0] = s0i + d0i;

                const int32_t t1r = s1r + d1i, t1i = s1i - d1r;
                const int32_t t2r = s0r - d0r, t2i = s0i - d0i;
                const int32_t t3r = s1r - d1i, t3i = s1i + d1r;

                int32_t wr, wi;
                const uint32_t ks = k * step;
                w1024_q31(ks, &wr, &wi);
                re[i1] = qmul31(t1r, wr) - qmul31(t1i, wi);
                im[i1] = qmul31(t1r, wi) + qmul31(t1i, wr);

                w1024_q31(ks << 1u, &wr, &wi);
                re[i2] = qmul31(t2r, wr) - qmul31(t2i, wi);
                im[i2] = qmul31(t2r, wi) + qmul31(t2i, wr);

                w1024_q31(ks * 3u, &wr, &wi);
                re[i3] = qmul31(t3r, wr) - qmul31(t3i, wi);
                im[i3] = qmul31(t3r, wi) + qmul31(t3i, wr);
            }
        }
        n_sub >>= 2u;
        step <<= 2u;
    }

    for (uint32_t i0 = 0u; i0 < 256u; i0 += 4u) {
        const int32_t ar = re[i0],      ai = im[i0];
        const int32_t br = re[i0 + 1u], bi = im[i0 + 1u];
        const int32_t cr = re[i0 + 2u], ci = im[i0 + 2u];
        const int32_t dr = re[i0 + 3u], di = im[i0 + 3u];
        const int32_t s0r = ar + cr, s0i = ai + ci;
        const int32_t s1r = ar - cr, s1i = ai - ci;
        const int32_t d0r = br + dr, d0i = bi + di;
        const int32_t d1r = br - dr, d1i = bi - di;
        re[i0]      = s0r + d0r; im[i0]      = s0i + d0i;
        re[i0 + 1u] = s1r + d1i; im[i0 + 1u] = s1i - d1r;
        re[i0 + 2u] = s0r - d0r; im[i0 + 2u] = s0i - d0i;
        re[i0 + 3u] = s1r - d1i; im[i0 + 3u] = s1i + d1r;
    }
}

static void pruned_fft1024_q21(spec_state_t *st)
{
    for (uint32_t p = 0u; p < E2E_WS; p++) {
        const int32_t xr = st->fft_re[p];
        const int32_t xi = st->fft_im[p];

        int32_t wr, wi;
        w1024_q31(p, &wr, &wi);
        st->fft_re[256u + p] = qmul31(xr, wr) - qmul31(xi, wi);
        st->fft_im[256u + p] = qmul31(xr, wi) + qmul31(xi, wr);

        w1024_q31(p << 1u, &wr, &wi);
        st->fft_re[512u + p] = qmul31(xr, wr) - qmul31(xi, wi);
        st->fft_im[512u + p] = qmul31(xr, wi) + qmul31(xi, wr);

        w1024_q31(p * 3u, &wr, &wi);
        st->fft_re[768u + p] = qmul31(xr, wr) - qmul31(xi, wi);
        st->fft_im[768u + p] = qmul31(xr, wi) + qmul31(xi, wr);
    }
    for (uint32_t q = 0u; q < 4u; q++) {
        const uint32_t base = q << 8u;
        memset(st->fft_re + base + E2E_WS, 0, (256u - E2E_WS) * sizeof(int32_t));
        memset(st->fft_im + base + E2E_WS, 0, (256u - E2E_WS) * sizeof(int32_t));
        fft256_radix4_dif_q21(st->fft_re + base, st->fft_im + base);
    }
}

static void unpack_pair_mag_q21(const spec_state_t *st, int32_t *mag_x_q21, int32_t *mag_y_q21)
{
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const uint32_t k   = E2E_BIN_START + b;
        const uint32_t nk  = E2E_NFFT - k;
        const uint32_t pk  = ((k  & 3u) << 8u) | digitrev4(k  >> 2u);
        const uint32_t pnk = ((nk & 3u) << 8u) | digitrev4(nk >> 2u);

        const int32_t r_k = st->fft_re[pk],  i_k = st->fft_im[pk];
        const int32_t r_n = st->fft_re[pnk], i_n = st->fft_im[pnk];
        const int64_t xr = ((int64_t)r_k + (int64_t)r_n) >> 1;
        const int64_t xi = ((int64_t)i_k - (int64_t)i_n) >> 1;
        const int64_t yr = ((int64_t)i_k + (int64_t)i_n) >> 1;
        const int64_t yi = ((int64_t)r_n - (int64_t)r_k) >> 1;
        mag_x_q21[b] = (int32_t)isqrt64((uint64_t)(xr * xr + xi * xi));
        mag_y_q21[b] = (int32_t)isqrt64((uint64_t)(yr * yr + yi * yi));
    }
}

void spec_compute_window_q21(spec_state_t *st,
                             const int32_t win_buf[4][256],
                             uint32_t start_idx,
                             int32_t sp_mag_q21[E2E_NB],
                             int32_t ap_mag_q21[3][E2E_NB])
{
    zscore_200_q21(win_buf[0], start_idx, st->fft_re);
    zscore_200_q21(win_buf[1], start_idx, st->fft_im);
    pruned_fft1024_q21(st);
    unpack_pair_mag_q21(st, sp_mag_q21, ap_mag_q21[0]);

    zscore_200_q21(win_buf[2], start_idx, st->fft_re);
    zscore_200_q21(win_buf[3], start_idx, st->fft_im);
    pruned_fft1024_q21(st);
    unpack_pair_mag_q21(st, ap_mag_q21[1], ap_mag_q21[2]);
}
