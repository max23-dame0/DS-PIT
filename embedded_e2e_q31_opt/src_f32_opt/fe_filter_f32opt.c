/* S1a optimized (f32-algo-opt): unit-numerator SOS DF-II-T (9 muls/sample vs 20) */
#include <string.h>
#include "dspit_opt.h"
#include "e2e_f32opt_tables.h"

void fe_filter_init(fe_filter_t *st)
{
    memset(st, 0, sizeof(*st));
}

float fe_filter_sample(fe_filter_t *st, uint8_t ch, uint8_t mode, float x)
{
    const float b0 = (mode == E2E_MODE_DALIA) ? SOS_DALIA_B0 : SOS_WESAD_B0;
    const float (*a)[2] = (mode == E2E_MODE_DALIA) ? SOS_DALIA_A : SOS_WESAD_A;
    float (*z)[2] = st->z[ch];

    /* Stage 0: b = (b0, 2*b0, b0) */
    const float b0x = b0 * x;
    float y = b0x + z[0][0];
    z[0][0] = (b0x + b0x) - a[0][0] * y + z[0][1];
    z[0][1] = b0x - a[0][1] * y;
    float v = y;

    /* Stage 1: b = (1, +2, 1) */
    y = v + z[1][0];
    z[1][0] = (v + v) - a[1][0] * y + z[1][1];
    z[1][1] = v - a[1][1] * y;
    v = y;

    /* Stage 2: b = (1, -2, 1) */
    y = v + z[2][0];
    z[2][0] = -(v + v) - a[2][0] * y + z[2][1];
    z[2][1] = v - a[2][1] * y;
    v = y;

    /* Stage 3: b = (1, -2, 1) */
    y = v + z[3][0];
    z[3][0] = -(v + v) - a[3][0] * y + z[3][1];
    z[3][1] = v - a[3][1] * y;
    return y;
}
