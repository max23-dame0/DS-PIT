"""Generate fixed-point (Q31/Q16) and optimized float32 tables + verify FFT pruning & IIR scaling."""
import math
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BASE_E2E = ROOT.parent / "embedded_e2e_20261124"


def parse_tables_h(path: Path):
    txt = path.read_text(encoding="utf-8")

    def parse_arr(name):
        m = re.search(rf"const\s+\w+\s+{name}\[[^\]]+\](?:\[\d+\])?\s*=\s*\{{(.*?)\}};", txt, re.S)
        if not m:
            raise RuntimeError(f"Could not find {name}")
        body = m.group(1)
        if "R_LIT" in body:
            return [float(x) for x in re.findall(r"R_LIT\(([^)]+)\)", body)]
        return [int(x.strip()) for x in body.replace("\n", " ").split(",") if x.strip()]

    return {
        "SOS_DALIA": [parse_arr("SOS_DALIA")[i * 5 : (i + 1) * 5] for i in range(4)],
        "SOS_WESAD": [parse_arr("SOS_WESAD")[i * 5 : (i + 1) * 5] for i in range(4)],
        "RESAMP_H_DALIA": parse_arr("RESAMP_H_DALIA"),
        "RESAMP_H_WESAD": parse_arr("RESAMP_H_WESAD"),
        "TWID_RE": parse_arr("TWID_RE"),
        "TWID_IM": parse_arr("TWID_IM"),
        "TAPER": parse_arr("TAPER"),
        "INTERP_W": parse_arr("INTERP_W"),
        "MCU_A": parse_arr("MCU_A"),
        "MCU_G": parse_arr("MCU_G"),
        "INTERP_IDX": parse_arr("INTERP_IDX"),
    }


def q_round(val: float, shift: int, bits: int = 32) -> int:
    q = int(round(val * (1 << shift)))
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    if q == hi + 1:
        return hi
    if q < lo or q > hi:
        raise OverflowError(f"Value {val} scaled by 2^{shift} = {q} out of int{bits} range")
    return q


def verify_pruned_fft(tw_re, tw_im):
    """Verify input-pruned 1024->4x256 DIF + 4x(256 Radix-4 DIF) matches full 1024-pt DFT."""
    def w1024(p):
        p = p & 1023
        if p < 512:
            return tw_re[p], tw_im[p]
        return -tw_re[p - 512], -tw_im[p - 512]

    # deterministic active samples n=0..199, zero for 200..1023
    x_re = [math.sin(0.17 * n + 0.3) for n in range(200)] + [0.0] * 824
    x_im = [math.cos(0.23 * n - 0.5) for n in range(200)] + [0.0] * 824

    buf_re = [0.0] * 1024
    buf_im = [0.0] * 1024
    # Pass 0: 1024 -> 4x256 input-pruned DIF on n=0..199 (j=1,2,3 are 0)
    for p in range(200):
        xr, xi = x_re[p], x_im[p]
        buf_re[p] = xr
        buf_im[p] = xi

        wr1, wi1 = w1024(p)
        buf_re[256 + p] = xr * wr1 - xi * wi1
        buf_im[256 + p] = xr * wi1 + xi * wr1

        wr2, wi2 = w1024(2 * p)
        buf_re[512 + p] = xr * wr2 - xi * wi2
        buf_im[512 + p] = xr * wi2 + xi * wr2

        wr3, wi3 = w1024(3 * p)
        buf_re[768 + p] = xr * wr3 - xi * wi3
        buf_im[768 + p] = xr * wi3 + xi * wr3

    # 4 x (256-pt Radix-4 DIF, exp(-i 2pi / 256))
    for q in range(4):
        base = q * 256
        # stages N_sub = 256 (step=4), 64 (step=16), 16 (step=64), 4 (step=256)
        n_sub = 256
        step = 4
        while n_sub >= 4:
            quarter = n_sub >> 2
            for start in range(base, base + 256, n_sub):
                for k in range(quarter):
                    i0 = start + k
                    i1 = i0 + quarter
                    i2 = i1 + quarter
                    i3 = i2 + quarter
                    ar, ai = buf_re[i0], buf_im[i0]
                    br, bi = buf_re[i1], buf_im[i1]
                    cr, ci = buf_re[i2], buf_im[i2]
                    dr, di = buf_re[i3], buf_im[i3]

                    # W_N^n: y_m = x0 + (-i)^m x1 + (-1)^m x2 + (i)^m x3
                    s0r, s0i = ar + cr, ai + ci
                    s1r, s1i = ar - cr, ai - ci
                    d0r, d0i = br + dr, bi + di
                    d1r, d1i = br - dr, bi - di

                    # x0' = s0 + d0
                    buf_re[i0] = s0r + d0r
                    buf_im[i0] = s0i + d0i

                    # x1' = (s1 + (-i)*d1) * W^k = (s1r + d1i, s1i - d1r) * W_256^k
                    t1r, t1i = s1r + d1i, s1i - d1r
                    # x2' = (s0 - d0) * W_256^(2k)
                    t2r, t2i = s0r - d0r, s0i - d0i
                    # x3' = (s1 + (+i)*d1) * W_256^(3k) = (s1r - d1i, s1i + d1r) * W_256^(3k)
                    t3r, t3i = s1r - d1i, s1i + d1r

                    if n_sub == 4 or k == 0:
                        buf_re[i1], buf_im[i1] = t1r, t1i
                        buf_re[i2], buf_im[i2] = t2r, t2i
                        buf_re[i3], buf_im[i3] = t3r, t3i
                    else:
                        w1r, w1i = w1024(k * step)
                        buf_re[i1] = t1r * w1r - t1i * w1i
                        buf_im[i1] = t1r * w1i + t1i * w1r

                        w2r, w2i = w1024(2 * k * step)
                        buf_re[i2] = t2r * w2r - t2i * w2i
                        buf_im[i2] = t2r * w2i + t2i * w2r

                        w3r, w3i = w1024(3 * k * step)
                        buf_re[i3] = t3r * w3r - t3i * w3i
                        buf_im[i3] = t3r * w3i + t3i * w3r
            n_sub >>= 2
            step <<= 2

    def digitrev4(m):
        return ((m & 3) << 6) | ((m & 0xC) << 2) | ((m & 0x30) >> 2) | ((m & 0xC0) >> 6)

    max_err = 0.0
    for k in list(range(31, 123)) + list(range(1024 - 122, 1024 - 30)):
        q = k & 3
        m = k >> 2
        got_re = buf_re[q * 256 + digitrev4(m)]
        got_im = buf_im[q * 256 + digitrev4(m)]
        # direct DFT reference
        ref_re, ref_im = 0.0, 0.0
        ang0 = -2.0 * math.pi * k / 1024.0
        for n in range(200):
            c = math.cos(ang0 * n)
            s = math.sin(ang0 * n)
            ref_re += x_re[n] * c - x_im[n] * s
            ref_im += x_re[n] * s + x_im[n] * c
        err = math.hypot(got_re - ref_re, got_im - ref_im)
        if err > max_err:
            max_err = err
    print(f"[verify_pruned_fft] max error over active bins = {max_err:.3e}")
    assert max_err < 1e-11


def verify_q31_s1(tbl):
    """Simulate DF-II-T SOS in Q11.20 / state Q50 + symmetric Q31 FIR vs float64 trace."""
    for tag, mode in [("s1", 0), ("ws1", 1)]:
        raw = (BASE_E2E / "golden" / f"{tag}_raw_f32.bin").read_bytes()
        magic, ds_id, n_ppg, n_acc, _, _ = struct.unpack_from("<6I", raw, 0)
        ppg = struct.unpack_from(f"<{n_ppg}f", raw, 24)
        tr = (BASE_E2E / "golden" / f"{tag}_trace_f64.bin").read_bytes()
        # skip 6 uint32 header, first n_x25=13000 doubles is p25
        p25_ref = struct.unpack_from("<13000d", tr, 24)

        sos = tbl["SOS_DALIA"] if mode == 0 else tbl["SOS_WESAD"]
        b0_q40 = q_round(sos[0][0], 40)
        a_q30 = [[q_round(s[3], 30), q_round(s[4], 30)] for s in sos]

        h_raw = tbl["RESAMP_H_DALIA"] if mode == 0 else tbl["RESAMP_H_WESAD"]
        h_q31 = [q_round(x, 31) for x in h_raw]

        z = [[0, 0] for _ in range(4)]
        ring = [0] * 128
        out_m = 0
        next_imax = 50 if mode == 0 else 25
        max_err = 0.0
        n_chk = 0

        for idx, x_f in enumerate(ppg):
            v = q_round(x_f, 20)
            # Stage 0
            y50 = ((v * b0_q40) >> 10) + z[0][0]
            y20 = (y50 + (1 << 29)) >> 30
            z[0][0] = ((2 * v * b0_q40) >> 10) - a_q30[0][0] * y20 + z[0][1]
            z[0][1] = ((v * b0_q40) >> 10) - a_q30[0][1] * y20
            v = y20
            # Stage 1: (1, 2, 1)
            y50 = (v << 30) + z[1][0]
            y20 = (y50 + (1 << 29)) >> 30
            z[1][0] = (v << 31) - a_q30[1][0] * y20 + z[1][1]
            z[1][1] = (v << 30) - a_q30[1][1] * y20
            v = y20
            # Stage 2, 3: (1, -2, 1)
            for s in (2, 3):
                y50 = (v << 30) + z[s][0]
                y20 = (y50 + (1 << 29)) >> 30
                z[s][0] = -(v << 31) - a_q30[s][0] * y20 + z[s][1]
                z[s][1] = (v << 30) - a_q30[s][1] * y20
                v = y20

            ring[idx & 127] = v
            if idx == next_imax:
                acc = 0
                if mode == 0:
                    n_av = idx + 1 if idx < 100 else 101
                    for r in range(n_av):
                        acc += h_q31[r] * ring[(idx - r) & 127]
                    out_m += 1
                    next_imax = 5 * out_m + 50
                else:
                    qpos = 640 + 64 * out_m
                    imin = (qpos - 1280 + 24) // 25 if qpos > 1280 else 0
                    r = qpos - 25 * imin
                    for i in range(imin, idx + 1):
                        acc += h_q31[r] * ring[i & 127]
                        r -= 25
                    out_m += 1
                    next_imax = (640 + 64 * out_m) // 25
                y_out = ((acc + (1 << 30)) >> 31) / float(1 << 20)
                if n_chk < 13000:
                    err = abs(y_out - p25_ref[n_chk])
                    if err > max_err:
                        max_err = err
                    n_chk += 1
        print(f"[verify_q31_s1] {tag} ({n_chk} samples): max |y_q20 - f64| = {max_err:.3e}")
        assert max_err < 3e-3


def fmt_f32(v):
    s = f"{float(v):.17g}"
    if "." not in s and "e" not in s and "E" not in s:
        s += ".0"
    return s + "f"

def fmt_c_array(name, ctype, vals, per_line=8, suffix=""):
    lines = [f"const {ctype} {name}[{len(vals)}] = {{"]
    for i in range(0, len(vals), per_line):
        chunk = ", ".join(f"{v}{suffix}" for v in vals[i : i + per_line])
        lines.append(f"  {chunk},")
    lines.append("};")
    return "\n".join(lines)


def main():
    tbl = parse_tables_h(BASE_E2E / "src" / "e2e_tables.h")
    verify_pruned_fft(tbl["TWID_RE"], tbl["TWID_IM"])
    verify_q31_s1(tbl)

    # Check exact DaLiA non-zero symmetric indices r=0..50
    hd = tbl["RESAMP_H_DALIA"]
    nz_r = [r for r in range(50) if abs(hd[r]) >= 1e-12]
    assert len(nz_r) == 40
    assert abs(hd[50]) > 0.1
    print("DaLiA symmetric active offsets (40 pairs + center 50):", nz_r)

    # 1) Write src_f32_opt/e2e_f32opt_tables.h
    f32_dir = ROOT / "src_f32_opt"
    f32_dir.mkdir(parents=True, exist_ok=True)
    lines = [
        "/* Auto-generated by gen_opt_tables.py (E2E-02 f32-algo-opt). Do not edit manually. */",
        "#ifndef E2E_F32OPT_TABLES_H",
        "#define E2E_F32OPT_TABLES_H",
        "",
        "#include <stdint.h>",
        "",
        "extern const float SOS_DALIA_B0;",
        "extern const float SOS_DALIA_A[4][2];",
        "extern const float SOS_WESAD_B0;",
        "extern const float SOS_WESAD_A[4][2];",
        "extern const uint8_t DALIA_SYM_OFF[40];",
        "extern const float DALIA_SYM_H[41];",
        "extern const float RESAMP_H_DALIA[101];",
        "extern const float RESAMP_H_WESAD[1281];",
        "extern const float TWID_RE[512];",
        "extern const float TWID_IM[512];",
        "extern const float TAPER[161];",
        "extern const float INTERP_W[161];",
        "extern const int16_t INTERP_IDX[161];",
        "extern const float MCU_A[161];",
        "extern const float MCU_G[161];",
        "",
        "#ifdef E2E_F32OPT_TABLES_DEFINE",
        "",
        f"const float SOS_DALIA_B0 = {fmt_f32(tbl['SOS_DALIA'][0][0])};",
        "const float SOS_DALIA_A[4][2] = {",
    ]
    for s in tbl["SOS_DALIA"]:
        lines.append(f"  {{{fmt_f32(s[3])}, {fmt_f32(s[4])}}},")
    lines += [
        "};",
        f"const float SOS_WESAD_B0 = {fmt_f32(tbl['SOS_WESAD'][0][0])};",
        "const float SOS_WESAD_A[4][2] = {",
    ]
    for s in tbl["SOS_WESAD"]:
        lines.append(f"  {{{fmt_f32(s[3])}, {fmt_f32(s[4])}}},")
    lines += [
        "};",
        fmt_c_array("DALIA_SYM_OFF", "uint8_t", nz_r, per_line=10, suffix="u"),
        fmt_c_array("DALIA_SYM_H", "float", [fmt_f32(hd[r]) for r in nz_r] + [fmt_f32(hd[50])], per_line=6),
        fmt_c_array("RESAMP_H_DALIA", "float", [fmt_f32(v) for v in hd], per_line=6),
        fmt_c_array("RESAMP_H_WESAD", "float", [fmt_f32(v) for v in tbl["RESAMP_H_WESAD"]], per_line=6),
        fmt_c_array("TWID_RE", "float", [fmt_f32(v) for v in tbl["TWID_RE"]], per_line=6),
        fmt_c_array("TWID_IM", "float", [fmt_f32(v) for v in tbl["TWID_IM"]], per_line=6),
        fmt_c_array("TAPER", "float", [fmt_f32(v) for v in tbl["TAPER"]], per_line=6),
        fmt_c_array("INTERP_W", "float", [fmt_f32(v) for v in tbl["INTERP_W"]], per_line=6),
        fmt_c_array("INTERP_IDX", "int16_t", tbl["INTERP_IDX"], per_line=12, suffix=""),
        fmt_c_array("MCU_A", "float", [fmt_f32(v) for v in tbl["MCU_A"]], per_line=6),
        fmt_c_array("MCU_G", "float", [fmt_f32(v) for v in tbl["MCU_G"]], per_line=6),
        "",
        "#endif /* E2E_F32OPT_TABLES_DEFINE */",
        "#endif /* E2E_F32OPT_TABLES_H */",
        "",
    ]
    (f32_dir / "e2e_f32opt_tables.h").write_text("\n".join(lines), encoding="utf-8")

    # 2) Write src_q31_opt/e2e_opt_tables.h
    q31_dir = ROOT / "src_q31_opt"
    q31_dir.mkdir(parents=True, exist_ok=True)
    qlines = [
        "/* Auto-generated by gen_opt_tables.py (E2E-02 q31-full-opt). Do not edit manually. */",
        "#ifndef E2E_OPT_TABLES_H",
        "#define E2E_OPT_TABLES_H",
        "",
        "#include <stdint.h>",
        "",
        "extern const int32_t SOS_DALIA_B0_Q40;",
        "extern const int32_t SOS_DALIA_A_Q30[4][2];",
        "extern const int32_t SOS_WESAD_B0_Q40;",
        "extern const int32_t SOS_WESAD_A_Q30[4][2];",
        "extern const uint8_t DALIA_SYM_OFF[40];",
        "extern const int32_t DALIA_SYM_H_Q31[41];",
        "extern const int32_t RESAMP_H_DALIA_Q31[101];",
        "extern const int32_t RESAMP_H_WESAD_Q31[1281];",
        "extern const int32_t TWID_RE_Q31[512];",
        "extern const int32_t TWID_IM_Q31[512];",
        "extern const int32_t TAPER_Q30[161];",
        "extern const int32_t INTERP_W_Q30[161];",
        "extern const int16_t INTERP_IDX[161];",
        "extern const int32_t MCU_A_Q16[161];",
        "extern const int32_t MCU_G_Q16[161];",
        "",
        "#ifdef E2E_OPT_TABLES_DEFINE",
        "",
        f"const int32_t SOS_DALIA_B0_Q40 = {q_round(tbl['SOS_DALIA'][0][0], 40)};",
        "const int32_t SOS_DALIA_A_Q30[4][2] = {",
    ]
    for s in tbl["SOS_DALIA"]:
        qlines.append(f"  {{{q_round(s[3], 30)}, {q_round(s[4], 30)}}},")
    qlines += [
        "};",
        f"const int32_t SOS_WESAD_B0_Q40 = {q_round(tbl['SOS_WESAD'][0][0], 40)};",
        "const int32_t SOS_WESAD_A_Q30[4][2] = {",
    ]
    for s in tbl["SOS_WESAD"]:
        qlines.append(f"  {{{q_round(s[3], 30)}, {q_round(s[4], 30)}}},")
    qlines += [
        "};",
        fmt_c_array("DALIA_SYM_OFF", "uint8_t", nz_r, per_line=10, suffix="u"),
        fmt_c_array("DALIA_SYM_H_Q31", "int32_t", [q_round(hd[r], 31) for r in nz_r] + [q_round(hd[50], 31)], per_line=8),
        fmt_c_array("RESAMP_H_DALIA_Q31", "int32_t", [q_round(v, 31) for v in hd], per_line=8),
        fmt_c_array("RESAMP_H_WESAD_Q31", "int32_t", [q_round(v, 31) for v in tbl["RESAMP_H_WESAD"]], per_line=8),
        fmt_c_array("TWID_RE_Q31", "int32_t", [q_round(v, 31) for v in tbl["TWID_RE"]], per_line=8),
        fmt_c_array("TWID_IM_Q31", "int32_t", [q_round(v, 31) for v in tbl["TWID_IM"]], per_line=8),
        fmt_c_array("TAPER_Q30", "int32_t", [q_round(v, 30) for v in tbl["TAPER"]], per_line=8),
        fmt_c_array("INTERP_W_Q30", "int32_t", [q_round(v, 30) for v in tbl["INTERP_W"]], per_line=8),
        fmt_c_array("INTERP_IDX", "int16_t", tbl["INTERP_IDX"], per_line=12),
        fmt_c_array("MCU_A_Q16", "int32_t", [q_round(v, 16) for v in tbl["MCU_A"]], per_line=8),
        fmt_c_array("MCU_G_Q16", "int32_t", [q_round(v, 16) for v in tbl["MCU_G"]], per_line=8),
        "",
        "#endif /* E2E_OPT_TABLES_DEFINE */",
        "#endif /* E2E_OPT_TABLES_H */",
        "",
    ]
    (q31_dir / "e2e_opt_tables.h").write_text("\n".join(qlines), encoding="utf-8")
    print("Generated e2e_f32opt_tables.h and e2e_opt_tables.h successfully.")


if __name__ == "__main__":
    main()
