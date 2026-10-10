% exp_a2_fig_boxplot.m — 消融箱线图（评估配置的四臂 2x2）
%   四臂 = {宏观LBP模块关/开} x {无微观SSC(sigma=50)/微观SSC(sigma=2)}
%   Baseline / +SSC / +LBP / Full，三库（IEEE 23 条标准协议、DaLiA 15 受试、WESAD 15 受试）
%   注：论文最终导出的矢量箱线图由 figures/fig_boxplot_A2.tex (PGFPlots) 编译生成。
root = fileparts(mfilename('fullpath'));
mdir = fullfile(root, 'results');

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, 'state_lo_hz', 0.75, ...
    'state_hi_hz', 3.0, 'edge_taper', 30, 'smooth_mode', 'median', ...
    'smooth_m', 3, 'q_feat', 'off', 'sigma', 2, 'obs_mode', 'ratio', ...
    'wf_variant', 'orig');
cfg = a2_cfg(base);
armF = {'Baseline', 'Baseline + SSC', 'Baseline + LBP', 'DS-PIT (Full)'};
mk = @(sig, lbp_on) setfield(setfield(setfield(setfield(cfg, ...
    'sigma', sig), ...
    'state_lo_hz', 1.00 - 0.25 * lbp_on), ...
    'edge_taper', 30 * lbp_on), ...
    'lbp_temp_w', lbp_on);
arms = {mk(50, 0), mk(2, 0), mk(50, 1), mk(2, 1)};

dss = {'ieee', 'dalia', 'wesad'};
nU  = [23 15 15];
tag = {'IEEE SPC', 'PPG-DaLiA', 'WESAD'};
E = cell(3, 4); Msum = zeros(3, 4);
for d = 1:3
    for a = 1:4
        r = ds5(dss{d}, 1:nU(d), arms{a});
        E{d, a} = r.mae(:)';
        Msum(d, a) = r.mean;
        fprintf('%-10s %-14s MAE=%7.4f  n=%d\n', tag{d}, armF{a}, r.mean, numel(r.mae));
    end
end

% ---- 手绘箱线图 ----
% 消融编码：单一主色（#0F4D92）+ 递增 alpha（skill: ablation alpha encoding）
% Baseline < +SSC < +LBP < Full，越完整越深；alpha 0.25/0.50/0.72/1.00 合成到白底
blue = [0.235 0.388 0.627];   % #3C63A0（与 Fig.2/4 同一蓝）
tint = [0.914 0.933 0.973];   % #E9EEF8（Fig.4 的浅蓝框底色）
mx   = [0.00 0.25 0.50 0.75]'; % Baseline 最浅 -> Full 最深（提出方法最显著）
cl = mx * blue + (1 - mx) * tint;
% 方案 A（2026-09-22）：默认用"原稿风格"的鲜艳四色（蓝/橙/绿/红，色相分明）；
% PALETTE_MODE=paper 可回退到低饱和单色族（输出 _paper 后缀，对比用）。
mode = getenv('PALETTE_MODE'); if isempty(mode), mode = 'vivid'; end
sfx = '';
if strcmp(mode, 'paper')
    sfx = '_paper';
    cl = mx * blue + (1 - mx) * tint;   % 低饱和备选
else
    % 色号契约（2026-09-22）：蓝=我们的方法；红=真值/参考（故基线不再用红）
    cl = [1.000 0.753 0.000;    % Baseline #FFC000 橙黄
          0.000 0.690 0.314;    % +SSC     #00B050 绿
          1.000 0.498 0.000;    % +LBP     #FF7F00 橙
          0.000 0.000 1.000];   % Full     #0000FF 纯蓝（我们的方法）
end
fig = figure('Units', 'inches', 'Position', [0 0 7.0 2.75], 'Color', 'w');
ax = axes(fig); hold(ax, 'on');
bw = 0.17; off = [-0.30 -0.10 0.10 0.30];
for d = 1:3
    for a = 1:4
        v = E{d, a}(isfinite(E{d, a}));
        q = prctile(v, [25 50 75]); iqr_ = q(3) - q(1);
        lo = min(v(v >= q(1) - 1.5 * iqr_)); hi = max(v(v <= q(3) + 1.5 * iqr_));
        xc = d + off(a);
        rectangle(ax, 'Position', [xc - bw/2, q(1), bw, iqr_], ...
            'FaceColor', cl(a, :), 'EdgeColor', cl(a, :) * 0.7, 'LineWidth', 0.5);
        plot(ax, [xc - bw/2, xc + bw/2], [q(2) q(2)], '-', 'Color', cl(a, :) * 0.55, 'LineWidth', 1);
        plot(ax, [xc xc], [q(3) hi], '-', 'Color', cl(a, :) * 0.7, 'LineWidth', 0.6);
        plot(ax, [xc xc], [lo q(1)], '-', 'Color', cl(a, :) * 0.7, 'LineWidth', 0.6);
        plot(ax, [xc - bw/2, xc + bw/2], [hi hi], '-', 'Color', cl(a, :) * 0.7, 'LineWidth', 0.6);
        plot(ax, [xc - bw/2, xc + bw/2], [lo lo], '-', 'Color', cl(a, :) * 0.7, 'LineWidth', 0.6);
        outl = v(v > q(3) + 1.5 * iqr_ | v < q(1) - 1.5 * iqr_);
        if ~isempty(outl)
            plot(ax, xc * ones(size(outl)), outl, 'o', 'MarkerSize', 2.2, ...
                'MarkerEdgeColor', cl(a, :) * 0.8, 'LineWidth', 0.4);
        end
    end
end
for d = 2:3
    plot(ax, [d - 0.5, d - 0.5], [0 55], '-', 'Color', [0.15 0.15 0.15], 'LineWidth', 1.0);
end
set(ax, 'XTick', 1:3, 'XTickLabel', tag, 'YTick', 0:10:50, 'FontSize', 8, 'YLim', [0 53], 'XLim', [0.45 3.55]);
ylabel(ax, 'HR Error (BPM)', 'FontSize', 8);
h = gobjects(1, 4);
for a = 1:4, h(a) = patch(ax, 'XData', nan, 'YData', nan, 'FaceColor', cl(a, :), 'EdgeColor', cl(a, :) * 0.7); end
legend(ax, h, armF, 'FontSize', 7, 'Box', 'on', 'Location', 'northeast');
box(ax, 'on'); set(ax, 'YGrid', 'on', 'XGrid', 'off', 'GridLineStyle', '--', 'GridAlpha', 0.35);

out = fullfile(root, '..', 'figures', ['fig_boxplot_A2' sfx '.pdf']);
exportgraphics(fig, out, 'ContentType', 'vector', 'BackgroundColor', 'white');
% 注：exportgraphics 紧裁剪会让最外缘刻度文字贴边（碰撞审计判为 text-page-clipping）。
% 统一由 fix_pdf_margin.py 在导出后加 4 pt 白边，见 revision/audit/method_dev/fix_pdf_margin.py
fprintf('[saved] %s\n', out);
for d = 1:3
    fprintf('%s: %s -> %s\n', tag{d}, strjoin(armF, ' | '), mat2str(round(Msum(d, :), 3)));
end
save(fullfile(mdir, 'a2_fig_boxplot.mat'), 'E', 'Msum', 'armF', 'tag');
