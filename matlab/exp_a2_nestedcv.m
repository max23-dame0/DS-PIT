function exp_a2_nestedcv(Dopt)
% A′ 嵌套受试者交叉验证复算（评估配置 = C1；口径复刻 exp_nestedcv.m）
% 用法：exp_a2_nestedcv(3)（默认 3）
% 外层 5 折（每折留 3 人，交错），内层在其余 12 人上选 (band, taper) 配置，外层仅评分。
% 输出：results/a2_nestedcv_D3.mat + diary 日志 results/a2_nestedcv_log.txt
if nargin < 1 || isempty(Dopt), Dopt = 3; end
addpath(fileparts(mfilename('fullpath')));
d = fileparts(mfilename('fullpath'));
subs = 1:15;
bands = [0.70 0.75 0.80 0.85];
tapers = [20 25 30];
grid = [];
for b = bands
    for tp = tapers
        grid(end + 1, :) = [b, tp]; %#ok<AGROW>
    end
end
nC = size(grid, 1);
folds = {[1 6 11], [2 7 12], [3 8 13], [4 9 14], [5 10 15]};
res = struct();
for ds = {'dalia', 'wesad'}
    base = struct('f_lo', 40, 'f_hi', 200, 'D', Dopt, 'state_hi_hz', 3.0, ...
        'smooth_mode', 'median', 'smooth_m', 3, 'q_feat', 'off', 'sigma', 2, ...
        'obs_mode', 'ratio', 'wf_variant', 'orig');
    base = a2_cfg(base);
    M = nan(nC, 15);
    fprintf('\n######## %s : %d configs x 15 subjects (A'') ########\n', upper(ds{1}), nC);
    for i = 1:nC
        o = base; o.state_lo_hz = grid(i, 1); o.edge_taper = grid(i, 2);
        r = ds5(ds{1}, subs, o);
        M(i, :) = r.mae;
        fprintf('  band=%.2f taper=%2d  all15 MAE=%.3f\n', grid(i, 1), grid(i, 2), r.mean);
    end
    outerMAE = nan(1, 5); pick = nan(5, 2);
    for f = 1:5
        te = folds{f}; tr = setdiff(subs, te);
        inner = mean(M(:, tr), 2, 'omitnan');
        [~, bi] = min(inner);
        pick(f, :) = grid(bi, :);
        outerMAE(f) = mean(M(bi, te), 'omitnan');
    end
    optAll = mean(M, 2, 'omitnan'); [bestAll, biAll] = min(optAll);
    fprintf('  nested CV (outer) mean=%.3f  SD=%.3f | in-sample=%.3f  optimism=%.3f\n', ...
        mean(outerMAE), std(outerMAE), bestAll, mean(outerMAE) - bestAll);
    res.(ds{1}) = struct('M', M, 'grid', grid, 'outerMAE', outerMAE, 'pick', pick, ...
        'nested', mean(outerMAE), 'insample', bestAll, 'folds', {folds});
end
save(fullfile(d, 'results', sprintf('a2_nestedcv_D%d.mat', Dopt)), 'res', 'grid', 'folds');
fprintf('\n[saved] results/a2_nestedcv_D%d.mat\n', Dopt);
end
