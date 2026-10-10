/* EMB-01: embedded log-likelihood vectors (float32 LE, K per window, row-major windows) */
    .section .rodata
    .global win_data
    .align 4
win_data:
    .incbin "win_data.bin"
