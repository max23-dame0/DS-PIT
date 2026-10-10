function exp_a2_causal_smooth()
% exp_a2_causal_smooth.m — 输出滤波因果性对照（审查 V2 P0-2 选项 (b) 的前置评估）
%
% 用途：量化"把输出滤波改为因果"对 A′ 主结果的代价，供作者在
%       REVISION_ACTION_CHECKLIST_20260923.md §1.2 的
%       选项 (a)（保留居中中值、如实报 14 s）与 (b)（改因果输出）之间决策。
%
% 对照的三种输出规则（同一 raw 回溯输出 est，仅末端滤波不同）：
%   median       : es = movmedian(est,3)        居中窗 → 需 1 帧未来；目标窗起点等待 8+4+2 = 14 s  【现行论文口径】
%   mediancausal : es(j) = median(est(j-2..j))  尾随窗 → 无未来依赖；等待 8+4 = 12 s
%   off          : es = est                      无输出滤波            ；等待 8+4 = 12 s
%
% 关键设计：ds5 的 res.est 在平滑之前写入、且与 smooth_mode 无关
%   （ds5.m:380 `ALL{si} = est;` 在 :359-364 平滑之前）
%   → 每个数据集只需调用 ds5 一次，三种规则在离线重算 → 机时 = 1× exp_a2_core。
%   本脚本**不修改 ds5.m**。
%
% 依赖：cache2（只读，不重建；gt/act 直接取自缓存，与 ds5.m:105 同源）
%       ds5.m / a2_cfg.m
% 产物：results/a2_causal_smooth.mat + results/a2_causal_smooth_log.txt
% 护栏：先复核 median 口径逐位复现 5.8302/5.7569（复核失败即中止）
% 登记：method_dev/INDEX.md、results/README.md（另行追加）

addpath(fileparts(mfilename('fullpath')));
mdir = fileparts(mfilename('fullpath'));
cache = fullfile(mdir, 'cache2');
outdir = fullfile(mdir, 'results');
diary(fullfile(outdir, 'a2_causal_smooth_log.txt'));
fprintf('=== exp_a2_causal_smooth（输出滤波因果性对照）%s ===\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));

B = 10000;
tags = {'dalia', 'wesad'};
base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');
o = a2_cfg(base);

%% 0) 复核：median 口径必须复现 exp_a2_core 的 headline 与 bootstrap CI
fprintf('\n--- 0) 复核现行口径（median）期望 5.8302 / 5.7569，CI [4.83,6.93] / [4.37,7.50] ---\n');
rng(20260916);                    % 与 exp_a2_core.m:12 一致，且调用顺序相同
R = struct(); chk = struct();
for t = 1:numel(tags)
    tag = tags{t};
    R.(tag) = ds5(tag, 1:15, o);
    chk.(tag).mae = R.(tag).mae(:);
    chk.(tag).ci = bootci_mean(chk.(tag).mae, B);
    fprintf('  %-6s MAE=%.4f  SD=%.4f  CI=[%.2f, %.2f]  (n=%d)\n', tag, ...
        mean(chk.(tag).mae), std(chk.(tag).mae), chk.(tag).ci(1), chk.(tag).ci(2), numel(chk.(tag).mae));
end
okm = abs(mean(chk.dalia.mae) - 5.8302) < 5e-4 && abs(mean(chk.wesad.mae) - 5.7569) < 5e-4;
if okm, verdict = 'PASS（逐位复现现行口径）'; else, verdict = 'FAIL'; end
fprintf('  复核结论：%s\n', verdict);
assert(okm, 'median 口径复核失败：停止，不得用于任何结论');

%% 1) 三种输出规则的对照
modes = {'median', 'mediancausal', 'off'};
mlab = {'median   (centred, 14 s)', 'mediancausal (trailing, 12 s)', 'off      (none,    12 s)'};
mwait = [14, 12, 12];
res = struct();
for t = 1:numel(tags)
    tag = tags{t};
    est = R.(tag).est;            % 1×15 cell；raw est，与 smooth_mode 无关
    nS = numel(est);
    gt = cell(1, nS); act = cell(1, nS);
    for si = 1:nS
        F = load(fullfile(cache, sprintf('%s_S%d.mat', tag, si)));
        gt{si} = F.gt(:)'; act{si} = F.act(:)';
    end
    ua = unique(cell2mat(cellfun(@(a) unique(a(:))', act, 'uni', 0)));
    fprintf('\n######## %s ########\n', upper(tag));
    fprintf('  act 标签取值：%s   （与缓存一致；DaLiA 为逐窗活动标签）\n', mat2str(ua));

    M = struct();
    for mi = 1:numel(modes)
        mae = nan(1, nS); med = nan(1, nS); p95 = nan(1, nS);
        bias = nan(1, nS); gt10 = nan(1, nS); cov = nan(1, nS); nwin = zeros(1, nS); ntar = zeros(1, nS);
        for si = 1:nS
            es = out_filter(est{si}, modes{mi}, o.smooth_m);
            Q = out_metrics(es, gt{si}, act{si}, tag);
            mae(si) = Q.mae; med(si) = Q.med; p95(si) = Q.p95;
            bias(si) = Q.bias; gt10(si) = Q.gt10; cov(si) = Q.cov;
            nwin(si) = Q.nwin; ntar(si) = Q.ntar;
        end
        rng(20260916 + 100 * t + mi);          % 每个 (数据集, 规则) 独立可复现种子
        ci = bootci_mean(mae, B);
        fn = modes{mi};
        M.(fn) = struct('mae', mae, 'med', med, 'p95', p95, 'bias', bias, 'gt10', gt10, ...
            'cov', cov, 'nwin', nwin, 'ntar', ntar, 'ci', ci, ...
            'mean', mean(mae, 'omitnan'), 'sd', std(mae, 'omitnan'));
        q = M.(fn);
        fprintf('  [%s] MAE=%.4f  SD=%.4f  CI=[%.2f, %.2f]  Med=%.4f  P95=%.2f  >10%%=%.2f%%  cov=%.4f  有效窗=%d/%d\n', ...
            mlab{mi}, q.mean, q.sd, q.ci(1), q.ci(2), mean(med, 'omitnan'), mean(p95, 'omitnan'), ...
            100 * mean(gt10, 'omitnan'), mean(cov, 'omitnan'), sum(nwin), sum(ntar));
    end

    % 配对检验：vs median（家族 = 本数据集 2 个比较；探索性家族，非预注册）
    d = nan(2, 1); praw = nan(2, 1); cmp = cell(2, 1);
    for mi = 2:3
        fn = modes{mi};
        dif = M.(fn).mae - M.median.mae;
        rng(20260918 + 100 * t + mi);
        d(mi - 1) = mean(dif, 'omitnan');
        praw(mi - 1) = signflip(dif, B);
        cmp{mi - 1} = fn;
    end
    mm = numel(praw); [sp, ord] = sort(praw);
    adj = min(1, sp(:) .* ((mm:-1:1)')); for k = 2:mm, adj(k) = max(adj(k), adj(k - 1)); end
    holm = nan(mm, 1); holm(ord) = adj;
    fprintf('  [paired vs median]  delta(vs ref)   raw p    Holm p (m=%d)\n', mm);
    for mi = 1:mm
        fprintf('    %-16s %+8.4f     %.4f   %.4f\n', cmp{mi}, d(mi), praw(mi), holm(mi));
    end
    fprintf('  等待：median=14 s（8+4+2，含 1 帧未来）；mediancausal/off=12 s（8+4，无未来依赖）\n');
    fprintf('  有效窗总数：median=%d  medcausal=%d  off=%d  （相对 median：%+d / %+d）\n', ...
        sum(M.median.nwin), sum(M.mediancausal.nwin), sum(M.off.nwin), ...
        sum(M.off.nwin) - sum(M.median.nwin), sum(M.mediancausal.nwin) - sum(M.median.nwin));

    res.(tag) = M;
end

%% 2) 结语
fprintf('\n=== 结论摘要（供作者决策，未经 Astra/作者复核）===\n');
for t = 1:numel(tags)
    tag = tags{t}; M = res.(tag);
    fprintf('  %-6s  median %.4f (14 s)  vs  causal %.4f (12 s)  →  Δ=%+.4f BPM；无滤波 %.4f → Δ=%+.4f BPM\n', ...
        tag, M.median.mean, M.mediancausal.mean, M.mediancausal.mean - M.median.mean, ...
        M.off.mean, M.off.mean - M.median.mean);
end
fprintf('  注：本对照只覆盖主结果（headline）。嵌套 CV、延迟表、消融三处同样以平滑后的 es 计分，\n');
fprintf('      若采用因果输出，需另行复算（见 REVISION_ALIGNMENT_20260923.md §B.5 触发条件）。\n');

save(fullfile(outdir, 'a2_causal_smooth.mat'), 'res', 'chk', 'base', 'o', 'B', 'modes', 'mlab', 'mwait');
fprintf('\n[saved] results/a2_causal_smooth.mat\n');
diary off;
end

%% ---- 输出滤波规则 ----
function es = out_filter(est, mode, m)
est = est(:).';
switch mode
    case 'median'
        es = movmedian(est, m);                       % 居中窗（论文现行口径）
    case 'mediancausal'
        ke = floor(m / 2);
        mv = movmedian(est(:), m);                    % 居中结果右移 ke → es(j)=median(est(j-2ke..j))
        es = [nan(ke, 1); mv(1:end - ke)];
        es = es(:).';
    case 'off'
        es = est;
    otherwise
        error('unknown smooth mode: %s', mode);
end
end

%% ---- 指标（逐字复刻 ds5.m:366-379 的掩码与口径）----
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
    Q = struct('mae', NaN, 'rmse', NaN, 'med', NaN, 'p95', NaN, 'bias', NaN, ...
        'gt10', NaN, 'cov', 0, 'nwin', 0, 'ntar', n2);
    return;
end
Q.mae = mean(ae); Q.rmse = sqrt(mean(er.^2)); Q.med = median(ae);
Q.p95 = prctile(ae, 95); Q.bias = mean(er); Q.gt10 = mean(ae > 10);
Q.cov = sum(msk) / max(1, den); Q.nwin = sum(msk); Q.ntar = n2;
end

%% ---- 受试者级 bootstrap 均值 95% CI（与 exp_lbp_temp_t3.m 同式）----
function ci = bootci_mean(x, B)
x = x(:); n = numel(x);
if n < 2, ci = [NaN NaN]; return; end
bs = zeros(B, 1);
for b = 1:B
    bs(b) = mean(x(randi(n, n, 1)));
end
ci = prctile(bs, [2.5 97.5]);
end

%% ---- 双侧随机符号翻转（与 exp_lbp_temp_t3.m:175-183 同式）----
function p = signflip(dif, B)
dif = dif(:); n = numel(dif); obs = abs(mean(dif));
s = 0;
for b = 1:B
    sg = 2 * (rand(n, 1) > 0.5) - 1;
    if abs(mean(sg .* dif)) >= obs - 1e-12, s = s + 1; end
end
p = (s + 1) / (B + 1);
end
