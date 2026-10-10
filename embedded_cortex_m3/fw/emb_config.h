/* EMB-01 board/config constants, 2026-09-21 */
#ifndef EMB_CONFIG_H
#define EMB_CONFIG_H

#define N_WIN      256      /* embedded window count (prefix of DaLiA S1) */
#define D_LAG      3        /* fixed-lag depth (paper config) */
#ifndef BAND_HW
#define BAND_HW    6        /* banded half-width; W = 2*BAND_HW+1 = 13 */
#endif
#ifndef CLK_MHZ
#define CLK_MHZ    72       /* HSE x (CLK_MHZ/8); 24 / 48 / 72 supported */
#endif
#define BPM_MIN    40       /* state grid lower edge (paper config) */

/* stack paint region for high-water measurement (must sit above .bss/.results) */
#define PAINT_BASE 0x20008000u
#define PAINT_HEAD 256u

#define MAGIC_START     0x31420001u
#define MAGIC_AFTER_DS  0x31420002u
#define MAGIC_AFTER_BD  0x31420003u
#define MAGIC_DONE      0x3142FFFFu

#endif
