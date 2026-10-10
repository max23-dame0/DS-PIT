function exp_a2_prior()
% A′ 版：IEEE SPC 上 v1→v2 差距的"数据先验 / 证据带"对照（评估配置 = C1）
%   复刻 exp_ieee_prior_split.m（行归一核）与 exp_ieee_prior_arm2.m（计数-log 核），
%   但全部臂在 A′ 配置（a2_cfg）下运行，供表注 f / Limitations 引用。
%
% 臂：
%   1 行归一 LOXO 真值核 + 原带(1.0) 无斜坡
%   2 计数→moving(4)→log 真值核 + 原带(1.0) 无斜坡
%   3 解析核 + 原带(1.0) 无斜坡                （= 旧的 5.28 臂）
%   4 解析核 + 评估带(0.75)+斜坡 30            （= A′ headline，自洽核验）
%   5 行归一真值核 + 评估带+斜坡
% 输出：results/a2_prior.mat + diary 日志 results/a2_prior_log.txt（约 5–6 分钟）

d = fileparts(mfilename('fullpath'));
addpath(d);
cache = fullfile(d, 'cache2');
SB = 40:200; K = numel(SB);

fprintf('\n[1/2] 构建 LOXO 真值核（行归一版 + 计数-log 版）\n');
gtAll = cell(1, 23);
for i = 1:23
    F = load(fullfile(cache, sprintf('ieee_S%d.mat', i)));
    gtAll{i} = F.gt(:)';
end
Trow = cell(1, 23); Tcnt = cell(1, 23);
for i = 1:23
    C = zeros(K, K);
    for j = 1:23
        if j == i, continue; end
        b = round(gtAll{j}) - SB(1) + 1;
        b = b(:); b = b(b >= 1 & b <= K);
        if numel(b) < 2, continue; end
        C = C + accumarray([b(1:end-1), b(2:end)], 1, [K K]);
    end
    P = C + 0.5; P = P ./ sum(P, 2); Trow{i} = P;          % 行归一
    Cc = (movmean(C', 4))'; Cc = Cc + 1e-6; Tcnt{i} = Cc;  % 计数→moving(4)→log
end

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, 'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');
o2 = a2_cfg(base);

arms = { ...
    'row-norm truth kernel + band 1.0, taper 0',   'row', 1.0,  0; ...
    'count-log truth kernel + band 1.0, taper 0',  'cnt', 1.0,  0; ...
    'analytic + band 1.0, taper 0',                'ana', 1.0,  0; ...
    'analytic + band 0.75, taper 30 (= A'')',      'ana', 0.75, 30; ...
    'row-norm truth kernel + band 0.75, taper 30', 'row', 0.75, 30};

fprintf('\n[2/2] 5 臂（全部在 A'' 配置下；真值核臂逐记录 23 次运行）\n');
res = struct();
for a = 1:size(arms, 1)
    o = o2; o.state_lo_hz = arms{a, 3}; o.edge_taper = arms{a, 4};
    switch arms{a, 2}
        case 'ana'
            r = ds5('ieee', 1:23, o);
            mu = r.mean; sd = r.sd; mae = r.mae;
        otherwise
            TK = Trow; if strcmp(arms{a, 2}, 'cnt'), TK = Tcnt; end
            mae = nan(1, 23);
            for i = 1:23
                oi = o; oi.T_mat = TK{i};
                rr = ds5('ieee', i, oi);
                mae(i) = rr.mean;
            end
            mu = mean(mae, 'omitnan'); sd = std(mae, 'omitnan');
    end
    fprintf('  %-44s MAE=%.4f  SD=%.4f\n', arms{a, 1}, mu, sd);
    res(a).name = arms{a, 1}; res(a).mean = mu; res(a).sd = sd; res(a).mae = mae;
end

fprintf('\n--- 分解（A'' 配置）---\n');
fprintf('  原带无斜坡：解析核 %.4f | 行归一真值核 %.4f | 计数-log 真值核 %.4f\n', ...
    res(3).mean, res(1).mean, res(2).mean);
fprintf('  评估带+斜坡：解析核 %.4f（= headline）| 行归一真值核 %.4f\n', res(4).mean, res(5).mean);
fprintf('  带/斜坡净效应（解析核）：%+.4f BPM\n', res(4).mean - res(3).mean);
fprintf('  真值核净效应（同带同斜坡）：%+.4f BPM（行归一）\n', res(1).mean - res(3).mean);

save(fullfile(d, 'results', 'a2_prior.mat'), 'res', 'base', 'o2', 'SB');
fprintf('\n[saved] results/a2_prior.mat\n');
end
