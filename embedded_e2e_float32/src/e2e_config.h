/* E2E-01 configuration & portable numeric types (2026-11-24) */
#ifndef E2E_CONFIG_H
#define E2E_CONFIG_H

#include <math.h>
#include <stdint.h>

#ifdef REAL_DOUBLE
typedef double real_t;
#define R_LIT(x)   ((double)(x))
#define R_SQRT(x)  sqrt(x)
#define R_LOG(x)   log(x)
#define R_EXP(x)   exp(x)
#define R_FABS(x)  fabs(x)
#define R_ROUND(x) round(x)
#define R_EPS      2.2204460492503131e-16
#define R_NEG_INF  (-1.0e300)
#else
typedef float real_t;
#define R_LIT(x)   ((float)(x))
#define R_SQRT(x)  sqrtf(x)
#define R_LOG(x)   logf(x)
#define R_EXP(x)   expf(x)
#define R_FABS(x)  fabsf(x)
#define R_ROUND(x) roundf(x)
#define R_EPS      2.2204460492503131e-16f
#define R_NEG_INF  (-3.0e38f)
#endif

#define E2E_MODE_DALIA 0u
#define E2E_MODE_WESAD 1u

#define E2E_FSD        25u
#define E2E_WIN_SEC    8u
#define E2E_HOP_SEC    2u
#define E2E_WS         200u   /* 8 * 25 */
#define E2E_HS         50u    /* 2 * 25 */
#define E2E_NFFT       1024u
#define E2E_BIN_START  31u    /* k=31 -> 0.756836 Hz */
#define E2E_NB         92u    /* k=31..122 -> 0.75..3.0 Hz */
#define E2E_K          161u   /* 40..200 BPM */
#define E2E_BPM_MIN    40
#define E2E_D          3u
#define E2E_BAND_HW    6
#define E2E_WF_LEN     15u
#define E2E_HIST_LEN   15u
#define E2E_VEL_L      5u     /* veh buffer capacity = VEL_L + 1 = 6 */
#define E2E_VEL_MAX    2
#define E2E_TEMP_WIN   30u
#define E2E_TEMP_LO    0.7
#define E2E_TEMP_HI    1.3

#define E2E_DALIA_FS   125u
#define E2E_DALIA_BLK  250u   /* 2 * 125 */
#define E2E_WESAD_FS   64u
#define E2E_WESAD_BLK  128u   /* 2 * 64 */
#define E2E_WESAD_ABLK 64u    /* 2 * 32 */

#define E2E_NWIN       257u
#define E2E_NEVAL      254u

#endif /* E2E_CONFIG_H */
