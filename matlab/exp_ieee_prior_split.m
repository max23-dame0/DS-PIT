function exp_ieee_prior_split()
% §8#3 消融：IEEE SPC 上 v1→v2 的精度差距，由"数据先验"与"证据带"各承担多少
%
% 背景（EXPERIMENT_SUMMARY §8#3 / REVISION_TIMELINE §4.2）：
%   v1（原稿，1.50 ± 1.54）与 v2（统一协议，6.796）覆盖**同一批 23 条记录**，
%   差距来自两处配置变化：
%     ① 状态转移核：v1 用**其他记录真值轨迹统计出的 LOSO 经验转移矩阵**
%        （X:\trans_prob.m，60–180 BPM 分箱，见 WFPV_OVD_PISC.m:49）；
%        v2 用**解析高斯核**（norm_tm，σ=2），即 v2 严格 training-free。
%     ② 证据带：v1 为 1.0–3.0 Hz 无斜坡；v2 为 0.75–3.0 Hz + 30 BPM 边斜坡。
%
% 方法：构造 2×2 全因子对照
%         { 真值核(LOSO) , 解析核 } × { v1 带无斜坡 , v2 带 + 斜坡 }
%   真值核直接建在 **v2 的状态网格**（40:1:200 BPM）上，逐记录留一（LOXO）：
%   对第 i 条记录，用其余 22 条记录的逐窗真值 `gt`（取自 cache2/ieee_S*.mat）
%   统计相邻窗的 BPM 转移计数，行归一化后加小底数保证严格正。
%   注入路径：ds5 的 o.T_mat（2026-09-17 新增，不传时行为不变）。
%
% 用法：exp_ieee_prior_split()   （约 6 分钟）

d = fileparts(mfilename('fullpath'));
addpath(d);
cache = fullfile(d, 'cache2');
SB = 40:200; K = numel(SB);

%% 1) 逐记录建立 LOXO 真值转移核
fprintf('\n[1/2] 建立 LOXO 真值转移核（网格 %d–%d BPM, K=%d）\n', SB(1), SB(end), K);
gtAll = cell(1, 23);
for i = 1:23
    F = load(fullfile(cache, sprintf('ieee_S%d.mat', i)));
    gtAll{i} = F.gt(:)';
end
Tk = cell(1, 23);
for i = 1:23
    C = zeros(K, K);
    for j = 1:23
        if j == i, continue; end
        b = round(gtAll{j}) - SB(1) + 1;      % 网格是整数 BPM，四舍五入即精确分箱
        b = b(:);
        b = b(b >= 1 & b <= K);               % 去掉落在网格外的窗
        if numel(b) < 2, continue; end
        C = C + accumarray([b(1:end-1), b(2:end)], 1, [K K]);
    end
    P = C + 0.5;                    % 加底数：保证严格正，log 安全
    P = P ./ sum(P, 2);             % 行归一
    Tk{i} = P;
end
fprintf('      完成；单核密度中位数 = %.4g，非零占比 = %.3f\n', ...
    median(Tk{1}(:)), nnz(Tk{1}) / K ^ 2);

%% 2) 2×2 全因子
fprintf('\n[2/2] 2x2 对照（IEEE 全 23 条，subject-macro MAE ± 记录间 SD）\n');
base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_hi_hz', 3.0, 'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, 'obs_mode', 'ratio', 'wf_variant', 'orig');

arms = { ...
    'v1 config : truth-kernel + band 1.0-3.0, no taper', true,  1.0, 0; ...
    'v2 config : analytic     + band 0.75-3.0, taper 30', false, 0.75, 30; ...
    'analytic  + band 1.0-3.0, no taper',                false, 1.0, 0; ...
    'truth-kernel + band 0.75-3.0, taper 30',            true,  0.75, 30};

res = struct();
for a = 1:size(arms, 1)
    o = base;
    o.state_lo_hz = arms{a, 3}; o.edge_taper = arms{a, 4};
    if arms{a, 2}
        mae = nan(1, 23);
        for i = 1:23
            oi = o; oi.T_mat = Tk{i};
            r = ds5('ieee', i, oi);
            mae(i) = r.mean;
        end
        mu = mean(mae, 'omitnan'); sd = std(mae, 'omitnan');
    else
        r = ds5('ieee', 1:23, o);
        mu = r.mean; sd = r.sd; mae = r.mae;
    end
    fprintf('  %-52s MAE=%.4f  SD=%.4f\n', arms{a, 1}, mu, sd);
    res(a).name = arms{a, 1}; res(a).mean = mu; res(a).sd = sd; res(a).mae = mae;
end

%% 3) 分解
v1c = res(1).mean; v2c = res(2).mean;
fprintf('\n--- 分解（相对 v1 同口径）---\n');
fprintf('  v1 同口径（真值核 + v1 带）= %.4f\n', v1c);
fprintf('  仅换证据带（真值核 + v2 带）= %.4f  → 证据带贡献 %+.4f BPM\n', res(4).mean, res(4).mean - v1c);
fprintf('  仅去数据先验（解析核 + v1 带）= %.4f  → 数据先验贡献 %+.4f BPM\n', res(3).mean, res(3).mean - v1c);
fprintf('  两者同时换（= 现行 v2）    = %.4f  → 合计 %+.4f BPM\n', v2c, v2c - v1c);
fprintf('\n  参照：v1 原稿报告 1.50（真值核 + v1 带 + moving(4) 平滑）\n');
fprintf('        v1 未平滑     1.94162\n');

save(fullfile(d, 'results', 'ieee_prior_split.mat'), 'res', 'Tk', 'base', 'SB');
fprintf('\n[saved] results/ieee_prior_split.mat\n');
end
