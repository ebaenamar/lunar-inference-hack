function fig = lunar_dashboard(cfg, geo, res, eco)
%LUNAR_DASHBOARD Static summary of one scenario: geometry, power, placement, KPIs.

td = geo.t'/86400;
ts = res.ts;
fig = figure('Name','Lunar inference dashboard','Color','w','Position',[60 60 1400 820]);
try, theme(fig,'light'); catch, end
tl = tiledlayout(fig,4,2,'TileSpacing','compact','Padding','compact');
title(tl, sprintf('%s | %d robots | base: %s | %s | policy: %s', geo.siteInfo.name, ...
      cfg.nRobots, res.baseH.name, cfg.power, cfg.policy), 'FontWeight','bold');

% 1. Link to Earth and relays
nexttile(tl,1);
area(td, geo.linkMbps, 'FaceColor',[0.30 0.55 0.85], 'EdgeColor','none'); hold on;
plot(td, sum(geo.satVis,1)*10, 'k-', 'LineWidth',0.8);
ylabel('Mbps'); title('Link to Earth (area) and LCRNS relays in view x10 (line)');
xlim([0 cfg.days]); grid on;

% 2. Sun and power
nexttile(tl,2);
yyaxis left; area(td, double(geo.sunlit), 'FaceColor',[1 0.85 0.3],'EdgeColor','none','FaceAlpha',0.5);
ylabel('sunlit'); ylim([0 1.2]);
if ~strcmp(cfg.power,'Fission')
    yyaxis right; plot(td, ts.soc*100, 'LineWidth',1.2); ylabel('battery %'); ylim([0 105]);
end
title(sprintf('Illumination %.0f%%  |  base uptime %.0f%%', 100*geo.illumFrac, 100*res.baseUptime));
xlim([0 cfg.days]); grid on;

% 3. Where perception runs
nexttile(tl,3);
P = [ts.perBase; ts.perBoard; ts.perEarth; ts.perMiss]'/cfg.dt;
ar = area(td, P, 'EdgeColor','none');
set(ar(1),'FaceColor',[0.20 0.60 0.30]); set(ar(2),'FaceColor',[0.95 0.65 0.20]);
set(ar(3),'FaceColor',[0.30 0.45 0.85]); set(ar(4),'FaceColor',[0.85 0.25 0.25]);
legend({'base','on board','Earth','missed'},'Location','eastoutside'); ylabel('req/s');
title(sprintf('Perception (deadline %.1f s): %.1f%% on time', cfg.perceptionDeadline, 100*res.perOnTime));
xlim([0 cfg.days]); grid on;

% 4. Where planning runs
nexttile(tl,4);
L = [ts.planBase; ts.planEarth; ts.planMiss]'/cfg.dt*3600;
ar = area(td, L, 'EdgeColor','none');
set(ar(1),'FaceColor',[0.20 0.60 0.30]); set(ar(2),'FaceColor',[0.30 0.45 0.85]); set(ar(3),'FaceColor',[0.85 0.25 0.25]);
legend({['base (' res.planBaseName ')'],'Earth (Kimi K3)','missed'},'Location','eastoutside'); ylabel('req/h');
title(sprintf('Planning (deadline %d s): %.1f%% on time', cfg.planDeadline, 100*res.planOnTime));
xlim([0 cfg.days]); grid on;

% 5. Base power
nexttile(tl,5);
plot(td, ts.genKW, 'Color',[0.9 0.6 0.1]); hold on; plot(td, ts.baseKW, 'k', 'LineWidth',1);
ylabel('kW'); legend({'generation','base load'},'Location','eastoutside');
title(sprintf('Base: peak %.1f kW, average %.1f kW', res.PmaxKW, res.baseAvgKW));
xlim([0 cfg.days]); grid on;

% 6. Science data
nexttile(tl,6);
plot(td, ts.backlogMB/1e3, 'LineWidth',1.2); ylabel('backlog GB');
title(sprintf('Science return: %.0f%% of the planned volume delivered', 100*res.sciDelivered));
xlim([0 cfg.days]); grid on; xlabel('days');

% 7-8. KPI panel
ax = nexttile(tl,7,[1 2]); axis(ax,'off');
c = res.cost;
lines = {
 sprintf('Per request   vision-language 7B: base %.0f J / %.3f s | on board (Thor) %.0f J / %.2f s | Earth: %.2f s + 2.56 s RTT', ...
         c.perBase.energyJ, c.perBase.latency, c.perBoard.energyJ, c.perBoard.latency, c.perEarth.latency)
 sprintf('              planner: base %s %.2f kJ / %.1f s | Earth Kimi K3 %.2f kJ / %.1f s | Kimi K3 fits at base: %s', ...
         res.planBaseName, c.planBase.energyJ/1e3, c.planBase.latency, c.planEarth.energyJ/1e3, c.planEarth.latency, mat2str(c.K3Base.fits))
 sprintf('Energy        base %.0f kWh  |  Earth %.0f kWh  |  robots on board %.0f kWh  (over %d days)', ...
         res.baseKWh, res.earthKWh, res.boardKWh, cfg.days)
 sprintf('Mass to Moon  %.0f kg  (compute %.0f, power %.0f, battery %.0f, radiators %.0f)', ...
         eco.mass.total, eco.mass.compute, eco.mass.power, eco.mass.battery, eco.mass.radiators)
 sprintf('Cost          launch at %s ($%s/kg): $%.1f M  |  lunar energy $%.2f/kWh vs Earth $%.2f/kWh', ...
         cfg.launchPrice, num2str(eco.usdPerKg), eco.launchUSD/1e6, eco.moonUSDperKWh, eco.earthUSDperKWh)
 };
text(ax, 0, 0.9, lines, 'FontName','Menlo','FontSize',10,'VerticalAlignment','top','Interpreter','none');
end
