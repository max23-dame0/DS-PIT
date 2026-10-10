function prep_winlen(dataset, win_sec)
% R3-C19：生成不同分析窗长的缓存（受控对照）
% 设计：**保持每个窗的终点与目标索引不变，只改变分析窗长度**。
%   8 s 原始窗 k 覆盖样本 [(k-1)*hs+1, (k-1)*hs+ws]，终点 e = (k-1)*hs+ws。
%   窗长 L 的变体覆盖 [e-L+1, e]，窗数、步长与参考序列完全一致，
%   因此两库的 MAE 差异可归因于窗长本身，而非目标错位。
if nargin < 2, win_sec = 8; end
root = fileparts(mfilename('fullpath'));
outdir = fullfile(root, sprintf('cache_w%d', round(win_sec * 10)));
if ~exist(outdir, 'dir'), mkdir(outdir); end
N = 1024; fsd = 25;
f = (0:N - 1) * (fsd / N);
sel = find(f >= 0.35 & f <= 4.5);
fb = f(sel);
switch dataset
    case 'dalia', nS = 15; fs_in = 125;
    case 'wesad', nS = 15; fs_in = 64;
end
fprintf('[%s win=%.1fs] -> %s\n', dataset, win_sec, outdir);
for s = 1:nS
    dst = fullfile(outdir, sprintf('%s_S%d.mat', dataset, s));
    if exist(dst, 'file'), continue; end
    [ppg, acc, ~, ~, ~, ~] = load_raw_local(dataset, s);
    [b, a] = butter(4, [0.4 4] / (fsi_half(dataset)), 'bandpass');
    p = filter(b, a, ppg);
    ac = zeros(3, numel(ppg));
    for j = 1:3, ac(j, :) = filter(b, a, acc(j, :)); end
    [pr, ~] = resample(p, fsd, fs_in);
    acr = zeros(3, numel(pr));
    for j = 1:3, [acr(j, :), ~] = resample(ac(j, :), fsd, fs_in); end
    ws = 8 * fsd; hs = 2 * fsd; L = round(win_sec * fsd);
    nWin = max(0, floor((numel(pr) - ws) / hs) + 1);
    S = zeros(nWin, numel(sel)); A = zeros(nWin, numel(sel), 3);
    if numel(fb) ~= numel(sel), fb = f(sel); end
    X = zeros(nWin, L); Xa = zeros(nWin, L, 3);
    rmsP = zeros(1, nWin); rmsA = zeros(3, nWin);
    for k = 1:nWin
        e = (k - 1) * hs + ws;                 % 窗终点，与 8 s 窗一致
        i0 = max(1, e - L + 1); i1 = e;
        x0 = pr(i0:i1); if numel(x0) < L, x0 = [zeros(1, L - numel(x0)), x0]; end
        rmsP(k) = std(x0);
        x = (x0 - mean(x0)) / (std(x0) + eps);
        X(k, :) = x; Sk = fft(x, N); S(k, :) = Sk(sel);
        for j = 1:3
            y0 = acr(j, i0:i1); if numel(y0) < L, y0 = [zeros(1, L - numel(y0)), y0]; end
            rmsA(j, k) = std(y0);
            y = (y0 - mean(y0)) / (std(y0) + eps);
            Xa(k, :, j) = y; Aj = fft(y, N); A(k, :, j) = Aj(sel);
        end
    end
    fb = fb; nWin = nWin; sid = s;
    save(dst, 'S', 'A', 'X', 'Xa', 'fb', 'nWin', 'sid', 'rmsP', 'rmsA', '-v7.3');
end
% 参考与活动标签沿用 cache2（目标序列不变）
try
    for s = 1:nS
        dst = fullfile(outdir, sprintf('%s_S%d.mat', dataset, s));
        if ~exist(dst, 'file'), continue; end
        C = load(fullfile(root, 'cache2', sprintf('%s_S%d.mat', dataset, s)));
        gt = C.gt; act = C.act;
        save(dst, 'gt', 'act', '-append');
    end
catch e
    fprintf('  gt/act copy failed: %s\n', e.message);
end
fprintf('  done (%d subjects)\n', nS);
end

function h = fsi_half(dataset)
switch dataset
    case 'dalia', h = 125 / 2;
    otherwise, h = 64 / 2;
end
end

function [ppg, acc, gt, act, fs_in, sid] = load_raw_local(dataset, s)
fs_in = 0; gt = []; act = []; sid = s;
if strcmp(dataset, 'dalia')
    D = load(fullfile(get_data_root('PPG-dalia'), 'PPG_data', sprintf('S%d.mat', s)));
    sig = D.sig; fs_in = 125;
    ppg = sig(1, :); acc = sig(3:5, :);
else
    ids = {'S2','S3','S4','S5','S6','S7','S8','S9','S10','S11','S13','S14','S15','S16','S17'};
    D = load(fullfile(get_data_root('PPG-WESAD'), sprintf('%s.mat', ids{s})));
    ppg = double(D.BVP(:))'; fs_in = 64;
    aa = double(D.ACC); if size(aa, 1) == 3, aa = aa'; end
    t_a = (0:size(aa, 1) - 1) / 32; t_p = (0:numel(ppg) - 1) / fs_in;
    acc = zeros(3, numel(ppg));
    for j = 1:3, acc(j, :) = interp1(t_a, aa(:, j), t_p, 'linear', 'extrap'); end
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
