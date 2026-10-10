function exp_a2_tables()
% A′ 表格类指标复算（评估配置 = C1）
%
% 内容（口径复刻自 exp_paper_v3 §3 / exp_sigma_ablation / exp_fe_unified /
%   exp_acc_mae / exp_bias_strata / exp_gate_unified）：
%   1. 带宽消融 + 配对检验（σ=3/4/5、自适应；含 D=15 对照，Holm 家族=5）
%   2. 延迟表（D=1,2,3,4,6,10,15）
%   3. 前端消融（Full / −WF2 / −WF1 / −both）
%   4. ACC 参考 MAE 级对照（sum / x / y / z / pc1）
%   5. bias 机制 2×2（taper × 输出滤波）
%   6. 门控复测（soft N15 / hard keep N15；用于 §II-C 的"被否定形态"叙述）
% 输出：results/a2_tables.mat + diary 日志 results/a2_tables_log.txt

addpath(fileparts(mfilename('fullpath')));
mdir = fileparts(mfilename('fullpath'));
rng(20260918);

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');
b2 = a2_cfg(base);
res = struct();

for ds = {'dalia', 'wesad'}
    tag = ds{1};
    fprintf('\n######## %s ########\n', upper(tag));
    S = struct();

    % ---- 1) 带宽消融 + 配对（家族=5：4 带宽 + D=15）----
    r0 = ds5(tag, 1:15, b2);
    fprintf('[1] sigma ablation + paired (base MAE=%.4f)\n', r0.mean);
    sig = { ...
        'selected 2',        struct(); ...
        'fixed 3',           struct('sigma', 3); ...
        'fixed 4',           struct('sigma', 4); ...
        'fixed 5',           struct('sigma', 5); ...
        'adaptive [2,5]',    struct('q_feat', 'kurt', 'sigma_lo', 2, 'sigma_hi', 5, 'q_dir', 'norm')};
    nm = {'selected 2'}; mn = r0.mean; PS = r0.mae(:);
    for i = 2:size(sig, 1)
        o = b2; f = fieldnames(sig{i, 2});
        for k = 1:numel(f), o.(f{k}) = sig{i, 2}.(f{k}); end
        r = ds5(tag, 1:15, o);
        nm{end + 1} = sig{i, 1}; mn(end + 1) = r.mean; PS(:, end + 1) = r.mae(:);   %#ok<AGROW>
        fprintf('    %-16s MAE=%.4f\n', sig{i, 1}, r.mean);
    end
    o = b2; o.D = 15; rd = ds5(tag, 1:15, o);
    nm{end + 1} = 'D=15'; mn(end + 1) = rd.mean; PS(:, end + 1) = rd.mae(:);
    fprintf('    %-16s MAE=%.4f\n', 'D=15', rd.mean);
    nC = numel(nm) - 1; dm = nan(1, nC); pv = nan(1, nC);
    for j = 1:nC
        dif = PS(:, 1) - PS(:, j + 1);   % selected - alternative（负 = 选中的更好）
        dm(j) = mean(dif); pv(j) = signflip(dif, 10000);
    end
    [sp, ord] = sort(pv); m = numel(sp);
    adj = min(1, sp(:) .* ((m:-1:1)'));
    for k = 2:m, adj(k) = max(adj(k), adj(k - 1)); end
    ph = nan(1, nC); ph(ord) = adj;
    for j = 1:nC
        fprintf('    %-16s delta=%+.4f  raw p=%.4f  Holm=%.4f\n', nm{j + 1}, dm(j), pv(j), ph(j));
    end
    S.sigma = struct('names', {nm}, 'means', mn, 'perSubject', PS, 'delta', dm, 'p', pv, 'pHolm', ph);

    % ---- 2) 延迟表 ----
    fprintf('[2] latency sweep\n');
    Dl = [1 2 3 4 6 10 15]; lat = nan(1, numel(Dl)); latPS = nan(15, numel(Dl));
    for i = 1:numel(Dl)
        if Dl(i) == 3, r = r0; else, o = b2; o.D = Dl(i); r = ds5(tag, 1:15, o); end
        lat(i) = r.mean; latPS(:, i) = r.mae(:);
        fprintf('    D=%2d wait=%2ds MAE=%.4f\n', Dl(i), 2 * (Dl(i) - 1), r.mean);
    end
    S.latency = struct('D', Dl, 'wait', 2 * (Dl - 1), 'mae', lat, 'perSubject', latPS);

    % ---- 3) 前端消融 ----
    fprintf('[3] front-end ablation\n');
    fe = {'Full (WF1+WF2)', struct(); '- second Wiener', struct('obs_mode', 'wf1'); ...
          '- first Wiener', struct('obs_mode', 'wf2'); '- both', struct('obs_mode', 'raw')};
    nm = {}; mn = []; PS = [];
    for i = 1:size(fe, 1)
        o = b2; f = fieldnames(fe{i, 2});
        for k = 1:numel(f), o.(f{k}) = fe{i, 2}.(f{k}); end
        if i == 1, r = r0; else, r = ds5(tag, 1:15, o); end
        nm{end + 1} = fe{i, 1}; mn(end + 1) = r.mean; PS(:, end + 1) = r.mae(:);   %#ok<AGROW>
        fprintf('    %-20s MAE=%.4f\n', fe{i, 1}, r.mean);
    end
    dm = nan(1, 3); pv = nan(1, 3);
    for j = 1:3
        dif = PS(:, 1) - PS(:, j + 1);
        dm(j) = mean(dif); pv(j) = signflip(dif, 10000);
        fprintf('    full - %-14s delta=%+.4f  p=%.4f\n', nm{j + 1}, dm(j), pv(j));
    end
    S.fe = struct('names', {nm}, 'means', mn, 'perSubject', PS, 'delta', dm, 'p', pv);

    % ---- 4) ACC 参考 ----
    fprintf('[4] acc reference\n');
    ac = {'sum (evaluated)', struct(); 'x only', struct('acc_axes', 'x'); ...
          'y only', struct('acc_axes', 'y'); 'z only', struct('acc_axes', 'z'); ...
          'pc1', struct('acc_axes', 'pc1')};
    nm = {}; mn = []; PS = [];
    for i = 1:size(ac, 1)
        o = b2; f = fieldnames(ac{i, 2});
        for k = 1:numel(f), o.(f{k}) = ac{i, 2}.(f{k}); end
        if i == 1, r = r0; else, r = ds5(tag, 1:15, o); end
        nm{end + 1} = ac{i, 1}; mn(end + 1) = r.mean; PS(:, end + 1) = r.mae(:);   %#ok<AGROW>
        fprintf('    %-18s MAE=%.4f  delta=%+.4f\n', ac{i, 1}, r.mean, r.mean - r0.mean);
    end
    dm = nan(1, 4); pv = nan(1, 4);
    for j = 1:4
        dif = PS(:, j + 1) - PS(:, 1);
        dm(j) = mean(dif); pv(j) = signflip(dif, 10000);
    end
    S.acc = struct('names', {nm}, 'means', mn, 'perSubject', PS, 'delta', dm, 'p', pv);

    % ---- 5) bias 2×2 ----
    fprintf('[5] bias mechanism 2x2\n');
    bs = {'taper on, filter on', struct(); 'taper off, filter on', struct('edge_taper', 0); ...
          'taper on, filter off', struct('smooth_m', 1); 'taper off, filter off', struct('edge_taper', 0, 'smooth_m', 1)};
    nm = {}; mn = []; bi = []; rm = [];
    for i = 1:size(bs, 1)
        o = b2; f = fieldnames(bs{i, 2});
        for k = 1:numel(f), o.(f{k}) = bs{i, 2}.(f{k}); end
        if i == 1, r = r0; else, r = ds5(tag, 1:15, o); end
        E = cell2mat(cellfun(@(c) c(:).', r.err, 'uni', 0)); es = -E;
        nm{end + 1} = bs{i, 1}; mn(end + 1) = r.mean; bi(end + 1) = mean(es);   %#ok<AGROW>
        rm(end + 1) = sqrt(mean(es.^2));                                         %#ok<AGROW>
        fprintf('    %-22s MAE=%.4f  bias=%+.4f  RMSE=%.4f\n', bs{i, 1}, r.mean, mean(es), sqrt(mean(es.^2)));
    end
    S.bias = struct('names', {nm}, 'means', mn, 'bias', bi, 'rmse', rm);

    % ---- 6) 门控复测（被否定形态）----
    fprintf('[6] gate re-test under A'' base\n');
    g = {'soft N15', struct('lbp_gate', 'soft'); 'hard keep N15', struct('lbp_gate', 'hard'); ...
         'hard append N15', struct('lbp_gate', 'hard', 'lbp_buf_mode', 'append')};
    nm = {}; mn = []; PS = [];
    for i = 1:size(g, 1)
        o = b2; f = fieldnames(g{i, 2});
        for k = 1:numel(f), o.(f{k}) = g{i, 2}.(f{k}); end
        r = ds5(tag, 1:15, o);
        nm{end + 1} = g{i, 1}; mn(end + 1) = r.mean; PS(:, end + 1) = r.mae(:);   %#ok<AGROW>
        fprintf('    %-18s MAE=%.4f  delta=%+.4f\n', g{i, 1}, r.mean, r.mean - r0.mean);
    end
    dm = nan(1, 3); pv = nan(1, 3);
    for j = 1:3
        dif = PS(:, j) - r0.mae(:);
        dm(j) = mean(dif); pv(j) = signflip(dif, 10000);
    end
    S.gate = struct('names', {nm}, 'means', mn, 'perSubject', PS, 'delta', dm, 'p', pv, 'base', r0.mean);

    res.(tag) = S;
end

save(fullfile(mdir, 'results', 'a2_tables.mat'), 'res', 'base', 'b2', '-v7.3');
fprintf('\n[saved] results/a2_tables.mat\n');
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
