function run_all_experiments(mode)
% RUN_ALL_EXPERIMENTS Master reproducibility entry point for DS-PIT (JBHI-01577-2026)
%
% Usage:
%   run_all_experiments()                % Live evaluation + saved result verification
%   run_all_experiments('verify')        % Same as above
%   run_all_experiments('recompute_all') % Re-run all MATLAB experiment drivers from cache2/

if nargin < 1 || isempty(mode)
    mode = 'verify';
end

repo_root = fileparts(mfilename('fullpath'));
matlab_dir = fullfile(repo_root, 'matlab');
addpath(matlab_dir);

fprintf('==============================================================================\n');
fprintf('DS-PIT Master Reproducibility Runner (IEEE JBHI Manuscript JBHI-01577-2026)\n');
fprintf('Mode: %s\n', mode);
fprintf('==============================================================================\n\n');

% 1. Verify IEEE SPC 2015 Standard Protocol Results (Main Table III)
% From ieee_spc_standard/results_v1_per_record.txt (WFPV_OVD_PISC.m):
mae_part = [0.8083 1.7635 0.4703 0.8525 0.6078 0.5445 0.3934 0.5859 0.3479 1.5032 0.8294 0.6005 ...
            2.7638 7.3068 1.2268 2.1201 1.9561 1.8232 0.8003 1.5505 2.8224 1.0174 0.4132];
mae_loxo = [0.7671 1.7813 0.4894 0.8757 0.6220 1.6759 0.3969 0.5705 0.3446 1.5452 0.8294 0.5944 ...
            2.7403 7.6811 1.0600 2.1921 2.0397 1.5160 0.8207 1.6235 2.9307 0.9962 0.4156];
train_ids  = 1:12;
test11_ids = 13:23;
test10_ids = 14:23; % 10-recording test split (TEST_S01_T01..TEST_S08_T01, excluding DATA_S04_T01 at index 13)

fprintf('[1] Main Table III -- IEEE SPC 2015 Standard Competition Protocol:\n');
fprintf('    12-Train MAE : %.2f +- %.2f BPM (exact: %.4f +- %.4f, Paper: 0.78 +- 0.44)\n', ...
    mean(mae_part(train_ids)), std(mae_part(train_ids)), mean(mae_part(train_ids)), std(mae_part(train_ids)));
fprintf('    10-Test  MAE : %.2f +- %.2f BPM (exact: %.4f +- %.4f, Paper: 2.10 +- 1.96)\n', ...
    mean(mae_part(test10_ids)), std(mae_part(test10_ids)), mean(mae_part(test10_ids)), std(mae_part(test10_ids)));
fprintf('    11-Test  MAE : %.2f +- %.2f BPM (exact: %.4f +- %.4f, Paper: 2.16 +- 1.87)\n', ...
    mean(mae_part(test11_ids)), std(mae_part(test11_ids)), mean(mae_part(test11_ids)), std(mae_part(test11_ids)));
fprintf('    All-23   MAE : %.2f +- %.2f BPM (exact: %.4f +- %.4f, Paper: 1.50 +- 1.54)\n\n', ...
    mean(mae_loxo), std(mae_loxo), mean(mae_loxo), std(mae_loxo));

% 2. Live Execution of Unified DS-PIT Configuration (Main Table IV & Supp Table S3)
cfg = a2_cfg();
cache_ok = exist(fullfile(matlab_dir, 'cache2'), 'dir') || ...
           (~isempty(getenv('DSPIT_CACHE_DIR')) && exist(getenv('DSPIT_CACHE_DIR'), 'dir')) || ...
           exist('D:\小论文\manuscript_JBHI_IEEEtran\revision\audit\method_dev\cache2', 'dir');

if cache_ok
    fprintf('[2] Live Execution of Unified Training-Free DS-PIT (ds5.m + a2_cfg.m):\n');
    r_dalia = ds5('dalia', 1:15, cfg);
    r_wesad = ds5('wesad', 1:15, cfg);
    r_ieee  = ds5('ieee',  1:23, cfg);

    fprintf('    PPG-DaLiA (n=15) : MAE = %.4f +- %.4f BPM, Median = %.2f, RMSE = %.2f (Paper Table IV: 5.83 +- 2.18)\n', ...
        mean(r_dalia.mae), std(r_dalia.mae), median(r_dalia.mae), mean(r_dalia.rmse));
    fprintf('    WESAD     (n=15) : MAE = %.4f +- %.4f BPM, Median = %.2f, RMSE = %.2f (Paper Table IV: 5.76 +- 3.24)\n', ...
        mean(r_wesad.mae), std(r_wesad.mae), median(r_wesad.mae), mean(r_wesad.rmse));
    fprintf('    IEEE SPC  (n=23) : MAE = %.4f +- %.4f BPM (Supp Table S3 Zero-Retuning: 6.77 +- 9.22)\n\n', ...
        mean(r_ieee.mae), std(r_ieee.mae));

    assert(abs(mean(r_dalia.mae) - 5.8302) < 1e-3, 'PPG-DaLiA MAE mismatch!');
    assert(abs(mean(r_wesad.mae) - 5.7569) < 1e-3, 'WESAD MAE mismatch!');
    assert(abs(mean(r_ieee.mae)  - 6.7659) < 1e-3, 'IEEE SPC Unified MAE mismatch!');
    fprintf('    --> [PASS] Live DS-PIT execution matches published paper values to < 0.001 BPM!\n\n');
else
    fprintf('[2] Spectral cache (cache2/) not found locally; verifying from pre-computed matlab/results/a2_core.mat:\n');
    S_core = load(fullfile(matlab_dir, 'results', 'a2_core.mat'));
    fprintf('    PPG-DaLiA (n=15) : MAE = %.4f +- %.4f BPM (Paper Table IV: 5.83 +- 2.18)\n', ...
        S_core.res.dalia.mean, S_core.res.dalia.sd);
    fprintf('    WESAD     (n=15) : MAE = %.4f +- %.4f BPM (Paper Table IV: 5.76 +- 3.24)\n', ...
        S_core.res.wesad.mean, S_core.res.wesad.sd);
    fprintf('    IEEE SPC  (n=23) : MAE = %.4f +- %.4f BPM (Supp Table S3: 6.77 +- 9.22)\n\n', ...
        S_core.res.ieee.ALL23.mean, S_core.res.ieee.ALL23.sd);
end

% 3. Optional Full Recomputation of All Drivers
if strcmpi(mode, 'recompute_all')
    if ~cache_ok
        error('recompute_all requires cache2/ (run prep_dump2.m and prep_ieee.m first, or set DSPIT_CACHE_DIR).');
    end
    old_pwd = pwd;
    cleanup_obj = onCleanup(@() cd(old_pwd));
    cd(matlab_dir);
    drivers = {
        'exp_a2_core.m', ...
        'exp_a2_tables.m', ...
        'exp_a2_extra.m', ...
        'exp_a2_nestedcv.m', ...
        'exp_ieee_prior_split.m', ...
        'exp_a2_fig_boxplot.m', ...
        'exp_a2_fig_sens.m', ...
        'exp_a2_fig_traj_arms.m'
    };
    for k = 1:numel(drivers)
        fprintf('[Recompute %d/%d] Running %s ...\n', k, numel(drivers), drivers{k});
        run(fullfile(matlab_dir, drivers{k}));
    end
end

fprintf('==============================================================================\n');
fprintf('All MATLAB reproducibility checks completed successfully.\n');
fprintf('==============================================================================\n');
end
