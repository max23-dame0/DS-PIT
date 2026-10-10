function exp_a2_bandtaper()
% A′ 补充复算：证据带下沿 × 边缘斜坡 2×2（评估配置 = C1）
% 口径：state 带固定 0.75–3.0 Hz（不随 arms 改变），arms = {band_lo 0.75（宽）/1.0（窄）} ×
%   {edge_taper 30 / 0}；用于改写 §II-A 的"两改动互补、单独均无效"叙述。
% 输出：results/a2_bandtaper.mat + diary 日志 results/a2_bandtaper_log.txt
addpath(fileparts(mfilename('fullpath')));
d = fileparts(mfilename('fullpath'));

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, 'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');
base = a2_cfg(base);

arms = { ...
    'wide  (0.75-3.0) + taper 30', struct(); ...
    'wide  (0.75-3.0) + taper 0',  struct('edge_taper', 0); ...
    'narrow(1.0-3.0) + taper 30',  struct('state_lo_hz', 1.0); ...
    'narrow(1.0-3.0) + taper 0',   struct('state_lo_hz', 1.0, 'edge_taper', 0)};

res = struct();
for ds = {'dalia', 'wesad'}
    tag = ds{1};
    fprintf('\n######## %s ########\n', upper(tag));
    names = {}; means = [];
    for i = 1:size(arms, 1)
        o = base; f = fieldnames(arms{i, 2});
        for k = 1:numel(f), o.(f{k}) = arms{i, 2}.(f{k}); end
        % 窄带 arm：仅切证据带下沿（observation 的 band 由 f_lo 控制，40–200 BPM 之外
        % 无法直接表达 60 BPM；用 f_lo=60 表示窄带下沿）
        if isfield(o, 'eb_lo_hz'), o.f_lo = o.eb_lo_hz; o = rmfield(o, 'eb_lo_hz'); end
        r = ds5(tag, 1:15, o);
        names{end + 1} = arms{i, 1};                 %#ok<AGROW>
        means(end + 1) = r.mean;                      %#ok<AGROW>
        fprintf('  %-30s MAE=%.4f  SD=%.4f\n', arms{i, 1}, r.mean, r.sd);
    end
    res.(tag) = struct('names', {names}, 'means', means);
end
save(fullfile(d, 'results', 'a2_bandtaper.mat'), 'res', 'arms');
fprintf('\n[saved] results/a2_bandtaper.mat\n');
end
