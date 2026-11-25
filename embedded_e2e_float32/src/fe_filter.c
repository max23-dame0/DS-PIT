/* S1a: 4-stage DF-II-T SOS bandpass filter (0.4-4 Hz Butterworth 4th-order) */
#include <string.h>
#include "dspit_e2e.h"
#include "e2e_tables.h"

void fe_filter_init(fe_filter_t *st)
{
    memset(st, 0, sizeof(*st));
}

real_t fe_filter_sample(fe_filter_t *st, uint8_t ch, uint8_t mode, real_t x)
{
    const real_t (*sos)[5] = (mode == E2E_MODE_DALIA) ? SOS_DALIA : SOS_WESAD;
    real_t v = x;
    for (uint8_t s = 0u; s < 4u; s++) {
        const real_t b0 = sos[s][0];
        const real_t b1 = sos[s][1];
        const real_t b2 = sos[s][2];
        const real_t a1 = sos[s][3];
        const real_t a2 = sos[s][4];
        const real_t y  = b0 * v + st->z[ch][s][0];
        st->z[ch][s][0] = b1 * v - a1 * y + st->z[ch][s][1];
        st->z[ch][s][1] = b2 * v - a2 * y;
        v = y;
    }
    return v;
}
