function prep_ieee()
% 构建 IEEE SPC 2015 的宽带缓存（与 prep_dump2 输出同构，供 ds5 直接读取）
%
% 数据：X:\all_data\（X: 是 D: 的映射）——PPG_data / BPM_data
%   23 条记录 = 12 条 training（DATA_01..DATA_12）+ 11 条 test
%   （TEST_S01..S08 共 10 条 + 1 条 DATA_S04_T01，见 WFPV_OVD_PISC.m 的 IDData）
%
% 通道映射来自投稿版代码 WFPV_OVD_PISC.m:69-73（权威）：
%   idnb>13（测试段）：ch1..ch5 = 1,2,3,4,5
%   否则（训练段）    ：ch1..ch5 = 2,3,4,5,6   ← 训练 sig 有 6 行，第 1 行不用
%
% 预处理复现投稿版 WFPV_OVD_PISC.m:20,101-110：
%   4 阶 Butterworth 带通 0.4–4 Hz（因果 filter）→ 两路 PPG 各自 z-score 后等权平均
%   → downsample 5 倍（125→25 Hz）。抗混叠由该 0.4–4 Hz 带通提供（4 Hz < 12.5 Hz）
%
% 真值：BPM0（0.5 Hz，即每 2 s 一个值），长度恰等于窗数，逐窗直接对应。

root = fileparts(mfilename('fullpath'));
outdir = fullfile(root, 'cache2');
srcdir = getenv('DSPIT_IEEE_ROOT'); if isempty(srcdir), if exist('X:\all_data','dir'), srcdir='X:\all_data'; else, srcdir=fullfile(fileparts(mfilename('fullpath')),'..','raw_data','all_data'); end; end

ID = {'DATA_01_TYPE01','DATA_02_TYPE02','DATA_03_TYPE02','DATA_04_TYPE02', ...
      'DATA_05_TYPE02','DATA_06_TYPE02','DATA_07_TYPE02','DATA_08_TYPE02', ...
      'DATA_09_TYPE02','DATA_10_TYPE02','DATA_11_TYPE02','DATA_12_TYPE02', ...
      'DATA_S04_T01', ...
      'TEST_S01_T01','TEST_S02_T01','TEST_S02_T02','TEST_S03_T02', ...
      'TEST_S04_T02','TEST_S05_T02','TEST_S06_T01','TEST_S06_T02', ...
      'TEST_S07_T02','TEST_S08_T01'};
isTest = false(1, numel(ID)); isTest(14:end) = true;   % idnb>13 为测试段

fs_in = 125; fsd = 25; dec = 5;
ws = 8 * fs_in; hs = 2 * fs_in;                 % 8 s 窗 / 2 s 步
N = 1024; sel = 1:513;
fb = (0:numel(sel) - 1) * fs_in / N;            % 与 prep_dump2 一致的频率刻度
[b, a] = butter(4, [0.4 4] / (fs_in / 2), 'bandpass');

fprintf('band bins: %d (0-%.1f Hz)\n', numel(sel), fb(end));

for s = 1:numel(ID)
    nm = ID{s};
    D = load(fullfile(srcdir, 'PPG_data', [nm '.mat']));
    sig = D.sig;
    if isTest(s)
        ch = 1:5;
        G = load(fullfile(srcdir, 'BPM_data', ['True' nm(5:end) '.mat']));
    else
        ch = 2:6;
        G = load(fullfile(srcdir, 'BPM_data', [nm '_BPMtrace.mat']));
    end
    if size(sig, 1) < max(ch), error('%s: sig 只有 %d 行，无法取通道 %d', nm, size(sig, 1), max(ch)); end

    p1 = filter(b, a, sig(ch(1), :));
    p2 = filter(b, a, sig(ch(2), :));
    p = 0.5 * (p1 - mean(p1)) / (std(p1) + eps) + 0.5 * (p2 - mean(p2)) / (std(p2) + eps);
    ac = zeros(3, numel(p));
    for j = 1:3, ac(j, :) = filter(b, a, sig(ch(2 + j), :)); end

    g0 = G.BPM0(:)';
    nWin = floor((numel(p) - ws) / hs) + 1;
    if numel(g0) >= nWin, gt = g0(1:nWin); else, gt = [g0, nan(1, nWin - numel(g0))]; end
    act = ones(1, nWin);
    sid = nm;

    S = zeros(nWin, N); A = zeros(nWin, N, 3);
    X = zeros(nWin, ws); Xa = zeros(nWin, ws, 3);
    rmsP = zeros(1, nWin); rmsA = zeros(3, nWin);
    for k = 1:nWin
        idx = (k - 1) * hs + (1:ws);
        x0 = p(idx); rmsP(k) = std(x0);
        for j = 1:3, rmsA(j, k) = std(ac(j, idx)); end
        x = (x0 - mean(x0)) / (std(x0) + eps);
        X(k, :) = x; S(k, :) = fft(x, N);
        for j = 1:3
            y = ac(j, idx); y = (y - mean(y)) / (std(y) + eps);
            Xa(k, :, j) = y; A(k, :, j) = fft(y, N);
        end
    end
    S = S(:, sel); A = A(:, sel, :);

    save(fullfile(outdir, sprintf('ieee_S%d.mat', s)), 'S', 'A', 'X', 'Xa', 'fb', 'gt', 'act', ...
        'rmsP', 'rmsA', 'nWin', 'sid', 'fs_in', 'fsd', '-v7.3');
    fprintf('  ieee S%-2d %-18s test=%d  nWin=%4d  gt=[%.1f %.1f]  saved\n', ...
        s, nm, isTest(s), nWin, min(gt), max(gt));
end
save(fullfile(outdir, 'ieee_meta.mat'), 'ID', 'isTest');
fprintf('[saved] cache2/ieee_S1..S%d.mat + ieee_meta.mat\n', numel(ID));
end
