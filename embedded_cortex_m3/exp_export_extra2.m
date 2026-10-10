function exp_export_extra2()
% EMB-01b（2026-09-21）：额外记录导出第二批（DaLiA S3、WESAD S2）。
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', 'method_dev'));
outdir = fullfile(here, 'results');
diary(fullfile(outdir, 'mcu_export_extra2_log.txt'));
fprintf('=== EMB-01 extra2 export start %s ===\n', datestr(now)); %#ok<TNOW1,DATST>
base = struct('f_lo', 40, 'f_hi', 200, 'D', 3, ...
    'state_lo_hz', 0.75, 'state_hi_hz', 3.0, 'edge_taper', 30, ...
    'smooth_mode', 'median', 'smooth_m', 3, ...
    'q_feat', 'off', 'sigma', 2, ...
    'obs_mode', 'ratio', 'wf_variant', 'orig', 'dump_logL', true);
targets = {'dalia', 3, 's3'; 'wesad', 2, 'ws2'};
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
fprintf('=== EMB-01 extra2 export done ===\n');
diary off;
end
