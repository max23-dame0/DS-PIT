/* S6 (f32-algo-opt): Streaming 3-point median smoother */
#include <string.h>
#include "dspit_opt.h"

void smooth_init(smooth_state_t *st)
{
    memset(st, 0, sizeof(*st));
}

static float median3(float a, float b, float c)
{
    if (a > b) { float t = a; a = b; b = t; }
    if (b > c) { b = c; }
    if (a > b) { b = a; }
    return b;
}

uint8_t smooth_push(smooth_state_t *st, float est_val, float *es_out)
{
    if (st->cnt == 0u) {
        st->buf[0] = est_val;
        st->cnt = 1u;
        return 0u;
    }
    if (st->cnt == 1u) {
        st->buf[1] = est_val;
        st->cnt = 2u;
        *es_out = 0.5f * (st->buf[0] + st->buf[1]);
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
