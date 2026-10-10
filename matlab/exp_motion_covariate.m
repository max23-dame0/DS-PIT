function exp_motion_covariate()
% E6（ROUND2_CHECKLIST CM3a；R2-M4 后段 / R3-M6）：窗口级误差 vs 运动量
%
% 目的：把"误差随运动强度增加"从活动排序（相关）升级为窗口级定量关系。
%   运动量 = 每窗三轴加速度标准差的均值（mean(rmsA,1)，与 ds5 的质量指数同源）；
%   误差 = |ref - est|，其中 est 为 ds5 原始估计经 movmedian(3) 平滑后的发射值
%   （与 ds5 的度量口径一致；脚本内含逐受试 MAE 对照核验）。
%
% 输出：results/motion_covariate.mat（+ diary 日志 results/motion_covariate_log.txt）

addpath(fileparts(mfilename('fullpath')));
d = fileparts(mfilename('fullpath'));
cachedir = fullfile(d, 'cache2');

o = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');

res = struct();
for ds = {'dalia', 'wesad'}
    tag = ds{1};
    fprintf('\n######## %s ########\n', upper(tag));
    r = ds5(tag, 1:15, o);
    A = []; B = [];  Q = []; MAEchk = nan(1, 15);
    for si = 1:15
        F = load(fullfile(cachedir, sprintf('%s_S%d.mat', tag, si)));
        gt = F.gt(:)'; act = F.act(:)';
        mot = mean(F.rmsA, 1);                         % 运动量（三轴 RMS 均值）
        qr = mean(F.rmsA, 1) ./ (F.rmsP + eps);        % 质量指数（同源构造）
        es = movmedian(r.est{si}, o.smooth_m);
        n2 = min([numel(gt), numel(es), numel(act)]);
        g = gt(1:n2); e = es(1:n2); av = act(1:n2);
        if strcmp(tag, 'wesad')
            msk = ~isnan(e) & ~isnan(g) & av > 0 & av < 5 & g > 0;
        else
            msk = ~isnan(e) & ~isnan(g) & g > 0;
        end
        aerr = abs(e(msk) - g(msk));
        MAEchk(si) = mean(aerr);
        A = [A, aerr];                                  %#ok<AGROW>
        B = [B, mot(msk)];                              %#ok<AGROW>
        Q = [Q, qr(msk)];                               %#ok<AGROW>
    end
    fprintf('  sanity: max |recomputed - ds5| per-subject MAE = %.2e\n', max(abs(MAEchk - r.mae(:).')));
    cc = corrcoef(A, B); cc2 = corrcoef(A, Q);
    fprintf('  pooled n=%d windows\n', numel(A));
    fprintf('  Pearson(|err|, motion)  = %.3f   [motion = mean acc RMS]\n', cc(1, 2));
    fprintf('  Pearson(|err|, quality) = %.3f   [quality = acc RMS / PPG RMS]\n', cc2(1, 2));
    try
        sc = corrcoef(tiedrank(A), tiedrank(B));
        fprintf('  Spearman(|err|, motion) = %.3f\n', sc(1, 2));
    catch
        fprintf('  Spearman: tiedrank 不可用（跳过）\n');
    end
    % 运动量四分位分箱
    qq = prctile(B, [25 50 75]);
    edges = [-inf qq inf];
    fprintf('  --- motion quartiles: mean |err| / bias / >10%% ---\n');
    bins = zeros(4, 4);
    for k = 1:4
        m = B >= edges(k) & B < edges(k + 1);
        bins(k, :) = [sum(m), mean(A(m)), mean((A(m) > 10)), median(B(m))];
        fprintf('  Q%d  n=%6d  median_motion=%.4f  MAE=%.2f  >10%%=%.1f%%\n', ...
            k, sum(m), bins(k, 4), bins(k, 2), 100 * bins(k, 3));
    end
    res.(tag) = struct('pearson_motion', cc(1, 2), 'pearson_quality', cc2(1, 2), ...
        'n', numel(A), 'bins', bins, 'MAEchk', MAEchk);
end

save(fullfile(d, 'results', 'motion_covariate.mat'), 'res', 'o');
fprintf('\n[saved] results/motion_covariate.mat\n');
end
