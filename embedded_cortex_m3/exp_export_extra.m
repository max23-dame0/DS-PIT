function exp_export_extra()
% EMB-01b（2026-09-21）：为固件交叉验证导出额外记录（DaLiA S2、WESAD S1）。
%
% 说明：dump_logL 注入点已于同日 18:53 通过 headline 复现验证
%       （5.9584 / 5.7836，见 results/mcu_export_log.txt），注入点未改动；
%       本脚本仅以相同注入点导出其他记录，不触碰论文数值。
%
% 输出（results/）：
%   mcu_logL_s2.bin / mcu_ref_est_s2.txt      —— DaLiA S2
%   mcu_logL_ws1.bin / mcu_ref_est_ws1.txt    —— WESAD S1
%   mcu_export_extra_log.txt                  —— diary
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', 'method_dev'));
outdir = fullfile(here, 'results');
diary(fullfile(outdir, 'mcu_export_extra_log.txt'));
fprintf('=== EMB-01 extra export start %s ===\n', datestr(now)); %#ok<TNOW1,DATST>

base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig', 'dump_logL', true);

targets = {'dalia', 2, 's2'; 'wesad', 1, 'ws1'};
for k = 1:size(targets, 1)
    dsname = targets{k, 1}; subj = targets{k, 2}; tag = targets{k, 3};
    r = ds5(dsname, subj, base);
    logL = r.logL{1}; est = r.est{1};
    fw = fopen(fullfile(outdir, sprintf('mcu_logL_%s.bin', tag)), 'wb');
    fwrite(fw, logL, 'single'); fclose(fw);
    fw = fopen(fullfile(outdir, sprintf('mcu_ref_est_%s.txt', tag)), 'w');
    fprintf(fw, '%.17g\n', est); fclose(fw);
    fprintf('[export] %s S%d -> %s : K=%d nWin=%d estNaN=%d\n', ...
        dsname, subj, tag, size(logL, 1), size(logL, 2), sum(isnan(est)));
end
fprintf('=== EMB-01 extra export done ===\n');
diary off;
end
