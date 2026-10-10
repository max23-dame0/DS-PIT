% exp_a2_fig_sens.m — 敏感性图（评估配置）重绘（v2，按 nature-figure 审计修正）
%   (a) SSC 带宽 sigma 消融（两库，带跨受试者 SEM 误差棒）
%   (b) 解码延迟 D：MAE 随解码前瞻时间（两库，带 ±SEM 阴影带）
% 数据直接取自 results/a2_tables.mat（不重算）；原 N_hist 面板无评估配置对应数据，已移出。
% v2 修正：关网格（网格线穿字）、共享图例外置、补不确定度、导出后由
%         fix_pdf_margin.py 加白边（消除 text-page-clipping）。
root = fileparts(mfilename('fullpath'));
S = load(fullfile(root, 'results', 'a2_tables.mat'));
ds = {'dalia', 'wesad'};
nm = {'PPG-DaLiA', 'WESAD'};
% 与 Fig.4 同族：蓝 #3C63A0（PPG-DaLiA）+ 暖赭 #A9762F（WESAD）
cl = [0.235 0.388 0.627; 0.663 0.463 0.184];
% 方案 A：默认鲜艳两色（MATLAB 默认蓝/橙）；PALETTE_MODE=paper 回退低饱和
mode = getenv('PALETTE_MODE'); if isempty(mode), mode = 'vivid'; end
sfx = '';
if strcmp(mode, 'paper')
    sfx = '_paper';
    cl = [0.235 0.388 0.627; 0.663 0.463 0.184];
else
    % 色号契约：#0000FF = 我们的方法（PPG-DaLiA）；#00B0F0 = 第二个数据集（WESAD）
    % 2026-09-23 作者决定：数据集改用青色，避免与 Fig.5 的"基线=橙黄"撞色
    cl = [0.000 0.000 1.000; 0.000 0.690 0.941];
end

sig_nm = {'2 (used)', '3', '4', '5', 'adapt [2,5]'};
Ms = zeros(2, 5); Es = zeros(2, 5);
Ml = zeros(2, 7); El = zeros(2, 7); W = [];
for i = 1:2
    Ms(i, :) = S.res.(ds{i}).sigma.means(1:5);
    Es(i, :) = std(S.res.(ds{i}).sigma.perSubject(:, 1:5), 0, 1, 'omitnan') / sqrt(15);
    Ml(i, :) = S.res.(ds{i}).latency.mae;
    % latency.perSubject 为扁平向量（D-major：7 段 × 15 受试）→ reshape 成 受试×D
    P = reshape(S.res.(ds{i}).latency.perSubject, 15, 7);
    El(i, :) = std(P, 0, 1, 'omitnan') / sqrt(15);
    W = S.res.(ds{i}).latency.wait;
end

fig = figure('Units', 'inches', 'Position', [0 0 3.5 4.4], 'Color', 'w');
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% ---- (a) sigma ablation（柱 + SEM 误差棒）--------------------------------
ax1 = nexttile(tl); hold(ax1, 'on');
b = bar(ax1, Ms', 0.78, 'grouped');
b(1).FaceColor = cl(1, :); b(2).FaceColor = cl(2, :);
b(1).EdgeColor = 'none'; b(2).EdgeColor = 'none';
for j = 1:2
    errorbar(ax1, b(j).XEndPoints, Ms(j, :), Es(j, :), 'k', ...
        'LineStyle', 'none', 'LineWidth', 0.6, 'CapSize', 2);
end
% 只在"在用档"上方给一组数值：逐柱标注在窄窗口下会互相重叠并被误差棒穿过
% （碰撞审计 FAIL）。其余档位数值见正文与 Table。
text(ax1, 1, max(Ms(:, 1) + Es(:, 1)) + 0.10, ...
    sprintf('%.2f / %.2f', Ms(1, 1), Ms(2, 1)), ...
    'HorizontalAlignment', 'center', 'FontSize', 6.2, 'Color', [0.2 0.2 0.2]);
set(ax1, 'XTick', 1:5, 'XTickLabel', sig_nm, 'FontSize', 7.5);
% 完整显示均值±SEM；误差棒不用于推断配对臂差异。
ylimits = [floor(min(Ms(:)-Es(:))*2)/2, ceil((max(Ms(:)+Es(:))+0.2)*2)/2];
assert(all(Ms(:)-Es(:) >= ylimits(1)) && all(Ms(:)+Es(:) <= ylimits(2)));
ylim(ax1, ylimits); ylabel(ax1, 'Subject-macro MAE (BPM)', 'FontSize', 8);
xlabel(ax1, '$\sigma_{SSC}$ (BPM)', 'Interpreter', 'latex', 'FontSize', 8);
title(ax1, '(a) Transition bandwidth', 'FontSize', 8);
box(ax1, 'on'); set(ax1, 'YGrid', 'on', 'XGrid', 'off', 'GridLineStyle', '--', 'GridAlpha', 0.3);

% ---- (b) latency（折线 + ±SEM 阴影带）-----------------------------------
ax2 = nexttile(tl); hold(ax2, 'on');
for i = 1:2
    xf = [W, fliplr(W)];
    yf = [Ml(i, :) + El(i, :), fliplr(Ml(i, :) - El(i, :))];
    fill(ax2, xf, yf, cl(i, :), 'FaceAlpha', 0.18, 'EdgeColor', 'none');
end
for i = 1:2
    plot(ax2, W, Ml(i, :), '-o', 'Color', cl(i, :), 'LineWidth', 1.2, ...
        'MarkerSize', 3.4, 'MarkerFaceColor', 'w');
end
plot(ax2, W(3), Ml(1, 3), 'o', 'Color', cl(1, :), 'MarkerSize', 5.4, 'LineWidth', 1.2);
plot(ax2, W(3), Ml(2, 3), 'o', 'Color', cl(2, :), 'MarkerSize', 5.4, 'LineWidth', 1.2);
text(ax2, W(3) + 0.8, Ml(1, 3) + 0.08, 'D = 3 (4 s)', 'FontSize', 6.5, 'Color', cl(1, :));
xlabel(ax2, 'Decoder look-ahead (D-1)\times2 (s)', 'FontSize', 8);
ylabel(ax2, 'Subject-macro MAE (BPM)', 'FontSize', 8);
title(ax2, '(b) Decoding delay', 'FontSize', 8);
set(ax2, 'FontSize', 7.5); box(ax2, 'on'); set(ax2, 'YGrid', 'on', 'XGrid', 'on', 'GridLineStyle', '--', 'GridAlpha', 0.3);

% ---- 共享图例（外置一行，skill: prefer one shared legend strip）---------
lg = legend(ax1, b, nm, 'FontSize', 6.5, 'Box', 'off', 'Orientation', 'horizontal');
lg.Layout.Tile = 'north';

out = fullfile(root, '..', 'figures', ['fig_sens_A2' sfx '.pdf']);
exportgraphics(fig, out, 'ContentType', 'vector', 'BackgroundColor', 'white');
fprintf('[saved] %s\n', out);
fprintf('sigma DaLiA: %s\n', mat2str(round(Ms(1, :), 3)));
fprintf('sigma WESAD: %s\n', mat2str(round(Ms(2, :), 3)));
fprintf('latency DaLiA: %s\n', mat2str(round(Ml(1, :), 3)));
fprintf('latency WESAD: %s\n', mat2str(round(Ml(2, :), 3)));

fprintf('sigma SEM bounds: %.6f .. %.6f; ylim: %s\n', min(Ms(:)-Es(:)), max(Ms(:)+Es(:)), mat2str(ylimits));
