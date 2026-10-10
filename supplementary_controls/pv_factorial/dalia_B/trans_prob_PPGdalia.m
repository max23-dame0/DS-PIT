function trans_full = trans_prob_PPGdalia(rangeID, FreqRange)
% 输入: 
% rangeID - 训练集数据的索引列表 (例如排除当前测试集后的其他所有ID)
% FreqRange - 频率范围 (用于确定矩阵维度)

numS = length(FreqRange); 

% === 修改点 1: 更新数据集 ID 列表 ===
% 对应 PPG-Dalia 的 15 个受试者
IDData = {'S1','S2','S3','S4','S5','S6','S7','S8','S9','S10','S11','S12','S13','S14','S15'};

trans_full = zeros(numS, numS);

% 遍历训练集列表
for idnb = rangeID
    % === 修改点 2: 更新路径逻辑 ===
    % 直接指向我们新生成的 PPG-dalia/BPM_data 文件夹
    % 假设 Python 生成的文件名为 SX_BPMtrace.mat，变量名为 BPM0
    fpath = ['D:/小论文/实验代码/PPG-master/PPG-dalia\BPM_data\' IDData{idnb} '_BPMtrace.mat'];
    
    if exist(fpath, 'file')
        gt_data = load(fpath);
        % 获取 BPM0 数据
        if isfield(gt_data, 'BPM0')
            BPM0 = gt_data.BPM0;
        else
            error(['文件 ' fpath ' 中找不到变量 BPM0']);
        end
    else
        warning(['文件不存在: ' fpath '，跳过此文件。']);
        continue;
    end
    
    % 以下逻辑保持原样 (统计直方图和转移矩阵)
    % ------------------------------------------------
    
    %# discretization/quantization into levels matching numS
    x = BPM0;
    
    % 注意：这里的 60, 180 是 BPM 范围，需要确保与主程序中的 CutoffFreq 对应
    % 主程序 CutoffFreqHzHP=1 (60BPM), LP=3 (180BPM)
    edges = linspace(60, 180, numS+1);
    [counts, bins] = histc(x, edges);
    
    % 处理边界情况
    bins(bins==0) = 1;
    if ~isempty(counts)
        counts(1) = sum(bins==1);
        % fix last level of histc output
        last = numel(counts);
        bins(bins==last) = last - 1;
        counts(last-1) = counts(last-1) + counts(last);
        counts(last) = [];
    end
    
    %# transition matrix
    % 防止空数据导致的错误
    if length(bins) > 1
        trans = full(sparse(bins(1:end-1), bins(2:end), 1, numS, numS));
        % 对角线清零或不做处理? 原代码似乎有特殊逻辑:
        dim = setdiff(1:numS, 1:size(trans,2)); % 这一行原代码逻辑有点奇怪，但保留原样
        trans(dim, dim) = 0; 
        
        trans_full = trans_full + trans;
    end
end

% 归一化 (概率和为1)
trans_full = bsxfun(@rdivide, trans_full, sum(trans_full, 2));
trans_full(isnan(trans_full)) = eps; % 防止除以0出现的 NaN

end