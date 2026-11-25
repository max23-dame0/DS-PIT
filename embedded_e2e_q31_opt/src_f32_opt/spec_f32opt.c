/* S2 optimized (f32-algo-opt): input-pruned 1024->4x256 DIF + Radix-4 256-pt DIF FFT */
#include <string.h>
#include "dspit_opt.h"
#include "e2e_f32opt_tables.h"

void spec_init(spec_state_t *st)
{
    memset(st, 0, sizeof(*st));
}

static void zscore_200(const float *ring, uint32_t start_idx, float *dst)
{
    float sum = 0.0f;
    for (uint32_t i = 0u; i < E2E_WS; i++) {
        sum += ring[(start_idx + i) & 255u];
    }
    const float mean = sum * (1.0f / 200.0f);
    float var_sum = 0.0f;
    for (uint32_t i = 0u; i < E2E_WS; i++) {
        const float d = ring[(start_idx + i) & 255u] - mean;
        dst[i] = d;
        var_sum += d * d;
    }
    const float inv_sd = 1.0f / (sqrtf(var_sum * (1.0f / 199.0f)) + R_EPS_F32);
    for (uint32_t i = 0u; i < E2E_WS; i++) {
        dst[i] *= inv_sd;
    }
}

static inline void w1024_f(uint32_t idx, float *wr, float *wi)
{
    idx &= 1023u;
    if (idx < 512u) {
        *wr = TWID_RE[idx];
        *wi = TWID_IM[idx];
    } else {
        *wr = -TWID_RE[idx - 512u];
        *wi = -TWID_IM[idx - 512u];
    }
}

static inline uint32_t digitrev4(uint32_t m)
{
    return ((m & 3u) << 6) | ((m & 0xCu) << 2) | ((m & 0x30u) >> 2) | ((m & 0xC0u) >> 6);
}

static void fft256_radix4_dif(float *re, float *im)
{
    /* Stages: n_sub = 256 (step 4), 64 (step 16), 16 (step 64) with twiddles; 4 (twiddle-free) */
    uint32_t n_sub = 256u;
    uint32_t step = 4u;
    while (n_sub > 4u) {
        const uint32_t quarter = n_sub >> 2u;
        for (uint32_t start = 0u; start < 256u; start += n_sub) {
            /* k = 0: twiddles all (1, 0) */
            {
                const uint32_t i0 = start;
                const uint32_t i1 = i0 + quarter;
                const uint32_t i2 = i1 + quarter;
                const uint32_t i3 = i2 + quarter;
                const float ar = re[i0], ai = im[i0];
                const float br = re[i1], bi = im[i1];
                const float cr = re[i2], ci = im[i2];
                const float dr = re[i3], di = im[i3];
                const float s0r = ar + cr, s0i = ai + ci;
                const float s1r = ar - cr, s1i = ai - ci;
                const float d0r = br + dr, d0i = bi + di;
                const float d1r = br - dr, d1i = bi - di;
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
                const float ar = re[i0], ai = im[i0];
                const float br = re[i1], bi = im[i1];
                const float cr = re[i2], ci = im[i2];
                const float dr = re[i3], di = im[i3];
                const float s0r = ar + cr, s0i = ai + ci;
                const float s1r = ar - cr, s1i = ai - ci;
                const float d0r = br + dr, d0i = bi + di;
                const float d1r = br - dr, d1i = bi - di;
                re[i0] = s0r + d0r; im[i0] = s0i + d0i;

                const float t1r = s1r + d1i, t1i = s1i - d1r;
                const float t2r = s0r - d0r, t2i = s0i - d0i;
                const float t3r = s1r - d1i, t3i = s1i + d1r;

                float wr, wi;
                const uint32_t ks = k * step;
                w1024_f(ks, &wr, &wi);
                re[i1] = t1r * wr - t1i * wi;
                im[i1] = t1r * wi + t1i * wr;

                w1024_f(ks << 1u, &wr, &wi);
                re[i2] = t2r * wr - t2i * wi;
                im[i2] = t2r * wi + t2i * wr;

                w1024_f(ks * 3u, &wr, &wi);
                re[i3] = t3r * wr - t3i * wi;
                im[i3] = t3r * wi + t3i * wr;
            }
        }
        n_sub >>= 2u;
        step <<= 2u;
    }

    /* Final stage n_sub == 4: twiddle-free */
    for (uint32_t i0 = 0u; i0 < 256u; i0 += 4u) {
        const float ar = re[i0],      ai = im[i0];
        const float br = re[i0 + 1u], bi = im[i0 + 1u];
        const float cr = re[i0 + 2u], ci = im[i0 + 2u];
        const float dr = re[i0 + 3u], di = im[i0 + 3u];
        const float s0r = ar + cr, s0i = ai + ci;
        const float s1r = ar - cr, s1i = ai - ci;
        const float d0r = br + dr, d0i = bi + di;
        const float d1r = br - dr, d1i = bi - di;
        re[i0]      = s0r + d0r; im[i0]      = s0i + d0i;
        re[i0 + 1u] = s1r + d1i; im[i0 + 1u] = s1i - d1r;
        re[i0 + 2u] = s0r - d0r; im[i0 + 2u] = s0i - d0i;
        re[i0 + 3u] = s1r - d1i; im[i0 + 3u] = s1i + d1r;
    }
}

static void pruned_fft1024(spec_state_t *st)
{
    /* Pass 0: z-scored samples already in fft_re/im[0..199] (q=0 in-place!) */
    for (uint32_t p = 0u; p < E2E_WS; p++) {
        const float xr = st->fft_re[p];
        const float xi = st->fft_im[p];

        float wr, wi;
        w1024_f(p, &wr, &wi);
        st->fft_re[256u + p] = xr * wr - xi * wi;
        st->fft_im[256u + p] = xr * wi + xi * wr;

        w1024_f(p << 1u, &wr, &wi);
        st->fft_re[512u + p] = xr * wr - xi * wi;
        st->fft_im[512u + p] = xr * wi + xi * wr;

        w1024_f(p * 3u, &wr, &wi);
        st->fft_re[768u + p] = xr * wr - xi * wi;
        st->fft_im[768u + p] = xr * wi + xi * wr;
    }
    for (uint32_t q = 0u; q < 4u; q++) {
        const uint32_t base = q << 8u;
        memset(st->fft_re + base + E2E_WS, 0, (256u - E2E_WS) * sizeof(float));
        memset(st->fft_im + base + E2E_WS, 0, (256u - E2E_WS) * sizeof(float));
        fft256_radix4_dif(st->fft_re + base, st->fft_im + base);
    }
}

static void unpack_pair_mag(const spec_state_t *st, float *mag_x, float *mag_y)
{
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const uint32_t k   = E2E_BIN_START + b;
        const uint32_t nk  = E2E_NFFT - k;
        const uint32_t pk  = ((k  & 3u) << 8u) | digitrev4(k  >> 2u);
        const uint32_t pnk = ((nk & 3u) << 8u) | digitrev4(nk >> 2u);

        const float r_k = st->fft_re[pk],  i_k = st->fft_im[pk];
        const float r_n = st->fft_re[pnk], i_n = st->fft_im[pnk];
        const float xr = 0.5f * (r_k + r_n);
        const float xi = 0.5f * (i_k - i_n);
        const float yr = 0.5f * (i_k + i_n);
        const float yi = 0.5f * (r_n - r_k);
        mag_x[b] = sqrtf(xr * xr + xi * xi);
        mag_y[b] = sqrtf(yr * yr + yi * yi);
    }
}

void spec_compute_window(spec_state_t *st,
                         const float win_buf[4][256],
                         uint32_t start_idx,
                         float sp_mag[E2E_NB],
                         float ap_mag[3][E2E_NB])
{
    zscore_200(win_buf[0], start_idx, st->fft_re);
    zscore_200(win_buf[1], start_idx, st->fft_im);
    pruned_fft1024(st);
    unpack_pair_mag(st, sp_mag, ap_mag[0]);

    zscore_200(win_buf[2], start_idx, st->fft_re);
    zscore_200(win_buf[3], start_idx, st->fft_im);
    pruned_fft1024(st);
    unpack_pair_mag(st, ap_mag[1], ap_mag[2]);
}
