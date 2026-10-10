function prep_dump2(dataset)
% 修正版频谱导出（M01/M02）
%  - 通带放宽到 0.4-8 Hz，覆盖 40-200 BPM 的基频与二次谐波（二次谐波最高 6.67 Hz）
%  - 逐窗保留：PPG 时域窗（25 Hz, 200 点，供自相关/峰间期证据）
%  - 保留跨通道幅度信息：分别记录 PPG 与各 ACC 轴的原始 RMS（标准化前）
%  - 逐窗标准化只用于谱形状；运动强度由 RMS 比值给出
if nargin < 1, dataset = 'dalia'; end
outdir = fullfile(fileparts(mfilename('fullpath')), 'cache2');
if ~exist(outdir, 'dir'), mkdir(outdir); end
N = 1024; fsd = 25;
f = (0:N - 1) * (fsd / N);
sel = find(f >= 0.35 & f <= 4.5);
fb = f(sel); nb = numel(sel);
fprintf('[%s] band bins %d (%.3f-%.3f Hz), Nyquist=%.1f Hz\n', dataset, nb, fb(1), fb(end), fsd / 2);

switch dataset
    case 'dalia', nS = 15; fs_in = 125;
    case 'wesad', nS = 15; fs_in = 64;
end
for s = 1:nS
    [ppg, acc, gt, act, fsi, sid] = load_raw(dataset, s);
    [b, a] = butter(4, [0.4 4] / (fsi / 2), 'bandpass');
    p = filter(b, a, ppg);
    ac = zeros(3, numel(ppg));
    for j = 1:3, ac(j, :) = filter(b, a, acc(j, :)); end
    p = resample(p, fsd, fsi);
    acr = zeros(3, numel(p));
    for j = 1:3, acr(j, :) = resample(ac(j, :), fsd, fsi); end
    ac = acr;
    ws = 8 * fsd; hs = 2 * fsd;
    nWin = floor((numel(p) - ws) / hs) + 1;
    S = zeros(nWin, N); A = zeros(nWin, N, 3);
    X = zeros(nWin, ws);                 % PPG 时域窗（25 Hz, 200 点）
    Xa = zeros(nWin, ws, 3);             % ACC 时域窗（25 Hz, 200 点）
    rmsP = zeros(1, nWin); rmsA = zeros(3, nWin);
    for k = 1:nWin
        idx = (k - 1) * hs + (1:ws);
        x0 = p(idx);
        rmsP(k) = std(x0);
        for j = 1:3, rmsA(j, k) = std(ac(j, idx)); end
        x = (x0 - mean(x0)) / (std(x0) + eps);
        X(k, :) = x;
        S(k, :) = fft(x, N);
        for j = 1:3
            y = ac(j, idx); y = (y - mean(y)) / (std(y) + eps);
            Xa(k, :, j) = y;
            A(k, :, j) = fft(y, N);
        end
    end
    S = S(:, sel); A = A(:, sel, :);
    save(fullfile(outdir, sprintf('%s_S%d.mat', dataset, s)), 'S', 'A', 'X', 'Xa', 'fb', 'gt', 'act', ...
        'rmsP', 'rmsA', 'nWin', 'sid', 'fs_in', 'fsd', '-v7.3');
    fprintf('  %s subj%-2d (id=%s): nWin=%d saved\n', dataset, s, sid, nWin);
end
end

function [ppg, acc, gt, act, fs_in, sid] = load_raw(dataset, s)
switch dataset
    case 'dalia'
        D = load(fullfile(get_data_root('PPG-dalia'), 'PPG_data', sprintf('S%d.mat', s)));
        sig = D.sig; fs_in = 125; sid = sprintf('S%d', s);
        ppg = sig(1, :); acc = sig(3:5, :);
        G = load(fullfile(get_data_root('PPG-dalia'), 'BPM_data', sprintf('S%d_BPMtrace.mat', s)));
        gt = G.BPM0(:)';
        % 修复（2026-09-15）：原为 act = ones(1, numel(gt))，使 DaLiA 活动分层失效。
        % 现优先读取 build_dalia_act.m 生成的逐窗标签；缺失时退回全 1 并告警。
        actFile = fullfile(fileparts(mfilename('fullpath')), 'results', 'dalia_activity.mat');
        if exist(actFile, 'file')
            AV = load(actFile); act = AV.A{s}(:).';
            if numel(act) < numel(gt), act(end+1:numel(gt)) = 9; end
        else
            act = ones(1, numel(gt));
            fprintf('  [warn] dalia_activity.mat 缺失，S%d 的活动标签退回全 1；请先运行 build_dalia_act\n', s);
        end
    case 'wesad'
        ids = {'S2','S3','S4','S5','S6','S7','S8','S9','S10','S11','S13','S14','S15','S16','S17'};
        D = load(fullfile(get_data_root('PPG-WESAD'), sprintf('%s.mat', ids{s})));
        sid = ids{s};
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

function r = get_data_root(sub)
base = getenv('DSPIT_DATA_ROOT');
if isempty(base)
    if exist(fullfile('X:\', sub), 'dir'), r = fullfile('X:\', sub); return; end
    base = fullfile(fileparts(mfilename('fullpath')), '..', 'raw_data');
end
r = fullfile(base, sub);
end
