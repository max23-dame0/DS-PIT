CC = gcc
CFLAGS = -O2 -Wall -Wextra -std=c99 -DDSPIT_ENABLE_TRACE

F32OPT_SRCS = ../src_f32_opt/e2e_f32opt_tables.c ../src_f32_opt/fe_filter_f32opt.c \
              ../src_f32_opt/fe_resample_f32opt.c ../src_f32_opt/spec_f32opt.c \
              ../src_f32_opt/enhance_f32opt.c ../src_f32_opt/lbp_f32opt.c \
              ../src_f32_opt/decode_f32opt.c ../src_f32_opt/smooth_f32opt.c \
              ../src_f32_opt/dspit_f32opt.c test_e2e_opt.c

Q31OPT_SRCS = ../src_q31_opt/e2e_opt_tables.c ../src_q31_opt/fe_filter_q31.c \
              ../src_q31_opt/fe_resample_q31.c ../src_q31_opt/spec_q31.c \
              ../src_q31_opt/enhance_opt.c ../src_q31_opt/lbp_opt.c \
              ../src_q31_opt/decode_q16.c ../src_q31_opt/smooth_opt.c \
              ../src_q31_opt/dspit_q31opt.c test_e2e_opt.c

all: test_f32opt.exe test_q31opt.exe

test_f32opt.exe: $(F32OPT_SRCS) ../src_f32_opt/dspit_opt.h ../src_f32_opt/e2e_f32opt_tables.h
	$(CC) $(CFLAGS) -I../src_f32_opt $(F32OPT_SRCS) -lm -o $@

test_q31opt.exe: $(Q31OPT_SRCS) ../src_q31_opt/dspit_opt.h ../src_q31_opt/e2e_opt_tables.h
	$(CC) $(CFLAGS) -I../src_q31_opt $(Q31OPT_SRCS) -lm -o $@

clean:
	cmd /c "if exist test_f32opt.exe del /Q test_f32opt.exe"
	cmd /c "if exist test_q31opt.exe del /Q test_q31opt.exe"

E1_DIR := $(shell if exist ..\..\embedded_e2e_float32\src (echo ../../embedded_e2e_float32) else (echo ../../embedded_e2e_20261124))
E1_SRCS := $(E1_DIR)/src/e2e_tables.c $(E1_DIR)/src/fe_filter.c $(E1_DIR)/src/fe_resample.c \
           $(E1_DIR)/src/spec.c $(E1_DIR)/src/enhance.c $(E1_DIR)/src/lbp.c \
           $(E1_DIR)/src/decode.c $(E1_DIR)/src/smooth.c $(E1_DIR)/src/dspit_e2e.c

run_full30: run_full30_f32opt.exe run_full30_q31opt.exe run_full30_e2e01.exe

run_full30_f32opt.exe: $(F32OPT_SRCS:test_e2e_opt.c=run_full30.c)
	$(CC) -O3 -Wall -Wextra -std=c99 -I../src_f32_opt $(F32OPT_SRCS:test_e2e_opt.c=run_full30.c) -lm -o $@

run_full30_q31opt.exe: $(Q31OPT_SRCS:test_e2e_opt.c=run_full30.c)
	$(CC) -O3 -Wall -Wextra -std=c99 -I../src_q31_opt $(Q31OPT_SRCS:test_e2e_opt.c=run_full30.c) -lm -o $@

run_full30_e2e01.exe: $(E1_SRCS) run_full30.c
	$(CC) -O3 -Wall -Wextra -std=c99 -DUSE_E2E01_HDR -I$(E1_DIR)/src $(E1_SRCS) run_full30.c -lm -o $@
