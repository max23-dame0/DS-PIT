function o = a2_cfg(o)
% A′ 评估配置注入（路线 A 弱成立候选 C1；见 ROUTE_A_BRIEF_20260918.md §13）
%
% C1 = 长时可靠性自适应观测温度（LBP 新形态，评估配置启用）：
%   lbp_vel_L   = 5   （因果趋势 v̂：最近 5 个已发射值的中位增量，钳位 ±2 BPM/窗）
%   lbp_temp_w  = 1   （启用自适应观测温度）
%   lbp_temp_win= 30  （可靠性 EMA 窗；τ = 0.7 + 0.6·EMA ∈ [0.7, 1.3]）
% 若未传入 base 结构体，则自动初始化为论文统一基础配置（Table II）。
if nargin < 1 || isempty(o)
    o = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
        'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
        'smooth_mode', 'median', 'smooth_m', 3, ...
        'q_feat', 'off', 'sigma', 2, ...
        'obs_mode', 'ratio', 'wf_variant', 'orig');
end
o.lbp_vel_L = 5;
o.lbp_temp_w = 1;
o.lbp_temp_win = 30;
end
