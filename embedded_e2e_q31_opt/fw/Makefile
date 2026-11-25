# E2E-02 multi-variant firmware Makefile (Cortex-M3 f32_opt, q31_opt + Cortex-M4F static check)
CC      = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
SIZE    = arm-none-eabi-size

COMMON_CFLAGS = -mthumb -O3 -Wall -Wextra -std=c99 -fno-math-errno -ffunction-sections -fdata-sections -fno-common
M3_FLAGS      = -mcpu=cortex-m3
M4F_FLAGS     = -mcpu=cortex-m4 -mfpu=fpv4-sp-d16 -mfloat-abi=hard
LDFLAGS_BASE  = -T stm32f103.ld -nostartfiles --specs=nano.specs -Wl,--gc-sections

F32_C = startup.c main.c \
        ../src_f32_opt/e2e_f32opt_tables.c ../src_f32_opt/fe_filter_f32opt.c \
        ../src_f32_opt/fe_resample_f32opt.c ../src_f32_opt/spec_f32opt.c \
        ../src_f32_opt/enhance_f32opt.c ../src_f32_opt/lbp_f32opt.c \
        ../src_f32_opt/decode_f32opt.c ../src_f32_opt/smooth_f32opt.c \
        ../src_f32_opt/dspit_f32opt.c

Q31_C = startup.c main.c \
        ../src_q31_opt/e2e_opt_tables.c ../src_q31_opt/fe_filter_q31.c \
        ../src_q31_opt/fe_resample_q31.c ../src_q31_opt/spec_q31.c \
        ../src_q31_opt/enhance_opt.c ../src_q31_opt/lbp_opt.c \
        ../src_q31_opt/decode_q16.c ../src_q31_opt/smooth_opt.c \
        ../src_q31_opt/dspit_q31opt.c

all: fw_f32_opt.elf fw_f32_opt.bin fw_q31_opt.elf fw_q31_opt.bin fw_m4f.elf fw_m4f.bin

fw_f32_opt.elf: $(F32_C) stm32f103.ld
	$(CC) $(M3_FLAGS) $(COMMON_CFLAGS) -I../src_f32_opt $(LDFLAGS_BASE),-Map=fw_f32_opt.map $(F32_C) -lm -lgcc -o $@
	$(SIZE) $@

fw_f32_opt.bin: fw_f32_opt.elf
	$(OBJCOPY) -O binary $< $@

fw_q31_opt.elf: $(Q31_C) stm32f103.ld
	$(CC) $(M3_FLAGS) $(COMMON_CFLAGS) -I../src_q31_opt $(LDFLAGS_BASE),-Map=fw_q31_opt.map $(Q31_C) -lm -lgcc -o $@
	$(SIZE) $@

fw_q31_opt.bin: fw_q31_opt.elf
	$(OBJCOPY) -O binary $< $@

fw_m4f.elf: $(F32_C) stm32f103.ld
	$(CC) $(M4F_FLAGS) $(COMMON_CFLAGS) -DENABLE_M4F_CPACR -I../src_f32_opt $(LDFLAGS_BASE),-Map=fw_m4f.map $(F32_C) -lm -lgcc -o $@
	$(SIZE) $@

fw_m4f.bin: fw_m4f.elf
	$(OBJCOPY) -O binary $< $@

clean:
	cmd /c "del /Q *.o fw_*.elf fw_*.bin fw_*.map 2>nul & exit /b 0"
