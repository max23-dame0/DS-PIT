function exp_a2_latency_causal()
% exp_a2_latency_causal.m — 延迟扫描在「居中中值」与「尾随中值」两种输出规则下的对照
%
% 背景：作者已定 P0-2 路线 (a) 保留居中中值 + 如实报 14 s（见 REVISION_ACTION_CHECKLIST_20260923.md §1.2）。
%       本脚本按作者要求把延迟表在因果规则下也重扫一遍，用于：
%       ① 复核现行延迟表在居中中值口径下逐位可复现（并与 results/a2_tables.mat 交叉比对）；
%       ② 给出尾随（因果）中值下的 D=1…15 曲线，量化「1 帧有效时间滞后」的代价随 D 的变化。
%
% 与 exp_a2_tables.m §[2] 的口径完全一致：Dl = [1 2 3 4 6 10 15]、wait_look = 2*(D-1)、perSubject 15×|Dl|
%
% 关键设计：每个 (数据集, D) 只调用一次 ds5，两种输出规则共用同一份 raw est 离线重算
%   （res.est 在平滑之前写入、与 smooth_mode 无关：ds5.m:380 vs :359-364）→ 机时 ≈ 1× 延迟扫描。
%   本脚本**不修改 ds5.m**。
%
% 等待口径（目标窗起点计）：
%   median       居中窗 → 8 + 2(D-1) + 2
%   mediancausal 尾随窗 → 8 + 2(D-1)
%
% 依赖：cache2（只读）
% 产物：results/a2_latency_causal.mat + results/a2_latency_causal_log.txt
% 护栏：D=3 的居中行必须逐位复现 5.8302 / 5.7569

addpath(fileparts(mfilename('fullpath')));
mdir = fileparts(mfilename('fullpath'));
cache = fullfile(mdir, 'cache2');
outdir = fullfile(mdir, 'results');
diary(fullfile(outdir, 'a2_latency_causal_log.txt'));
fprintf('=== exp_a2_latency_causal（延迟扫描 · 居中 vs 尾随中值）%s ===\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));

B = 10000;
Dl = [1 2 3 4 6 10 15];
tags = {'dalia', 'wesad'};
base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');
o0 = a2_cfg(base);

rng(20260916);                    % 与 exp_a2_core / exp_a2_tables 一致

res = struct(); okm = true(1, numel(tags));
for t = 1:numel(tags)
    tag = tags{t};
    nS = 15;
    gt = cell(1, nS); act = cell(1, nS);
    for si = 1:nS
        F = load(fullfile(cache, sprintf('%s_S%d.mat', tag, si)));
        gt{si} = F.gt(:)'; act{si} = F.act(:)';
    end

    nD = numel(Dl);
    maeC = nan(nS, nD); maeK = nan(nS, nD);          % C = 居中(median)，K = 尾随(mediancausal)
    for i = 1:nD
        o = o0; o.D = Dl(i);
        r = ds5(tag, 1:nS, o);
        for si = 1:nS
            esC = out_filter(r.est{si}, 'median', o.smooth_m);
            esK = out_filter(r.est{si}, 'mediancausal', o.smooth_m);
            maeC(si, i) = out_metrics(esC, gt{si}, act{si}, tag).mae;
            maeK(si, i) = out_metrics(esK, gt{si}, act{si}, tag).mae;
        end
        fprintf('  [%s] D=%2d  centred MAE=%.4f   trailing MAE=%.4f\n', ...
            lower(tag), Dl(i), mean(maeC(:, i), 'omitnan'), mean(maeK(:, i), 'omitnan'));
    end

    waitLook = 2 * (Dl - 1);
    waitC = 8 + waitLook + 2;
    waitK = 8 + waitLook;

    % ---- 交叉复核：与 results/a2_tables.mat 的居中延迟行逐位比对 ----
    xc = 'n/a';
    fT = fullfile(outdir, 'a2_tables.mat');
    if exist(fT, 'file')
        S = load(fT);
        if isfield(S, 'res') && isfield(S.res, tag) && isfield(S.res.(tag), 'latency')
            ref = S.res.(tag).latency.mae(:)';
            dmax = max(abs(ref - mean(maeC, 1, 'omitnan')));
            if dmax < 5e-4, xc = sprintf('PASS（与 a2_tables.mat 最大差 %.2e）', dmax);
            else, xc = sprintf('FAIL（最大差 %.4f）', dmax); end
        else
            xc = 'a2_tables.mat 无该数据集 latency 字段';
        end
    else
        xc = 'a2_tables.mat 缺失';
    end

    okc = abs(mean(maeC(:, Dl == 3), 'omitnan') - (5.8302 * strcmp(tag, 'dalia') + 5.7569 * strcmp(tag, 'wesad'))) < 5e-4;
    okm(t) = okc;

    fprintf('\n######## %s ########\n', upper(tag));
    fprintf('  护栏：D=3 居中行复现 %s\n', ternary(okc, 'PASS', 'FAIL'));
    fprintf('  交叉复核（vs a2_tables.mat）：%s\n', xc);
    fprintf('  %-3s | %-9s | %-9s | %-11s | %-11s | %s\n', ...
        'D', 'wait_look', 'wait_ctr', 'centred MAE', 'trailing MAE', 'delta(trailing-centred)');
    for i = 1:nD
        fprintf('  %-3d | %-9d | %-9d | %-11.4f | %-11.4f | %+.4f\n', ...
            Dl(i), waitLook(i), waitC(i), mean(maeC(:, i), 'omitnan'), ...
            mean(maeK(:, i), 'omitnan'), mean(maeK(:, i) - maeC(:, i), 'omitnan'));
    end

    % ---- 同一 D 下「尾随 vs 居中」的配对检验（家族 = 7 个 D 值，Holm）----
    d = nan(nD, 1); praw = nan(nD, 1);
    for i = 1:nD
        dif = maeK(:, i) - maeC(:, i);
        d(i) = mean(dif, 'omitnan');
        rng(20260920 + 10 * t + i);
        praw(i) = signflip(dif, B);
    end
    [sp, ord] = sort(praw); adj = min(1, sp(:) .* ((nD:-1:1)')); for k = 2:nD, adj(k) = max(adj(k), adj(k - 1)); end
    holm = nan(nD, 1); holm(ord) = adj;
    ciC = cell(nD, 1); ciK = cell(nD, 1);
    for i = 1:nD
        rng(20260930 + 10 * t + i); ciC{i} = bootci_mean(maeC(:, i), B);
        rng(20260940 + 10 * t + i); ciK{i} = bootci_mean(maeK(:, i), B);
    end
    fprintf('  [trailing vs centred @ same D]  delta    raw p    Holm p (m=%d)\n', nD);
    for i = 1:nD
        fprintf('    D=%2d  %+8.4f  %.4f   %.4f\n', Dl(i), d(i), praw(i), holm(i));
    end
    fprintf('  CI95 居中：  %s\n', sprintf('[%.2f,%.2f] ', cell2mat(ciC(:)')));
    fprintf('  CI95 尾随：  %s\n', sprintf('[%.2f,%.2f] ', cell2mat(ciK(:)')));

    % ---- 读法：尾随在多大 D 上追平居中的 D=3（等待等价点）----
    lvl = mean(maeC(:, Dl == 3), 'omitnan');
    idx = find(mean(maeK, 1, 'omitnan') <= lvl, 1, 'first');
    if isempty(idx)
        fprintf('  追平居中 D=3（MAE=%.4f）所需的最小 D：列表范围内未达到（最大 D=%d 时 %.4f）\n', ...
            lvl, Dl(end), mean(maeK(:, end), 'omitnan'));
    else
        fprintf('  追平居中 D=3（MAE=%.4f）所需的最小 D：**D=%d**（等待 %.0f s vs 居中 D=3 的 %.0f s）\n', ...
            lvl, Dl(idx), waitK(idx), waitC(Dl == 3));
    end

    Q = struct();
    Q.D = Dl; Q.waitLook = waitLook; Q.waitCentred = waitC; Q.waitTrailing = waitK;
    Q.maeCentred = maeC; Q.maeTrailing = maeK;
    Q.perSubjectCentred = maeC; Q.perSubjectTrailing = maeK;
    Q.meanCentred = mean(maeC, 1, 'omitnan'); Q.meanTrailing = mean(maeK, 1, 'omitnan');
    Q.delta = d; Q.praw = praw; Q.pHolm = holm;
    Q.ciCentred = ciC; Q.ciTrailing = ciK;
    Q.crossCheck = xc;
    res.(tag) = Q;
end

assert(all(okm), 'D=3 居中行复核失败：停止');
save(fullfile(outdir, 'a2_latency_causal.mat'), 'res', 'Dl', 'base', 'o0', 'B');
fprintf('\n[saved] results/a2_latency_causal.mat\n');
diary off;
end

%% ---- 输出滤波规则（与 exp_a2_causal_smooth.m 同实现）----
function es = out_filter(est, mode, m)
est = est(:).';
switch mode
    case 'median'
        es = movmedian(est, m);
    case 'mediancausal'
        ke = floor(m / 2);
        mv = movmedian(est(:), m);
        es = [nan(ke, 1); mv(1:end - ke)];
        es = es(:).';
    case 'off'
        es = est;
    otherwise
        error('unknown smooth mode: %s', mode);
end
end

%% ---- 指标（逐字复刻 ds5.m:366-379）----
function Q = out_metrics(es, gt, act, tag)
es = es(:).'; gt = gt(:).'; act = act(:).';
n2 = min([numel(gt), numel(es), numel(act)]);
g = gt(1:n2); e = es(1:n2); av = act(1:n2);
if strcmp(tag, 'wesad')
    msk = ~isnan(e) & ~isnan(g) & av > 0 & av < 5 & g > 0;
    den = sum(~isnan(g) & av > 0 & av < 5);
else
    msk = ~isnan(e) & ~isnan(g) & g > 0;
    den = sum(~isnan(g));
end
er = g(msk) - e(msk); ae = abs(er);
if isempty(ae)
    Q = struct('mae', NaN, 'med', NaN, 'p95', NaN, 'bias', NaN, 'gt10', NaN, 'cov', 0, 'nwin', 0, 'ntar', n2);
    return;
end
Q.mae = mean(ae); Q.med = median(ae); Q.p95 = prctile(ae, 95);
Q.bias = mean(er); Q.gt10 = mean(ae > 10);
Q.cov = sum(msk) / max(1, den); Q.nwin = sum(msk); Q.ntar = n2;
end

%% ---- 受试者级 bootstrap 均值 95% CI ----
function ci = bootci_mean(x, B)
x = x(:); n = numel(x);
if n < 2, ci = [NaN NaN]; return; end
bs = zeros(B, 1);
for b = 1:B
    bs(b) = mean(x(randi(n, n, 1)));
end
ci = prctile(bs, [2.5 97.5]);
end

%% ---- 双侧随机符号翻转 ----
function p = signflip(dif, B)
dif = dif(:); n = numel(dif); obs = abs(mean(dif));
s = 0;
for b = 1:B
    sg = 2 * (rand(n, 1) > 0.5) - 1;
    if abs(mean(sg .* dif)) >= obs - 1e-12, s = s + 1; end
end
p = (s + 1) / (B + 1);
end

%% ---- 小工具 ----
function s = ternary(cond, a, b)
if cond, s = a; else, s = b; end
end
