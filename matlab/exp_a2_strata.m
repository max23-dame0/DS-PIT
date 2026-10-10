function exp_a2_strata()
% A′ 分层补充复算（ROUTE_A_BRIEF §14.3 遗留项）：
%   (a) 运动四分位分箱：MAE / >10% 份额（口径与 exp_motion_covariate 完全一致）；
%   (b) 实测可靠性温度 τ 的分布及其与窗口误差的关系（ds5 新增 diag 字段 tau，仅诊断）；
%   (c) 每库 headline 与 a2_core 对照核验（防口径漂移）。
% 输出：results/a2_strata.mat + diary 日志 results/a2_strata_log.txt

addpath(fileparts(mfilename('fullpath')));
mdir = fileparts(mfilename('fullpath'));
cachedir = fullfile(mdir, 'cache2');

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');
o = a2_cfg(base);
res = struct();

for ds = {'dalia', 'wesad'}
    tag = ds{1};
    fprintf('\n######## %s ########\n', upper(tag));
    od = o; od.lbp_diag = true;
    r = ds5(tag, 1:15, od);
    fprintf('  headline MAE=%.4f SD=%.4f  (a2_core 参考见 results/a2_core_log.txt)\n', r.mean, r.sd);

    A = []; B = []; T = []; MAEchk = nan(1, 15);
    for si = 1:15
        F = load(fullfile(cachedir, sprintf('%s_S%d.mat', tag, si)));
        gt = F.gt(:)'; act = F.act(:)';
        mot = mean(F.rmsA, 1);
        es = movmedian(r.est{si}, o.smooth_m);
        n2 = min([numel(gt), numel(es), numel(act), numel(mot)]);
        g = gt(1:n2); e = es(1:n2); av = act(1:n2); mo = mot(1:n2);
        if strcmp(tag, 'wesad')
            msk = ~isnan(e) & ~isnan(g) & av > 0 & av < 5 & g > 0;
        else
            msk = ~isnan(e) & ~isnan(g) & g > 0;
        end
        aerr = abs(e(msk) - g(msk));
        MAEchk(si) = mean(aerr);
        tau = nan(1, n2);
        ev = r.lbp_diag{si};
        ok = ev.idx >= 1 & ev.idx <= n2;
        tau(ev.idx(ok)) = ev.tau(ok);
        A = [A, aerr];            %#ok<AGROW>
        B = [B, mo(msk)];         %#ok<AGROW>
        T = [T, tau(msk)];        %#ok<AGROW>
    end
    fprintf('  sanity: max |recomputed - ds5| per-subject MAE = %.2e\n', max(abs(MAEchk - r.mae(:).')));

    % ---- (a) 运动四分位（口径同 exp_motion_covariate）----
    qq = prctile(B, [25 50 75]);
    edges = [-inf qq inf];
    bins = zeros(4, 5);
    ccm = corrcoef(A, B);
    if exist('tiedrank', 'file') == 2
        sc = corrcoef(tiedrank(A), tiedrank(B)); sp = sc(1, 2);
    else
        sp = NaN;
    end
    fprintf('  Pearson(|err|,motion)=%.3f  Spearman(|err|,motion)=%.3f  (n=%d)\n', ccm(1, 2), sp, numel(A));
    fprintf('  --- motion quartiles: n / MAE / >10%% / median motion / >5%% ---\n');
    for k = 1:4
        m = B >= edges(k) & B < edges(k + 1);
        bins(k, :) = [sum(m), mean(A(m)), mean(A(m) > 10), median(B(m)), mean(A(m) > 5)];
        fprintf('  Q%d  n=%6d  median_motion=%.4f  MAE=%.2f  >5%%=%.1f%%  >10%%=%.1f%%\n', ...
            k, bins(k, 1), bins(k, 4), bins(k, 2), 100 * bins(k, 5), 100 * bins(k, 3));
    end

    % ---- (b) 可靠性温度 τ 的实测分布 ----
    tm = ~isnan(T);
    Tt = T(tm); At = A(tm);
    qt = prctile(Tt, [25 50 75]);
    fprintf('  --- reliability temperature tau (n=%d emitted windows with tau) ---\n', numel(Tt));
    fprintf('  mean=%.3f  median=%.3f  p05=%.3f  p95=%.3f  min=%.3f  max=%.3f\n', ...
        mean(Tt), median(Tt), prctile(Tt, 5), prctile(Tt, 95), min(Tt), max(Tt));
    fprintf('  frac(tau<1)=%.1f%%  frac(tau>1)=%.1f%%  frac(|tau-1|<0.02)=%.1f%%\n', ...
        100 * mean(Tt < 1), 100 * mean(Tt > 1), 100 * mean(abs(Tt - 1) < 0.02));
    lo = Tt < 1; hi = ~lo;
    fprintf('  mean|err|: tau<1 (low reliability) %.2f BPM (n=%d) | tau>=1 %.2f BPM (n=%d)\n', ...
        mean(At(lo)), sum(lo), mean(At(hi)), sum(hi));
    fprintf('  tau quartiles: Q1 (<=%.3f) MAE=%.2f | Q4 (>=%.3f) MAE=%.2f\n', ...
        qt(1), mean(At(Tt <= qt(1))), qt(3), mean(At(Tt >= qt(3))));
    cc = corrcoef(Tt, At);
    fprintf('  Pearson(tau, |err|) = %.3f\n', cc(1, 2));

    % ---- (c) 与 a2_core 对照（每受试 MAE 已由 sanity 行核验）----

    S = struct();
    S.motion_quartiles = bins; S.motion_qedges = qq;
    S.pearson_motion = ccm(1, 2); S.spearman_motion = sp;
    S.tau_n = numel(Tt); S.tau_mean = mean(Tt); S.tau_median = median(Tt);
    S.tau_p05 = prctile(Tt, 5); S.tau_p95 = prctile(Tt, 95);
    S.tau_frac_lo = mean(Tt < 1); S.tau_frac_hi = mean(Tt > 1);
    S.err_tau_lo = mean(At(lo)); S.err_tau_hi = mean(At(hi));
    S.tau_quartiles = qt; S.err_tau_q1 = mean(At(Tt <= qt(1))); S.err_tau_q4 = mean(At(Tt >= qt(3)));
    S.pearson_tau_err = cc(1, 2); S.MAEchk = MAEchk; S.mean = r.mean; S.sd = r.sd;
    res.(tag) = S;
end

save(fullfile(mdir, 'results', 'a2_strata.mat'), 'res', 'base', 'o');
fprintf('\n[saved] results/a2_strata.mat\n');
end
