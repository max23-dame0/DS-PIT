/* S1a fixed-point (q31-full-opt): Q11.20 I/O + Q50 DF-II-T state + unit-numerator SOS */
#include <string.h>
#include "dspit_opt.h"
#include "e2e_opt_tables.h"

void fe_filter_init(fe_filter_t *st)
{
    memset(st, 0, sizeof(*st));
}

int32_t fe_filter_sample_q20(fe_filter_t *st, uint8_t ch, uint8_t mode, int32_t x_q20)
{
    const int32_t b0 = (mode == E2E_MODE_DALIA) ? SOS_DALIA_B0_Q40 : SOS_WESAD_B0_Q40;
    const int32_t (*a)[2] = (mode == E2E_MODE_DALIA) ? SOS_DALIA_A_Q30 : SOS_WESAD_A_Q30;
    int64_t (*z)[2] = st->z[ch];

    /* Stage 0: b0 in Q40, x in Q20 -> Q60 >> 10 = Q50 */
    const int64_t b0x_50 = ((int64_t)b0 * (int64_t)x_q20) >> 10;
    int64_t y50 = b0x_50 + z[0][0];
    int32_t y20 = (int32_t)((y50 + (1LL << 29)) >> 30);
    z[0][0] = (b0x_50 << 1) - (int64_t)a[0][0] * (int64_t)y20 + z[0][1];
    z[0][1] = b0x_50 - (int64_t)a[0][1] * (int64_t)y20;
    int64_t v20 = (int64_t)y20;

    /* Stage 1: b = (1, +2, 1) */
    y50 = (v20 << 30) + z[1][0];
    y20 = (int32_t)((y50 + (1LL << 29)) >> 30);
    z[1][0] = (v20 << 31) - (int64_t)a[1][0] * (int64_t)y20 + z[1][1];
    z[1][1] = (v20 << 30) - (int64_t)a[1][1] * (int64_t)y20;
    v20 = (int64_t)y20;

    /* Stage 2: b = (1, -2, 1) */
    y50 = (v20 << 30) + z[2][0];
    y20 = (int32_t)((y50 + (1LL << 29)) >> 30);
    z[2][0] = -(v20 << 31) - (int64_t)a[2][0] * (int64_t)y20 + z[2][1];
    z[2][1] = (v20 << 30) - (int64_t)a[2][1] * (int64_t)y20;
    v20 = (int64_t)y20;

    /* Stage 3: b = (1, -2, 1) */
    y50 = (v20 << 30) + z[3][0];
    y20 = (int32_t)((y50 + (1LL << 29)) >> 30);
    z[3][0] = -(v20 << 31) - (int64_t)a[3][0] * (int64_t)y20 + z[3][1];
    z[3][1] = (v20 << 30) - (int64_t)a[3][1] * (int64_t)y20;
    return y20;
}
