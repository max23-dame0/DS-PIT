/* E2E-02 bare-metal startup for STM32F103 / Cortex-M (2026-11-24) */
#include <stdint.h>

extern uint32_t _sidata, _sdata, _edata, _sbss, _ebss, _estack;
extern int main(void);

void Reset_Handler(void);
__attribute__((noreturn)) static void Default_Handler(void) { for (;;) { } }

__attribute__((section(".isr_vector"), used))
const void *const g_vectors[] = {
    (const void *)&_estack,
    (const void *)Reset_Handler,
    (const void *)Default_Handler,
    (const void *)Default_Handler,
    (const void *)Default_Handler,
    (const void *)Default_Handler,
    (const void *)Default_Handler,
    0, 0, 0, 0,
    (const void *)Default_Handler,
    (const void *)Default_Handler,
    0,
    (const void *)Default_Handler,
    (const void *)Default_Handler
};

void Reset_Handler(void)
{
#ifdef ENABLE_M4F_CPACR
    /* Enable CP10 & CP11 full access in SCB->CPACR (0xE000ED88) on Cortex-M4F */
    volatile uint32_t *cpacr = (volatile uint32_t *)0xE000ED88u;
    *cpacr |= (0xFu << 20);
    __asm volatile ("dsb");
    __asm volatile ("isb");
#endif
    uint32_t *src = &_sidata;
    uint32_t *dst = &_sdata;
    while (dst < &_edata) { *dst++ = *src++; }
    dst = &_sbss;
    while (dst < &_ebss) { *dst++ = 0u; }
    (void)main();
    for (;;) { }
}
