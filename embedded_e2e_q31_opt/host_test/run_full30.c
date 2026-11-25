/* Standalone PC host runner for full 30-subject evaluation of exact MCU C99 sources */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef USE_E2E01_HDR
#include "dspit_e2e.h"
#else
#include "dspit_opt.h"
#endif

static uint32_t read_u32(FILE *f)
{
    uint32_t v = 0u;
    if (fread(&v, sizeof(uint32_t), 1u, f) != 1u) {
        fprintf(stderr, "Failed reading uint32 header\n");
        exit(2);
    }
    return v;
}

int main(int argc, char **argv)
{
    if (argc != 5) {
        fprintf(stderr, "Usage: %s <raw_f32_bin> <out_es_f32_bin> <mode:0|1> <banded:0|1>\n", argv[0]);
        return 1;
    }
    const char *in_path = argv[1];
    const char *out_path = argv[2];
    const uint8_t mode = (uint8_t)atoi(argv[3]);
    const uint8_t banded = (uint8_t)atoi(argv[4]);

    FILE *fi = fopen(in_path, "rb");
    if (!fi) {
        fprintf(stderr, "Cannot open input: %s\n", in_path);
        return 2;
    }
    const uint32_t n_ppg = read_u32(fi);
    const uint32_t n_acc = read_u32(fi);

    float *ppg = (float *)malloc((size_t)n_ppg * sizeof(float));
    float *ax  = (float *)malloc((size_t)n_acc * sizeof(float));
    float *ay  = (float *)malloc((size_t)n_acc * sizeof(float));
    float *az  = (float *)malloc((size_t)n_acc * sizeof(float));
    if (!ppg || !ax || !ay || !az) {
        fprintf(stderr, "OOM input buffers\n");
        return 3;
    }
    if (fread(ppg, sizeof(float), n_ppg, fi) != n_ppg ||
        fread(ax,  sizeof(float), n_acc, fi) != n_acc ||
        fread(ay,  sizeof(float), n_acc, fi) != n_acc ||
        fread(az,  sizeof(float), n_acc, fi) != n_acc) {
        fprintf(stderr, "Short input read\n");
        return 4;
    }
    fclose(fi);

    const uint32_t es_cap = (n_ppg / 40u) + 128u;
    float *es_out = (float *)malloc((size_t)es_cap * sizeof(float));
    if (!es_out) {
        fprintf(stderr, "OOM es_out\n");
        return 5;
    }
    for (uint32_t i = 0u; i < es_cap; i++) {
        es_out[i] = NAN;
    }

    static dspit_e2e_t st;
    dspit_init(&st, mode, banded);

    const uint32_t blk_ppg = (mode == 0u) ? E2E_DALIA_BLK : E2E_WESAD_BLK;
    const uint32_t blk_acc = (mode == 0u) ? E2E_DALIA_BLK : E2E_WESAD_ABLK;
    uint32_t p_off = 0u;
    uint32_t a_off = 0u;
    uint32_t n_es = 0u;

    while (p_off < n_ppg || a_off < n_acc) {
        uint32_t np = n_ppg - p_off;
        uint32_t na = n_acc - a_off;
        if (np > blk_ppg) { np = blk_ppg; }
        if (na > blk_acc) { na = blk_acc; }

        dspit_block_out_t bout;
        dspit_push_block(&st,
                         ppg + p_off, np,
                         ax + a_off, ay + a_off, az + a_off, na,
                         &bout, NULL, NULL);
        if (bout.has_es && bout.es_index < es_cap) {
            es_out[bout.es_index] = bout.es_bpm;
            if (bout.es_index + 1u > n_es) {
                n_es = bout.es_index + 1u;
            }
        }
        p_off += np;
        a_off += na;
    }

    /* Flush 0.4-s polyphase FIR group delay without exceeding resample output length */
    const uint32_t flush_ppg = (mode == 0u) ? 50u : 26u;
    const uint32_t flush_acc = (mode == 0u) ? 50u : 13u;
    float z_ppg[64] = {0.0f};
    float z_acc[64] = {0.0f};
    dspit_block_out_t bout;
    dspit_push_block(&st, z_ppg, flush_ppg, z_acc, z_acc, z_acc, flush_acc, &bout, NULL, NULL);
    if (bout.has_es && bout.es_index < es_cap) {
        es_out[bout.es_index] = bout.es_bpm;
        if (bout.es_index + 1u > n_es) {
            n_es = bout.es_index + 1u;
        }
    }

    FILE *fo = fopen(out_path, "wb");
    if (!fo) {
        fprintf(stderr, "Cannot open output: %s\n", out_path);
        return 6;
    }
    fwrite(&n_es, sizeof(uint32_t), 1u, fo);
    if (n_es > 0u) {
        fwrite(es_out, sizeof(float), n_es, fo);
    }
    fclose(fo);

    free(es_out);
    free(ppg);
    free(ax);
    free(ay);
    free(az);
    return 0;
}
