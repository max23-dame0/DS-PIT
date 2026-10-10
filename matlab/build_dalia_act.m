function build_dalia_act()
% 重建 DaLiA 的逐窗活动标签（修复 prep_dump2.m:64 把 act 硬编码为 1 的问题）
% 数据源：PPG_FieldStudy/S*/*_activity.csv，格式为 "# ACTIVITY, start_second"（起始时刻以秒计）
% 映射（对齐 CurToSS Table II 的 9 类）：1 Sitting 2 Stairs 3 Soccer 4 Cycling
%   5 Driving 6 Lunch 7 Walking 8 Working 9 Transition/其它
% 窗定义：BPM0 为 0.5 Hz，第 k 个窗对应第 k 个 2 s 步，即秒区间 [(k-1)*2, k*2)
root = fileparts(mfilename('fullpath'));
src = 'D:\小论文\实验代码\PPG-master\PPG_FieldStudy';
map = struct('BASELINE', 1, 'STAIRS', 2, 'SOCCER', 3, 'CYCLING', 4, 'DRIVING', 5, ...
    'LUNCH', 6, 'WALKING', 7, 'WORKING', 8, 'NO_ACTIVITY', 9);
A = cell(1, 15);
for s = 1:15
    f = fullfile(src, sprintf('S%d', s), sprintf('S%d_activity.csv', s));
    if ~exist(f, 'file'), fprintf('  S%d: activity file missing\n', s); continue; end
    txt = fileread(f);
    lines = regexp(txt, '\r?\n', 'split');
    seg = []; nam = {};
    for i = 1:numel(lines)
        L = strtrim(lines{i});
        if isempty(L) || ~startsWith(L, '#'), continue; end
        p = strsplit(strtrim(L(2:end)), ',');
        if numel(p) < 2, continue; end
        nm = strtrim(upper(p{1})); t0 = str2double(strtrim(p{2}));
        if isnan(t0), continue; end
        seg(end + 1) = t0; nam{end + 1} = nm; %#ok<AGROW>
    end
    if isempty(seg), fprintf('  S%d: no activity records\n', s); continue; end
    % 逐秒标签
    totalS = seg(end) + 600;                       % 末段补齐
    lab = 9 * ones(1, totalS);                     % 默认 Transition
    for i = 1:numel(seg)
        t1 = seg(i) + 1;
        t2 = totalS; if i < numel(seg), t2 = seg(i + 1); end
        if t1 > totalS, continue; end
        v = 9; if isfield(map, nam{i}), v = map.(nam{i}); end
        lab(max(1, t1):min(totalS, t2)) = v;
    end
    % BPM0 长度决定窗数
    G = load(sprintf('X:\\PPG-dalia\\BPM_data\\S%d_BPMtrace.mat', s));
    nWin = numel(G.BPM0);
    a = nan(1, nWin);
    for k = 1:nWin
        i0 = (k - 1) * 2 + 1; i1 = min(totalS, k * 2);
        if i0 > totalS, break; end
        a(k) = mode(lab(i0:i1));
    end
    A{s} = a;
    u = unique(a(~isnan(a)));
    fprintf('  S%d: nWin=%d  acts=%s  counts=%s\n', s, nWin, mat2str(u), ...
        mat2str(arrayfun(@(x) sum(a == x), u)));
end
save(fullfile(root, 'results', 'dalia_activity.mat'), 'A');
fprintf('[saved] results/dalia_activity.mat\n');
end
