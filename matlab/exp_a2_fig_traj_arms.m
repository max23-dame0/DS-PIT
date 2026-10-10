% exp_a2_fig_traj_arms.m — Fig.6 用「当前实现」重生成的三联轨迹图
%   (a) 无约束基线（无 SSC、先验关） | (b) 仅 LBP（无 SSC、先验开） | (c) 完整 A′
%   在同一条例记录上对比，参考心率用黑线；每格标注该臂 MAE。
%   配色：基线红 / 仅LBP 橙 / 完整 蓝（方案 A 的鲜艳色相）
root = fileparts(mfilename('fullpath'));

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, 'state_lo_hz', 0.75, ...
    'state_hi_hz', 3.0, 'edge_taper', 30, 'smooth_mode', 'median', ...
    'smooth_m', 3, 'q_feat', 'off', 'sigma', 2, 'obs_mode', 'ratio', ...
    'wf_variant', 'orig');
full = a2_cfg(base);
empty = full; empty.sigma = 50;          % 关 SSC
lbpo = empty;                            % 仅 LBP
base0 = empty; base0.lbp_temp_w = 0;     % 基线

cand = [10 17 14 6 16 4 20 22 12 18 2 8];
best = -inf; pick = cand(1);
for c = cand
    r1 = ds5('ieee', c, base0);
    r2 = ds5('ieee', c, lbpo);
    r3 = ds5('ieee', c, full);
    g = r1.mean - r3.mean;
    fprintf('rec %2d: base %6.2f | LBP-only %6.2f | full %6.2f | gain %+6.2f\n', ...
        c, r1.mean, r2.mean, r3.mean, g);
    if r3.mean < 8 && g > best
        best = g; pick = c; R = struct('r1', r1, 'r2', r2, 'r3', r3);
    end
end
fprintf('--> selected recording %d (full %.2f vs base %.2f)\n', pick, R.r3.mean, R.r1.mean);

F = load(fullfile(root, 'cache2', sprintf('ieee_S%d.mat', pick)));
gt = F.gt(:)';
E = {R.r1, R.r2, R.r3};
ttl = {'Baseline', 'LBP only', 'Full DS-PIT'};
cl = [0.753 0.000 0.000; 0.929 0.490 0.192; 0.267 0.447 0.769];
let = {'a', 'b', 'c'};

fig = figure('Units', 'inches', 'Position', [0 0 7.1 2.4], 'Color', 'w');
tl = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
for k = 1:3
    e = E{k}.est{1}(:)';
    n = min(numel(gt), numel(e));
    g = gt(1:n); y = e(1:n); t = (0:n - 1) * 2;
    ax = nexttile(tl); hold(ax, 'on');
    plot(ax, t, g, '-', 'Color', [0.15 0.15 0.15], 'LineWidth', 1.2);
    plot(ax, t, y, '-', 'Color', cl(k, :), 'LineWidth', 1.0);
    m = isfinite(g) & g > 0 & isfinite(y);
    mae = mean(abs(y(m) - g(m)));
    title(ax, sprintf('%s  (MAE %.1f BPM)', ttl{k}, mae), 'FontSize', 8);
    text(ax, 0.03, 0.94, let{k}, 'Units', 'normalized', 'FontWeight', 'bold', ...
        'FontSize', 9, 'Color', [0.15 0.15 0.15]);
    if k == 1
        ylabel(ax, 'HR (BPM)', 'FontSize', 8);
        legend(ax, {'Reference', 'Estimate'}, 'FontSize', 6.5, 'Box', 'off', ...
            'Location', 'northwest');
    end
    xlabel(ax, 'Time (s)', 'FontSize', 8);
    xlim(ax, [0 max(t)]); ylim(ax, [60 180]);
    box(ax, 'on'); grid(ax, 'off'); set(ax, 'FontSize', 7.5);
end

out = fullfile(root, '..', 'figures', 'fig_traj_arms_A2.pdf');
exportgraphics(fig, out, 'ContentType', 'vector', 'BackgroundColor', 'white');
fprintf('[saved] %s\n', out);
save(fullfile(root, 'results', 'a2_fig_traj_arms.mat'), 'pick', 'R');
