function exp_a2_extra()
% A′ 补充复算：(a) IEEE 窄带对照与逐记录份额/池化统计；(b) ACC 参考配对 p 值；
%   (c) 活动分层（复刻 exp_r3c05_v2，A′ 配置）
% 输出：results/a2_extra.mat + diary 日志 results/a2_extra_log.txt
addpath(fileparts(mfilename('fullpath')));
mdir = fileparts(mfilename('fullpath'));
cachedir = fullfile(mdir, 'cache2');

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, 'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');
b2 = a2_cfg(base);
res = struct();

% ---- (a) IEEE 窄带对照 + 逐记录 ----
fprintf('=== IEEE under A'' ===\n');
r = ds5('ieee', 1:23, b2);
o = b2; o.state_lo_hz = 1.0;
rn = ds5('ieee', 1:23, o);
fprintf('wideband+taper MAE=%.4f | narrow(1.0Hz)+taper MAE=%.4f | delta=%+.4f\n', ...
    r.mean, rn.mean, r.mean - rn.mean);
E = cell2mat(cellfun(@(c) c(:).', r.err, 'uni', 0)); ae = abs(E);
fprintf('pooled: Med=%.3f P95=%.3f >5%%=%.2f%% >10%%=%.2f%% RMSE=%.3f\n', ...
    median(ae), prctile(ae, 95), 100 * mean(ae > 5), 100 * mean(ae > 10), sqrt(mean(E.^2)));
fprintf('record-macro: RMSE=%.3f >5%%=%.2f%%\n', mean(r.rmse), ...
    100 * mean(cellfun(@(c) mean(abs(c(:)) > 5), r.err)));
absSum = cellfun(@(c) sum(abs(c(:))), r.err);
[~, ord] = sort(absSum, 'descend');
fprintf('top records by abs error: %s (share %.1f%%)\n', mat2str(ord(1:3)), ...
    100 * sum(absSum(ord(1:3))) / sum(absSum));
res.ieee = struct('wide', r.mean, 'narrow', rn.mean, 'pooledMed', median(ae), ...
    'pooledP95', prctile(ae, 95), 'pooledGt5', mean(ae > 5), 'pooledGt10', mean(ae > 10), ...
    'pooledRMSE', sqrt(mean(E.^2)), 'recRMSE', mean(r.rmse), 'top3', ord(1:3), ...
    'top3share', sum(absSum(ord(1:3))) / sum(absSum), 'mae', r.mae);

% ---- (b) ACC 配对 p 值（读取 a2_tables）----
T = load(fullfile(mdir, 'results', 'a2_tables.mat'));
fprintf('\n=== ACC paired p (A'') ===\n');
for ds = {'dalia', 'wesad'}
    A = T.res.(ds{1}).acc;
    fprintf('%s: ', upper(ds{1}));
    for j = 1:numel(A.p)
        fprintf('%s delta=%+.3f p=%.4f | ', A.names{j + 1}, A.delta(j), A.p(j));
    end
    fprintf('\n');
end
res.accP = struct('dalia', T.res.dalia.acc, 'wesad', T.res.wesad.acc);

% ---- (c) 活动分层（口径同 exp_r3c05_v2；A' 配置）----
DA = load(fullfile(mdir, 'results', 'dalia_activity.mat'));
nmDA = {'Sitting', 'Stairs', 'TableSoccer', 'Cycling', 'Driving', 'Lunch', 'Walking', 'Working', 'Transition'};
nmWE = {'Baseline', 'Stress', 'Amusement', 'Meditation'};
fprintf('\n=== activity strata (A'') ===\n');
for ds = {'dalia', 'wesad'}
    isW = strcmp(ds{1}, 'wesad');
    rr = ds5(ds{1}, 1:15, b2);
    fprintf('--- %s (headline %.3f) ---\n', upper(ds{1}), rr.mean);
    A = []; E = [];
    for si = 1:15
        F = load(fullfile(cachedir, sprintf('%s_S%d.mat', ds{1}, si)));
        gt = F.gt(:)';
        if isW
            act = F.act(:)';
        else
            act = DA.A{si}(:).';
            if numel(act) < numel(gt), act(end + 1:numel(gt)) = 9; end
            act = act(1:numel(gt));
        end
        es = movmedian(rr.est{si}, 3);
        n2 = min([numel(gt), numel(es), numel(act)]);
        A = [A, act(1:n2)];                  %#ok<AGROW>
        E = [E, abs(gt(1:n2) - es(1:n2))];   %#ok<AGROW>
    end
    ok = ~isnan(E) & A > 0;
    if isW, ok = ok & A < 5; end
    A = A(ok); E = E(ok);
    tot = sum(E);
    for k = unique(A)
        v = E(A == k);
        if numel(v) < 50, continue; end
        if isW, nm = nmWE{k}; else, nm = nmDA{k}; end
        fprintf('  %-12s n=%6d share=%5.1f%% MAE=%7.3f >10%%=%5.1f%% contrib=%5.1f%%\n', ...
            nm, numel(v), 100 * mean(A == k), mean(v), 100 * mean(v > 10), 100 * sum(v) / tot);
    end
    fprintf('  %-12s n=%6d MAE=%7.3f >10%%=%5.1f%%\n', 'ALL', numel(A), mean(E), 100 * mean(E > 10));
    res.(ds{1}).act = struct('n', numel(A), 'mae', mean(E), 'gt10', mean(E > 10));
end
save(fullfile(mdir, 'results', 'a2_extra.mat'), 'res');
fprintf('\n[saved] results/a2_extra.mat\n');
end
