/* S6 fixed-point (q31-full-opt): Streaming 3-pt median smoother */
#include <string.h>
#include "dspit_opt.h"

void smooth_init(smooth_state_t *st)
{
    memset(st, 0, sizeof(*st));
}

static int32_t median3_i32(int32_t a, int32_t b, int32_t c)
{
    if (a > b) { int32_t t = a; a = b; b = t; }
    if (b > c) { b = c; }
    if (a > b) { b = a; }
    return b;
}

uint8_t smooth_push_q16(smooth_state_t *st, int32_t est_q16, int32_t *es_q16_out)
{
    if (st->cnt == 0u) {
        st->buf[0] = est_q16;
        st->cnt = 1u;
        return 0u;
    }
    if (st->cnt == 1u) {
        st->buf[1] = est_q16;
        st->cnt = 2u;
        *es_q16_out = (st->buf[0] + st->buf[1]) >> 1;
        return 1u;
    }
    if (st->cnt == 2u) {
        st->buf[2] = est_q16;
        st->cnt = 3u;
    } else {
        st->buf[0] = st->buf[1];
        st->buf[1] = st->buf[2];
        st->buf[2] = est_q16;
    }
    *es_q16_out = median3_i32(st->buf[0], st->buf[1], st->buf[2]);
    return 1u;
}
