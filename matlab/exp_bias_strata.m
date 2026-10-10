function exp_bias_strata()
% E3 + E5（ROUND2_CHECKLIST CM2a / CM4a；R2-M4 / R3-M3 / R1-M5 / R2-m4）
%
% 内容：
%   1. bias 机制拆分：{taper on/off} × {median-of-3 输出滤波 on/off}，各 4 组
%      （统一配置其余参数不变），报告 MAE / bias(est-ref) / LoA / RMSE
%   2. 参考 HR 带分层（headline 配置）：<60 / 60-90 / 90-120 / 120-150 / >=150 BPM
%      （响应"低 HR 区被锥形衰减且从未按 HR 带分层"的质疑）
%   3. coverage 缺口核验：本地重算覆盖并与 ds5 返回的 cov 对照，统计每受试缺失窗数
%
% 输出：results/bias_strata.mat（+ diary 日志 results/bias_strata_log.txt）

addpath(fileparts(mfilename('fullpath')));
d = fileparts(mfilename('fullpath'));
cachedir = fullfile(d, 'cache2');

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');

cfg = { ...
    'taper on,  filter on (headline)', struct(); ...
    'taper off, filter on',            struct('edge_taper', 0); ...
    'taper on,  filter off',           struct('smooth_m', 1); ...
    'taper off, filter off',           struct('edge_taper', 0, 'smooth_m', 1)};

res = struct();
for ds = {'dalia', 'wesad'}
    tag = ds{1};
    fprintf('\n######## %s ########\n', upper(tag));
    r1 = [];
    for i = 1:size(cfg, 1)
        o = base; f = fieldnames(cfg{i, 2});
        for k = 1:numel(f), o.(f{k}) = cfg{i, 2}.(f{k}); end
        r = ds5(tag, 1:15, o);
        E = cell2mat(cellfun(@(c) c(:).', r.err, 'uni', 0));   % ref - est
        es = -E;                                                % est - ref
        loa = [mean(es) - 1.96 * std(es), mean(es) + 1.96 * std(es)];
        fprintf('  %-30s MAE=%.4f  bias=%+.4f  LoA=[%+.2f, %+.2f]  RMSE=%.4f\n', ...
            cfg{i, 1}, r.mean, mean(es), loa(1), loa(2), sqrt(mean(es.^2)));
        res.(tag).(sprintf('cfg%d', i)) = struct('name', cfg{i, 1}, 'mae', r.mean, ...
            'sd', r.sd, 'bias', mean(es), 'loa', loa, 'rmse', sqrt(mean(es.^2)), ...
            'perSubjBias', cellfun(@(c) -mean(c), r.err));
        if i == 1, r1 = r; end
    end

    % ---- 参考 HR 带分层（headline）----
    PT = cell2mat(cellfun(@(c) c, r1.pairs, 'uni', 0));   % 2 x N: [est; ref]
    e = PT(1, :); g = PT(2, :); aerr = abs(e - g); sb = e - g;
    edges = [0 60 90 120 150 1000];
    nm = {'<60', '60-90', '90-120', '120-150', '>=150'};
    fprintf('  --- HR-band strata (headline) ---\n');
    fprintf('  band      n      share     MAE    bias    >10%%\n');
    strata = zeros(5, 4);
    for k = 1:5
        m = g >= edges(k) & g < edges(k + 1);
        strata(k, :) = [sum(m), mean(aerr(m)), mean(sb(m)), mean(aerr(m) > 10)];
        fprintf('  %-8s %6d %6.2f%%  %6.2f  %+6.2f  %5.1f%%\n', nm{k}, ...
            sum(m), 100 * mean(m), strata(k, 1), strata(k, 2), 100 * strata(k, 4));
    end
    res.(tag).strata = strata; res.(tag).strataNames = nm;

    % ---- coverage 缺口核验 ----
    covL = nan(1, 15); miss = nan(1, 15);
    for si = 1:15
        F = load(fullfile(cachedir, sprintf('%s_S%d.mat', tag, si)));
        gt = F.gt(:)'; act = F.act(:)';
        es2 = movmedian(r1.est{si}, base.smooth_m);
        n2 = min([numel(gt), numel(es2), numel(act)]);
        g2 = gt(1:n2); e2 = es2(1:n2); av = act(1:n2);
        if strcmp(tag, 'wesad')
            den = sum(~isnan(g2) & av > 0 & av < 5);
            msk = ~isnan(e2) & ~isnan(g2) & av > 0 & av < 5 & g2 > 0;
        else
            den = sum(~isnan(g2));
            msk = ~isnan(e2) & ~isnan(g2) & g2 > 0;
        end
        covL(si) = sum(msk) / max(1, den);
        miss(si) = den - sum(msk);
    end
    fprintf('  coverage: local=%.4f  ds5=%.4f  mean missing windows/subject=%.2f (min %d, max %d)\n', ...
        mean(covL), mean(r1.cov), mean(miss), min(miss), max(miss));
    res.(tag).covLocal = mean(covL); res.(tag).covDs5 = mean(r1.cov); res.(tag).miss = miss;
end

save(fullfile(d, 'results', 'bias_strata.mat'), 'res', 'base', 'cfg');
fprintf('\n[saved] results/bias_strata.mat\n');
end
