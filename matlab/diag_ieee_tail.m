function diag_ieee_tail()
% IEEE SPC 高尾诊断（A′ 配置）：解释 6.77 BPM 的 SD 9.22 与最差记录 43 BPM 来自哪里
%   - 逐记录：MAE / bias / 真值与估计均值 / 比值 / |err|>20 占比
%   - 锁相检测：est ≈ 2·gt、gt/2、3·gt、gt/3（容差 ±10 BPM）的窗口占比
%   - 带边滞留：est 落在 [45,75] 或 [150,180]（斜坡区）占比；最长常数段
%   - 对照：v1（1.50 口径）同索引记录的归档 MAE（results/verify_ieee_150_log.txt）
% 输出：results/diag_ieee_tail.mat + diary 日志 results/diag_ieee_tail_log.txt

d = fileparts(mfilename('fullpath'));
addpath(d);
cache = fullfile(d, 'cache2');

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, 'obs_mode', 'ratio', 'wf_variant', 'orig');
o = a2_cfg(base);

v1 = nan(1, 23);
fid = fopen(fullfile(d, 'results', 'verify_ieee_150_log.txt'), 'r');
if fid > 0
    k = 0; while ~feof(fid)
        L = fgetl(fid); if ~ischar(L), break; end
        tok = regexp(L, '^\s*S(\d+)\s+\S+\s+([\d.]+)\s*$', 'tokens', 'once');
        if ~isempty(tok), k = k + 1; v1(str2double(tok{1})) = str2double(tok{2}); end
    end
    fclose(fid);
end

r = ds5('ieee', 1:23, o);
fprintf('IEEE ALL23 headline = %.4f (a2_core 参考 6.7659)\n', r.mean);
fprintf('%-4s %-8s %7s %7s %7s %7s %6s %6s %6s %6s %6s %6s %7s\n', ...
    'rec', 'sid', 'MAE', 'bias', 'gtMean', 'estMean', 'r>20', 'x2', 'x0.5', 'x3', 'x1/3', 'edge', 'maxRun');
R = struct();
for i = 1:23
    F = load(fullfile(cache, sprintf('ieee_S%d.mat', i)));
    gt = F.gt(:)'; es = movmedian(r.est{i}, o.smooth_m);
    n = min(numel(gt), numel(es)); gt = gt(1:n); es = es(1:n);
    m = isfinite(gt) & isfinite(es) & gt > 0;
    g = gt(m); e = es(m); er = e - g;
    f20 = mean(abs(er) > 20);
    f2 = mean(abs(e - 2 * g) < 10); fh = mean(abs(e - g / 2) < 10);
    f3 = mean(abs(e - 3 * g) < 10); ft = mean(abs(e - g / 3) < 10);
    fedge = mean((e >= 45 & e < 75) | (e > 150 & e <= 180));
    % 最长常数段（1 BPM 网格上的重复值）
    dr = [0, diff(e) ~= 0, 0]; ii = find(dr); [maxRun, ~] = max(diff(ii) - 1);
    fprintf('%-4d %-8s %7.2f %+7.2f %7.2f %7.2f %6.2f %6.2f %6.2f %6.2f %6.2f %6.2f %7d\n', ...
        i, F.sid, mean(abs(er)), mean(er), mean(g), mean(e), f20, f2, fh, f3, ft, fedge, maxRun);
    R(i).sid = F.sid; R(i).mae = mean(abs(er)); R(i).bias = mean(er); R(i).gt = mean(g);
    R(i).est = mean(e); R(i).f20 = f20; R(i).f2 = f2; R(i).fh = fh; R(i).f3 = f3;
    R(i).ft = ft; R(i).fedge = fedge; R(i).maxRun = maxRun; R(i).v1 = v1(i);
end

[~, ord] = sort([R.mae], 'descend');
fprintf('\n--- worst 5 records ---\n');
for k = 1:5
    i = ord(k);
    fprintf('rec %2d (sid %s): MAE %.2f | bias %+.2f | gt %.1f est %.1f | >20 %.0f%% | 2x %.0f%% | 0.5x %.0f%% | edge %.0f%% | v1-index MAE %s\n', ...
        i, R(i).sid, R(i).mae, R(i).bias, R(i).gt, R(i).est, 100 * R(i).f20, 100 * R(i).f2, ...
        100 * R(i).fh, 100 * R(i).fedge, num2str(R(i).v1, '%.3f'));
end
fprintf('\n--- 三库对照（A′ vs v1 索引；v1 顺序见 verify_ieee_150_log.txt）---\n');
fprintf('A′ 逐记录 MAE 排序前十: %s\n', mat2str(round([R(ord(1:10)).mae], 2)));
fprintf('v1 同索引 MAE:        %s\n', mat2str(round([R(ord(1:10)).v1], 2)));
save(fullfile(d, 'results', 'diag_ieee_tail.mat'), 'R', 'r');
fprintf('\n[saved] results/diag_ieee_tail.mat\n');
end
