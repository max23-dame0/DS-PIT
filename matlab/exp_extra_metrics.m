function exp_extra_metrics()
% R3-C14 补充指标：pooled RMSE 与 >5 BPM 窗口比例（三库，当前统一配置）
%
% 背景（RECORD/审计）：R3-C14 要求 MAE 之外的稳健性指标。论文已报 MedAE /
% P95 / >10% / bias / LoA / pooled r / coverage；本脚本补最后两项：
%   pooled RMSE   = sqrt(mean(E.^2))     （E = ref - est，pooled 全窗口）
%   >5 BPM 比例   = mean(|E| > 5)
% 口径与论文 §3.1 的 pooled 指标一致（逐窗、跨受试者合并）；同时落盘
% subject-macro RMSE（mean of per-subject RMSE，ds5 已输出 res.rmse）。
%
% 数据源：cache2（只读，不重建）；配置与 exp_paper_v3 / exp_ieee_unified 完全一致。
% 用法：matlab -batch "exp_extra_metrics"   （工作目录 = 本文件所在目录）
% 产物：results/extra_metrics.mat + results/extra_metrics_log.txt

d = fileparts(mfilename('fullpath'));
addpath(d);
diary(fullfile(d, 'results', 'extra_metrics_log.txt'));
diary on;

o = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');

fprintf('=== R3-C14 extra metrics (fixed sigma=2, D=3) ===\n');
sets = {'dalia', 1:15; 'wesad', 1:15; 'ieee', 1:23};
res = struct();
for i = 1:size(sets, 1)
    r = ds5(sets{i, 1}, sets{i, 2}, o);
    E = cell2mat(cellfun(@(c) c(:).', r.err, 'uni', 0));   % ref - est, pooled
    ae = abs(E);
    pooled_rmse = sqrt(mean(E.^2, 'omitnan'));
    pooled_gt5  = mean(ae > 5, 'omitnan');
    pooled_gt10 = mean(ae > 10, 'omitnan');
    pooled_med  = median(ae, 'omitnan');
    pooled_p95  = prctile(ae, 95);
    subj_rmse   = mean(r.rmse, 'omitnan');
    subj_gt5    = mean(cellfun(@(c) mean(abs(c(:)) > 5), r.err), 'omitnan');
    subj_gt10   = mean(r.gt10, 'omitnan');                 % 论文已报口径（核对 15.7/15.2）
    subj_med    = mean(r.med, 'omitnan');                  % 论文已报口径（核对 2.45/2.47）
    subj_p95    = mean(r.p95, 'omitnan');                  % 论文已报口径（核对 26.8/22.3）
    fprintf('%-6s n=%2d\n', sets{i, 1}, numel(sets{i, 2}));
    fprintf('  subject-macro : RMSE=%.4f  >5%%=%.2f%%  >10%%=%.2f%%  Med=%.4f  P95=%.2f\n', ...
        subj_rmse, 100 * subj_gt5, 100 * subj_gt10, subj_med, subj_p95);
    fprintf('  pooled        : RMSE=%.4f  >5%%=%.2f%%  >10%%=%.2f%%  Med=%.4f  P95=%.2f\n', ...
        pooled_rmse, 100 * pooled_gt5, 100 * pooled_gt10, pooled_med, pooled_p95);
    res.(sets{i, 1}) = struct('pooled_rmse', pooled_rmse, 'gt5', pooled_gt5, ...
        'gt10_check', pooled_gt10, 'subject_rmse', subj_rmse, ...
        'subject_rmse_sd', std(r.rmse, 'omitnan'), 'nwin', numel(E), ...
        'subject_gt5', subj_gt5, 'subject_gt10', subj_gt10, ...
        'subject_med', subj_med, 'subject_p95', subj_p95, ...
        'pooled_med', pooled_med, 'pooled_p95', pooled_p95);
end
save(fullfile(d, 'results', 'extra_metrics.mat'), 'res', 'o', 'sets');
fprintf('\n[saved] results/extra_metrics.mat\n');
diary off;
end
