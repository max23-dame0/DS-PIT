function verify_ieee_150()
% 独立验证：稿中 IEEE SPC 1.50 ± 1.54 能否从作者存档 Results/ 复现
% 依据 revision/audit/REPRO-01_LOG.md §4.1：
%   Results/ 23 条记录，BPM_est_online 经 moving(x,4) 平滑后逐记录 MAE 宏平均
%   → 1.50036 ± 1.54004
%
% 2026-09-17 修复（记录审计 RA-03）：
%   ① `moving.m` 对行向量输入返回**列向量**，原写法 `gt - moving(est,4)` 触发
%      146×146 广播，宏平均被算成 17.88556；现统一转为列向量后逐元素相减。
%   ② 补 `addpath('X:\')`——`moving.m` 位于作者存档根目录，缺少时直接报
%      `Undefined function 'moving'`。
%   修复后输出 1.50036 / 1.54004（与 REPRO-01_LOG.md 逐位一致）。
%
% 建议复现命令（工作目录 revision/audit/method_dev）：
%   D:\matlab\bin\matlab.exe -batch "diary('results/verify_ieee_150_log.txt'); verify_ieee_150; diary off"

addpath('X:\');                                 % moving.m 位于作者存档根目录
d = dir('X:\Results\Result_*_WFPV_OVD_PISC.mat');
n = numel(d);
mS = nan(1, n); mR = nan(1, n); nm = cell(1, n);
for i = 1:n
    S = load(fullfile('X:\Results', d(i).name));
    est = S.BPM_est_online(:);                  % 列向量
    gt  = S.BPM0(:);                            % 列向量
    ns  = min(numel(est), numel(gt));
    est = est(1:ns); gt = gt(1:ns);
    m4  = moving(est, 4); m4 = m4(:);           % 列进列出，长度与 est 相同
    e_s = abs(gt - m4);                         % 平滑后（列安全，无广播）
    e_r = abs(gt - est);                        % 未平滑
    mS(i) = mean(e_s(~isnan(e_s)));
    mR(i) = mean(e_r(~isnan(e_r)));
    nm{i} = d(i).name;
end
fprintf('records = %d\n', n);
fprintf('--- smoothed with moving(4) ---\n');
fprintf('macro MAE = %.5f  SD = %.5f      (REPRO-01 / manuscript: 1.50036 / 1.54004)\n', mean(mS), std(mS));
fprintf('--- unsmoothed ---\n');
fprintf('macro MAE = %.5f  SD = %.5f      (REPRO-01: 1.94162 / 1.60141)\n', mean(mR), std(mR));
fprintf('--- per-record (smoothed) ---\n');
for i = 1:n
    fprintf('  S%-2d  %-46s %7.4f\n', i, nm{i}, mS(i));
end
fprintf('worst record: %.4f (idx %d)   best: %.4f (idx %d)\n', max(mS), find(mS == max(mS), 1), min(mS), find(mS == min(mS), 1));
fprintf('records with MAE>5: %d\n', sum(mS > 5));
end
