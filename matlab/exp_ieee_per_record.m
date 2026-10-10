function exp_ieee_per_record()
% E2：IEEE SPC 逐记录统计 + recording-level bootstrap CI（ROUND2_CHECKLIST BLK-2b/2c）
%
% 背景：表 III 表注 f 声明"三条记录贡献了大部分残余误差"，但全文无逐记录结果；
%   且 6.80 BPM 的聚合单位与区间未给出（23 条记录，8 个测试 ID，重叠不可判定）。
%
% 输出（results/ieee_per_record_log.txt + results/ieee_per_record.mat）：
%   1. 23 条记录逐条 MAE / 窗数 / 占总绝对误差份额（支撑/修正"三记录主导"声明）
%   2. 记录级统计：mean、SD、median、min、max（对应表 III 的 6.80 ± 9.27）
%   3. recording-level bootstrap 95% CI（n=23，10000 次，seed 20260918）
%   4. 失败计数：MAE > 5 / 10 / 15 BPM 的记录数与占比
%   5. 窗数总和（与表 I 的 3,203 对账）

addpath(fileparts(mfilename('fullpath')));
d = fileparts(mfilename('fullpath'));

o = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');

r = ds5('ieee', 1:23, o);
mae = r.mae(:);
nRec = numel(mae);

% ---- 逐记录统计 ----
totAbs = zeros(nRec, 1); nWinRec = zeros(nRec, 1);
for si = 1:nRec
    e = r.err{si};
    totAbs(si) = sum(abs(e));
    nWinRec(si) = numel(e);
end
share = totAbs / sum(totAbs);
[~, ord] = sort(mae, 'descend');
fprintf('\n[E2] IEEE SPC per-recording (unified config, D=3, sigma=2)\n');
fprintf('rec  MAE(BPM)  windows  err-share(%%)\n');
for si = 1:nRec
    mark = ''; if ismember(si, ord(1:3)), mark = '  <-- top-3'; end
    fprintf('%3d %9.2f %8d %13.2f%s\n', si, mae(si), nWinRec(si), 100 * share(si), mark);
end
fprintf('--- summary ---\n');
fprintf('mean=%.4f  SD=%.4f  median=%.4f  min=%.4f  max=%.4f  (n=%d)\n', ...
    mean(mae), std(mae), median(mae), min(mae), max(mae), nRec);
fprintf('top-3 share of total abs err = %.1f%%\n', 100 * sum(share(ord(1:3))));
fprintf('total windows = %d (Table I: 3,203)\n', sum(nWinRec));

% ---- recording-level bootstrap CI ----
rng(20260918);
B = 10000; bs = zeros(B, 1);
for b = 1:B
    bs(b) = mean(mae(randi(nRec, nRec, 1)));
end
ci = prctile(bs, [2.5 97.5]);
fprintf('bootstrap 95%% CI (recording-level, n=%d) = [%.3f, %.3f]\n', nRec, ci(1), ci(2));

% ---- failure counts ----
for thr = [5 10 15]
    kk = sum(mae > thr);
    fprintf('records with MAE > %2g BPM: %2d / %d (%.1f%%)\n', thr, kk, nRec, 100 * kk / nRec);
end

res = struct('mae', mae, 'nWin', nWinRec, 'totAbs', totAbs, 'share', share, ...
    'mean', mean(mae), 'sd', std(mae), 'median', median(mae), ...
    'min', min(mae), 'max', max(mae), 'ci', ci, 'top3', ord(1:3)', ...
    'top3share', sum(share(ord(1:3))), 'totalWin', sum(nWinRec));
save(fullfile(d, 'results', 'ieee_per_record.mat'), 'res', 'o');
fprintf('\n[saved] results/ieee_per_record.mat\n');
end
