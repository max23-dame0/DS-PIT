function [final_bpm, lt_state] = LongTerm_Tracking_Constraint(curr_bpm, lt_state, hist_len)
% LONGTERM_TRACKING_CONSTRAINT 基于长期历史的平滑约束 (仿 TAPIR Step 5)
%
% 输入:
%   curr_bpm  - 当前算法(Viterbi/Top3)输出的初步 BPM 估计
%   lt_state  - 状态结构体 (首次调用传空 [])，包含历史 Buffer 和初始化标志
%
% 输出:
%   final_bpm - 经过约束修正后的 BPM
%   lt_state  - 更新后的状态结构体 (必须在主循环中传递给下一次调用)
%
% 逻辑:
%   1. 初始化阶段：等待直到收集到一段标准差很小(稳定)的数据作为基线。
%   2. 跟踪阶段：计算历史"有效"数据的均值。
%   3. 判决：如果 当前值 处于 [0.7 *均值, 1.4 * 均值] 范围内 -> 接受并更新历史。
%   4. 拒绝：如果超出范围 -> 拒绝当前值，输出历史均值(或上一有效值)，且不污染历史 Buffer。

    % --- 1. 参数配置 (参考 TAPIR 论文) ---
    Params.HistLen = hist_len;        % 历史窗口长度 (窗口数)。15 * 2s = 30秒历史
    Params.Init_Std_Thresh = 10;% 初始化阈值：历史标准差 < 10 BPM 才算建立基线
    Params.Lower_Bound = 0.7;   % 下界因子 (TAPIR: 70%)
    Params.Upper_Bound = 1.4;   % 上界因子 (TAPIR: 140%)
    
    % --- 2. 状态初始化 ---
    if isempty(lt_state)
        lt_state.buffer = [];        % 历史 BPM 缓存
        lt_state.is_initialized = false; 
        lt_state.last_valid = NaN;   % 上一次有效值
    end
    
    % 异常值保护
    if isnan(curr_bpm) || curr_bpm <= 0
        final_bpm = curr_bpm; 
        return; 
    end

    % --- 3. 核心逻辑 ---
    
    % 阶段 A: 尚未建立基线 (Initialization)
    if ~lt_state.is_initialized
        % 简单地接受当前值放入 buffer
        lt_state.buffer = [lt_state.buffer, curr_bpm];
        final_bpm = curr_bpm; % 初始化阶段暂不修正，直接透传
        
        % 检查 buffer 是否填满且稳定
        if length(lt_state.buffer) >= Params.HistLen
            curr_std = std(lt_state.buffer);
            if curr_std < Params.Init_Std_Thresh
                % 找到稳定基线，锁定状态，进入跟踪模式
                lt_state.is_initialized = true;
                lt_state.last_valid = curr_bpm;
                % fprintf('Long-Term Tracking: Baseline Established (Std: %.2f)\n', curr_std);
            else
                % 不稳定，移除最早的一个点，继续滑动寻找
                lt_state.buffer(1) = [];
            end
        end
        return;
    end
    
    % 阶段 B: 长期跟踪 (Tracking)
    % 计算历史均值 (即预测值)
    avg_hist = mean(lt_state.buffer);
    
    % 定义安全范围 (TAPIR Bounds)
    min_allow = avg_hist * Params.Lower_Bound;
    max_allow = avg_hist * Params.Upper_Bound;
    
    % 判决
    if curr_bpm >= min_allow && curr_bpm <= max_allow
        % [Accept]: 值在合理范围内
        final_bpm = curr_bpm;
        
        % 更新状态
        lt_state.last_valid = final_bpm;
        % 更新 Buffer (FIFO: 移除最旧，加入最新)
        lt_state.buffer(1) = [];
        lt_state.buffer(end+1) = final_bpm;
    else
        % [Reject]: 值突变过大，认为是伪影/错误
        % 策略：使用历史均值代替 (或者使用 last_valid)
        % TAPIR 原文是 "Interval marked as bad"，这里我们做平滑替代
        
        % 这种替代可以平滑掉突然的尖峰错误
        final_bpm = lt_state.last_valid; % 或者 avg_hist
        
        % 【关键】: 不更新 Buffer！防止错误值污染历史记录，导致后续预测偏移。
        % fprintf('LT Reject: Input %.1f -> Out %.1f (Range: %.1f-%.1f)\n', curr_bpm, final_bpm, min_allow, max_allow);
    end

end