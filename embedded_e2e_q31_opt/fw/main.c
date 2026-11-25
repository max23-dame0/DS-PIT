/* E2E-02 bare-metal STM32F103 (72 MHz ARM Cortex-M3) streaming harness */
#include <stdint.h>
#include <stddef.h>
#include "dspit_opt.h"

#ifndef CLK_MHZ
#define CLK_MHZ 72u
#endif

#define MAGIC_READY 0xE2E00001u
#define MAGIC_BUSY  0xE2E0CAFEu
#define MAGIC_DONE  0xE2E0D00Eu

#define CMD_INIT        1u
#define CMD_PUSH_BLOCK  2u
#define CMD_QUERY_STACK 3u

extern uint32_t _estack;
extern uint32_t _end_ram_used;

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
    uint32_t cmd;
    uint32_t seq;
    uint32_t done_seq;
    uint32_t mode;
    uint32_t banded;
    uint32_t n_ppg;
    uint32_t n_acc;
    uint32_t win_ran;
    uint32_t has_est;
    uint32_t has_es;
    uint32_t est_index;
    uint32_t es_index;
    float    est_bpm;
    float    es_bpm;
    float    tau;
    uint32_t cyc_s[6];
    uint32_t cyc_total;
    uint32_t stack_used;
    uint32_t algo_ram_sz;
    uint32_t s_sizes[7];
    float    in_slab[1000];
} e2e_mailbox_t;

__attribute__((section(".mailbox"), used))
static volatile e2e_mailbox_t mb;

static dspit_e2e_t g_state;

typedef struct {
    uint32_t t0[6];
    uint32_t cyc[6];
} cyc_ctx_t;

static void hook_begin(uint8_t s, void *u)
{
    cyc_ctx_t *ctx = (cyc_ctx_t *)u;
    ctx->t0[s] = DWT_CYCCNT;
}

static void hook_end(uint8_t s, void *u)
{
    cyc_ctx_t *ctx = (cyc_ctx_t *)u;
    ctx->cyc[s] += (DWT_CYCCNT - ctx->t0[s]);
}

static uint32_t clock_init(void)
{
    FLASH_ACR = 0x10u | ((CLK_MHZ > 48u) ? 2u : ((CLK_MHZ > 24u) ? 1u : 0u));
    RCC_CR |= (1u << 0);
    while (!(RCC_CR & (1u << 1))) { }
    RCC_CR |= (1u << 16);
    uint32_t to = 0x100000u;
    while (!(RCC_CR & (1u << 17)) && --to) { }
    const uint32_t hse_ok = (RCC_CR >> 17) & 1u;
    uint32_t cfgr;
    if (hse_ok) {
        const uint32_t mull = (uint32_t)(CLK_MHZ / 8u - 2u);
        cfgr = (1u << 16) | (mull << 18) | (4u << 8);
    } else {
        cfgr = (14u << 18) | (4u << 8);
    }
    RCC_CFGR = cfgr;
    RCC_CR |= (1u << 24);
    while (!(RCC_CR & (1u << 25))) { }
    RCC_CFGR |= 2u;
    while (((RCC_CFGR >> 2) & 3u) != 2u) { }
    return hse_ok ? (uint32_t)CLK_MHZ * 1000000u : 64000000u;
}

static void dwt_init(void)
{
    DEMCR |= (1u << 24);
    DWT_CYCCNT = 0u;
    DWT_CTRL |= 1u;
}

static inline uint32_t read_sp(void)
{
    uint32_t sp;
    __asm volatile ("mov %0, sp" : "=r"(sp));
    return sp;
}

static void paint_stack(void)
{
    uint32_t *p = &_end_ram_used;
    const uint32_t sp_lim = read_sp() - 128u;
    while ((uint32_t)p < sp_lim) {
        *p++ = 0xC0DEBEEFu;
    }
}

static uint32_t measure_stack_used(void)
{
    const uint32_t *p = &_end_ram_used;
    const uint32_t *e = &_estack;
    while (p < e && *p == 0xC0DEBEEFu) {
        p++;
    }
    return (uint32_t)&_estack - (uint32_t)p;
}

int main(void)
{
    paint_stack();
    mb.magic = MAGIC_BUSY;
    mb.done_seq = 0u;
    mb.seq = 0u;
    mb.cmd = 0u;
    mb.clk_hz = clock_init();
    mb.cfgr = RCC_CFGR;
    dwt_init();

    mb.algo_ram_sz = (uint32_t)sizeof(dspit_e2e_t);
    mb.s_sizes[0] = (uint32_t)(sizeof(fe_filter_t) + sizeof(fe_resamp_t));
    mb.s_sizes[1] = (uint32_t)sizeof(spec_state_t);
    mb.s_sizes[2] = (uint32_t)sizeof(enhance_state_t);
    mb.s_sizes[3] = (uint32_t)sizeof(lbp_state_t);
    mb.s_sizes[4] = (uint32_t)sizeof(decode_state_t);
    mb.s_sizes[5] = (uint32_t)sizeof(smooth_state_t);
    mb.s_sizes[6] = (uint32_t)(sizeof(dspit_e2e_t) -
                    (mb.s_sizes[0] + mb.s_sizes[1] + mb.s_sizes[2] +
                     mb.s_sizes[3] + mb.s_sizes[4] + mb.s_sizes[5]));
    mb.stack_used = measure_stack_used();
    __asm volatile ("dmb" ::: "memory");
    mb.magic = MAGIC_READY;

    uint32_t last_seq = 0u;
    for (;;) {
        const uint32_t cur_seq = mb.seq;
        if (cur_seq == last_seq) {
            __asm volatile ("nop");
            continue;
        }
        __asm volatile ("dmb" ::: "memory");
        mb.magic = MAGIC_BUSY;
        const uint32_t cmd = mb.cmd;

        if (cmd == CMD_INIT) {
            dspit_init(&g_state, (uint8_t)mb.mode, (uint8_t)mb.banded);
            mb.win_ran = 0u;
            mb.has_est = 0u;
            mb.has_es = 0u;
            for (int i = 0; i < 6; i++) { mb.cyc_s[i] = 0u; }
            mb.cyc_total = 0u;
        } else if (cmd == CMD_PUSH_BLOCK) {
            const uint32_t np = mb.n_ppg;
            const uint32_t na = mb.n_acc;
            const float *ppg = (const float *)&mb.in_slab[0];
            const float *ax  = ppg + np;
            const float *ay  = ax + na;
            const float *az  = ay + na;

            cyc_ctx_t ctx;
            for (int i = 0; i < 6; i++) { ctx.cyc[i] = 0u; ctx.t0[i] = 0u; }
            dspit_hooks_t hooks = { hook_begin, hook_end, &ctx };
            dspit_block_out_t bout;
            dspit_push_block(&g_state, ppg, np, ax, ay, az, na, &bout, &hooks, NULL);

            mb.win_ran   = bout.win_ran;
            mb.has_est   = bout.has_est;
            mb.has_es    = bout.has_es;
            mb.est_index = bout.est_index;
            mb.es_index  = bout.es_index;
            mb.est_bpm   = bout.est_bpm;
            mb.es_bpm    = bout.es_bpm;
            mb.tau       = bout.tau;

            uint32_t tot = 0u;
            for (int i = 0; i < 6; i++) {
                mb.cyc_s[i] = ctx.cyc[i];
                tot += ctx.cyc[i];
            }
            mb.cyc_total = tot;
        }
        mb.stack_used = measure_stack_used();
        __asm volatile ("dmb" ::: "memory");
        mb.done_seq = cur_seq;
        mb.magic = MAGIC_DONE;
        last_seq = cur_seq;
    }
}
