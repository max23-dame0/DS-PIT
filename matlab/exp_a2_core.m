function exp_a2_core()
% A′ 核心指标重算（评估配置 = C1；两库 + IEEE SPC）
%
% 产出（口径与 exp_paper_v3 §1 / exp_extra_metrics / exp_bias_strata / exp_motion_covariate 一致）：
%   headline：MAE / SD / 受试者级 bootstrap 95% CI / MedAE / P95 / >10% / coverage /
%   bias / LoA / pooled r；补充：subject-macro RMSE、>5%；HR 带分层；运动四分位；IEEE 三口径。
% 输出：results/a2_core.mat + diary 日志 results/a2_core_log.txt

addpath(fileparts(mfilename('fullpath')));
mdir = fileparts(mfilename('fullpath'));
cachedir = fullfile(mdir, 'cache2');
rng(20260916);

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');
o = a2_cfg(base);
fprintf('=== A'' core metrics (config = C1: lbp_temp_w=1, W=30, tau in [0.7,1.3]) ===\n');

res = struct();
bands = [-inf 60; 60 90; 90 120; 120 150; 150 inf];
for ds = {'dalia', 'wesad'}
    tag = ds{1};
    fprintf('\n######## %s ########\n', upper(tag));
    r = ds5(tag, 1:15, o);
    mae = r.mae(:);
    B = 10000; bs = zeros(B, 1);
    for b = 1:B, bs(b) = mean(mae(randi(15, 15, 1))); end
    ci = prctile(bs, [2.5 97.5]);
    E = cell2mat(cellfun(@(c) c(:).', r.err, 'uni', 0));   % ref - est, pooled
    es = -E;
    ee = cell2mat(cellfun(@(c) c(1, :), r.pairs, 'uni', 0));
    gg = cell2mat(cellfun(@(c) c(2, :), r.pairs, 'uni', 0));
    cc = corrcoef(ee, gg);
    subj_gt5 = mean(cellfun(@(c) mean(abs(c(:)) > 5), r.err), 'omitnan');
    fprintf('[headline] MAE=%.4f SD=%.4f CI=[%.3f, %.3f] Med=%.4f P95=%.2f >10%%=%.2f%% cov=%.4f\n', ...
        r.mean, r.sd, ci(1), ci(2), mean(r.med), mean(r.p95), 100 * mean(r.gt10), mean(r.cov));
    fprintf('[pooled]   bias=%+.4f SD(err)=%.4f LoA=[%+.2f, %+.2f] r=%.4f\n', ...
        mean(es), std(es), mean(es) - 1.96 * std(es), mean(es) + 1.96 * std(es), cc(1, 2));
    fprintf('[extra]    RMSE(subj-macro)=%.4f  >5%%=%.2f%%  (per-subject MAE: %s)\n', ...
        mean(r.rmse, 'omitnan'), 100 * subj_gt5, mat2str(round(mae.', 3)));

    % HR 带分层（pooled；e = est - ref）
    bS = zeros(size(bands, 1), 4);   % [n, sum|e|, sum e, sum(|e|>10)]
    moP = []; eP = [];
    for si = 1:15
        F = load(fullfile(cachedir, sprintf('%s_S%d.mat', tag, si)));
        gt = F.gt(:)'; av = F.act(:)'; mot = mean(F.rmsA, 1);
        n = min([numel(gt), F.nWin, numel(av), numel(mot)]);
        gt = gt(1:n); av = av(1:n); mot = mot(1:n);
        if strcmp(tag, 'wesad')
            msk = isfinite(gt) & av > 0 & av < 5 & gt > 0;
        else
            msk = isfinite(gt) & gt > 0;
        end
        esm = movmedian(r.est{si}, base.smooth_m); esm = esm(1:n);
        msk = msk & isfinite(esm);
        e = esm - gt;
        moP = [moP, mot(msk)];   %#ok<AGROW>
        eP = [eP, abs(e(msk))];  %#ok<AGROW>
        for k = 1:size(bands, 1)
            bm = msk & gt >= bands(k, 1) & gt < bands(k, 2);
            if any(bm)
                bS(k, 1) = bS(k, 1) + sum(bm);
                bS(k, 2) = bS(k, 2) + sum(abs(e(bm)));
                bS(k, 3) = bS(k, 3) + sum(e(bm));
                bS(k, 4) = bS(k, 4) + sum(abs(e(bm)) > 10);
            end
        end
    end
    fprintf('[HR bands]  band | n | MAE | bias | >10%%\n');
    for k = 1:size(bands, 1)
        if bS(k, 1) > 0
            fprintf('    [%.0f,%.0f) n=%6d MAE=%6.2f bias=%+7.2f >10%%=%5.1f%%\n', ...
                bands(k, 1), bands(k, 2), bS(k, 1), bS(k, 2) / bS(k, 1), ...
                bS(k, 3) / bS(k, 1), 100 * bS(k, 4) / bS(k, 1));
        end
    end
    q = prctile(moP, [25 50 75]);
    fprintf('[motion]   quartile MAE: ');
    qt = 1 + (moP >= q(1)) + (moP >= q(2)) + (moP >= q(3));
    qmae = zeros(1, 4);
    for t = 1:4
        qmae(t) = mean(eP(qt == t));
        fprintf('Q%d=%.2f  ', t, qmae(t));
    end
    ccm = corrcoef(eP, moP);
    fprintf('| Pearson(|err|,motion)=%.3f\n', ccm(1, 2));

    S = struct();
    S.mean = r.mean; S.sd = r.sd; S.ci = ci; S.med = mean(r.med); S.p95 = mean(r.p95);
    S.gt10 = mean(r.gt10); S.cov = mean(r.cov); S.bias = mean(es);
    S.loa = [mean(es) - 1.96 * std(es), mean(es) + 1.96 * std(es)]; S.pooledr = cc(1, 2);
    S.subj_rmse = mean(r.rmse, 'omitnan'); S.subj_gt5 = subj_gt5; S.mae = mae.';
    S.bandSum = bS; S.bands = bands; S.qedges = q; S.qmae = qmae; S.pearson_motion = ccm(1, 2);
    S.perSubjectMAE = mae.';
    res.(tag) = S;
end

fprintf('\n######## IEEE (3 splits) ########\n');
sets = {'ALL23', 1:23; 'TRAIN12', 1:12; 'TEST11', 13:23};
res.ieee = struct();
for i = 1:size(sets, 1)
    r = ds5('ieee', sets{i, 2}, o);
    E = cell2mat(cellfun(@(c) c(:).', r.err, 'uni', 0));
    se = std(E); es = -E;
    ee = cell2mat(cellfun(@(c) c(1, :), r.pairs, 'uni', 0));
    gg = cell2mat(cellfun(@(c) c(2, :), r.pairs, 'uni', 0));
    cc = corrcoef(ee, gg);
    nrec = numel(sets{i, 2});
    bs = zeros(10000, 1); rng(20260916);
    for b = 1:10000, bs(b) = mean(r.mae(randi(nrec, nrec, 1))); end
    ci = prctile(bs, [2.5 97.5]);
    fprintf('%-8s n=%2d MAE=%.4f SD=%.4f CI=[%.2f,%.2f] Med=%.4f P95=%.2f >10%%=%.1f%% bias=%+.3f LoA=[%+.2f,%+.2f] r=%.4f cov=%.4f\n', ...
        sets{i, 1}, nrec, r.mean, r.sd, ci(1), ci(2), mean(r.med), mean(r.p95), ...
        100 * mean(r.gt10), mean(es), mean(es) - 1.96 * se, mean(es) + 1.96 * se, cc(1, 2), mean(r.cov));
    fprintf('         per-record MAE: %s\n', mat2str(round(r.mae, 2)));
    t = struct('mean', r.mean, 'sd', r.sd, 'ci', ci, 'med', mean(r.med), ...
        'p95', mean(r.p95), 'gt10', mean(r.gt10), 'cov', mean(r.cov), ...
        'bias', mean(es), 'loa', [mean(es) - 1.96 * se, mean(es) + 1.96 * se], ...
        'pooledr', cc(1, 2), 'mae', r.mae, 'subj_rmse', mean(r.rmse, 'omitnan'));
    res.ieee.(sets{i, 1}) = t;
end

save(fullfile(mdir, 'results', 'a2_core.mat'), 'res', 'base', 'o', 'bands');
fprintf('\n[saved] results/a2_core.mat\n');
end
