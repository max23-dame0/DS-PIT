/* S2: Window z-score + 1024-pt real-packed radix-2 DIT FFT + band magnitude */
#include <string.h>
#include "dspit_e2e.h"
#include "e2e_tables.h"

void spec_init(spec_state_t *st)
{
    memset(st, 0, sizeof(*st));
}

static void zscore_into(const real_t *ring, uint32_t start_idx, real_t *dst)
{
    real_t sum = R_LIT(0.0);
    for (uint32_t i = 0u; i < E2E_WS; i++) {
        sum += ring[(start_idx + i) & 255u];
    }
    const real_t mean = sum / R_LIT(200.0);
    real_t var_sum = R_LIT(0.0);
    for (uint32_t i = 0u; i < E2E_WS; i++) {
        const real_t d = ring[(start_idx + i) & 255u] - mean;
        dst[i] = d;
        var_sum += d * d;
    }
    const real_t inv_sd = R_LIT(1.0) / (R_SQRT(var_sum / R_LIT(199.0)) + R_EPS);
    for (uint32_t i = 0u; i < E2E_WS; i++) {
        dst[i] *= inv_sd;
    }
    for (uint32_t i = E2E_WS; i < E2E_NFFT; i++) {
        dst[i] = R_LIT(0.0);
    }
}

static void fft1024(real_t *re, real_t *im)
{
    /* Bit-reversal permutation for N = 1024 (10 bits) */
    uint32_t j = 0u;
    for (uint32_t i = 1u; i < E2E_NFFT; i++) {
        uint32_t bit = E2E_NFFT >> 1u;
        while (j & bit) {
            j ^= bit;
            bit >>= 1u;
        }
        j ^= bit;
        if (i < j) {
            real_t tr = re[i]; re[i] = re[j]; re[j] = tr;
            real_t ti = im[i]; im[i] = im[j]; im[j] = ti;
        }
    }

    /* Iterative Cooley-Tukey DIT butterflies */
    for (uint32_t len = 2u; len <= E2E_NFFT; len <<= 1u) {
        const uint32_t half = len >> 1u;
        const uint32_t step = E2E_NFFT / len;
        for (uint32_t i = 0u; i < E2E_NFFT; i += len) {
            uint32_t tw_idx = 0u;
            for (uint32_t k = 0u; k < half; k++) {
                const real_t wr = TWID_RE[tw_idx];
                const real_t wi = TWID_IM[tw_idx];
                const uint32_t i0 = i + k;
                const uint32_t i1 = i0 + half;
                const real_t tr = re[i1] * wr - im[i1] * wi;
                const real_t ti = re[i1] * wi + im[i1] * wr;
                re[i1] = re[i0] - tr;
                im[i1] = im[i0] - ti;
                re[i0] += tr;
                im[i0] += ti;
                tw_idx += step;
            }
        }
    }
}

static void unpack_pair_mag(const real_t *re, const real_t *im,
                            real_t *mag_x, real_t *mag_y)
{
    for (uint32_t b = 0u; b < E2E_NB; b++) {
        const uint32_t k  = E2E_BIN_START + b;
        const uint32_t nk = E2E_NFFT - k;
        const real_t xr = R_LIT(0.5) * (re[k] + re[nk]);
        const real_t xi = R_LIT(0.5) * (im[k] - im[nk]);
        const real_t yr = R_LIT(0.5) * (im[k] + im[nk]);
        const real_t yi = R_LIT(0.5) * (re[nk] - re[k]);
        mag_x[b] = R_SQRT(xr * xr + xi * xi);
        mag_y[b] = R_SQRT(yr * yr + yi * yi);
    }
}

void spec_compute_window(spec_state_t *st,
                         const real_t win_buf[4][256],
                         uint32_t start_idx,
                         real_t sp_mag[E2E_NB],
                         real_t ap_mag[3][E2E_NB])
{
    /* Pair 1: PPG (real) + ACC_x (imag) */
    zscore_into(win_buf[0], start_idx, st->fft_re);
    zscore_into(win_buf[1], start_idx, st->fft_im);
    fft1024(st->fft_re, st->fft_im);
    unpack_pair_mag(st->fft_re, st->fft_im, sp_mag, ap_mag[0]);

    /* Pair 2: ACC_y (real) + ACC_z (imag) */
    zscore_into(win_buf[2], start_idx, st->fft_re);
    zscore_into(win_buf[3], start_idx, st->fft_im);
    fft1024(st->fft_re, st->fft_im);
    unpack_pair_mag(st->fft_re, st->fft_im, ap_mag[1], ap_mag[2]);
}
