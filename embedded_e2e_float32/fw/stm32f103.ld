/* E2E-01: STM32F103 (256 KiB flash / 64 KiB RAM) bare-metal link script */
ENTRY(Reset_Handler)

MEMORY
{
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 256K
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
  .isr_vector : { KEEP(*(.isr_vector)) } > FLASH

  .text : {
    *(.text*)
    *(.rodata*)
    . = ALIGN(4);
  } > FLASH

  .ARM.exidx : { *(.ARM.exidx*) } > FLASH

  _sidata = LOADADDR(.data);
  .data : {
    . = ALIGN(4);
    _sdata = .;
    *(.data*)
    . = ALIGN(4);
    _edata = .;
  } > RAM AT> FLASH

  .bss : {
    . = ALIGN(4);
    _sbss = .;
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
  } > RAM

  /* SWD streaming mailbox (NOLOAD so startup doesn't overwrite live control) */
  .mailbox (NOLOAD) : {
    . = ALIGN(4);
    *(.mailbox*)
    . = ALIGN(4);
    _end_ram_used = .;
  } > RAM

  /DISCARD/ : { *(.comment) *(.note*) }
}
