/* EMB-01 bare-metal startup for STM32F103 (Cortex-M3), 2026-09-21 */
#include <stdint.h>

extern uint32_t _sidata, _sdata, _edata, _sbss, _ebss, _estack;
extern int main(void);

void Reset_Handler(void);
__attribute__((noreturn)) static void Default_Handler(void) { for (;;) { } }

__attribute__((section(".isr_vector"), used))
const void *const g_vectors[] = {
    (const void *)&_estack,
    (const void *)Reset_Handler,
    (const void *)Default_Handler,   /* NMI */
    (const void *)Default_Handler,   /* HardFault */
    (const void *)Default_Handler,   /* MemManage */
    (const void *)Default_Handler,   /* BusFault */
    (const void *)Default_Handler,   /* UsageFault */
    0, 0, 0, 0,
    (const void *)Default_Handler,   /* SVCall */
    (const void *)Default_Handler,   /* DebugMonitor */
    0,
    (const void *)Default_Handler,   /* PendSV */
    (const void *)Default_Handler    /* SysTick */
};

void Reset_Handler(void)
{
    uint32_t *src = &_sidata;
    uint32_t *dst = &_sdata;
    while (dst < &_edata) { *dst++ = *src++; }
    dst = &_sbss;
    while (dst < &_ebss) { *dst++ = 0u; }
    (void)main();
    for (;;) { }
}
