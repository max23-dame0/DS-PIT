function exp_a2_heatmap_plot()
mdir = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(mdir)));
S = load(fullfile(mdir,'results','a2_heatmap.mat'));
M = S.M; N = S.N; bn = S.bandNames; nm = S.nm; tot = S.tot;
fprintf('pooled MAE %.4f, cells %d\n', tot, sum(~isnan(M(:))));
% palette
% 色标模式：blue（默认，与 Fig.2/4 同族）| turbo | parula（鲜艳备选，供对比）
cmap_mode = getenv('HEATMAP_CMAP'); if isempty(cmap_mode), cmap_mode = 'blue'; end
sfx = '';
switch cmap_mode
    case 'turbo',  cm = turbo(256);  sfx = '_turbo';
    case 'parula', cm = parula(256); sfx = '_parula';
    otherwise
        % 蓝色族顺序色标：末端对齐色号契约的 #0000FF（我们的方法），整条偏亮
        anc = [0.00 0.960 0.972 1.000; 0.20 0.847 0.878 1.000;
               0.40 0.702 0.753 1.000; 0.60 0.502 0.573 1.000;
               0.80 0.251 0.341 1.000; 1.00 0.000 0.000 1.000];
        cm = interp1(anc(:,1), anc(:,2:4), linspace(0,1,256)');
end

% 色阶上限收到 15：多数格子落在 2-8 BPM，原 0-20 窗口把低端辨色力浪费掉
vmax = 15;  Mv = min(max(M,0),vmax);
idx = max(1, min(256, round(Mv/vmax*255)+1));
rgb = reshape(cm(idx,:), size(M,1), size(M,2), 3);
lum = 0.2126*rgb(:,:,1) + 0.7152*rgb(:,:,2) + 0.0722*rgb(:,:,3);

fig = figure('Units','inches','Position',[0 0 3.5 3.9],'Color','w');
ax = axes(fig); hold(ax,'on');
image(ax, [1 6], [1 9], rgb); set(ax,'YDir','reverse');
gray = [0.90 0.90 0.90];
for k = 1:9
  for b = 1:6
    if isnan(M(k,b))
      rectangle(ax,'Position',[b-0.5 k-0.5 1 1],'FaceColor',gray,'EdgeColor','w');
      text(ax,b,k,'n/a','HorizontalAlignment','center','FontSize',5.5,'Color',[0.55 0.55 0.55]);
    else
      if lum(k,b) < 0.58, tc = [1 1 1]; else, tc = [0.10 0.12 0.16]; end
      text(ax,b,k-0.16,sprintf('%.1f',M(k,b)),'HorizontalAlign','center','FontSize',6.2,'Color',tc);
      text(ax,b,k+0.26,sprintf('%d',N(k,b)),'HorizontalAlign','center','FontSize',4.6,'Color',tc);
    end
  end
end
set(ax,'XLim',[0.5 6.5],'YLim',[0.5 9.5],'FontSize',6.5,'TickLength',[0 0]);
set(ax,'XTick',1:6,'XTickLabel',bn,'YTick',1:9,'YTickLabel',nm);
xlabel(ax,'Reference HR band (BPM)','FontSize',7);
title(ax,'PPG-DaLiA: MAE by activity and HR band','FontSize',7.5);
box(ax,'on'); set(ax,'LineWidth',0.5);
cb = colorbar(ax); colormap(ax,cm); caxis(ax,[0 vmax]);
cb.Label.String = 'MAE (BPM)'; cb.Label.FontSize = 6.5; set(cb,'FontSize',6);
out = fullfile(root,'figures',['Error_Heatmap_DSPIT_A2' sfx '.pdf']);   % root 已是仓库根
exportgraphics(fig,out,'ContentType','vector','BackgroundColor','white');
fprintf('[saved] %s\n',out);
end