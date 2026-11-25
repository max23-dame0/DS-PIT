# E2E-01 STM32F103 bare-metal firmware Makefile
TARGET  = fw
CC      = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
SIZE    = arm-none-eabi-size
NM      = arm-none-eabi-nm

CFLAGS  = -mcpu=cortex-m3 -mthumb -O2 -Wall -Wextra -std=c99 \
          -fno-math-errno -ffunction-sections -fdata-sections -fno-common -I../src
LDFLAGS = -T stm32f103.ld -nostartfiles --specs=nano.specs \
          -Wl,--gc-sections,-Map=$(TARGET).map

OBJS = startup.o main.o e2e_tables.o fe_filter.o fe_resample.o spec.o \
       enhance.o lbp.o decode.o smooth.o dspit_e2e.o

all: $(TARGET).elf $(TARGET).bin

startup.o: startup.c
	$(CC) $(CFLAGS) -c $< -o $@

main.o: main.c ../src/dspit_e2e.h ../src/e2e_config.h
	$(CC) $(CFLAGS) -c $< -o $@

%.o: ../src/%.c ../src/dspit_e2e.h ../src/e2e_config.h ../src/e2e_tables.h
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET).elf: $(OBJS) stm32f103.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) -lm -lgcc -o $@
	$(SIZE) -B $(OBJS) $(TARGET).elf

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $(TARGET).elf $(TARGET).bin

clean:
	cmd /c "del /Q *.o fw.elf fw.bin fw.map 2>nul & exit /b 0"
