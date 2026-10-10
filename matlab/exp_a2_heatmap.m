function exp_a2_heatmap()
% A′ 误差热力图重算（活动 × HR 带；PPG-DaLiA）
%   - 单元格 = 池化窗口 MAE（口径：ds5 发射值 movmedian(3) 平滑后，gt>0 且有限）
%   - 单元格同时标注窗口数 n（旧图缺样本量，本图补齐）
%   - 输出：results/a2_heatmap.mat + results/a2_heatmap_log.txt + 仓库根目录 Error_Heatmap_DSPIT_A2.pdf
%
% 说明：PASS=不写原图 Error_Heatmap_DSPIT.pdf；新文件为独立资产，正文改引用新文件。

addpath(fileparts(mfilename('fullpath')));
mdir = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(mdir)));   % 仓库根（main.tex 所在目录）
cachedir = fullfile(mdir, 'cache2');

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');
o = a2_cfg(base);

DA = load(fullfile(mdir, 'results', 'dalia_activity.mat'));
% 行序与表 VI（tab:activity）一致：按 MAE 升序；列 = 参考 HR 带
nm = {'Working', 'Driving', 'Lunch', 'Sitting', 'Transition', 'Walking', 'Cycling', 'TableSoccer', 'Stairs'};
aid = [8 5 6 1 9 7 4 3 2];   % 与 dalia_activity 标签编号的映射
bandNames = {'<60', '60-80', '80-100', '100-120', '120-140', '>140'};
bands = [-inf 60; 60 80; 80 100; 100 120; 120 140; 140 inf];
nB = size(bands, 1);

r = ds5('dalia', 1:15, o);
fprintf('=== A'' error heatmap (PPG-DaLiA, headline %.4f) ===\n', r.mean);
S = zeros(9, nB); N = zeros(9, nB);
for si = 1:15
    F = load(fullfile(cachedir, sprintf('dalia_S%d.mat', si)));
    gt = F.gt(:)';
    act = DA.A{si}(:).';
    if numel(act) < numel(gt), act(end + 1:numel(gt)) = 9; end
    act = act(1:numel(gt));
    es = movmedian(r.est{si}, o.smooth_m);
    n2 = min([numel(gt), numel(es), numel(act)]);
    g = gt(1:n2); e = es(1:n2); a = act(1:n2);
    msk = isfinite(g) & isfinite(e) & g > 0;
    for k = 1:9
        for b = 1:nB
            m = msk & a == aid(k) & g >= bands(b, 1) & g < bands(b, 2);
            S(k, b) = S(k, b) + sum(abs(e(m) - g(m)));
            N(k, b) = N(k, b) + sum(m);
        end
    end
end
M = S ./ max(N, 1); M(N < 50) = NaN;   % 样本 <50 的单元格不报值

fprintf('%-11s', 'Activity');
for b = 1:nB, fprintf('%14s', bandNames{b}); end
fprintf('\n');
for k = 1:9
    fprintf('%-11s', nm{k});
    for b = 1:nB
        if isnan(M(k, b))
            fprintf('%14s', '--');
        else
            fprintf('%8.2f(%5d)', M(k, b), N(k, b));
        end
    end
    fprintf('\n');
end
tot = sum(S(:)) / sum(N(:));
fprintf('ALL: pooled MAE=%.3f over n=%d windows\n', tot, sum(N(:)));
[mx, imx] = max(M(:));
[kk, bb] = ind2sub(size(M), imx);
fprintf('max cell: %s @ %s BPM = %.2f BPM (n=%d)\n', nm{kk}, bandNames{bb}, mx, N(kk, bb));

% ---- 绘图（单栏纵向版式）----
fig = figure('Units', 'inches', 'Position', [0 0 3.5 3.9], 'Color', 'w');
ax = axes(fig); hold(ax, 'on');
h = imagesc(ax, M, 'AlphaData', ~isnan(M));
set(ax, 'Color', [0.86 0.86 0.86]);
colormap(ax, flipud(hot));
caxis(ax, [0 20]);
cb = colorbar(ax); cb.Label.String = 'MAE (BPM)';
cb.Label.FontSize = 6.5; set(cb, 'FontSize', 6);
set(ax, 'XTick', 1:nB, 'XTickLabel', bandNames, 'YTick', 1:9, 'YTickLabel', nm, ...
    'FontSize', 6.5, 'TickLength', [0 0], 'YDir', 'reverse');
xlabel(ax, 'Reference HR band (BPM)', 'FontSize', 7);
title(ax, 'PPG-DaLiA: MAE by activity and HR band', 'FontSize', 7.5);
for k = 1:9
    for b = 1:nB
        if isnan(M(k, b))
            text(ax, b, k, 'n/a', 'HorizontalAlignment', 'center', 'FontSize', 5.5, 'Color', [0.3 0.3 0.3]);
        else
            text(ax, b, k - 0.18, sprintf('%.1f', M(k, b)), 'HorizontalAlignment', 'center', 'FontSize', 5.8, 'Color', 'k');
            text(ax, b, k + 0.26, sprintf('%d', N(k, b)), 'HorizontalAlignment', 'center', 'FontSize', 4.2, 'Color', [0.2 0.2 0.2]);
        end
    end
end
xlim(ax, [0.5 nB + 0.5]); ylim(ax, [0.5 9.5]);
box(ax, 'on'); set(ax, 'LineWidth', 0.5);
out = fullfile(root, 'Error_Heatmap_DSPIT_A2.pdf');
exportgraphics(fig, out, 'ContentType', 'vector', 'BackgroundColor', 'white');
fprintf('[saved] %s\n', out);

save(fullfile(mdir, 'results', 'a2_heatmap.mat'), 'M', 'N', 'bandNames', 'nm', 'tot');   % 只存矩阵与标签（r 含逐受试估计，体积大且可由 exp_a2_core 复得）
fprintf('[saved] results/a2_heatmap.mat\n');
end
