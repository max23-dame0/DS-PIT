/* EMB-01: fixed-lag Viterbi decision-layer benchmark on STM32F103 (Cortex-M3).
 *
 * Ports the ds5.m decision layer (paper configuration):
 *   transition  logT(k,j) = g[|k-j|] + a[k],  g[d] = -d^2/(2*sigma^2), sigma = 2,
 *               a[k] = -log(row-sum)  (precomputed table, exact in float32)
 *   recursion   v_new[j] = logL[j] + max_k ( v_old[k] + a[k] + g[|k-j|] )
 *   fixed lag   D = 3: at time t emit state at t-2 by backtracking 2 steps
 *   variants    dense K^2 scan and banded K*W scan (W = 13)
 * Measurement: DWT->CYCCNT per window; results read back over SWD from .results.
 */
#include <stdint.h>
#include "emb_config.h"
#include "mcu_tables.h"

extern const float win_data[];   /* N_WIN * MCU_K float32, window-major */
extern uint32_t _estack;

#define REG32(a) (*(volatile uint32_t *)(a))
#define RCC_CR      REG32(0x40021000u)
#define RCC_CFGR    REG32(0x40021004u)
#define FLASH_ACR   REG32(0x40022000u)
#define DEMCR       REG32(0xE000EDFCu)
#define DWT_CTRL    REG32(0xE0001000u)
#define DWT_CYCCNT  REG32(0xE0001004u)

typedef struct {
    uint32_t magic;
    uint32_t clk_hz;
    uint32_t cfgr;
    uint32_t stack_used;
    uint32_t n_win;
    uint32_t cycles_dense[N_WIN];
    uint32_t cycles_banded[N_WIN];
    float    est_dense[N_WIN];
    float    est_banded[N_WIN];
} results_t;

__attribute__((section(".results"), used))
static results_t res;

static float u[MCU_K];
static float vold[MCU_K];
static float vnew[MCU_K];
static float gt[MCU_K];
static int16_t pring[2][MCU_K];

static uint32_t clock_init(void)
{
    FLASH_ACR = 0x10u | ((CLK_MHZ > 48) ? 2u : ((CLK_MHZ > 24) ? 1u : 0u));
    RCC_CR |= (1u << 0);                  /* HSION */
    while (!(RCC_CR & (1u << 1))) { }
    RCC_CR |= (1u << 16);                 /* HSEON (8 MHz crystal) */
    uint32_t to = 0x100000u;
    while (!(RCC_CR & (1u << 17)) && --to) { }
    const uint32_t hse_ok = (RCC_CR >> 17) & 1u;
    uint32_t cfgr;
    if (hse_ok) {
        const uint32_t mull = (uint32_t)(CLK_MHZ / 8 - 2);  /* PLLMULL = mul - 2 */
        cfgr = (1u << 16) | (mull << 18) | (4u << 8);       /* HSE x mull, APB1 /2 */
    } else {
        cfgr = (14u << 18) | (4u << 8);               /* HSI/2 x16 = 64 MHz, APB1 /2 */
    }
    RCC_CFGR = cfgr;
    RCC_CR |= (1u << 24);                 /* PLLON */
    while (!(RCC_CR & (1u << 25))) { }
    RCC_CFGR |= 2u;                       /* SYSCLK = PLL */
    while (((RCC_CFGR >> 2) & 3u) != 2u) { }
    return hse_ok ? (uint32_t)CLK_MHZ * 1000000u : 64000000u;
}

static void dwt_init(void)
{
    DEMCR |= (1u << 24);
    DWT_CYCCNT = 0u;
    DWT_CTRL |= 1u;
}

static void paint_stack(void)
{
    uint32_t *p = (uint32_t *)PAINT_BASE;
    uint32_t *e = (uint32_t *)((uint32_t)&_estack - PAINT_HEAD);
    while (p < e) { *p++ = 0xC0DEBEEFu; }
}

static uint32_t stack_used(void)
{
    const uint32_t *p = (const uint32_t *)PAINT_BASE;
    const uint32_t *e = (const uint32_t *)((uint32_t)&_estack - PAINT_HEAD);
    while (p < e && *p == 0xC0DEBEEFu) { p++; }
    return (uint32_t)&_estack - (uint32_t)p;
}

static void run_variant(const uint32_t banded)
{
    uint32_t *cyc = banded ? res.cycles_banded : res.cycles_dense;
    float *est = banded ? res.est_banded : res.est_dense;
    for (int i = 0; i < N_WIN; i++) { est[i] = -1.0f; }
    int cur = 0;
    for (int t = 0; t < N_WIN; t++) {
        const float *logL = win_data + (uint32_t)t * MCU_K;
        const uint32_t c0 = DWT_CYCCNT;
        if (t == 0) {
            for (int j = 0; j < MCU_K; j++) {
                vnew[j] = logL[j] + MCU_A[j];   /* diag(logT0) = g[0] + a[j] = a[j] */
                pring[0][j] = 0;
            }
        } else {
            for (int k = 0; k < MCU_K; k++) { u[k] = vold[k] + MCU_A[k]; }
            if (banded) {
                for (int j = 0; j < MCU_K; j++) {
                    int k0 = j - BAND_HW; if (k0 < 0) { k0 = 0; }
                    int k1 = j + BAND_HW; if (k1 > MCU_K - 1) { k1 = MCU_K - 1; }
                    float best = -3.0e38f;
                    int bi = k0;
                    for (int k = k0; k <= k1; k++) {
                        int d = k - j; if (d < 0) { d = -d; }
                        const float tmp = u[k] + gt[d];
                        if (tmp > best) { best = tmp; bi = k; }
                    }
                    vnew[j] = logL[j] + best;
                    pring[cur][j] = (int16_t)bi;
                }
            } else {
                for (int j = 0; j < MCU_K; j++) {
                    float best = -3.0e38f;
                    int bi = 0;
                    for (int k = 0; k < MCU_K; k++) {
                        int d = k - j; if (d < 0) { d = -d; }
                        const float tmp = u[k] + gt[d];
                        if (tmp > best) { best = tmp; bi = k; }
                    }
                    vnew[j] = logL[j] + best;
                    pring[cur][j] = (int16_t)bi;
                }
            }
        }
        if (t >= D_LAG - 1) {
            float best = -3.0e38f;
            int st = 0;
            for (int j = 0; j < MCU_K; j++) {
                if (vnew[j] > best) { best = vnew[j]; st = j; }
            }
            st = pring[cur][st];
            st = pring[cur ^ 1][st];
            est[t - (D_LAG - 1)] = (float)(BPM_MIN + st);
        }
        cur ^= 1;
        for (int j = 0; j < MCU_K; j++) { vold[j] = vnew[j]; }
        cyc[t] = DWT_CYCCNT - c0;
    }
}

static void set_magic(uint32_t v)
{
    *(volatile uint32_t *)&res.magic = v;
}

int main(void)
{
    paint_stack();
    set_magic(MAGIC_START);
    res.clk_hz = clock_init();
    res.cfgr = RCC_CFGR;
    res.n_win = N_WIN;
    dwt_init();
    for (int d = 0; d < MCU_K; d++) {
        gt[d] = (float)(-(double)d * (double)d / 8.0);
    }
    run_variant(0u);
    set_magic(MAGIC_AFTER_DS);
    run_variant(1u);
    *(volatile uint32_t *)&res.stack_used = stack_used();
    set_magic(MAGIC_DONE);
    for (;;) { }
}
