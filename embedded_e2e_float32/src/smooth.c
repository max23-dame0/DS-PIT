/* S6: Streaming 3-point median smoother matching MATLAB movmedian(est, 3) */
#include <string.h>
#include "dspit_e2e.h"

void smooth_init(smooth_state_t *st)
{
    memset(st, 0, sizeof(*st));
}

static real_t median3(real_t a, real_t b, real_t c)
{
    if (a > b) { real_t t = a; a = b; b = t; }
    if (b > c) { b = c; }
    if (a > b) { b = a; }
    return b;
}

uint8_t smooth_push(smooth_state_t *st, real_t est_val, real_t *es_out)
{
    if (st->cnt == 0u) {
        st->buf[0] = est_val;
        st->cnt = 1u;
        return 0u;
    }
    if (st->cnt == 1u) {
        st->buf[1] = est_val;
        st->cnt = 2u;
        *es_out = R_LIT(0.5) * (st->buf[0] + st->buf[1]);
        return 1u;
    }
    if (st->cnt == 2u) {
        st->buf[2] = est_val;
        st->cnt = 3u;
    } else {
        st->buf[0] = st->buf[1];
        st->buf[1] = st->buf[2];
        st->buf[2] = est_val;
    }
    *es_out = median3(st->buf[0], st->buf[1], st->buf[2]);
    return 1u;
}
