function exp_fe_unified()
% E4（ROUND2_CHECKLIST CM1a/CM1b；R2-m8 / R3-M4）：统一配置下的前端消融重跑
%
% 论文 tab:fontend_ablation 现有 4 行来自**投稿版原始管线**（v1 探针，见
%   REPRO_LOG_20260916.md），协议与评估配置不同。本脚本在统一配置下重跑其中
%   可在评估管线（ds5）中表达的三个开关臂：
%     Full  = WF1 + WF2（obs_mode='ratio'，= headline 5.9584 / 5.7836）
%     -WF2  = 仅 WF1（obs_mode='wf1'）
%     -WF1  = 仅 WF2（obs_mode='wf2'）
%     -both = 原始幅度谱（obs_mode='raw'）
%   注：评估管线**不含相位声码器（PV）阶段**，故 PV 行无法在统一配置下重跑，
%   仍以 v1 原始管线证据 + 协议标注保留（见论文 §II-B 与表注）。
%
% 输出：results/fe_unified.mat（+ diary 日志 results/fe_unified_log.txt）

addpath(fileparts(mfilename('fullpath')));
d = fileparts(mfilename('fullpath'));

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');

cfg = { ...
    'Full (WF1 + WF2)',        struct(); ...
    '- second Wiener stage',   struct('obs_mode', 'wf1'); ...
    '- first Wiener stage',    struct('obs_mode', 'wf2'); ...
    '- both Wiener stages',    struct('obs_mode', 'raw')};

res = struct();
for ds = {'dalia', 'wesad'}
    tag = ds{1};
    fprintf('\n######## %s ########\n', upper(tag));
    names = {}; means = []; PS = [];
    for i = 1:size(cfg, 1)
        o = base; f = fieldnames(cfg{i, 2});
        for k = 1:numel(f), o.(f{k}) = cfg{i, 2}.(f{k}); end
        r = ds5(tag, 1:15, o);
        names{end + 1} = cfg{i, 1};              %#ok<AGROW>
        means(end + 1) = r.mean;                  %#ok<AGROW>
        PS(:, end + 1) = r.mae(:);                %#ok<AGROW>
        fprintf('  %-24s MAE=%.4f  SD=%.4f\n', cfg{i, 1}, r.mean, r.sd);
    end
    rng(20260918);
    nC = numel(names) - 1; pv = nan(1, nC); dm = nan(1, nC);
    for j = 1:nC
        dif = PS(:, 1) - PS(:, j + 1);            % full - ablation（负 = 去掉该级更差，即该级有帮助）
        dm(j) = mean(dif); pv(j) = signflip(dif, 10000);
    end
    fprintf('  [paired] ablations vs full (delta = full - ablation; negative = removing the stage hurts, i.e. the stage helps)\n');
    for j = 1:nC
        fprintf('  %-24s %+8.4f  p=%.4f\n', names{j + 1}, dm(j), pv(j));
    end
    res.(tag) = struct('names', {names}, 'means', means, 'perSubject', PS, 'delta', dm, 'p', pv);
end

save(fullfile(d, 'results', 'fe_unified.mat'), 'res', 'base', 'cfg');
fprintf('\n[saved] results/fe_unified.mat\n');
end

% ---- 配对符号翻转检验（与 exp_paper_v3.m 同实现）----
function p = signflip(dif, B)
dif = dif(:); n = numel(dif); obs = abs(mean(dif));
s = 0;
for b = 1:B
    sg = 2 * (rand(n, 1) > 0.5) - 1;
    if abs(mean(sg .* dif)) >= obs - 1e-12, s = s + 1; end
end
p = (s + 1) / (B + 1);
end
