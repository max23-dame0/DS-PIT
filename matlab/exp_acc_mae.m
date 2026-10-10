function exp_acc_mae()
% M-20（ROUND2_CHECKLIST；R3-m7）：加速度参考的 MAE 级对照（统一配置）
%
% 背景：R3-C04 的轴和验证基于跨频相关系数（`exp_r3c04.m`），R3-m7 要求补
%   MAE 级对照并说明主成分是否去均值。本脚本在统一配置下比较五种参考：
%   sum（论文口径）/ x / y / z / pc1（逐窗去均值三轴 SVD 第一主成分）。
%   其中 `ds5.m` 新增 `acc_axes` 选项（默认 'sum'=论文口径，逐位兼容）。
%
% 输出：results/acc_mae.mat（+ diary 日志 results/acc_mae_log.txt）

addpath(fileparts(mfilename('fullpath')));
d = fileparts(mfilename('fullpath'));

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');

cfg = { ...
    'sum (evaluated)',            struct(); ...
    'x only',                     struct('acc_axes', 'x'); ...
    'y only',                     struct('acc_axes', 'y'); ...
    'z only',                     struct('acc_axes', 'z'); ...
    'first principal component',  struct('acc_axes', 'pc1')};

res = struct();
for ds = {'dalia', 'wesad'}
    tag = ds{1};
    fprintf('\n######## %s ########\n', upper(tag));
    names = {}; means = []; PS = [];
    for i = 1:size(cfg, 1)
        o = base; f = fieldnames(cfg{i, 2});
        for k = 1:numel(f), o.(f{k}) = cfg{i, 2}.(f{k}); end
        r = ds5(tag, 1:15, o);
        names{end + 1} = cfg{i, 1};                 %#ok<AGROW>
        means(end + 1) = r.mean;                     %#ok<AGROW>
        PS(:, end + 1) = r.mae(:);                   %#ok<AGROW>
        fprintf('  %-26s MAE=%.4f  SD=%.4f\n', cfg{i, 1}, r.mean, r.sd);
    end
    rng(20260918);
    nC = numel(names) - 1; pv = nan(1, nC); dm = nan(1, nC);
    for j = 1:nC
        dif = PS(:, j + 1) - PS(:, 1);               % alternative - sum（正 = 参考更差）
        dm(j) = mean(dif); pv(j) = signflip(dif, 10000);
    end
    fprintf('  [paired vs sum]  delta(alt - sum)\n');
    for j = 1:nC
        fprintf('  %-26s %+8.4f  p=%.4f\n', names{j + 1}, dm(j), pv(j));
    end
    res.(tag) = struct('names', {names}, 'means', means, 'perSubject', PS, 'delta', dm, 'p', pv);
end

save(fullfile(d, 'results', 'acc_mae.mat'), 'res', 'base', 'cfg');
fprintf('\n[saved] results/acc_mae.mat\n');
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
