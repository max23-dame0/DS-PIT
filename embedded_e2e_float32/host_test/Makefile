CC = gcc
CFLAGS = -O2 -Wall -Wextra -std=c99 -I../src
SRCS = ../src/e2e_tables.c ../src/fe_filter.c ../src/fe_resample.c ../src/spec.c \
       ../src/enhance.c ../src/lbp.c ../src/decode.c ../src/smooth.c ../src/dspit_e2e.c \
       test_e2e.c

all: test_f64.exe test_f32.exe

test_f64.exe: $(SRCS) ../src/dspit_e2e.h ../src/e2e_config.h ../src/e2e_tables.h
	$(CC) $(CFLAGS) -DREAL_DOUBLE $(SRCS) -lm -o $@

test_f32.exe: $(SRCS) ../src/dspit_e2e.h ../src/e2e_config.h ../src/e2e_tables.h
	$(CC) $(CFLAGS) $(SRCS) -lm -o $@

clean:
	cmd /c "if exist test_f64.exe del /Q test_f64.exe"
	cmd /c "if exist test_f32.exe del /Q test_f32.exe"
