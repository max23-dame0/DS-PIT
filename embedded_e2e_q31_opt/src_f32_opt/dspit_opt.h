/* E2E-02 (f32-algo-opt) unified C99 pipeline interface */
#ifndef DSPIT_OPT_H
#define DSPIT_OPT_H

#include <math.h>
#include <stdint.h>

#define DSPIT_VARIANT_NAME "f32opt"
#define E2E_MODE_DALIA 0u
#define E2E_MODE_WESAD 1u

#define E2E_FSD        25u
#define E2E_WIN_SEC    8u
#define E2E_HOP_SEC    2u
#define E2E_WS         200u
#define E2E_HS         50u
#define E2E_NFFT       1024u
#define E2E_BIN_START  31u
#define E2E_NB         92u
#define E2E_K          161u
#define E2E_BPM_MIN    40
#define E2E_D          3u
#define E2E_BAND_HW    6
#define E2E_WF_LEN     15u
#define E2E_HIST_LEN   15u
#define E2E_VEL_L      5u

#define E2E_DALIA_BLK  250u
#define E2E_WESAD_BLK  128u
#define E2E_WESAD_ABLK 64u

#define R_EPS_F32      2.2204460492503131e-16f
#define R_NEG_INF_F32  (-3.0e38f)

typedef float real_t;

typedef struct {
    void (*on_stage_begin)(uint8_t stage_id, void *user);
    void (*on_stage_end)(uint8_t stage_id, void *user);
    void *user;
} dspit_hooks_t;

typedef struct {
    float z[4][4][2];
} fe_filter_t;

typedef struct {
    float    ring[4][128];
    uint32_t in_cnt[4];
    uint32_t out_m[4];
    uint32_t next_imax[4];
    float    wesad_acc_prev[3];
    uint8_t  wesad_acc_has_prev[3];
} fe_resamp_t;

typedef struct {
    float fft_re[E2E_NFFT];
    float fft_im[E2E_NFFT];
} spec_state_t;

typedef struct {
    float   w_hist[E2E_WF_LEN][E2E_NB];
    float   w_sum[E2E_NB];
    uint8_t hist_pos;
    uint8_t hist_cnt;
} enhance_state_t;

typedef struct {
    float   hist_g[E2E_HIST_LEN];
    uint8_t hist_pos;
    uint8_t hist_cnt;
    float   veh[E2E_VEL_L + 1u];
    uint8_t veh_pos;
    uint8_t veh_cnt;
    float   r_rel;
} lbp_state_t;

typedef struct {
    float    v_old[E2E_K];
    float    v_new[E2E_K];
    float    u_vec[E2E_K];
    int16_t  pring[2][E2E_K];
    uint32_t step;
    uint8_t  cur;
    uint8_t  banded;
} decode_state_t;

typedef struct {
    float    buf[3];
    uint32_t cnt;
} smooth_state_t;

typedef struct {
    void (*on_x25)(uint32_t ch, uint32_t sample_idx, double val, void *user);
    void (*on_window)(uint32_t win_idx,
                      const double *sp_mag,
                      const double ap_mag[3][E2E_NB],
                      const double *obv,
                      const double *psp,
                      const double *logL_pre,
                      double tau,
                      const double *logL_post,
                      void *user);
    void *user;
} dspit_trace_cb_t;

typedef struct {
    uint8_t  mode;
    uint8_t  banded;
    fe_filter_t     fe_filt;
    fe_resamp_t     fe_res;
    spec_state_t    spec;
    enhance_state_t enh;
    lbp_state_t     lbp;
    decode_state_t  dec;
    smooth_state_t  sm;

    float    win_buf[4][256];
    uint32_t out_cnt[4];
    uint32_t next_win_end;
    uint32_t win_idx;
    uint32_t est_idx;
    uint32_t es_idx;

    float sp_mag[E2E_NB];
    float ap_mag[3][E2E_NB];
    float obv[E2E_NB];
    float psp[E2E_K];
    float logL[E2E_K];
} dspit_e2e_t;

typedef struct {
    uint8_t  win_ran;
    uint8_t  has_est;
    uint8_t  has_es;
    uint32_t est_index;
    uint32_t es_index;
    float    est_bpm;
    float    es_bpm;
    float    tau;
} dspit_block_out_t;

enum {
    DSPIT_STAGE_S1_FRONTEND = 0,
    DSPIT_STAGE_S2_SPECTRAL = 1,
    DSPIT_STAGE_S3_ENHANCE  = 2,
    DSPIT_STAGE_S4_LBP      = 3,
    DSPIT_STAGE_S5_VITERBI  = 4,
    DSPIT_STAGE_S6_SMOOTH   = 5
};

void fe_filter_init(fe_filter_t *st);
float fe_filter_sample(fe_filter_t *st, uint8_t ch, uint8_t mode, float x);

void fe_resamp_init(fe_resamp_t *st, uint8_t mode);
uint8_t fe_resamp_push(fe_resamp_t *st, uint8_t ch, uint8_t mode, float x, float *y_out);

void spec_init(spec_state_t *st);
void spec_compute_window(spec_state_t *st,
                         const float win_buf[4][256],
                         uint32_t start_idx,
                         float sp_mag[E2E_NB],
                         float ap_mag[3][E2E_NB]);

void enhance_init(enhance_state_t *st);
void enhance_window(enhance_state_t *st,
                    const float sp_mag[E2E_NB],
                    const float ap_mag[3][E2E_NB],
                    float obv_out[E2E_NB],
                    float psp_out[E2E_K],
                    float logL_out[E2E_K]);

void lbp_init(lbp_state_t *st);
float lbp_update_tau(lbp_state_t *st, const float obv[E2E_NB], float logL[E2E_K]);
void lbp_push_est(lbp_state_t *st, float rb);

void decode_init(decode_state_t *st, uint8_t banded);
uint8_t decode_step(decode_state_t *st, const float logL[E2E_K], float *rb_out);

void smooth_init(smooth_state_t *st);
uint8_t smooth_push(smooth_state_t *st, float est_val, float *es_out);

void dspit_init(dspit_e2e_t *st, uint8_t mode, uint8_t banded);
void dspit_push_block(dspit_e2e_t *st,
                      const float *ppg, uint32_t n_ppg,
                      const float *ax, const float *ay, const float *az, uint32_t n_acc,
                      dspit_block_out_t *out,
                      const dspit_hooks_t *hooks,
                      const dspit_trace_cb_t *trace_cb);

#endif /* DSPIT_OPT_H */
