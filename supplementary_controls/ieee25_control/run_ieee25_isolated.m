function run_ieee25_isolated()
% CB-IEEE25-20261004 generated runner; the Python driver is the source of truth.
nb=getenv('CB25_NEW'); md=getenv('CB25_MD'); dt=getenv('CB25_DATA'); xt=getenv('CB25_EXT');
assert(~isempty(nb)&&~isempty(md)&&~isempty(dt),'CB25_NEW/CB25_MD/CB25_DATA must be set');
if strcmp(xt,'1'), addpath(md,'-end'); end   % original method_dev appended; never shadows nb
addpath(nb); cd(nb);
assert(~isfile(fullfile(nb,'results.json')),'results.json exists: refusing to overwrite');
assert(exist(fullfile(nb,'cache25'),'dir')==7,'cache25 dir missing');
fprintf('PROBE new_dir = %s\n',nb); fprintf('PROBE method_dev_read_only = %s\n',md); fprintf('PROBE data = %s\n',dt);
fprintf('PROBE which ds5 = %s\n',which('ds5')); fprintf('PROBE which prep_ieee25 = %s\n',which('prep_ieee25'));
fprintf('PROBE cache = %s | helper_path_appended = %d\n',fullfile(nb,'cache25'),strcmp(xt,'1'));
assert(startsWith(which('ds5'),nb),'ds5 must resolve to the copied file in the new dir');
assert(startsWith(which('prep_ieee25'),nb),'prep_ieee25 must resolve inside the new dir');
v=load(fullfile(md,'results','a2_core.mat'),'o','res'); o=v.o; o.cachedir='cache25';   % only option change
b125=v.res.ieee.ALL23.mae(:); assert(numel(b125)==23 && all(isfinite(b125)),'saved baseline vector invalid');
fprintf('BASELINE label = 125-Hz saved cache2 via a2_core.mat (read-only), mean = %.12f\n',mean(b125));
fprintf('BASELINE ref check |mean-6.765860267452| = %.3e (informational only)\n',abs(mean(b125)-6.765860267452));
prep_ieee25(); NW=zeros(1,23); SID=cell(1,23);
for s=1:23
  O=load(fullfile(md,'cache2',sprintf('ieee_S%d.mat',s)));   % read-only
  N=load(fullfile(nb,'cache25',sprintf('ieee_S%d.mat',s)));
  assert(O.nWin==N.nWin,sprintf('S%d nWin %d vs saved %d',s,N.nWin,O.nWin));
  assert(isequal(O.gt,N.gt),sprintf('S%d gt differs from the saved cache',s));
  assert(numel(N.gt)==N.nWin && all(isfinite(N.gt)),sprintf('S%d gt length/non-finite',s));
  assert(strcmp(N.sid,O.sid),sprintf('S%d sid %s vs saved %s',s,N.sid,O.sid));
  assert(isequal(size(N.X),[N.nWin 200]),sprintf('S%d X is not nWin x 200',s));
  assert(isequal(size(N.Xa),[N.nWin 200 3]),sprintf('S%d Xa is not nWin x 200 x 3',s));
  assert(isequal(size(N.S),[N.nWin 513]) && isequal(size(N.A),[N.nWin 513 3]),sprintf('S%d S/A shape',s));
  assert(isequal(N.fb,(0:512)*25/1024),sprintf('S%d fb is not fsd/1024 spaced',s));
  assert(N.fs_in==125 && N.fsd==25,sprintf('S%d fs tags',s));
  NW(s)=N.nWin; SID{s}=N.sid;
  fprintf('GUARD S%-2d %-18s nWin=%4d gt=[%.1f %.1f] exact\n',s,N.sid,N.nWin,min(N.gt),max(N.gt));
end
fprintf('GUARD 23/23 exact: nWin, gt, sid, X200, Xa200x3, hop50, fb=fsd/1024, fs tags, record order\n');
M=load(fullfile(nb,'cache25','ieee_meta.mat')); r=ds5('ieee',1:23,o);
assert(numel(r.mae)==23,'ds5 did not return 23 records'); per=struct();
for s=1:23
  e=r.est{s}; nv=NW(s)-o.D+1;   % ds5 allocates est=nan(1,nWin) and fills the first nWin-D+1 slots
  assert(numel(e)==NW(s),sprintf('S%d raw est length %d vs nWin %d',s,numel(e),NW(s)));
  assert(all(isfinite(e(1:nv))),sprintf('S%d est prefix 1..%d not all finite',s,nv));
  assert(all(isnan(e(nv+1:end))),sprintf('S%d est tail %d..%d is not an all-NaN D-1 tail',s,nv+1,NW(s)));
  pr=r.pairs{s}; er=r.err{s};
  assert(all(isfinite(pr(:))) && all(isfinite(er(:))),sprintf('S%d pairs/err not all finite',s));
  assert(isequal(size(pr),[2 numel(er)]),sprintf('S%d pairs 2x%d vs err %d',s,size(pr,2),numel(er)));
  assert(max(abs(er(:)-(pr(2,:)-pr(1,:)).'))<=1e-9,sprintf('S%d err != pair row2 - row1',s));
  mf=[r.mae(s) r.rmse(s) r.med(s) r.p95(s) r.cov(s) r.bias(s) r.gt10(s)];
  assert(all(isfinite(mf)),sprintf('S%d required metric not finite',s));
  per(s).index=s; per(s).sid=SID{s}; per(s).nWin=NW(s); per(s).isTest=M.isTest(s);
  per(s).n_raw_slots=numel(e); per(s).n_raw_valid=nv; per(s).n_nan_tail=numel(e)-nv;
  per(s).n_pairs=numel(er); per(s).pearson_25hz=r.pearson(s);
  per(s).mae_25hz=r.mae(s); per(s).mae_125hz=b125(s); per(s).delta_25minus125=r.mae(s)-b125(s);
  per(s).rmse_25hz=r.rmse(s); per(s).med_25hz=r.med(s); per(s).p95_25hz=r.p95(s); per(s).cov_25hz=r.cov(s);
  per(s).bias_25hz=r.bias(s); per(s).frac_gt10_25hz=r.gt10(s);
  per(s).est=e; per(s).pairs_est_gt=pr; per(s).err_gt_minus_est=er;
end
sets={'ALL23',1:23;'TRAIN12_reported',1:12;'TEST11_reported',13:23}; sp=struct();
for i=1:size(sets,1)
  q=sets{i,2};
  sp.(sets{i,1})=struct('n',numel(q),'indices',q,'mae_mean_25hz',mean(r.mae(q)),'mae_sd_25hz',std(r.mae(q)), ...
    'mae_mean_125hz',mean(b125(q)),'mae_sd_125hz',std(b125(q)),'delta_mean_25minus125',mean(r.mae(q))-mean(b125(q)), ...
    'rmse_mean_25hz',mean(r.rmse(q)),'med_mean_25hz',mean(r.med(q)),'p95_mean_25hz',mean(r.p95(q)),'cov_mean_25hz',mean(r.cov(q)), ...
    'per_record_mae_25hz',r.mae(q),'per_record_mae_125hz',b125(q));
end
out=struct(); out.contract='CB-IEEE25-20261004'; out.status='EXECUTED_PENDING_ASTRA_REVIEW';
out.purpose='IEEE SPC 25-Hz isolated control: integer 5x decimation in the front end only; filter/tracking unchanged';
out.sampling=struct('native_fs_hz',125,'decimation',5,'cache_fs_hz',25,'window_samples',200,'window_seconds',8,'hop_samples',50, ...
  'hop_seconds',2,'fft_length',1024,'fft_bins_kept',513,'bin_spacing_hz',25/1024,'native_bandpass_hz',[0.4 4], ...
  'filter','4th-order Butterworth causal filter() before decimation','nWin_total',sum(NW), ...
  'spectrum','S=fft(x,1024) on the 200-sample 25-Hz window; bins 1..513 kept (0..12.5 Hz)');
out.new_dir=nb; out.cache_dir=fullfile(nb,'cache25'); out.method_dev_read_only=md;
out.baseline_label='125-Hz saved cache2 via results/a2_core.mat res.ieee.ALL23.mae (read-only)';
out.baseline_reference_mean=6.765860267452; out.baseline_saved_mean=v.res.ieee.ALL23.mean;
out.baseline_reference_check_absdiff=abs(mean(b125)-6.765860267452);
out.split_note='saved isTest (idnb>13 => S14..S23) differs from the reported TRAIN12/TEST11 = S1..S12 / S13..S23; recorded only, not changed here';
out.id_list=M.ID; out.isTest=M.isTest; out.per_record=per; out.splits=sp;
out.macro=struct('n',23,'mae_mean_25hz',r.mean,'mae_sd_25hz',r.sd,'mae_mean_125hz',mean(b125),'mae_sd_125hz',std(b125),'delta_mean_25minus125',r.mean-mean(b125));
out.notes={'descriptive only: no significance test, no tuning, no prior change, no best-of-N selection', ...
  'jsonencode maps NaN/Inf to null (e.g. pearson when undefined)', ...
  'mae_125hz per record is the exactly loaded saved vector, not the external reference mean'};
fid=fopen(fullfile(nb,'results.json'),'w'); assert(fid>=0); fprintf(fid,'%s',jsonencode(out)); fclose(fid);
save(fullfile(nb,'ieee25_results.mat'),'r','o','-v7.3');
fprintf('RESULT ALL23 MAE 25Hz = %.6f | 125Hz = %.6f | delta(25-125) = %+.6f\n',r.mean,mean(b125),r.mean-mean(b125));
fprintf('SAVED results.json + ieee25_results.mat in %s\n',nb); end
