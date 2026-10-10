function exp_lbp_temp_t3()
% T3 验收（第四批 · C 长时可靠性自适应观测温度；两库全 15 受试者）
%
% 预注册见 ROUTE_A_BRIEF_20260918.md §13.2：
%   · 变体：off / C1=C(τ∈[0.7,1.3], W=30)（主口径）/ C2=C(τ∈[0.7,1.3], W=15)（记忆敏感性）；
%   · 机制：rel = exp(−(d_obs/20)²)（d_obs = 当帧观测峰与长时锚的距离；锚 = 历史均值 + v̂），
%     可靠性 EMA（窗 W）→ τ = 0.7 + 0.6·EMA，logL ← τ·logL；
%   · 指标：全局 + 90–150 带 + 运动 Q4 + 恢复段；受试者级配对符号翻转 + bootstrap CI +
%     Holm（家族 = 2×4 = 8）；判级沿用 §1，并标注实践显著性（|Δ| ≥ 0.3 BPM 为有意义）。
% 输出：results/lbp_temp_t3.mat + diary 日志 results/lbp_temp_t3_log.txt

addpath(fileparts(mfilename('fullpath')));
mdir = fileparts(mfilename('fullpath'));
cachedir = fullfile(mdir, 'cache2');
rng(20260918, 'twister');

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');

nS = 15;
vkeys = {'off', 'C1', 'C2'};
vlab = {'off (paper)', 'C1: adapt-temp (W=30)', 'C2: adapt-temp (W=15)'};
vset = struct();
vset.off = struct();
vset.C1 = struct('lbp_vel_L', 5, 'lbp_temp_w', 1, 'lbp_temp_win', 30);
vset.C2 = struct('lbp_vel_L', 5, 'lbp_temp_w', 1, 'lbp_temp_win', 15);
nV = numel(vkeys);
outNames = {'global MAE', 'regime A: 90-150 BPM', 'regime B: motion Q4', 'regime C: recovery (1..5 after Q4)'};

res = struct();
for ds = {'dalia', 'wesad'}
    tag = ds{1};
    if strcmp(tag, 'wesad'), expect = 5.7836; else, expect = 5.9584; end
    fprintf('\n######## %s ########\n', upper(tag));

    R = struct(); MAE = nan(nS, nV); runMean = nan(1, nV);
    for i = 1:nV
        o = base; f = fieldnames(vset.(vkeys{i}));
        for k = 1:numel(f), o.(f{k}) = vset.(vkeys{i}).(f{k}); end
        R.(vkeys{i}) = ds5(tag, 1:nS, o);
        MAE(:, i) = R.(vkeys{i}).mae(:);
        runMean(i) = R.(vkeys{i}).mean;
        fprintf('[run] %-24s MAE=%.4f  SD=%.4f  delta(vs off)=%+.4f\n', ...
            vlab{i}, runMean(i), R.(vkeys{i}).sd, runMean(i) - runMean(1));
    end
    assert(abs(runMean(1) - expect) < 1e-4, 'off 未复现论文口径');

    MOT = cell(1, nS); MSK = cell(1, nS); GT = cell(1, nS); ERR = struct();
    for i = 1:nV, ERR.(vkeys{i}) = cell(1, nS); end
    for si = 1:nS
        F = load(fullfile(cachedir, sprintf('%s_S%d.mat', tag, si)));
        gt = F.gt(:)'; av = F.act(:)'; mot = mean(F.rmsA, 1);
        n = min([numel(gt), F.nWin, numel(av), numel(mot)]);
        gt = gt(1:n); av = av(1:n); mot = mot(1:n);
        if strcmp(tag, 'wesad')
            msk = isfinite(gt) & av > 0 & av < 5 & gt > 0;
        else
            msk = isfinite(gt) & gt > 0;
        end
        es0 = movmedian(R.off.est{si}, base.smooth_m); es0 = es0(1:n);
        msk = msk & isfinite(es0);
        GT{si} = gt; MOT{si} = mot; MSK{si} = msk;
        for i = 1:nV
            es = movmedian(R.(vkeys{i}).est{si}, base.smooth_m);
            e = abs(es(1:n) - gt); e(~msk) = NaN;
            ERR.(vkeys{i}){si} = e;
        end
    end

    moP = [];
    for si = 1:nS, moP = [moP, MOT{si}(MSK{si})]; end   %#ok<AGROW>
    q = prctile(moP, [25 50 75]);
    Q4 = cell(1, nS); rec = cell(1, nS); band = cell(1, nS);
    for si = 1:nS
        Q4{si} = MSK{si} & (MOT{si} >= q(3));
        Hm = Q4{si}; n = numel(Hm); u = false(1, n);
        for k = 1:5
            sh = false(1, n);
            if n > k, sh(1 + k:n) = Hm(1:n - k); end
            u = u | (sh & MSK{si});
        end
        rec{si} = u;
        band{si} = MSK{si} & GT{si} >= 90 & GT{si} < 150;
    end

    Y = nan(nS, nV, 4);
    for si = 1:nS
        for i = 1:nV
            e = ERR.(vkeys{i}){si};
            Y(si, i, 1) = mean(e(MSK{si}), 'omitnan');
            Y(si, i, 2) = mean(e(band{si}), 'omitnan');
            Y(si, i, 3) = mean(e(Q4{si}), 'omitnan');
            Y(si, i, 4) = mean(e(rec{si}), 'omitnan');
        end
    end
    fprintf('  指标均值（受试者平均）：');
    for k = 1:4
        fprintf('\n    %-34s', outNames{k});
        for i = 1:nV, fprintf('  %s=%.3f', vkeys{i}, mean(Y(:, i, k), 'omitnan')); end
    end
    fprintf('\n');

    comp = zeros(0, 4);
    for i = 2:nV
        for k = 1:4
            dif = Y(:, i, k) - Y(:, 1, k); dif = dif(~isnan(dif));
            comp(end + 1, :) = [i, k, mean(dif), signflip(dif, 10000)];   %#ok<AGROW>
        end
    end
    [sp, ord] = sort(comp(:, 4)); m = numel(sp);
    adj = min(1, sp(:) .* ((m:-1:1)'));
    for k = 2:m, adj(k) = max(adj(k), adj(k - 1)); end
    ci = nan(numel(ord), 2);
    for j = 1:numel(ord)
        dif = Y(:, comp(ord(j), 1), comp(ord(j), 2)) - Y(:, 1, comp(ord(j), 2));
        dif = dif(~isnan(dif));
        ci(j, :) = bootci_mean(dif, 10000);
    end
    tbl = nan(size(comp, 1), 5);
    fprintf('  [paired vs off]  delta   raw p   Holm p   CI95\n');
    for j = 1:numel(ord)
        r0 = ord(j);
        tbl(r0, :) = [comp(r0, 3), comp(r0, 4), adj(j), ci(j, :)];
        fprintf('    %-4s %-34s %+7.4f  %6.4f  %6.4f  [%+.3f, %+.3f]\n', ...
            vkeys{comp(r0, 1)}, outNames{comp(r0, 2)}, comp(r0, 3), comp(r0, 4), adj(j), ci(j, 1), ci(j, 2));
    end

    glob = tbl(comp(:, 2) == 1, :);
    degSig = any(glob(:, 3) < 0.05 & glob(:, 1) > 0);
    impSig = any(glob(:, 3) < 0.05 & glob(:, 1) < 0);
    regImp = any(comp(:, 2) > 1 & tbl(:, 3) < 0.05 & tbl(:, 1) < 0);
    practical = any(abs(glob(:, 1)) >= 0.3);
    if degSig
        lvl = '不成立（本库全局显著劣化）';
    elseif impSig
        lvl = '强成立（全局显著改善）';
    elseif regImp
        lvl = '弱成立（预定义 regime 内显著改善）';
    else
        lvl = '不成立（无显著改善，且未显著劣化）';
    end
    fprintf('  判级：%s', lvl);
    if impSig || regImp
        if practical
            fprintf('；实践显著性：有（存在 |Δ| ≥ 0.3 BPM 的显著项）\n');
        else
            fprintf('；实践显著性：**无**（显著项 |Δ| 均 < 0.3 BPM）\n');
        end
    else
        fprintf('\n');
    end

    S = struct();
    S.MAE = MAE; S.runMean = runMean; S.Y = Y; S.q = q;
    S.comp = comp; S.tbl = tbl; S.outNames = outNames; S.order = ord;
    S.level = lvl; S.practical = practical; S.expect = expect;
    RV = struct();
    for i = 1:nV
        v = vkeys{i}; t = struct();
        t.mean = R.(v).mean; t.sd = R.(v).sd; t.mae = R.(v).mae; t.est = R.(v).est;
        RV.(v) = t;
    end
    S.RV = RV; S.base = base; S.vkeys = {vkeys}; S.vlab = {vlab};
    res.(tag) = S;
end

save(fullfile(mdir, 'results', 'lbp_temp_t3.mat'), 'res', '-v7.3');
fprintf('\n[saved] results/lbp_temp_t3.mat\n');
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

% ---- 受试者级 bootstrap 均值 95% CI ----
function ci = bootci_mean(x, B)
x = x(:); n = numel(x);
if n < 2, ci = [NaN NaN]; return; end
bs = zeros(B, 1);
for b = 1:B
    bs(b) = mean(x(randi(n, n, 1)));
end
ci = prctile(bs, [2.5 97.5]);
end
