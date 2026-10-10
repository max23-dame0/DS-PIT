function exp_winlen_cmp()
% R3-C19 窗长对照的复现脚本（记录审计 RA-07 补做）
%
% 设计：受控对照——保持每个窗的**终点与目标索引不变**，只改变分析窗长
%   （生成器见 prep_winlen.m）。缓存：cache_w40（4 s）、cache_w60（6 s）、
%   cache2（8 s 主缓存）。
% 口径：**D=15 + 自适应 σ∈[2,5]（q_feat='kurt', q_dir='norm'）**——即
%   2026-09-15 首次测得该对照时所用的统一配置。现行论文口径已改为
%   D=3 + 固定 σ=2，本对照仅用于窗长的**相对**比较，不是现行 headline 的复现。
% 产物：results/winlen.mat + results/winlen_log.txt（diary）
%
% 复现命令（工作目录 revision/audit/method_dev）：
%   D:\matlab\bin\matlab.exe -batch "exp_winlen_cmp"
root = fileparts(mfilename('fullpath'));
addpath(root);
resdir = fullfile(root, 'results');
if ~exist(resdir, 'dir'), mkdir(resdir); end
diary(fullfile(resdir, 'winlen_log.txt')); diary on;
fprintf('[exp_winlen_cmp] %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('配置：D=15, band 0.75-3.0 Hz + taper 30, adaptive sigma in [2,5], obs=ratio, wf=orig\n');
base = struct('f_lo', 40, 'f_hi', 200, 'D', 15, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'kurt', 'q_dir', 'norm', 'sigma_lo', 2, 'sigma_hi', 5, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');
wins = [4 6 8];
W = struct();
for ds = {'dalia', 'wesad'}
    tag = ds{1};
    fprintf('\n######## %s ########\n', tag);
    fprintf('%-6s %-11s %8s %8s %8s %8s\n', 'win', 'cachedir', 'MAE', 'SD', 'MedAE', 'P95');
    mae = nan(1, 3); sd = nan(1, 3); med = nan(1, 3); p95 = nan(1, 3); subj = cell(1, 3);
    for k = 1:3
        win = wins(k);
        if win == 8, cdir = 'cache2'; else, cdir = sprintf('cache_w%d', win * 10); end
        if ~exist(fullfile(root, cdir), 'dir')
            fprintf('%-6s %-11s  [缓存缺失，跳过]\n', sprintf('%ds', win), cdir); continue;
        end
        o = base; o.cachedir = cdir;
        r = ds5(tag, 1:15, o);
        mae(k) = r.mean; sd(k) = r.sd;
        med(k) = mean(r.med, 'omitnan'); p95(k) = mean(r.p95, 'omitnan');
        subj{k} = r.mae;
        fprintf('%-6s %-11s %8.3f %8.3f %8.3f %8.3f\n', sprintf('%ds', win), cdir, mae(k), sd(k), med(k), p95(k));
    end
    [best, bi] = min(mae, [], 'omitnan');
    if ~isnan(best)
        fprintf('最优窗长 = %ds (%.3f)；8 s = %.3f，距最优 %.3f BPM\n', wins(bi), best, mae(3), mae(3) - best);
    end
    S = struct('wins', wins, 'mae', mae, 'sd', sd, 'med', med, 'p95', p95, ...
        'best_win', wins(bi), 'delta_8s', mae(3) - best, 'opt', base);
    S.subj_mae = subj;
    W.(tag) = S;
end
save(fullfile(resdir, 'winlen.mat'), 'W');
fprintf('\n[saved] results/winlen.mat\n');
diary off;
end
