function exp_export_mcu()
% EMB-01（2026-09-21）：为 STM32F103 板级实测导出逐窗观测似然向量。
%
% 用途：先用论文统一配置复现 headline（规则：新增 dump_logL 注入点默认关闭，
%       须复现 5.9584/5.7836 后方可继续），再以 dump_logL=true 导出
%       PPG-DaLiA S1 的逐窗 logL（K×nWin, single）与参考输出 est/es，
%       供裸机固件的保真比对（MCU est == MATLAB est）。
%
% 输出（本目录 results/）：
%   mcu_export.mat      —— logL / est / es_default / es_omitnan / K / nWin / sb / base
%   mcu_export_log.txt  —— diary（headline 复核值 + 导出统计）
%
% 依赖：cache2（只读，不重建）；ds5.m（dump_logL 注入点，默认关闭）
% 边界：本脚本不改动任何论文数值；仅导出数据。
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', 'method_dev'));
outdir = fullfile(here, 'results');
if ~exist(outdir, 'dir'), mkdir(outdir); end
diary(fullfile(outdir, 'mcu_export_log.txt'));

fprintf('=== EMB-01 export start %s ===\n', datestr(now)); %#ok<TNOW1,DATST>
base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig');

% ---- 1) headline 复现（默认关闭注入点后的回归门槛）----
r1 = ds5('dalia', 1:15, base);
fprintf('[headline] dalia mean = %.4f (expect 5.9584)\n', r1.mean);
r2 = ds5('wesad', 1:15, base);
fprintf('[headline] wesad mean = %.4f (expect 5.7836)\n', r2.mean);

% ---- 2) 导出 DaLiA S1 逐窗似然（dump_logL=true）----
o = base;
o.dump_logL = true;
r = ds5('dalia', 1, o);
logL = r.logL{1};          % K×nWin single
est = r.est{1};            % 1×nWin double（fixed-lag 输出，前 D-1 个为 NaN）
K = size(logL, 1);
nWin = size(logL, 2);
sb = base.f_lo:base.f_hi;

% 参考平滑输出：默认调用（与 ds5 内部一致）与 omitnan 变体各存一份，供比对消歧
es_default = movmedian(est, 3);
es_omitnan = movmedian(est, 3, 'omitnan');
fprintf('[export] K=%d nWin=%d  est(NaN)=%d\n', K, nWin, sum(isnan(est)));

save(fullfile(outdir, 'mcu_export.mat'), ...
    'logL', 'est', 'es_default', 'es_omitnan', 'K', 'nWin', 'sb', 'base', '-v7.3');

% ---- 3) 二进制/文本导出（供 SWD 加载与逐窗比对）----
fw = fopen(fullfile(outdir, 'mcu_logL_s1.bin'), 'wb');
fwrite(fw, logL, 'single');    % MATLAB 列优先：每窗（每列）K 个 float32 连续
fclose(fw);
fw = fopen(fullfile(outdir, 'mcu_ref_est_s1.txt'), 'w');
fprintf(fw, '%.17g\n', est);   % NaN 会打印为 NaN
fclose(fw);
fprintf('[export] bin=%.1f KB, ref_est=%d lines\n', numel(logL) * 4 / 1024, nWin);
fprintf('=== EMB-01 export done ===\n');
diary off;
end
