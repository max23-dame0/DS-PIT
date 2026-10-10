function res = ds5(dataset, subjects, o)
% DS-PIT v5 = v4 + 吸收 CurToSS 的三条机制
%
% ⚠️ 默认值警示（记录审计 T4）：本函数的**默认参数**（state 0.6–3.4 Hz、σ=5、
%   smooth_m=4、smooth_mode='mean'、sigma_lo=3/sigma_hi=8、edge_taper=0）对应
%   **旧配置**；直接调用 ds5(ds,1:15) 得到的**不是论文口径**。
%   论文口径必须显式传入配置，见 exp_paper_v3.m:14-18：
%     f_lo=40, f_hi=200, D=3, state_lo_hz=0.75, state_hi_hz=3.0, edge_taper=30,
%     smooth_mode='median', smooth_m=3, q_feat='off', sigma=2,
%     obs_mode='ratio', wf_variant='orig'
%   ① 曲线积分 MA 判别：ACC 的 MA 证据沿**时间窗积分**（近似曲线积分），而非逐帧点值
%      - 新增 acc_int_w（积分半窗，0=退化为 v4 的逐帧点值）
%      - 新增 ma_pen（曲线级 MA 惩罚权重）
%   ② 门控重捕获：仅在"曲线中断"帧放宽转移（局部追踪为主 + 中断时重捕获）
%      - 新增 rc_mode='off'|'always'|'gated'，rc_rho（宽尾权重），rc_th（中断判定 BPM）
%   ③ 完整指标：额外返回合并的带符号误差以计算 Bland-Altman LoA 与 Pearson r
%   ④ E1 附加（2026-09-18，二轮修订 BLK-1a；默认关闭、向后兼容）：
%      - 新增 lbp_gate='off'|'soft'（等式所述软 LBP 门控的复核用注入点），
%        lbp_lo/lbp_hi（验收区间，默认 0.7/1.4）、lbp_eps（区间外权重，默认 1e-2）、
%        lbp_hist_min/lbp_hist_max（历史缓冲，默认 15/15）
%      - lbp_gate='off' 时行为与加入前逐位一致（exp_gate_unified.m 已复核）
%   ⑤ G1 附加（2026-09-18，PD-1 路线 A 的补充复测；默认关闭、向后兼容）：
%      - lbp_gate='hard'：输出替换式门控（参考实现的实际形态），
%        lbp_buf_mode='keep'（论文描述：替换时缓冲不变）/ 'append'（dspit2.m 实现：写入替换值）
%   ⑥ T1 附加（2026-09-18，路线 A 机制诊断；默认关闭、向后兼容）：
%      - lbp_diag=true 时额外返回 res.lbp_diag：逐受试者的门控事件
%        （发射窗 idx、决策时 μ、门控前原始输出 raw、实际输出 out、
%          动作 act：0=无门控或 μ 不足 / 1=接受 / 2=硬替换或软区间外、决策时缓冲长度 buf）
if nargin < 3, o = struct(); end
o = d(o, 'f_lo', 40); o = d(o, 'f_hi', 200); o = d(o, 'step', 1);
o = d(o, 'state_lo_hz', 0.6); o = d(o, 'state_hi_hz', 3.4);
o = d(o, 'obs_mode', 'ratio');
o = d(o, 'spec_w', 1); o = d(o, 'ac_w', 0);
o = d(o, 'sigma', 5); o = d(o, 'jump_rho', 0);
o = d(o, 'obs_mix', 0); o = d(o, 'q_ref', 0.5); o = d(o, 'eps_max', 0.5);
o = d(o, 'D', 3); o = d(o, 'smooth_m', 4);
o = d(o, 'WFlength', 15); o = d(o, 'lum_bw', 5);
o = d(o, 'acc_int_w', 0); o = d(o, 'ma_pen', 0);
o = d(o, 'ma_form', 'exp'); o = d(o, 'ma_thr', 0.6);
o = d(o, 'cachedir', 'cache2');
o = d(o, 'smooth_mode', 'mean'); o = d(o, 'wf_variant', 'orig');
o = d(o, 'q_feat', 'off'); o = d(o, 'sigma_lo', 3); o = d(o, 'sigma_hi', 8); o = d(o, 'q_dir', 'norm');
o = d(o, 'edge_taper', 0); o = d(o, 'q_flat', 0);   % 质量驱动的观测平坦化强度
o = d(o, 'obs_gamma', 1); % 观测似然温度
o = d(o, 'rc_mode', 'off'); o = d(o, 'rc_rho', 0.02); o = d(o, 'rc_th', 12);
o = d(o, 'lbp_gate', 'off'); o = d(o, 'lbp_lo', 0.7); o = d(o, 'lbp_hi', 1.4);   % E1：软 LBP 门控注入点（默认 off=论文口径）
o = d(o, 'lbp_eps', 1e-2); o = d(o, 'lbp_hist_min', 15); o = d(o, 'lbp_hist_max', 15);
o = d(o, 'acc_axes', 'sum');   % M-20：加速度参考配置（sum=论文口径；x/y/z/pc1 仅用于对照）
o = d(o, 'lbp_buf_mode', 'keep');
o = d(o, 'lbp_diag', false);   % T1：门控事件落盘（默认关闭，不影响任何数值）
o = d(o, 'dump_logL', false);  % EMB-01：逐窗观测似然落盘（默认关闭，只读注入，不影响数值）
o = d(o, 'lbp_cf', 0);          % V-CF：确认释放——连续超区间达到该窗数后接受新水平并重置历史（0=关闭）
o = d(o, 'lbp_prior_w', 0);     % V2：吸引式长期先验权重 λ（0=关闭）
o = d(o, 'lbp_prior_sig', 10);  % V2：先验带宽 σ_hist（论文参考值 10）
o = d(o, 'lbp_vel_L', 0);       % M-LBP-V：速度/趋势估计窗（0=关闭；≥2 启用）
o = d(o, 'lbp_vel_max', 2);     % M-LBP-V：速度钳位（BPM/窗）
o = d(o, 'lbp_vel_use', 'off'); % M-LBP-V：'off'|'kernel'（转移核中心前移 v̂）|'lead'（输出端滞后补偿 c·v̂）|'both'
o = d(o, 'lbp_vel_lead', 1);    % M-LBP-V：lead 系数 c
o = d(o, 'lbp_cand_g', 0);      % M-C：候选峰长时先验强度 γ（0=关闭）
o = d(o, 'lbp_cand_sh', 12);    % M-C：先验带宽 σ_h（BPM）
o = d(o, 'lbp_cand_sc', 2);     % M-C：候选峰核宽 σ_c（BPM）
o = d(o, 'lbp_harm_w', 0);      % A1：谐波一致性证据权重 λh（0=关闭）
o = d(o, 'lbp_harm_r', 2);      % A1：谐波比 r（状态频率 = r × 观测峰）
o = d(o, 'lbp_spec_w', 0);      % A2：长时谱先验权重 λt（0=关闭）
o = d(o, 'lbp_spec_a', 1/30);   % A2：长时谱 EMA 系数 α
o = d(o, 'lbp_sel_g', 0);       % B：长时一致性投票-选择锐化 γ_sel（0=关闭）
o = d(o, 'lbp_sel_sh', 12);     % B：锚带宽 σh（BPM）
o = d(o, 'lbp_sel_sc', 2);      % B：锐化核宽 σc（BPM）
o = d(o, 'lbp_sel_ring', 5);    % B：投票环长（帧）
o = d(o, 'lbp_sel_tol', 3);     % B：投票容差（BPM）
o = d(o, 'lbp_temp_w', 0);      % C：长时可靠性自适应观测温度（0=关闭）
o = d(o, 'lbp_temp_win', 30);   % C：可靠性 EMA 窗（帧）
o = d(o, 'lbp_temp_lo', 0.7);   % C：低可靠性温度
o = d(o, 'lbp_temp_hi', 1.3);   % C：高可靠性温度   % G1：hard 门控替换时历史缓冲 'keep'（论文描述）/ 'append'（dspit2 实现）

cache = fullfile(fileparts(mfilename('fullpath')), o.cachedir);
if ~exist(cache, 'dir') && ~isempty(getenv('DSPIT_CACHE_DIR')) && exist(getenv('DSPIT_CACHE_DIR'), 'dir')
    cache = getenv('DSPIT_CACHE_DIR');
elseif ~exist(cache, 'dir') && strcmp(o.cachedir, 'cache2') && exist('D:\小论文\manuscript_JBHI_IEEEtran\revision\audit\method_dev\cache2', 'dir')
    cache = 'D:\小论文\manuscript_JBHI_IEEEtran\revision\audit\method_dev\cache2';
end
sb = o.f_lo:o.step:o.f_hi; K = numel(sb); shz = sb / 60;
% 转移核：默认用解析高斯核；若传入 o.T_mat（K×K、行归一、严格正）则改为注入外部核。
% 该选项仅为 §8#3 的"数据先验 vs 证据带"消融而加（exp_ieee_prior_split.m），
% 不传时行为与加入前完全一致（论文口径不受影响）。
if isfield(o, 'T_mat') && ~isempty(o.T_mat)
    assert(isequal(size(o.T_mat), [K K]), 'o.T_mat 尺寸必须为 K×K');
    makeT = @(sig, rho) o.T_mat;
else
    makeT = @(sig, rho) norm_tm(sig, rho, K);
end
logT0 = log(makeT(o.sigma, o.jump_rho));
% M-LBP-V：预计算整数速度位移的转移核（仅 kernel/both 且未注入 T_mat 时）
velK = round(o.lbp_vel_max); TS = [];
if (strcmp(o.lbp_vel_use, 'kernel') || strcmp(o.lbp_vel_use, 'both')) && ...
        ~(isfield(o, 'T_mat') && ~isempty(o.T_mat))
    TS = cell(2 * velK + 1, 1);
    for m = -velK:velK
        TS{m + velK + 1} = log(shift_tm(o.sigma, o.jump_rho, K, m));
    end
end

nS = numel(subjects);
mae = nan(1, nS); rmse = nan(1, nS); med = nan(1, nS); p95 = nan(1, nS);
bias = nan(1, nS); gt10 = nan(1, nS); cov = nan(1, nS); pears = nan(1, nS);
ALL = cell(1, nS); ERR = cell(1, nS); PR = cell(1, nS); DIAG = cell(1, nS); OBSK = cell(1, nS); TOPK = cell(1, nS);
LOGL = cell(1, nS);   % EMB-01：逐窗观测似然（仅 dump_logL=true 时填充）
for si = 1:nS
    F = load(fullfile(cache, sprintf('%s_S%d.mat', dataset, subjects(si))));
    S = F.S; A = F.A; if isfield(F,'X'), X = F.X; else, X = []; end; fb = F.fb; gt = F.gt(:)'; act = F.act(:)';
    nWin = F.nWin; rmsP = F.rmsP; rmsA = F.rmsA;
    qRaw = mean(rmsA, 1) ./ (rmsP + eps);
    qN = qRaw / (median(qRaw) + eps);
    inb = fb >= o.state_lo_hz & fb <= o.state_hi_hz;
    fbc = fb(inb); Spc = S(:, inb); Apc = A(:, inb, :);
    nb = numel(fbc);
    % ---- ACC 归一化 MA 证据，并按时间窗积分（曲线积分近似）----
    Acn = zeros(nWin, nb);
    for t = 1:nWin
        v = 0;
        for j = 1:3
            aj = abs(reshape(Apc(t, :, j), [1, nb]));
            v = v + aj / (max(aj) + eps);
        end
        Acn(t, :) = v / 3;
    end
    if o.acc_int_w > 0
        AcnI = movmean(Acn, 2 * o.acc_int_w + 1, 1);
    else
        AcnI = Acn;
    end
    % ---- 前向贪心预扫描：用于"曲线中断"判定（因果）----
    brk = false(1, nWin);
    if strcmp(o.rc_mode, 'gated')
        g = nan(1, nWin); gprev = NaN;
        for t = 1:nWin
            ov = obs_vec(Spc(t, :), reshape(Apc(t, :, :), [nb, 3]).', o, AcnI(t, :));
            [~, im] = max(ov.v); hb = 60 * fbc(im);   % P0 修正：v 建在证据带 fbc 上，不能用状态网格 sb 索引
            if ~isnan(gprev) && abs(hb - gprev) > o.rc_th, brk(t) = true; end
            g(t) = hb; gprev = hb;
        end
    end
    % ---- 窗级质量（CurToSS 式峰度门控的借用）----
    qn = ones(1, nWin);
    if ~strcmp(o.q_feat, 'off')
        qf = zeros(1, nWin);
        for t = 1:nWin
            v = abs(Spc(t, :)); v = v / (max(v) + eps);
            switch o.q_feat
                case 'kurt'
                    m = mean(v); s = std(v) + eps; qf(t) = mean(((v - m) / s).^4);
                case 'prom'
                    pv = findpeaks(v);
                    if numel(pv) >= 2, pv = sort(pv, 'descend'); qf(t) = pv(1) / (pv(2) + eps); else, qf(t) = 1; end
                otherwise
                    qf(t) = 1;
            end
        end
        qn = qf / (median(qf) + eps); qn = min(max(qn, 0), 2);
    end
    W1h = []; W2h = [];
    if o.dump_logL, LOGL{si} = zeros(K, nWin, 'single'); end   % EMB-01：逐窗观测似然缓存（只读注入）
    est = nan(1, nWin); ptr = zeros(K, nWin); vOld = []; hist_g = []; lastValid_g = NaN;
    ev_i = []; ev_mu = []; ev_raw = []; ev_out = []; ev_act = []; ev_buf = [];   % T1：门控事件（仅 lbp_diag）
    ev_tau = [];   % A′：逐发射窗的实际可靠性温度 τ（仅 lbp_diag）
    cout = 0;   % V-CF：连续超出区间计数
    veh = [];   % M-LBP-V：已发射值（解码器自身输出）缓冲，供速度估计
    ring = {}; Rrel = 0.5; Sspec = [];   % B：投票环；C：可靠性 EMA；A2：长时谱模板
    obs_pk = nan(1, nWin);   % diag：逐帧观测峰（evidence band 上 argmax，仅 lbp_diag）
    top_f = nan(3, nWin); top_v = nan(3, nWin);   % diag：逐帧 top-3 局部极大峰（仅 lbp_diag）   % hist_g: E1/G1 门控历史
    for t = 1:nWin
        vhat = 0;   % M-LBP-V：因果速度估计（已发射值的中位增量，钳位取整）
        if o.lbp_vel_L >= 2 && numel(veh) >= o.lbp_vel_L + 1
            dv = diff(veh(end - o.lbp_vel_L:end));
            vhat = round(min(max(median(dv), -o.lbp_vel_max), o.lbp_vel_max));
        end
        sp = Spc(t, :); ap = reshape(Apc(t, :, :), [nb, 3]).';
        ob = obs_vec(sp, ap, o, AcnI(t, :), W1h, W2h);
        if isfield(ob, 'W1h'), W1h = ob.W1h; W2h = ob.W2h; end
        if o.lbp_diag   % 观测峰与 top-3 局部极大（fbc 坐标；仅诊断）
            [~, impk] = max(ob.v); obs_pk(t) = 60 * fbc(impk);
            cand = find(islocalmax(ob.v));
            if numel(cand) < 3, cand = 1:numel(ob.v); end
            [~, oo] = sort(ob.v(cand), 'descend');
            tp = cand(oo(1:min(3, numel(oo))));
            top_f(1:numel(tp), t) = 60 * fbc(tp);
            top_v(1:numel(tp), t) = ob.v(tp);
        end
        cand_pk = [];   % 当帧候选峰（BPM；供 M-C / B / C 共用）
        if o.lbp_cand_g > 0 || o.lbp_sel_g > 0 || o.lbp_temp_w > 0
            cc = find(islocalmax(ob.v));
            if ~isempty(cc), cand_pk = 60 * fbc(cc); end
        end
        a_lb = NaN;   % 长时锚：历史均值 + 因果趋势（供 M-C / B / C 共用）
        if numel(hist_g) >= o.lbp_hist_min, a_lb = mean(hist_g) + vhat; end
        Psp = interp1(60 * fbc, ob.v, sb, 'linear', 0);
        if o.edge_taper > 0   % 带边斜坡，消除证据带切口造成的虚假吸引子
            lo_q = 60 * o.state_lo_hz; hi_q = 60 * o.state_hi_hz; wq = o.edge_taper;
            rmp = min(1, max(0, (sb - lo_q) / wq)) .* min(1, max(0, (hi_q - sb) / wq));
            Psp = Psp .* rmp;
        end
        Psp = (Psp - min(Psp)) / (max(Psp) - min(Psp) + eps);
        L = o.spec_w * Psp;
        if o.ac_w > 0
            Pac = ac_evidence(X(t, :), sb, 25);
            L = L + o.ac_w * Pac;
        end
        L = (L - min(L)) / (max(L) - min(L) + eps) + 1e-6;
        if o.lbp_cand_g > 0 && ~isempty(cand_pk) && ~isnan(a_lb)   % M-C：候选峰长时先验（有界乘性）
            wq = exp(-((cand_pk - a_lb).^2) / (2 * o.lbp_cand_sh^2));
            wq = wq / (sum(wq) + eps);
            Pc = zeros(1, K);
            for kk = 1:numel(cand_pk)
                Pc = Pc + wq(kk) * exp(-((sb - cand_pk(kk)).^2) / (2 * o.lbp_cand_sc^2));
            end
            L = L .* (1 + o.lbp_cand_g * Pc);
        end
        if o.lbp_harm_w > 0   % A1：谐波一致性证据（状态频率 = r × 观测峰；仅半频/1.5 倍等整比混淆）
            Lh = interp1(60 * fbc, ob.v, sb / o.lbp_harm_r, 'linear', 0);
            L = L + o.lbp_harm_w * max(0, Lh(:)');
        end
        if o.lbp_spec_w > 0   % A2：长时谱先验（因果 EMA 的观测证据模板，乘性有界）
            Es = interp1(60 * fbc, ob.v, sb, 'linear', 0); Es = Es(:)';
            if isempty(Sspec), Sspec = Es; else, Sspec = (1 - o.lbp_spec_a) * Sspec + o.lbp_spec_a * Es; end
            L = L .* (1 + o.lbp_spec_w * (Sspec / (max(Sspec) + eps)));
        end
        if o.lbp_sel_g > 0 && ~isempty(cand_pk)   % B：长时一致性投票选择候选峰并锐化
            if ~isnan(a_lb)
                vote = zeros(1, numel(cand_pk));
                for jj = 1:numel(ring)
                    q = ring{jj};
                    if ~isempty(q)
                        for kk = 1:numel(cand_pk)
                            vote(kk) = vote(kk) + any(abs(q - cand_pk(kk)) <= o.lbp_sel_tol);
                        end
                    end
                end
                sc = vote - ((cand_pk - a_lb).^2) / (2 * o.lbp_sel_sh^2);
                [~, kb] = max(sc);
                L = L .* (1 + o.lbp_sel_g * exp(-((sb - cand_pk(kb)).^2) / (2 * o.lbp_sel_sc^2)));
            end
            ring = [{cand_pk}, ring(1:min(numel(ring), o.lbp_sel_ring - 1))];   % 更新投票环（不影响当帧）
        end
        if o.ma_pen > 0
            mp = interp1(60 * fbc, AcnI(t, :), sb, 'linear', 0); mp = max(0, mp(:)');
            if strcmp(o.ma_form, 'ratio')      % CurToSS 式(7)：ACC 曲线积分 / PPG 观测
                pen = max(0, mp ./ (Psp(:)' + 1e-3) - o.ma_thr);
            else
                pen = mp;
            end
            L = L .* exp(-o.ma_pen * pen);
        end
        if o.obs_mix > 0
            q = qN(t); epsq = o.eps_max * q / (o.q_ref + q);
            L = (1 - epsq) * L + epsq / K;
        end
        if o.q_flat > 0   % 质量驱动的观测平坦化：谱越不干净 -> 越向均匀分布靠拢
            ef = min(1, o.q_flat * max(0, 1 - min(qn(t), 1)));
            L = (1 - ef) * L + ef / K;
        end
        logL = o.obs_gamma * log(L);   % 观测温度：>1 锐化，<1 平坦化（检验观测权重是否合适）
        if o.dump_logL, LOGL{si}(:, t) = logL(:); end   % EMB-01：落盘逐窗似然（只读，不改数值）
        tau_c = NaN;   % diag：本帧实际使用的可靠性温度（仅 lbp_temp_w>0 时非 NaN）
        if o.lbp_temp_w > 0 && ~isnan(a_lb)   % C：长时可靠性 → 自适应观测温度
            [~, imo] = max(ob.v); d_obs = abs(60 * fbc(imo) - a_lb);
            rel = exp(-(d_obs / 20)^2);
            Rrel = (1 - 1 / o.lbp_temp_win) * Rrel + (1 / o.lbp_temp_win) * rel;
            tau_c = o.lbp_temp_lo + (o.lbp_temp_hi - o.lbp_temp_lo) * Rrel;
            logL = tau_c * logL;
        end
        if strcmp(o.lbp_gate, 'soft')   % E1：软 LBP 门控（ds3.m 同语义：区间外乘 lbp_eps）
            mu_g = NaN;
            if numel(hist_g) >= o.lbp_hist_min, mu_g = mean(hist_g); end
            if ~isnan(mu_g)
                gv = o.lbp_eps * ones(1, K);
                gv(sb >= o.lbp_lo * mu_g & sb <= o.lbp_hi * mu_g) = 1;
                logL = logL + log(gv);
            end
        end
        if ~strcmp(o.q_feat, 'off')
            if strcmp(o.q_dir, 'inv'), s_t = o.sigma_lo + (o.sigma_hi - o.sigma_lo) * min(qn(t), 1); else, s_t = o.sigma_hi - (o.sigma_hi - o.sigma_lo) * min(qn(t), 1); end
            logT = log(makeT(s_t, o.jump_rho));
        elseif strcmp(o.rc_mode, 'gated') && brk(t)
            logT = log(makeT(o.sigma, o.rc_rho));
        else
            logT = logT0;
        end
        if o.lbp_prior_w > 0 && numel(hist_g) >= o.lbp_hist_min   % V2：吸引式长期先验（对下一状态的对角惩罚，逐帧累积）
            mu_p = mean(hist_g);
            logT = logT - o.lbp_prior_w * ((sb(:)' - mu_p).^2) / (2 * o.lbp_prior_sig^2);
        end
        if vhat ~= 0 && ~isempty(TS)   % M-LBP-V：转移核中心随速度前移（仅基础路径；q_feat/rc 分支不叠加）
            logT = TS{vhat + velK + 1};
        end
        if t == 1
            v = logL(:) + log(diag(makeT(o.sigma, o.jump_rho))); p = ones(K, 1);
        else
            Mx = vOld(:) + logT; [bv, bi] = max(Mx, [], 1); v = logL(:) + bv(:); p = bi(:);
        end
        vOld = v; ptr(:, t) = p;
        if t >= o.D
            [~, st] = max(vOld);
            for k = 1:o.D - 1, st = ptr(st, t - k + 1); end
            rb = sb(st);
            raw_g = rb; act_g = 0; mu_d = NaN; nbuf0 = numel(hist_g);   % T1：门控前输出/动作/决策时 μ/缓冲长度
            if strcmp(o.lbp_gate, 'hard')   % G1：输出替换式门控（参考实现的实际形态）
                mu_g = NaN;
                if nbuf0 >= o.lbp_hist_min, mu_g = mean(hist_g); end
                mu_d = mu_g;
                if ~isnan(mu_g) && (rb < o.lbp_lo * mu_g || rb > o.lbp_hi * mu_g)
                    rb = lastValid_g;       % 区间外：替换为上一接受值
                    act_g = 2;
                    if strcmp(o.lbp_buf_mode, 'append') && ~isnan(rb)
                        hist_g = [hist_g, rb];
                        if numel(hist_g) > o.lbp_hist_max, hist_g(1) = []; end
                    end
                else
                    lastValid_g = rb;       % 区间内：接受并写入历史
                    hist_g = [hist_g, rb];
                    if numel(hist_g) > o.lbp_hist_max, hist_g(1) = []; end
                    if ~isnan(mu_g), act_g = 1; end
                end
            elseif strcmp(o.lbp_gate, 'soft')
                if nbuf0 >= o.lbp_hist_min, mu_d = mean(hist_g); end
                if ~isnan(mu_d)
                    if rb < o.lbp_lo * mu_d || rb > o.lbp_hi * mu_d, act_g = 2; else, act_g = 1; end
                end
                hist_g = [hist_g, rb];
                if numel(hist_g) > o.lbp_hist_max, hist_g(1) = []; end
            elseif o.lbp_prior_w > 0 || o.lbp_cand_g > 0 || o.lbp_sel_g > 0 || o.lbp_temp_w > 0
                hist_g = [hist_g, rb];
                if numel(hist_g) > o.lbp_hist_max, hist_g(1) = []; end
            end
            if strcmp(o.lbp_gate, 'hard') && o.lbp_cf > 0   % V-CF：确认释放（越界持续 ≥ lbp_cf 窗 → 判定水平迁移）
                if ~isnan(mu_d) && (raw_g < o.lbp_lo * mu_d || raw_g > o.lbp_hi * mu_d)
                    cout = cout + 1;
                    if cout >= o.lbp_cf
                        rb = raw_g; act_g = 3;          % 恢复 raw（不替换），门控历史重置为空（随后休眠）
                        lastValid_g = raw_g;
                        hist_g = [];
                        cout = 0;
                    end
                else
                    cout = 0;
                end
            end
            if o.lbp_diag
                ev_i(end + 1) = t - o.D + 1; ev_mu(end + 1) = mu_d;      %#ok<AGROW>
                ev_raw(end + 1) = raw_g; ev_out(end + 1) = rb;           %#ok<AGROW>
                ev_act(end + 1) = act_g; ev_buf(end + 1) = nbuf0;        %#ok<AGROW>
                ev_tau(end + 1) = tau_c;                                  %#ok<AGROW>
            end
            rb_pre = rb;   % M-LBP-V：速度历史记录解码器自身输出（未补偿）
            if vhat ~= 0 && (strcmp(o.lbp_vel_use, 'lead') || strcmp(o.lbp_vel_use, 'both'))
                rb = rb + o.lbp_vel_lead * vhat;   % M-LBP-V：输出端滞后补偿（不写入速度历史）
            end
            est(t - o.D + 1) = rb;
            if o.lbp_vel_L >= 2
                veh = [veh, rb_pre];
                if numel(veh) > o.lbp_vel_L + 1, veh(1) = []; end
            end
        end
    end
    if strcmp(o.smooth_mode, 'median')
        es = movmedian(est, o.smooth_m);
    elseif strcmp(o.smooth_mode, 'wmedian')
        es = movmean(movmedian(est, max(3, round(o.smooth_m / 2))), o.smooth_m);
    else
        es = movmean(est, o.smooth_m);
    end
    es = es(:)';
    n2 = min([numel(gt), numel(es), numel(act)]);
    g = gt(1:n2); e = es(1:n2); av = act(1:n2);
    if strcmp(dataset, 'wesad')
        msk = ~isnan(e) & ~isnan(g) & av > 0 & av < 5 & g > 0;
        den = sum(~isnan(g) & av > 0 & av < 5);
    else
        msk = ~isnan(e) & ~isnan(g) & g > 0; den = sum(~isnan(g));
    end
    er = g(msk) - e(msk); ae = abs(er);
    mae(si) = mean(ae); rmse(si) = sqrt(mean(er.^2)); med(si) = median(ae);
    p95(si) = prctile(ae, 95); bias(si) = mean(er); gt10(si) = mean(ae > 10);
    cov(si) = sum(msk) / max(1, den);
    if sum(msk) > 2, cc = corrcoef(e(msk), g(msk)); pears(si) = cc(1, 2); end
    ALL{si} = est; ERR{si} = er; PR{si} = [e(msk); g(msk)];
    if o.lbp_diag
        evd = struct(); evd.idx = ev_i; evd.mu = ev_mu; evd.raw = ev_raw;
        evd.out = ev_out; evd.act = ev_act; evd.buf = ev_buf; evd.tau = ev_tau;
        DIAG{si} = evd;
        OBSK{si} = obs_pk;
        tk = struct(); tk.f = top_f; tk.v = top_v;
        TOPK{si} = tk;
    end
end
res.opt = o; res.subjects = subjects; res.mae = mae; res.rmse = rmse; res.med = med;
res.p95 = p95; res.bias = bias; res.gt10 = gt10; res.cov = cov; res.est = ALL;
res.pearson = pears; res.err = ERR; res.pairs = PR;
if o.lbp_diag, res.lbp_diag = DIAG; res.obs_pk = OBSK; res.obs_top = TOPK; end   % T1/diag：门控事件、观测峰与 top-3 峰（默认不返回，向后兼容）
if o.dump_logL, res.logL = LOGL; end   % EMB-01：逐窗观测似然（默认不返回，向后兼容）
res.mean = mean(mae, 'omitnan'); res.sd = std(mae, 'omitnan');
end

% ---- 观测构造（支持 ACC 曲线积分证据）----
function out = obs_vec(sp, ap, o, accI, varargin)
nb = numel(sp);
if strcmp(o.obs_mode, 'ls')
    Pyy = abs(sp).^2; Pnn = sum(abs(ap).^2, 1);
    aa = (Pyy * Pnn') / (Pnn * Pnn' + eps);
    H1 = max(0, (Pyy - aa * Pnn) ./ (Pyy + eps));
    ob = abs(sp) .* sqrt(H1);
    v = ob / (std(ob) + eps); out.v = v; return;
end
if strcmp(o.obs_mode, 'raw')
    out.v = abs(sp); return;
end
if numel(varargin) >= 2, W1h = varargin{1}; W2h = varargin{2}; else, W1h = []; W2h = []; end
w1 = abs(sp) / (max(abs(sp)) + eps);
W1h = [W1h; w1]; if size(W1h, 1) > o.WFlength, W1h(1, :) = []; end
W1n = mean(W1h, 1); W1n = W1n / (max(W1n) + eps);
accn = zeros(1, nb);
switch lower(o.acc_axes)
    case 'x', axt = 1;
    case 'y', axt = 2;
    case 'z', axt = 3;
    case 'pc1', axt = 0;          % 三轴第一主成分（逐窗去均值后 SVD）
    otherwise, axt = 1:3;         % 'sum'：论文口径
end
if axt == 0
    Xc = ap.'; Xc = Xc - mean(Xc, 1);
    [~, ~, V] = svd(Xc, 'econ');
    pc = (Xc * V(:, 1)).';        % 符号任意；下方取幅度
    accn = abs(pc) / (max(abs(pc)) + eps);
else
    for j = axt
        mv = max(abs(ap(j, :)));
        if o.acc_int_w > 0, accn = accn + accI / (max(accI) + eps); else, accn = accn + abs(ap(j, :)) / (mv + eps); end
    end
    accn = accn / numel(axt);
end
base = accn ./ (W1n + eps); switch o.wf_variant, case 'clip0', WF1 = max(0,1-base); case 'sharp', WF1 = max(0,1-base).^2; case 'soft', WF1 = 1./(1+base.^2); case 'soft3', WF1 = 1./(1+base.^3); case 'hard', WF1 = double(base<1); otherwise, WF1 = 1-base; WF1(WF1<0) = -1; end
c1 = abs(sp) .* WF1;
w2 = abs(sp) / (max(abs(sp)) + eps);
W2h = [W2h; w2]; if size(W2h, 1) > o.WFlength, W2h(1, :) = []; end
W2n = mean(W2h, 1); W2n = W2n / (max(W2n) + eps);
c2 = abs(sp) .* (W2n ./ (accn + W2n + eps));
c1 = c1 / (std(c1) + eps); c2 = c2 / (std(c2) + eps);
switch o.obs_mode, case 'wf1', out.v = c1; case 'wf2', out.v = c2; otherwise, out.v = c1 + c2; end
out.W1h = W1h; out.W2h = W2h;
end

function tm = norm_tm(sig, rho, K)
sb = linspace(1, K, K);
tm = exp(-((sb(:) - sb(:)').^2) / (2 * sig^2)); tm = tm ./ sum(tm, 2);
if rho > 0, tm = (1 - rho) * tm + rho / K; end
end

function tm = shift_tm(sig, rho, K, sh)
% M-LBP-V：中心前移 sh（BPM/窗）的转移核；行 = 当前状态，列 = 下一状态
sb = linspace(1, K, K);
d = sb(:)' - sb(:) - sh;                     % (next - current) - velocity
tm = exp(-(d.^2) / (2 * sig^2)); tm = tm ./ sum(tm, 2);
if rho > 0, tm = (1 - rho) * tm + rho / K; end
end

function P = ac_evidence(x, sb, fs)
x = x(:) - mean(x);
n = numel(x);
Xf = fft(x, 2 * n);
r = real(ifft(abs(Xf).^2)); r = r(1:n); r = r / (r(1) + eps);
lg = 60 * fs ./ sb; lg = min(max(lg, 1.05), n - 1.05);
P = interp1((1:n - 1)', r(2:end), lg, 'linear', 0); P = P(:)';
P = (P - min(P)) / (max(P) - min(P) + eps);
end

function o = d(o, f, v), if ~isfield(o, f), o.(f) = v; end, end
