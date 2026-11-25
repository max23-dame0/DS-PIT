function exp_export_e2e()
% E2E-01 (2026-11-24): Export golden traces, raw inputs, and C header tables
% for full end-to-end DS-PIT benchmarking on STM32F103 Cortex-M3.
%
% Data root is read from getenv('DSPIT_DATA_ROOT') (fallback 'X:');
% NO local absolute paths are hardcoded.
%
% Three reference checks logged to results/e2e_export_log.txt:
%   Check A: full-recording filter(b,a) + resample vs cache2 S/A (<= 1e-10)
%   Check B: quantized raw prefix (522 s, 257 windows) with zp2sos 4-stage SOS
%            + resample + ds5(base+a2_cfg) -> host REAL_DOUBLE exact reference
%   Check C: Check B (254 eval windows) vs full-recording cache2 ds5 output

here = fileparts(mfilename('fullpath'));
mdev = fullfile(here, '..', 'method_dev');
addpath(mdev);

dataRoot = getenv('DSPIT_DATA_ROOT');
if isempty(dataRoot), dataRoot = 'X:'; end

gdir = fullfile(here, 'golden');
sdir = fullfile(here, 'src');
rdir = fullfile(here, 'results');
if ~exist(gdir, 'dir'), mkdir(gdir); end
if ~exist(sdir, 'dir'), mkdir(sdir); end
if ~exist(rdir, 'dir'), mkdir(rdir); end

logFile = fullfile(rdir, 'e2e_export_log.txt');
if exist(logFile, 'file'), delete(logFile); end
diary(logFile);

fprintf('=== E2E-01 export start %s ===\n', datestr(now)); %#ok<TNOW1,DATST>

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');
o = a2_cfg(base);

% Quick regression gate before export
r_base_d = ds5('dalia', 1:15, base);
r_base_w = ds5('wesad', 1:15, base);
r_a2_d   = ds5('dalia', 1:15, o);
r_a2_w   = ds5('wesad', 1:15, o);
fprintf('[REG] base=(%.4f, %.4f) a2_cfg=(%.4f, %.4f)\n', ...
    r_base_d.mean, r_base_w.mean, r_a2_d.mean, r_a2_w.mean);
assert(abs(r_base_d.mean - 5.9584) < 1e-4 && abs(r_base_w.mean - 5.7836) < 1e-4, 'base regression mismatch');
assert(abs(r_a2_d.mean - 5.8302) < 1e-4 && abs(r_a2_w.mean - 5.7569) < 1e-4, 'a2_cfg regression mismatch');

N_FFT = 1024;
FSD = 25;
WS = 8 * FSD;   % 200
HS = 2 * FSD;   % 50
N_WIN_E2E = 257;
N_EVAL = 254;   % est(1..255) -> es(1..254) valid without right-edge NaN
SEC_PREFIX = 522; % 261 blocks of 2 s (>= 520 s needed for 257 wins + 0.4 s resample margin)

f_all = (0:N_FFT - 1) * (FSD / N_FFT);
sel = find(f_all >= 0.35 & f_all <= 4.5);
fb = f_all(sel);
inb = fb >= o.state_lo_hz & fb <= o.state_hi_hz;
fbc = fb(inb);
nb = numel(fbc);
sb = o.f_lo:1:o.f_hi;
K = numel(sb);
assert(nb == 92 && K == 161, 'Unexpected nb or K');

% Filter designs
[b_d, a_d] = butter(4, [0.4 4] / (125 / 2), 'bandpass');
[zd, pd, kd] = butter(4, [0.4 4] / (125 / 2), 'bandpass');
[sos_d, g_d] = zp2sos(zd, pd, kd);
sos_d(1, 1:3) = sos_d(1, 1:3) * g_d;

[b_w, a_w] = butter(4, [0.4 4] / (64 / 2), 'bandpass');
[zw, pw, kw] = butter(4, [0.4 4] / (64 / 2), 'bandpass');
[sos_w, g_w] = zp2sos(zw, pw, kw);
sos_w(1, 1:3) = sos_w(1, 1:3) * g_w;

[~, h_d] = resample(zeros(1, 100), 25, 125);
[~, h_w] = resample(zeros(1, 100), 25, 64);

% Target 5 records matching EMB-01
recs = {
    'dalia', 1, 's1',  125, 0;
    'dalia', 2, 's2',  125, 0;
    'dalia', 3, 's3',  125, 0;
    'wesad', 1, 'ws1',  64, 1;
    'wesad', 2, 'ws2',  64, 1;
};

for ri = 1:size(recs, 1)
    dsname = recs{ri, 1};
    subj   = recs{ri, 2};
    tag    = recs{ri, 3};
    fs_in  = recs{ri, 4};
    ds_id  = recs{ri, 5};

    [ppg, acc, gt_full, act_full, sid] = load_raw_rec(dataRoot, mdev, dsname, subj);

    % ---- Check A: Full-recording prep_dump2 reproduction vs cache2 ----
    if ds_id == 0
        b_ref = b_d; a_ref = a_d; sos_use = sos_d;
    else
        b_ref = b_w; a_ref = a_w; sos_use = sos_w;
    end
    p_tf = filter(b_ref, a_ref, ppg);
    ac_tf = zeros(3, numel(ppg));
    for j = 1:3, ac_tf(j, :) = filter(b_ref, a_ref, acc(j, :)); end
    p_tf = resample(p_tf, FSD, fs_in);
    acr_tf = zeros(3, numel(p_tf));
    for j = 1:3, acr_tf(j, :) = resample(ac_tf(j, :), FSD, fs_in); end
    nWin_full = floor((numel(p_tf) - WS) / HS) + 1;
    S_rep = zeros(nWin_full, N_FFT);
    A_rep = zeros(nWin_full, N_FFT, 3);
    for k = 1:nWin_full
        idx = (k - 1) * HS + (1:WS);
        x0 = p_tf(idx);
        x = (x0 - mean(x0)) / (std(x0) + eps);
        S_rep(k, :) = fft(x, N_FFT);
        for j = 1:3
            y0 = acr_tf(j, idx);
            y = (y0 - mean(y0)) / (std(y0) + eps);
            A_rep(k, :, j) = fft(y, N_FFT);
        end
    end
    S_rep = S_rep(:, sel); A_rep = A_rep(:, sel, :);
    C2 = load(fullfile(mdev, 'cache2', sprintf('%s_S%d.mat', dsname, subj)));
    relS = max(abs(S_rep(:, inb) - C2.S(:, inb)), [], 'all') / max(abs(C2.S(:, inb)), [], 'all');
    relA = max(abs(A_rep(:, inb, :) - C2.A(:, inb, :)), [], 'all') / max(abs(C2.A(:, inb, :)), [], 'all');
    fprintf('[Check A] %s (%s %s): relErr_S=%.3e relErr_A=%.3e (thresh <=1e-10)\n', ...
        tag, dsname, sid, relS, relA);
    assert(relS <= 1e-10 && relA <= 1e-10, sprintf('Check A failed for %s', tag));

    % Full-recording cache2 ds5 reference
    oc2 = o; oc2.dump_trace = true;
    rc2 = ds5(dsname, subj, oc2);
    est_c2 = rc2.trace{1}.est(1:N_EVAL);
    es_c2  = rc2.trace{1}.es(1:N_EVAL);

    % ---- Check B: Raw prefix quantized to single -> double, SOS filter + resample + ds5 ----
    n_ppg = SEC_PREFIX * fs_in;
    if ds_id == 0
        n_acc = n_ppg;
        raw_ppg_f32 = single(ppg(1:n_ppg));
        raw_acc_f32 = single(acc(:, 1:n_acc));
        ppg_in = double(raw_ppg_f32);
        acc_in = double(raw_acc_f32);
    else
        n_acc = SEC_PREFIX * 32;
        % Re-read original 32 Hz ACC from raw file for exact WESAD ACC input
        D_w = load(fullfile(dataRoot, 'PPG-WESAD', sprintf('%s.mat', sid)));
        aa_w = double(D_w.ACC); if size(aa_w, 1) == 3, aa_w = aa_w'; end
        raw_ppg_f32 = single(double(D_w.BVP(1:n_ppg))');
        raw_acc_f32 = single(aa_w(1:n_acc, :)');  % 3 x n_acc
        ppg_in = double(raw_ppg_f32);
        acc_32_in = double(raw_acc_f32);
        t_a = (0:n_acc - 1) / 32;
        t_p = (0:n_ppg - 1) / 64;
        acc_in = zeros(3, n_ppg);
        for j = 1:3
            acc_in(j, :) = interp1(t_a, acc_32_in(j, :), t_p, 'linear', 'extrap');
        end
    end

    p_sos = sosfilt(sos_use, ppg_in);
    ac_sos = zeros(3, n_ppg);
    for j = 1:3, ac_sos(j, :) = sosfilt(sos_use, acc_in(j, :)); end

    p25 = resample(p_sos, FSD, fs_in);
    a25 = zeros(3, numel(p25));
    for j = 1:3, a25(j, :) = resample(ac_sos(j, :), FSD, fs_in); end

    n25_need = WS + (N_WIN_E2E - 1) * HS;  % 13000 samples (520 s)
    p25 = p25(1:n25_need);
    a25 = a25(:, 1:n25_need);

    S_b = zeros(N_WIN_E2E, numel(sel));
    A_b = zeros(N_WIN_E2E, numel(sel), 3);
    X_b = zeros(N_WIN_E2E, WS);
    rmsP_b = zeros(1, N_WIN_E2E);
    rmsA_b = zeros(3, N_WIN_E2E);
    for k = 1:N_WIN_E2E
        idx = (k - 1) * HS + (1:WS);
        x0 = p25(idx);
        rmsP_b(k) = std(x0);
        for j = 1:3, rmsA_b(j, k) = std(a25(j, idx)); end
        x = (x0 - mean(x0)) / (std(x0) + eps);
        X_b(k, :) = x;
        Sf = fft(x, N_FFT);
        S_b(k, :) = Sf(sel);
        for j = 1:3
            y0 = a25(j, idx);
            y = (y0 - mean(y0)) / (std(y0) + eps);
            Af = fft(y, N_FFT);
            A_b(k, :, j) = Af(sel);
        end
    end

    F_b = struct();
    F_b.S = S_b; F_b.A = A_b; F_b.X = X_b;
    F_b.fb = fb; F_b.gt = gt_full(1:N_WIN_E2E); F_b.act = act_full(1:N_WIN_E2E);
    F_b.rmsP = rmsP_b; F_b.rmsA = rmsA_b; F_b.nWin = N_WIN_E2E;

    ob = o; ob.dump_trace = true; ob.F_data = {F_b};
    rb = ds5(dsname, subj, ob);
    tr = rb.trace{1};

    % ---- Check C: SOS double prefix vs full cache2 ----
    est_b = tr.est(1:N_EVAL);
    es_b  = tr.es(1:N_EVAL);
    gt_e  = F_b.gt(1:N_EVAL);
    act_e = F_b.act(1:N_EVAL);
    if ds_id == 1
        msk = ~isnan(es_b) & ~isnan(gt_e) & act_e > 0 & act_e < 5 & gt_e > 0;
    else
        msk = ~isnan(es_b) & ~isnan(gt_e) & gt_e > 0;
    end
    agree_est = mean(est_b == est_c2);
    agree_es  = mean(es_b == es_c2);
    mae_b  = mean(abs(gt_e(msk) - es_b(msk)));
    mae_c2 = mean(abs(gt_e(msk) - es_c2(msk)));
    fprintf('[Check B vs C] %s: agree_est=%.4f (%.0f/254) agree_es=%.4f (%.0f/254) max|d_es|=%.4f MAE_b=%.4f MAE_c2=%.4f diff=%.4f\n', ...
        tag, agree_est, sum(est_b == est_c2), agree_es, sum(es_b == es_c2), ...
        max(abs(es_b - es_c2)), mae_b, mae_c2, abs(mae_b - mae_c2));

    % ---- Write golden binary files ----
    rawFile = fullfile(gdir, sprintf('%s_raw_f32.bin', tag));
    fid = fopen(rawFile, 'wb');
    fwrite(fid, uint32(hex2dec('45324552')), 'uint32'); % 'E2ER'
    fwrite(fid, uint32(ds_id), 'uint32');
    fwrite(fid, uint32(n_ppg), 'uint32');
    fwrite(fid, uint32(n_acc), 'uint32');
    fwrite(fid, uint32(N_WIN_E2E), 'uint32');
    fwrite(fid, uint32(N_EVAL), 'uint32');
    fwrite(fid, single(raw_ppg_f32(:)), 'float32');
    for j = 1:3
        fwrite(fid, single(raw_acc_f32(j, :)), 'float32');
    end
    fclose(fid);

    trFile = fullfile(gdir, sprintf('%s_trace_f64.bin', tag));
    fid = fopen(trFile, 'wb');
    fwrite(fid, uint32(hex2dec('45324554')), 'uint32'); % 'E2ET'
    fwrite(fid, uint32(ds_id), 'uint32');
    fwrite(fid, uint32(N_WIN_E2E), 'uint32');
    fwrite(fid, uint32(N_EVAL), 'uint32');
    fwrite(fid, uint32(nb), 'uint32');
    fwrite(fid, uint32(K), 'uint32');
    fwrite(fid, double(p25(:)), 'float64');            % 13000
    for j = 1:3, fwrite(fid, double(a25(j, :)), 'float64'); end % 3 x 13000
    fwrite(fid, double(abs(S_b(:, inb).')), 'float64');  % nb x 257 (window-major)
    for j = 1:3
        fwrite(fid, double(abs(A_b(:, inb, j).')), 'float64'); % nb x 257
    end
    fwrite(fid, double(tr.obv), 'float64');            % nb x 257
    fwrite(fid, double(tr.Psp), 'float64');            % K x 257
    fwrite(fid, double(tr.L), 'float64');              % K x 257
    fwrite(fid, double(tr.logL_pre), 'float64');       % K x 257
    tau_eff = tr.tau_c; tau_eff(isnan(tau_eff)) = 1.0;
    fwrite(fid, double(tau_eff(:)), 'float64');        % 257
    fwrite(fid, double(tr.logL_post), 'float64');      % K x 257
    fwrite(fid, double(est_b(:)), 'float64');          % 254
    fwrite(fid, double(es_b(:)), 'float64');           % 254
    fwrite(fid, double(est_c2(:)), 'float64');         % 254
    fwrite(fid, double(es_c2(:)), 'float64');          % 254
    fwrite(fid, double(gt_e(:)), 'float64');           % 254
    fwrite(fid, double(msk(:)), 'float64');            % 254 (1=eval valid, 0=skip)
    fclose(fid);
end

% ---- Generate src/e2e_tables.h ----
write_tables_header(fullfile(sdir, 'e2e_tables.h'), ...
    sos_d, sos_w, h_d, h_w, fbc, sb, o.sigma, o.state_lo_hz, o.state_hi_hz, o.edge_taper, N_FFT);

fprintf('=== E2E-01 export done ===\n');
diary off;
end

function [ppg, acc, gt, act, sid] = load_raw_rec(dataRoot, mdev, dsname, subj)
switch dsname
    case 'dalia'
        D = load(fullfile(dataRoot, 'PPG-dalia', 'PPG_data', sprintf('S%d.mat', subj)));
        sig = D.sig; sid = sprintf('S%d', subj);
        ppg = sig(1, :); acc = sig(3:5, :);
        G = load(fullfile(dataRoot, 'PPG-dalia', 'BPM_data', sprintf('S%d_BPMtrace.mat', subj)));
        gt = G.BPM0(:)';
        actFile = fullfile(mdev, 'results', 'dalia_activity.mat');
        if exist(actFile, 'file')
            AV = load(actFile); act = AV.A{subj}(:).';
            if numel(act) < numel(gt), act(end+1:numel(gt)) = 9; end
        else
            act = ones(1, numel(gt));
        end
    case 'wesad'
        ids = {'S2','S3'};
        sid = ids{subj};
        D = load(fullfile(dataRoot, 'PPG-WESAD', sprintf('%s.mat', sid)));
        ppg = double(D.BVP(:))'; fs_in = 64;
        aa = double(D.ACC); if size(aa, 1) == 3, aa = aa'; end
        t_a = (0:size(aa, 1) - 1) / 32; t_p = (0:numel(ppg) - 1) / fs_in;
        acc = zeros(3, numel(ppg));
        for j = 1:3, acc(j, :) = interp1(t_a, aa(:, j), t_p, 'linear', 'extrap'); end
        bpm0 = double(D.BPM0(:))'; actR = double(D.Activity(:))';
        ws = 8 * fs_in; hs = 2 * fs_in;
        nWin = floor((numel(ppg) - ws) / hs) + 1;
        gt = nan(1, nWin); act = nan(1, nWin);
        for k = 1:nWin
            i0 = (k - 1) * hs + 1; i1 = i0 + ws - 1;
            if i1 <= numel(bpm0), gt(k) = mean(bpm0(i0:i1)); act(k) = mode(actR(i0:i1)); end
        end
end
end

function write_tables_header(outPath, sos_d, sos_w, h_d, h_w, fbc, sb, sig, lo_hz, hi_hz, wq, N_FFT)
K = numel(sb);
d = (1:K)' - (1:K);
a_vec = -log(sum(exp(-(d.^2) / (2 * sig^2)), 2));
g_vec = -((0:K-1).^2) / (2 * sig^2);

% Taper
lo_q = 60 * lo_hz; hi_q = 60 * hi_hz;
taper = min(1, max(0, (sb - lo_q) / wq)) .* min(1, max(0, (hi_q - sb) / wq));

% Linear interp mapping from 60*fbc to sb
fbpm = 60 * fbc;
idx_map = zeros(1, K);
w_map = zeros(1, K);
for j = 1:K
    if sb(j) < fbpm(1) || sb(j) > fbpm(end)
        idx_map(j) = -1;
        w_map(j) = 0.0;
    else
        m = find(fbpm <= sb(j), 1, 'last');
        if m >= numel(fbpm)
            idx_map(j) = numel(fbpm) - 2;
            w_map(j) = 1.0;
        else
            idx_map(j) = m - 1; % 0-based
            w_map(j) = (sb(j) - fbpm(m)) / (fbpm(m + 1) - fbpm(m));
        end
    end
end

% Radix-2 FFT twiddles: W_N^k = cos(2*pi*k/N) - j*sin(2*pi*k/N)
k_tw = 0:(N_FFT / 2 - 1);
tw_re = cos(2 * pi * k_tw / N_FFT);
tw_im = -sin(2 * pi * k_tw / N_FFT);

fh = fopen(outPath, 'w');
fprintf(fh, '/* Auto-generated by exp_export_e2e.m (E2E-01, 2026-11-24). Do not edit manually. */\n');
fprintf(fh, '#ifndef E2E_TABLES_H\n#define E2E_TABLES_H\n\n');
fprintf(fh, '#include <stdint.h>\n#include "e2e_config.h"\n\n');
fprintf(fh, 'extern const real_t SOS_DALIA[4][5];\n');
fprintf(fh, 'extern const real_t SOS_WESAD[4][5];\n');
fprintf(fh, 'extern const real_t RESAMP_H_DALIA[101];\n');
fprintf(fh, 'extern const real_t RESAMP_H_WESAD[1281];\n');
fprintf(fh, 'extern const real_t TWID_RE[%d];\n', N_FFT / 2);
fprintf(fh, 'extern const real_t TWID_IM[%d];\n', N_FFT / 2);
fprintf(fh, 'extern const real_t TAPER[%d];\n', K);
fprintf(fh, 'extern const real_t INTERP_W[%d];\n', K);
fprintf(fh, 'extern const real_t MCU_A[%d];\n', K);
fprintf(fh, 'extern const real_t MCU_G[%d];\n', K);
fprintf(fh, 'extern const int16_t INTERP_IDX[%d];\n\n', K);
fprintf(fh, '#ifdef E2E_TABLES_DEFINE\n\n');

% SOS arrays: [4][5] = {b0, b1, b2, a1, a2} (a0=1)
emit_sos(fh, 'SOS_DALIA', sos_d);
emit_sos(fh, 'SOS_WESAD', sos_w);

emit_arr(fh, 'RESAMP_H_DALIA', h_d);
emit_arr(fh, 'RESAMP_H_WESAD', h_w);
emit_arr(fh, 'TWID_RE', tw_re);
emit_arr(fh, 'TWID_IM', tw_im);
emit_arr(fh, 'TAPER', taper);
emit_arr(fh, 'INTERP_W', w_map);
emit_arr(fh, 'MCU_A', a_vec);
emit_arr(fh, 'MCU_G', g_vec);

fprintf(fh, 'const int16_t INTERP_IDX[%d] = {\n', K);
for i = 1:K
    if mod(i - 1, 12) == 0, fprintf(fh, '  '); end
    fprintf(fh, '%d,', idx_map(i));
    if mod(i, 12) == 0, fprintf(fh, '\n'); end
end
fprintf(fh, '\n};\n\n#endif /* E2E_TABLES_DEFINE */\n#endif /* E2E_TABLES_H */\n');
fclose(fh);
fprintf('[tables] wrote %s\n', outPath);
end

function emit_sos(fh, name, sos)
fprintf(fh, 'const real_t %s[4][5] = {\n', name);
for r = 1:4
    vals = [sos(r, 1), sos(r, 2), sos(r, 3), sos(r, 5), sos(r, 6)];
    fprintf(fh, '  {');
    for c = 1:5
        if c > 1, fprintf(fh, ', '); end
        fprintf(fh, 'R_LIT(%.17g)', vals(c));
    end
    fprintf(fh, '},\n');
end
fprintf(fh, '};\n\n');
end

function emit_arr(fh, name, arr)
n = numel(arr);
fprintf(fh, 'const real_t %s[%d] = {\n', name, n);
for i = 1:n
    if mod(i - 1, 4) == 0, fprintf(fh, '  '); end
    fprintf(fh, 'R_LIT(%.17g), ', arr(i));
    if mod(i, 4) == 0, fprintf(fh, '\n'); end
end
fprintf(fh, '\n};\n\n');
end
