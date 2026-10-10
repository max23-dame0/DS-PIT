function exp_lbp_temp_ctrl()
% T3 控制实验（第四批 · C 机制）：极端剂量点 + 常数温度消融（两库全 15 受试者）
%
% 目的（预注册见 ROUTE_A_BRIEF §13.3 的剂量–响应框架）：
%   ① 极端剂量点 C7 = τ∈[0.4,1.6]（检验剂量–响应是否继续单调放大）；
%   ② 常数温度消融 C5 = τ≡1.15（锐化）、C6 = τ≡0.85（平坦化）——若常数 τ 与自适应
%      版本的改善相当，则"长时可靠性"叙事不成立（改善仅来自温度重标定）。
% 输出：results/lbp_temp_ctrl.mat + diary 日志 results/lbp_temp_ctrl_log.txt

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
vkeys = {'off', 'C7', 'C5', 'C6'};
vlab = {'off (paper)', 'C7: tau[0.4,1.6] W=30', 'C5: tau const 1.15', 'C6: tau const 0.85'};
vset = struct();
vset.off = struct();
vset.C7 = struct('lbp_vel_L', 5, 'lbp_temp_w', 1, 'lbp_temp_win', 30, 'lbp_temp_lo', 0.4, 'lbp_temp_hi', 1.6);
vset.C5 = struct('lbp_vel_L', 5, 'lbp_temp_w', 1, 'lbp_temp_win', 30, 'lbp_temp_lo', 1.15, 'lbp_temp_hi', 1.15);
vset.C6 = struct('lbp_vel_L', 5, 'lbp_temp_w', 1, 'lbp_temp_win', 30, 'lbp_temp_lo', 0.85, 'lbp_temp_hi', 0.85);
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

    fprintf('  [paired vs off]  delta   raw p\n');
    for i = 2:nV
        for k = 1:4
            dif = Y(:, i, k) - Y(:, 1, k); dif = dif(~isnan(dif));
            p = signflip(dif, 10000);
            fprintf('    %-4s %-34s %+7.4f  %6.4f\n', vkeys{i}, outNames{k}, mean(dif), p);
        end
    end

    S = struct(); S.MAE = MAE; S.runMean = runMean; S.Y = Y; S.q = q;
    S.outNames = outNames; S.expect = expect;
    RV = struct();
    for i = 1:nV
        v = vkeys{i}; t = struct();
        t.mean = R.(v).mean; t.sd = R.(v).sd; t.mae = R.(v).mae; t.est = R.(v).est;
        RV.(v) = t;
    end
    S.RV = RV; S.base = base; S.vkeys = {vkeys}; S.vlab = {vlab};
    res.(tag) = S;
end

save(fullfile(mdir, 'results', 'lbp_temp_ctrl.mat'), 'res', '-v7.3');
fprintf('\n[saved] results/lbp_temp_ctrl.mat\n');
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
