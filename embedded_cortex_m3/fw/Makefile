# EMB-01 bare-metal firmware build (arm-none-eabi-gcc)
TARGET  = fw
CC      = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
SIZE    = arm-none-eabi-size

EXTRA_DEFS ?=
CFLAGS  = -mcpu=cortex-m3 -mthumb -O2 -Wall -Wextra -std=c11 \
          -ffunction-sections -fdata-sections -fno-common -I. $(EXTRA_DEFS)
LDFLAGS = -T stm32f103.ld -nostartfiles -Wl,--gc-sections -Wl,-Map=$(TARGET).map

OBJS = startup.o main.o data.o

all: $(TARGET).elf $(TARGET).bin

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET).elf: $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) -o $@
	$(SIZE) $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $(TARGET).elf $(TARGET).bin

clean:
	rm -f $(OBJS) $(TARGET).elf $(TARGET).bin $(TARGET).map
