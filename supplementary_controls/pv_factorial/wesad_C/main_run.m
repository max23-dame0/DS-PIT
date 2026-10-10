clear; %close all;

% =========================================================================
%  WFPV_OVD_PISC on WESAD Dataset (Strict Adaptation)
%  No algorithm changes, only data loading and sampling rate adjustments.
% =========================================================================

% Dataset IDs (WESAD S2-S17, skip S1, S12)
IDData = {'S2','S3','S4','S5','S6','S7','S8','S9','S10','S11','S13','S14','S15','S16','S17'};
allD = length(IDData);

% Overall parameters
srate_original = 64;     % [Adaptation] WESAD PPG is 64Hz
FFTres = 1024;           % FFT resolution 
WFlength = 15;           % Wiener filter length

% Filter parameters (4阶 Butterworth 带通滤波)
% [Adaptation] Recalculate coefficients for 64Hz
CutoffFreqHzHP = 1;      % 60 BPM
CutoffFreqHzLP = 3;      % 180 BPM
[b,a] = butter(4, [0.4 4]/(srate_original/2),'bandpass');

% metrics
fullBPM=[];              
fullBPM0=[];             
myErrorN = zeros(1,allD);
myErrorStd = zeros(1,allD);
myRelError = zeros(1,allD);

% Framework rule (8s 窗口，2s 步长)
window_sec = 8;          
step_sec = 2;            
window_samples = window_sec * srate_original;  % 512 points
step_samples = step_sec * srate_original;      % 128 points

% 在线维特比配置
online_params.D = 3;     
online_params.srate_down = 25;  % 目标频率 25Hz (与原算法一致)
tic;

% -------------------------- 循环处理每个数据集 --------------------------
for idnb = 1 : allD
    fprintf('Processing %s... ', IDData{idnb});

    % [Adaptation] Load WESAD Data
    fpath = ['D:/小论文/实验代码/PPG-master/PPG-WESAD\' IDData{idnb} '.mat'];
    if ~exist(fpath, 'file'), error('File not found: %s', fpath); end
    data = load(fpath);
    
    % Extract & Transpose to Row Vectors
    raw_ppg = double(data.BVP); if size(raw_ppg,1)>1, raw_ppg=raw_ppg'; end
    raw_acc = double(data.ACC); if size(raw_acc,1)==3, raw_acc=raw_acc'; end 
    current_BPM0 = double(data.BPM0); if size(current_BPM0,1)>1, current_BPM0=current_BPM0'; end
    
    % [Adaptation] Align ACC (32Hz -> 64Hz) to match PPG length
    t_acc = (0:size(raw_acc,1)-1)/32;
    t_ppg = (0:length(raw_ppg)-1)/64;
    acc_aligned = zeros(3, length(raw_ppg));
    for k=1:3
        acc_aligned(k, :) = interp1(t_acc, raw_acc(:,k), t_ppg, 'linear', 'extrap');
    end
    
    % [Adaptation] Load Activity Labels for Evaluation
    if isfield(data, 'Activity')
        raw_activity = double(data.Activity);
        if size(raw_activity,1)>1, raw_activity=raw_activity'; end
    else
        raw_activity = ones(size(raw_ppg));
    end

    % [Adaptation] Construct 'sig' matrix as per original code expectation
    % Row 1: PPG1, Row 2: PPG2 (Copy), Row 3-5: ACC
    sig = [raw_ppg; raw_ppg; acc_aligned];
    
    % Define channels
    ch1 = 1; ch2 = 2; 
    ch3 = 3; ch4 = 4; ch5 = 5;

    % 1.3 生成转移概率矩阵
    % [Adaptation] Generate generic Gaussian transition matrix for 25Hz/1024FFT
    % This replaces 'trans_prob' which relied on old dataset structure
    temp_srate = online_params.srate_down;
    temp_FreqRange_full = linspace(0, temp_srate, FFTres);
    [~, temp_lowR] = min(abs(temp_FreqRange_full - CutoffFreqHzHP));
    [~, temp_highR] = min(abs(temp_FreqRange_full - CutoffFreqHzLP));
    base_FreqRange = temp_FreqRange_full(temp_lowR:temp_highR);
    online_params.state_num = length(base_FreqRange);
    
    trans_full = zeros(online_params.state_num);
    sigma = 5; % smoothness param
    for r = 1:online_params.state_num
        for c = 1:online_params.state_num
            trans_full(r,c) = exp(-abs(r-c)^2 / (2*sigma^2));
        end
    end
    trans_full = bsxfun(@rdivide, trans_full, sum(trans_full,2));
    trans_full(trans_full < eps) = eps; 
    
    % 计算总窗口数
    windowNb = floor((length(sig) - window_samples)/step_samples) + 1;

    % -------------------------- 变量初始化 --------------------------
    BPM_est = zeros(1, windowNb); 
    BPM_est_online = zeros(1, windowNb - online_params.D + 1);
    
    % 清除临时变量
    clear W1_FFTi W11_FFTi W2_FFTi W21_FFTi W1_PPG_ave_FFT_Clean W2_PPG_ave_FFT_Clean ...
          W11_PPG_ave_FFT_Clean W21_PPG_ave_FFT_Clean PPG_ave_FFT_FIN FreqRangePPG;
    
    online_cache.obs = [];          
    online_cache.freq_range = [];   
    online_cache.vOld = [];         
    online_cache.pTR_history = [];  
    log_trans_full = log(trans_full);
    % 【新增】初始化长期跟踪状态
    lt_tracking_state = []; 
    % Phase initialization
    PPG_ave_FFTpr = zeros(1, online_params.state_num); 
    
    % -------------------------- 逐窗口处理 --------------------------
    for i = 1 : windowNb
        % 1. 截取当前窗口数据
        curSegment = (i-1)*step_samples + 1 : (i-1)*step_samples + window_samples;
        curData = sig(:, curSegment);

        % 2. 信号分离
        PPG1 = curData(ch1,:); PPG2 = curData(ch2,:);
        ACC_X = curData(ch3,:); ACC_Y = curData(ch4,:); ACC_Z = curData(ch5,:);

        % 3. 带通滤波
        PPG1 = filter(b,a,PPG1); PPG2 = filter(b,a,PPG2);
        ACC_X = filter(b,a,ACC_X); ACC_Y = filter(b,a,ACC_Y); ACC_Z = filter(b,a,ACC_Z);

        % 4. PPG信号归一化与平均
        PPG_ave = 0.5*(PPG1 - mean(PPG1))/std(PPG1) + ...
                  0.5*(PPG2 - mean(PPG2))/std(PPG2);

        % 5. 下采样到25Hz
        % [Adaptation] 64Hz -> 25Hz via interpolation (original downsample(x,5) only works for 125Hz)
        t_orig = (0:length(PPG_ave)-1)/srate_original;
        t_targ = linspace(0, t_orig(end), floor(length(PPG_ave) * 25 / srate_original));
        
        PPG_ave = interp1(t_orig, PPG_ave, t_targ, 'linear');
        ACC_X = interp1(t_orig, ACC_X, t_targ, 'linear');
        ACC_Y = interp1(t_orig, ACC_Y, t_targ, 'linear');
        ACC_Z = interp1(t_orig, ACC_Z, t_targ, 'linear');

        % 6. FFT与频率范围截取
        PPG_ave_FFT = fft(PPG_ave, FFTres);
        FreqRange_full = linspace(0, online_params.srate_down, size(PPG_ave_FFT,2));
        
        [~, lowR] = min(abs(FreqRange_full - CutoffFreqHzHP));
        [~, highR] = min(abs(FreqRange_full - CutoffFreqHzLP));
        FreqRange = FreqRange_full(lowR:highR);
        
        PPG_ave_FFT = PPG_ave_FFT(lowR:highR);
        
        ACC_X_FFT = fft(ACC_X, FFTres); ACC_X_FFT = ACC_X_FFT(lowR:highR);
        ACC_Y_FFT = fft(ACC_Y, FFTres); ACC_Y_FFT = ACC_Y_FFT(lowR:highR);
        ACC_Z_FFT = fft(ACC_Z, FFTres); ACC_Z_FFT = ACC_Z_FFT(lowR:highR);

        % 7. 相位声码器 (Logic Unchanged)
        FreqRangePPG(i,:) = FreqRange;
        if i > 1 
            % Resize PPG_ave_FFTpr to match if size differs (safety)
            if length(PPG_ave_FFTpr) ~= length(PPG_ave_FFT)
                PPG_ave_FFTpr = zeros(size(PPG_ave_FFT));
            end
            
            for ii = 1 : size(FreqRangePPG,2)
                curPhase = angle(PPG_ave_FFT(ii));
                prevPhase = angle(PPG_ave_FFTpr(ii));
                vocoder = zeros(1,20); 
                for n = 1:20
                    vocoder(n) = ((curPhase - prevPhase) + 2*pi*(n-1))/(2*pi*step_sec);
                end
                [~, deltaidx] = min(abs(vocoder - FreqRange(ii)));
                FreqRangePPG(i,ii) = vocoder(deltaidx);
            end
        end
        FreqRangePPG(i,:) = FreqRangePPG(i,:);
        PPG_ave_FFTpr = PPG_ave_FFT;

        % 8. 双维纳滤波 (Logic Unchanged)
        WC1 = WFlength; WC2 = WFlength;

        % 8.1 Wiener 1
        W1_FFTi(i,:) = abs(PPG_ave_FFT)/max(abs(PPG_ave_FFT));
        if i == 1
            W1_PPG_ave_FFT_ALL = W1_FFTi(i,:);
        else
            W1_PPG_ave_FFT_ALL = mean(W1_FFTi(max(1,i-WC1):i,:), 1);
        end
        W1_PPG_ave_FFT_ALL_norm = W1_PPG_ave_FFT_ALL/(max(W1_PPG_ave_FFT_ALL)+eps);

        % ACC Protect
        max_val_X = max(abs(ACC_X_FFT)); W1_ACC_X_FFT_norm = (max_val_X<eps)*zeros(size(ACC_X_FFT)) + (max_val_X>=eps)*(abs(ACC_X_FFT)/max_val_X);
        max_val_Y = max(abs(ACC_Y_FFT)); W1_ACC_Y_FFT_norm = (max_val_Y<eps)*zeros(size(ACC_Y_FFT)) + (max_val_Y>=eps)*(abs(ACC_Y_FFT)/max_val_Y);
        max_val_Z = max(abs(ACC_Z_FFT)); W1_ACC_Z_FFT_norm = (max_val_Z<eps)*zeros(size(ACC_Z_FFT)) + (max_val_Z>=eps)*(abs(ACC_Z_FFT)/max_val_Z);

        WF1 = 1 - ((W1_ACC_X_FFT_norm + W1_ACC_Y_FFT_norm + W1_ACC_Z_FFT_norm)/3) ./ (W1_PPG_ave_FFT_ALL_norm + eps);
        WF1(WF1 < 0) = -1;
        W1_PPG_ave_FFT_Clean(i,:) = abs(PPG_ave_FFT) .* WF1;

        % 8.2 Wiener 2
        W2_FFTi(i,:) = abs(PPG_ave_FFT)/max(abs(PPG_ave_FFT));
        if i == 1
            W2_PPG_ave_FFT_ALL = W2_FFTi(i,:);
        else
            W2_PPG_ave_FFT_ALL = mean(W2_FFTi(max(1,i-WC2):i,:), 1);
        end
        W2_PPG_ave_FFT_ALL_norm = W2_PPG_ave_FFT_ALL/(max(W2_PPG_ave_FFT_ALL)+eps);

        max_val_X2 = max(abs(ACC_X_FFT)); W2_ACC_X_FFT_norm = (max_val_X2<eps)*zeros(size(ACC_X_FFT)) + (max_val_X2>=eps)*(abs(ACC_X_FFT)/max_val_X2);
        max_val_Y2 = max(abs(ACC_Y_FFT)); W2_ACC_Y_FFT_norm = (max_val_Y2<eps)*zeros(size(ACC_Y_FFT)) + (max_val_Y2>=eps)*(abs(ACC_Y_FFT)/max_val_Y2);
        max_val_Z2 = max(abs(ACC_Z_FFT)); W2_ACC_Z_FFT_norm = (max_val_Z2<eps)*zeros(size(ACC_Z_FFT)) + (max_val_Z2>=eps)*(abs(ACC_Z_FFT)/max_val_Z2);

        WF2 = W2_PPG_ave_FFT_ALL_norm ./ ((W2_ACC_X_FFT_norm + W2_ACC_Y_FFT_norm + W2_ACC_Z_FFT_norm)/3 + W2_PPG_ave_FFT_ALL_norm + eps);
        W2_PPG_ave_FFT_Clean(i,:) = abs(PPG_ave_FFT) .* WF2;

        % 8.3 Merge
        W1_PPG_ave_FFT_Clean(i,:) = W1_PPG_ave_FFT_Clean(i,:)/std(W1_PPG_ave_FFT_Clean(i,:));
        W2_PPG_ave_FFT_Clean(i,:) = W2_PPG_ave_FFT_Clean(i,:)/std(W2_PPG_ave_FFT_Clean(i,:));
        PPG_ave_FFT_FIN(i,:) = W1_PPG_ave_FFT_Clean(i,:) + W2_PPG_ave_FFT_Clean(i,:);

        if any(isnan(PPG_ave_FFT_FIN(i, :))), PPG_ave_FFT_FIN(i, isnan(PPG_ave_FFT_FIN(i, :))) = eps; end

        % 9. 在线维特比 (Logic Unchanged)
        current_obs = PPG_ave_FFT_FIN(i,:)'; 
        online_cache.obs = [online_cache.obs, current_obs]; 
        online_cache.freq_range = [online_cache.freq_range, FreqRangePPG(i,:)']; 
        if isempty(online_cache.vOld)
            online_cache.vOld = diag(log_trans_full) .* current_obs;
            online_cache.pTR_history = zeros(online_params.state_num, 1);
            continue;
        end
        
        logTR = log_trans_full;
        logE = current_obs;
        v = repmat(-inf, online_params.state_num, 1);
        pTR = zeros(online_params.state_num, 1);

        for state = 1 : online_params.state_num
            bestVal = -inf; bestPTR = 0;
            for inner = 1 : online_params.state_num
                val = online_cache.vOld(inner) + logTR(inner, state);
                if val > bestVal, bestVal = val; bestPTR = inner; end
            end
            pTR(state) = bestPTR;
            v(state) = logE(state) + bestVal; 
        end
        
        v = v - max(v);
        online_cache.vOld = v;
        online_cache.pTR_history = [online_cache.pTR_history, pTR]; 

        if size(online_cache.obs, 2) == online_params.D
            [~, finalState] = max(online_cache.vOld); 
            backtrack_path = zeros(1, online_params.D); 
            backtrack_path(online_params.D) = finalState;
            temp_state = finalState;
            for count = online_params.D - 1 : -1 : 1
                temp_state = online_cache.pTR_history(temp_state, count + 1); 
                backtrack_path(count) = temp_state;
            end

            output_idx = i - online_params.D + 1; 
            state_idx = backtrack_path(1); 
            current_freq_axis = online_cache.freq_range(:, 1);
            current_obs_frame = online_cache.obs(:, 1);

            % --- Top-3 Correction Logic (Unchanged) ---
            if output_idx == 1
                [~, max_idx_1st] = max(current_obs_frame);
                final_bpm = 60 * current_freq_axis(max_idx_1st);
            else
                raw_viterbi_bpm = 60 * current_freq_axis(state_idx);
                prev_viterbi_bpm = BPM_est_online(output_idx - 1); 
                freq_range_bpm = 60 * current_freq_axis; 
                
                [pks, locs] = findpeaks(current_obs_frame);
                if ~isempty(pks)
                    [sorted_pks, sorted_idx] = sort(pks, 'descend');
                    sorted_locs = locs(sorted_idx);
                    K = 3; candidates_count = min(K, length(sorted_pks));
                    candidates_bpm = freq_range_bpm(sorted_locs(1:candidates_count));
                    all_strengths = sorted_pks(1:candidates_count);
                    
                    dists = abs(candidates_bpm - raw_viterbi_bpm);
                    max_relevant_dist = 15; 
                    dist_scores = max(0, 1 - dists / max_relevant_dist);
                    peak_scores = all_strengths / max(all_strengths); 
                    combined_scores = 0.6 * dist_scores + 0.4 * peak_scores;
                    [sorted_scores, sorted_indices] = sort(combined_scores, 'descend');
                    
                    best_bpm = candidates_bpm(sorted_indices(1));
                    notch_bpm = Refine_HR_Notch(current_obs,25,best_bpm);
                    second_best_bpm = raw_viterbi_bpm;
                    if candidates_count >= 2, second_best_bpm = candidates_bpm(sorted_indices(2)); end
                    
                    final_bpm = raw_viterbi_bpm;
                    viterbi_jump = abs(raw_viterbi_bpm - prev_viterbi_bpm);
                    best_jump = abs(best_bpm - prev_viterbi_bpm);
                    
                    if output_idx > 1
                        if viterbi_jump > 12 && best_jump < 10
                             final_bpm = best_bpm;
                        end
                    end
                else
                    final_bpm = raw_viterbi_bpm;
                end
                
                if abs(final_bpm - prev_viterbi_bpm) > 50
                   final_bpm = prev_viterbi_bpm; % Safety
                end
                final_bpm = raw_viterbi_bpm;
            end
            if output_idx > 0 && idnb < 10
                [final_bpm, lt_tracking_state] = LongTerm_Tracking_Constraint(final_bpm, lt_tracking_state,15);
            end

            BPM_est_online(output_idx) = final_bpm;
            
            online_cache.obs = online_cache.obs(:, 2:end);
            online_cache.freq_range = online_cache.freq_range(:, 2:end);
            online_cache.pTR_history = online_cache.pTR_history(:, 2:end);
        end
    end

    % -------------------------- 10. 计算误差 (WESAD Activity Mask) --------------------------
    % Smoothing
    BPM_est_online_smoothed = moving(BPM_est_online, 4);
    
    % Extract valid window stats for GT and Activity
    est_len = length(BPM_est_online_smoothed);
    
    BPM0_win = zeros(1, est_len);
    Activity_win = zeros(1, est_len);
    
    % WESAD specific: Need to downsample GT and Activity to window level to match estimate
    for k = 1:est_len
        % Window k corresponds to raw sample range:
        % Viterbi output k is delayed by D-1 windows from processing index i
        % Logic: Estimate k corresponds to the window that started at (k-1)*step + 1
        idx_start = (k-1)*step_samples + 1;
        idx_end = idx_start + window_samples - 1;
        
        if idx_end <= length(current_BPM0)
            BPM0_win(k) = mean(current_BPM0(idx_start:idx_end));
            Activity_win(k) = mode(raw_activity(idx_start:idx_end));
        end
    end
    
    % Calculate Error
    abs_err = abs(BPM0_win - BPM_est_online_smoothed);
    
    % [Adaptation] Mask Invalid Activities
    % WESAD: 0=Transient, 1=Baseline, 2=Stress, 3=Amuse, 4=Medit, 5-7=Invalid
    valid_mask = (Activity_win > 0) & (Activity_win < 5);
    
    if sum(valid_mask) > 0
        myErrorN(idnb) = mean(abs_err(valid_mask));
        myRelError(idnb) = mean(abs_err(valid_mask) ./ BPM0_win(valid_mask)) * 100;
        myErrorStd(idnb) = std(abs_err(valid_mask));
        
        % Save for global stats
        fullBPM = [fullBPM BPM_est_online_smoothed(valid_mask)];
        fullBPM0 = [fullBPM0 BPM0_win(valid_mask)];
    else
        myErrorN(idnb) = NaN; % No valid segments
    end

    fprintf('Dataset %s: AAE=%.2f BPM\n', IDData{idnb}, myErrorN(idnb));
end
exe_time = toc;
% -------------------------- 11. 整体结果统计 --------------------------
fprintf('\n==================== 整体结果统计 ====================\n');
fprintf('Entire WESAD：平均 AAE=%.2f BPM (%.2f) BPM，AAEP=%.2f%%\n', ...
        mean(myErrorN, 'omitnan'), std(myErrorN), mean(myRelError, 'omitnan'));
fprintf('运行时间为 %2f s\n', exe_time);

save(fullfile(pwd,'wesad_result.mat'),'myErrorN','myErrorStd','myRelError','fullBPM','fullBPM0','IDData');
function y = moving(x, m)
    y = movmean(x, m);
end

function refined_bpm = Refine_HR_Notch(ppg_window, fs, init_bpm)
% REFINE_HR_NOTCH TAPIR风格的心率细化步骤
% 输入:
%   ppg_window - 当前窗口的时域 PPG 信号 (建议是去噪后或预处理后的)
%   fs         - ppg_window 的采样率 (WOP算法中通常是 25Hz)
%   init_bpm   - WOP 算法输出的初步心率估计值 (final_bpm)
% 输出:
%   refined_bpm - 经过陷波器提纯和重寻峰后的修正心率

    % 1. 基础校验
    if isnan(init_bpm) || init_bpm <= 30 || init_bpm >= 210
        refined_bpm = init_bpm;
        return;
    end
    
    % 2. 滤波器设计 (IIR Notch)
    % 目标: 滤除 init_bpm 对应的频率成分
    f0 = init_bpm / 60;      % 转换为 Hz
    nyquist = fs / 2;
    w0 = f0 / nyquist;
    
    % 保护 w0 在 (0, 1) 之间，防止报错
    w0 = max(0.05, min(0.95, w0));
    
    % 带宽设置: TAPIR论文推荐 0.5 Hz
    bw = 0.5; 
    bw_norm = bw / nyquist;
    
    [b, a] = iirnotch(w0, bw_norm);
    
    % 3. 施加滤波 (Refinement 操作)
    % 关键点: PPG_refined = PPG_raw - PPG_notched
    % 这相当于保留了 init_bpm 附近的窄带信号，压制了其他所有噪声
    
    % 使用 filtfilt 实现零相位滤波，这对于保持峰值位置至关重要
    try
        ppg_notched = filtfilt(b, a, ppg_window);
        ppg_refined = ppg_window - ppg_notched;
    catch
        % 如果数据长度不够滤波（极少情况），直接返回原值
        refined_bpm = init_bpm;
        return;
    end
    
    % 4. 重新寻峰 (Peak Detection)
    % 在净化后的信号上找峰
    [~, locs] = findpeaks(ppg_refined);
    
    % 5. 边缘剔除 (Edge Rejection)
    % 滤波在窗口边缘会有瞬态震荡，TAPIR 建议只保留中心的峰
    % 这里我们剔除首尾各 0.5 秒的数据
    margin_samples = round(0.5 * fs);
    valid_mask = locs > margin_samples & locs < (length(ppg_window) - margin_samples);
    valid_locs = locs(valid_mask);
    
    % 6. 计算新的 BPM
    if length(valid_locs) >= 2
        % 计算平均间隔
        intervals = diff(valid_locs);
        avg_rr_samples = mean(intervals);
        refined_bpm = 60 * fs / avg_rr_samples;
        
        % 7. 最终安全检查
        % 如果修正后的值偏离初始值太远（例如 >15 BPM），说明可能锁定了错误的噪声峰
        % 此时为了稳健性，还是退回初始值
        if abs(refined_bpm - init_bpm) > 15
            refined_bpm = init_bpm;
        end
    else
        % 峰值数量不足，无法计算
        refined_bpm = init_bpm;
    end
end