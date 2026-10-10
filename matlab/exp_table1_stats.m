function exp_table1_stats()
% 计算 Table I 所需的 HR 统计量（填入 RESULT PENDING 三格）
%   IEEE SPC：23 条记录（TYPE01 训练 12 条 / TYPE02 测试 11 条），参考来自 BPM_data/*_BPMtrace.mat
%   PPG-DaLiA / WESAD：来自 cache2 的逐窗参考 gt（与评估口径一致）
% 口径说明：统计的是**参考 HR 序列**（即评估所用的标签），按评估时的有效性掩码筛选。
%
% 2026-09-17 更新（记录审计 RA-06）：
%   ① 本脚本此前**只打印、不落盘**，且曾被错误登记为 `results/stats_all.mat` 的来源
%      （该 .mat 实为 `exp_stats.m` 的 CurToSS 机制吸收结果，G0–G7）。
%   ② 现新增 diary 日志 `results/table1_stats_log.txt` 与结构化产物
%      `results/table1_stats.mat`（结构体 T1，含全部 12 个统计格）。
%   建议复现命令（工作目录 revision/audit/method_dev）：
%     D:\matlab\bin\matlab.exe -batch "exp_table1_stats"
root = fileparts(mfilename('fullpath'));
resdir = fullfile(root, 'results');
if ~exist(resdir, 'dir'), mkdir(resdir); end
diary(fullfile(resdir, 'table1_stats_log.txt')); diary on;
fprintf('[exp_table1_stats] %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
base = 'D:\小论文\实验代码\PPG-master\all_data';
fprintf('\n===== IEEE SPC =====\n');
fprintf('%-30s %7s %8s %8s %8s\n', 'record', 'n', 'mean', 'min', 'max');
tr = []; te = [];
T1 = struct();
% --- 训练集：all_data/Training_data/*_BPMtrace.mat（12 条）---
d1 = dir(fullfile(base, 'Training_data', '*_BPMtrace.mat'));
for k = 1:numel(d1)
    L = load(fullfile(base, 'Training_data', d1(k).name));
    g = get_bpm(L);
    tr = [tr, g]; %#ok<AGROW>
    fprintf('%-30s %7d %8.2f %8.2f %8.2f\n', d1(k).name(1:min(30, end)), numel(g), mean(g), min(g), max(g));
end
% --- 测试集：all_data/TestData/TrueBPM/*.mat（11 条）---
d2 = dir(fullfile(base, 'TestData', 'TrueBPM', '*.mat'));
for k = 1:numel(d2)
    L = load(fullfile(base, 'TestData', 'TrueBPM', d2(k).name));
    g = get_bpm(L);
    te = [te, g]; %#ok<AGROW>
    fprintf('%-30s %7d %8.2f %8.2f %8.2f\n', d2(k).name(1:min(30, end)), numel(g), mean(g), min(g), max(g));
end
fprintf('\n');
T1.ieee_train = rep('IEEE SPC (Training, 12)', tr);
T1.ieee_test  = rep('IEEE SPC (Test, 11)', te);
T1.ieee_all   = rep('IEEE SPC (all 23)', [tr, te]);
for ds = {'dalia', 'wesad'}
    fprintf('\n===== %s (15 subjects) =====\n', upper(ds{1}));
    G = [];
    for s = 1:15
        F = load(fullfile(root, 'cache2', sprintf('%s_S%d.mat', ds{1}, s)));
        gt = F.gt(:)'; act = F.act(:)';
        if strcmp(ds{1}, 'wesad')
            m = ~isnan(gt) & gt > 0 & act > 0 & act < 5;
        else
            m = ~isnan(gt) & gt > 0;
        end
        G = [G, gt(m)]; %#ok<AGROW>
    end
    T1.(ds{1}) = rep(upper(ds{1}), G);
end
save(fullfile(resdir, 'table1_stats.mat'), 'T1');
fprintf('\n[saved] results/table1_stats.mat\n');
diary off;
end

function S = rep(name, g)
fprintf('%-24s %7d  mean=%6.2f  min=%6.2f  max=%6.2f  p1=%5.1f p99=%5.1f  | <60=%5.2f%%  >180=%5.2f%%\n', ...
    name, numel(g), mean(g), min(g), max(g), prctile(g, 1), prctile(g, 99), 100 * mean(g < 60), 100 * mean(g > 180));
S = struct('name', name, 'n', numel(g), 'mean', mean(g), 'min', min(g), 'max', max(g), ...
    'p1', prctile(g, 1), 'p99', prctile(g, 99), ...
    'pct_lt60', 100 * mean(g < 60), 'pct_gt180', 100 * mean(g > 180));
end

function g = get_bpm(L)
% 从 BPMtrace/TrueBPM 结构中取出参考 HR 序列（优先 BPM0）
if isfield(L, 'BPM0')
    g = double(L.BPM0(:))';
else
    fn = fieldnames(L); g = [];
    for i = 1:numel(fn)
        v = L.(fn{i});
        if isnumeric(v) && numel(v) > 10, g = double(v(:))'; break; end
    end
end
g = g(~isnan(g) & g > 0);
end
