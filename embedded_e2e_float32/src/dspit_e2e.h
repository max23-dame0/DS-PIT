/* E2E-01 portable C99 DS-PIT full pipeline interface (2026-11-24) */
#ifndef DSPIT_E2E_H
#define DSPIT_E2E_H

#include <stdint.h>
#include "e2e_config.h"

/* Optional stage profiling callback interface (zero overhead if NULL) */
typedef struct {
    void (*on_stage_begin)(uint8_t stage_id, void *user);
    void (*on_stage_end)(uint8_t stage_id, void *user);
    void *user;
} dspit_hooks_t;

/* S1: 4-stage DF-II-T SOS bandpass filter state (4 channels) */
typedef struct {
    real_t z[4][4][2];
} fe_filter_t;

/* S1: Streaming polyphase FIR resampler (+ WESAD 32->64 Hz ACC interp) */
typedef struct {
    real_t   ring[4][128];
    uint32_t in_cnt[4];
    uint32_t out_m[4];
    uint32_t next_imax[4];
    real_t   wesad_acc_prev[3];
    uint8_t  wesad_acc_has_prev[3];
} fe_resamp_t;

/* S2: Spectral buffer + radix-2 1024-pt real-packed FFT */
typedef struct {
    real_t fft_re[E2E_NFFT];
    real_t fft_im[E2E_NFFT];
} spec_state_t;

/* S3: Dual-branch ratio spectral enhancement */
typedef struct {
    real_t   w_hist[E2E_WF_LEN][E2E_NB];
    uint8_t  hist_pos;
    uint8_t  hist_cnt;
} enhance_state_t;

/* S4: Causal LBP reliability temperature modulation */
typedef struct {
    real_t  hist_g[E2E_HIST_LEN];
    uint8_t hist_pos;
    uint8_t hist_cnt;
    real_t  veh[E2E_VEL_L + 1u];
    uint8_t veh_pos;
    uint8_t veh_cnt;
    real_t  r_rel;
} lbp_state_t;

/* S5: Fixed-lag Viterbi decoder */
typedef struct {
    real_t   v_old[E2E_K];
    real_t   v_new[E2E_K];
    real_t   u_vec[E2E_K];
    int16_t  pring[2][E2E_K];
    uint32_t step;
    uint8_t  cur;
    uint8_t  banded;
} decode_state_t;

/* S6: Streaming 3-point median smoother */
typedef struct {
    real_t   buf[3];
    uint32_t cnt;
} smooth_state_t;

/* Per-window intermediate trace hook (used only on host validation if non-NULL) */
typedef struct {
    void (*on_x25)(uint32_t ch, uint32_t sample_idx, real_t val, void *user);
    void (*on_window)(uint32_t win_idx,
                      const real_t *sp_mag,
                      const real_t ap_mag[3][E2E_NB],
                      const real_t *obv,
                      const real_t *psp,
                      const real_t *lvec,
                      const real_t *logL_pre,
                      real_t tau,
                      const real_t *logL_post,
                      void *user);
    void *user;
} dspit_trace_cb_t;

/* Top-level E2E state */
typedef struct {
    uint8_t  mode;      /* E2E_MODE_DALIA or E2E_MODE_WESAD */
    uint8_t  banded;    /* 1 = W=13 banded, 0 = dense */
    fe_filter_t     fe_filt;
    fe_resamp_t     fe_res;
    spec_state_t    spec;
    enhance_state_t enh;
    lbp_state_t     lbp;
    decode_state_t  dec;
    smooth_state_t  sm;

    /* 25-Hz sliding window ring buffers (256 slots >= 200 + 50 max block) */
    real_t   win_buf[4][256];
    uint32_t out_cnt[4];
    uint32_t next_win_end;
    uint32_t win_idx;
    uint32_t est_idx;
    uint32_t es_idx;

    /* Working vectors between S2..S5 */
    real_t sp_mag[E2E_NB];
    real_t ap_mag[3][E2E_NB];
    real_t obv[E2E_NB];
    real_t psp[E2E_K];
    real_t lvec[E2E_K];
    real_t logL[E2E_K];
} dspit_e2e_t;

typedef struct {
    uint8_t  win_ran;
    uint8_t  has_est;
    uint8_t  has_es;
    uint32_t est_index;
    uint32_t es_index;
    real_t   est_bpm;
    real_t   es_bpm;
    real_t   tau;
} dspit_block_out_t;

/* Stage IDs for hooks */
enum {
    DSPIT_STAGE_S1_FRONTEND = 0,
    DSPIT_STAGE_S2_SPECTRAL = 1,
    DSPIT_STAGE_S3_ENHANCE  = 2,
    DSPIT_STAGE_S4_LBP      = 3,
    DSPIT_STAGE_S5_VITERBI  = 4,
    DSPIT_STAGE_S6_SMOOTH   = 5
};

/* Module entrypoints */
void fe_filter_init(fe_filter_t *st);
real_t fe_filter_sample(fe_filter_t *st, uint8_t ch, uint8_t mode, real_t x);

void fe_resamp_init(fe_resamp_t *st, uint8_t mode);
uint8_t fe_resamp_push(fe_resamp_t *st, uint8_t ch, uint8_t mode, real_t x, real_t *y_out);

void spec_init(spec_state_t *st);
void spec_compute_window(spec_state_t *st,
                         const real_t win_buf[4][256],
                         uint32_t start_idx,
                         real_t sp_mag[E2E_NB],
                         real_t ap_mag[3][E2E_NB]);

void enhance_init(enhance_state_t *st);
void enhance_window(enhance_state_t *st,
                    const real_t sp_mag[E2E_NB],
                    const real_t ap_mag[3][E2E_NB],
                    real_t obv_out[E2E_NB],
                    real_t psp_out[E2E_K],
                    real_t l_out[E2E_K],
                    real_t logL_out[E2E_K]);

void lbp_init(lbp_state_t *st);
real_t lbp_update_tau(lbp_state_t *st, const real_t obv[E2E_NB], real_t logL[E2E_K]);
void lbp_push_est(lbp_state_t *st, real_t rb);

void decode_init(decode_state_t *st, uint8_t banded);
uint8_t decode_step(decode_state_t *st, const real_t logL[E2E_K], real_t *rb_out);

void smooth_init(smooth_state_t *st);
uint8_t smooth_push(smooth_state_t *st, real_t est_val, real_t *es_out);

/* Top-level pipeline */
void dspit_init(dspit_e2e_t *st, uint8_t mode, uint8_t banded);
void dspit_push_block(dspit_e2e_t *st,
                      const real_t *ppg, uint32_t n_ppg,
                      const real_t *ax, const real_t *ay, const real_t *az, uint32_t n_acc,
                      dspit_block_out_t *out,
                      const dspit_hooks_t *hooks,
                      const dspit_trace_cb_t *trace_cb);

#endif /* DSPIT_E2E_H */
