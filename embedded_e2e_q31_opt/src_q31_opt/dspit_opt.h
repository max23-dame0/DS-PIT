/* E2E-02 (q31-full-opt) fixed-point C99 pipeline interface */
#ifndef DSPIT_OPT_H
#define DSPIT_OPT_H

#include <stdint.h>

#define DSPIT_VARIANT_NAME "q31"
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

#define Q16_ONE        65536
#define Q16_NEG_INF    (-2000000000)

typedef struct {
    void (*on_stage_begin)(uint8_t stage_id, void *user);
    void (*on_stage_end)(uint8_t stage_id, void *user);
    void *user;
} dspit_hooks_t;

/* S1: 64-bit Q50 DF-II-T filter state */
typedef struct {
    int64_t z[4][4][2];
} fe_filter_t;

/* S1: Q11.20 polyphase FIR resampler ring buffers */
typedef struct {
    int32_t  ring[4][128];
    uint32_t in_cnt[4];
    uint32_t out_m[4];
    uint32_t next_imax[4];
    int32_t  wesad_acc_prev[3];
    uint8_t  wesad_acc_has_prev[3];
} fe_resamp_t;

/* S2: Q10.21 FFT buffers (overflow-free <= 200 < 1024) */
typedef struct {
    int32_t fft_re[E2E_NFFT];
    int32_t fft_im[E2E_NFFT];
} spec_state_t;

/* S3: Fixed-point ratio enhancement with O(NB) Q26 running sum */
typedef struct {
    int32_t w_hist[E2E_WF_LEN][E2E_NB]; /* Q5.26 */
    int32_t w_sum[E2E_NB];              /* Q5.26 sum <= 15 * 2^26 < 2^30 */
    uint8_t hist_pos;
    uint8_t hist_cnt;
} enhance_state_t;

/* S4: Q15.16 causal LBP state */
typedef struct {
    int32_t hist_g[E2E_HIST_LEN]; /* Q15.16 */
    uint8_t hist_pos;
    uint8_t hist_cnt;
    int32_t veh[E2E_VEL_L + 1u];  /* Q15.16 */
    uint8_t veh_pos;
    uint8_t veh_cnt;
    int32_t r_rel_q16;            /* Q15.16 */
} lbp_state_t;

/* S5: Q15.16 fixed-lag Viterbi decoder */
typedef struct {
    int32_t  v_old[E2E_K];
    int32_t  v_new[E2E_K];
    int32_t  u_vec[E2E_K];
    int16_t  pring[2][E2E_K];
    uint32_t step;
    uint8_t  cur;
    uint8_t  banded;
} decode_state_t;

/* S6: Q15.16 streaming 3-pt median smoother */
typedef struct {
    int32_t  buf[3];
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

    int32_t  win_buf[4][256]; /* Q11.20 */
    uint32_t out_cnt[4];
    uint32_t next_win_end;
    uint32_t win_idx;
    uint32_t est_idx;
    uint32_t es_idx;

    int32_t sp_mag[E2E_NB];    /* Q10.21 */
    int32_t ap_mag[3][E2E_NB]; /* Q10.21 */
    int32_t obv_q16[E2E_NB];   /* Q15.16 */
    int32_t psp_q30[E2E_K];    /* Q1.30  */
    int32_t logL_q16[E2E_K];   /* Q15.16 */
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
int32_t fe_filter_sample_q20(fe_filter_t *st, uint8_t ch, uint8_t mode, int32_t x_q20);

void fe_resamp_init(fe_resamp_t *st, uint8_t mode);
uint8_t fe_resamp_push_q20(fe_resamp_t *st, uint8_t ch, uint8_t mode, int32_t x_q20, int32_t *y_q20);

void spec_init(spec_state_t *st);
void spec_compute_window_q21(spec_state_t *st,
                             const int32_t win_buf[4][256],
                             uint32_t start_idx,
                             int32_t sp_mag_q21[E2E_NB],
                             int32_t ap_mag_q21[3][E2E_NB]);

void enhance_init(enhance_state_t *st);
void enhance_window_q(enhance_state_t *st,
                      const int32_t sp_mag_q21[E2E_NB],
                      const int32_t ap_mag_q21[3][E2E_NB],
                      int32_t obv_q16[E2E_NB],
                      int32_t psp_q30[E2E_K],
                      int32_t logL_q16[E2E_K]);

void lbp_init(lbp_state_t *st);
int32_t lbp_update_tau_q16(lbp_state_t *st, const int32_t obv_q16[E2E_NB], int32_t logL_q16[E2E_K]);
void lbp_push_est_q16(lbp_state_t *st, int32_t rb_q16);

void decode_init(decode_state_t *st, uint8_t banded);
uint8_t decode_step_q16(decode_state_t *st, const int32_t logL_q16[E2E_K], int32_t *rb_q16_out);

void smooth_init(smooth_state_t *st);
uint8_t smooth_push_q16(smooth_state_t *st, int32_t est_q16, int32_t *es_q16_out);

void dspit_init(dspit_e2e_t *st, uint8_t mode, uint8_t banded);
void dspit_push_block(dspit_e2e_t *st,
                      const float *ppg, uint32_t n_ppg,
                      const float *ax, const float *ay, const float *az, uint32_t n_acc,
                      dspit_block_out_t *out,
                      const dspit_hooks_t *hooks,
                      const dspit_trace_cb_t *trace_cb);

#endif /* DSPIT_OPT_H */
