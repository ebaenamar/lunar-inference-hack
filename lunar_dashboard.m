function fig = lunar_dashboard(cfg, geo, res, eco)
%LUNAR_DASHBOARD Summary of one scenario by cognitive tier.

td = geo.t'/86400; ts = res.ts; c = res.cost;
G = [0.20 0.62 0.32]; R = [0.55 0.35 0.85]; E = [0.30 0.50 0.90]; X = [0.88 0.28 0.28]; O = [0.95 0.65 0.20];
fig = figure('Name','Lunar inference dashboard','Color','w','Position',[60 40 1450 900]);
try, theme(fig,'light'); catch, end
tl = tiledlayout(fig,4,2,'TileSpacing','compact','Padding','compact');
title(tl, sprintf('%s | %d robots (%.0f%% exploring) | %d relays | base %s | %s | policy %s', geo.siteInfo.name, ...
      cfg.nRobots, 100*cfg.fracExploring, cfg.nRelays, res.baseH.name, cfg.power, cfg.policy), 'FontWeight','bold');

nexttile(tl,1);
area(td, geo.linkMbps, 'FaceColor',E, 'EdgeColor','none','FaceAlpha',0.6); hold on;
stairs(td, 10*sum(geo.expVis & geo.satSun,1), 'Color',R, 'LineWidth',1);
ylabel('Mbps / relays x10'); xlim([0 cfg.days]); grid on;
title('Base link to Earth (area) and relays able to compute for explorers x10 (line)');

nexttile(tl,2);
area(td, double(geo.sunlit), 'FaceColor',[1 0.85 0.3],'EdgeColor','none','FaceAlpha',0.45); hold on;
if ~strcmp(cfg.power,'Fission'), plot(td, ts.soc, 'Color',O, 'LineWidth',1.2); end
ylim([0 1.1]); xlim([0 cfg.days]); grid on; ylabel('sunlit / battery');
title(sprintf('Illumination %.0f%% | base uptime %.0f%% | base avg %.1f kW', 100*geo.illumFrac, 100*res.baseUptime, res.baseAvgKW));

nexttile(tl,3);
ar = area(td, [ts.tacBoard; ts.tacBase; ts.tacRelay; ts.tacEarth; ts.tacMiss]'/cfg.dt*3600, 'EdgeColor','none');
set(ar(1),'FaceColor',O); set(ar(2),'FaceColor',G); set(ar(3),'FaceColor',R); set(ar(4),'FaceColor',E); set(ar(5),'FaceColor',X);
legend({'on board (3B, cascade)','lunar base','relay constellation','Earth','missed'},'Location','eastoutside');
ylabel('req/h'); xlim([0 cfg.days]); grid on;
title(sprintf('Tactical reasoning (30B-A3B + images, %d s): %.1f%% on time', cfg.tacticalDeadline, 100*res.tacOnTime));

nexttile(tl,4);
ar = area(td, [ts.deepEarth; ts.deepBase; ts.deepMiss]'/cfg.dt*3600, 'EdgeColor','none');
set(ar(1),'FaceColor',E); set(ar(2),'FaceColor',G); set(ar(3),'FaceColor',X); hold on;
plot(td, ts.deepQueue, 'k:', 'LineWidth',1);
legend({'Earth (Kimi K3)',['base (' res.deepBaseName ')'],'missed','queued'},'Location','eastoutside');
ylabel('req/h, queue'); xlim([0 cfg.days]); grid on;
title(sprintf('Deep reasoning (deadline %.0f min): %.1f%% on time, %.0f%% by Kimi K3', cfg.deepDeadline/60, 100*res.deepOnTime, 100*res.deepSuperior));

nexttile(tl,5);
ar = area(td, [ts.perBase; ts.perEarth; ts.perMiss]'/cfg.dt, 'EdgeColor','none');
set(ar(1),'FaceColor',G); set(ar(2),'FaceColor',E); set(ar(3),'FaceColor',[0.8 0.8 0.8]);
legend({'lunar base','Earth','missed'},'Location','eastoutside');
ylabel('req/s'); xlim([0 cfg.days]); grid on;
title(sprintf('Perception for robots in the base cell (7B, %.1f s): %.1f%% on time', cfg.perceptionDeadline, 100*res.perOnTime));

nexttile(tl,6);
plot(td, ts.backlogMB/1e3, 'Color',E, 'LineWidth',1.2); ylabel('backlog GB'); xlabel('days');
xlim([0 cfg.days]); grid on;
title(sprintf('Science return: %.0f%% of the planned volume delivered', 100*res.sciDelivered));

ax = nexttile(tl,7,[1 2]); axis(ax,'off');
L = {
 sprintf('Per request  perception 7B : base %.0f J %.3f s | on board (Orin NX) %.2f s | Earth %.2f s + 2.56 s RTT', ...
     c.perBase.energyJ, c.perBase.latency, c.perBoard.latency, c.perEarth.latency)
 sprintf('             tactical 30B  : base %.0f J %.2f s | relay node (Thor) %.0f J %.1f s | Earth %.0f J %.2f s + 2.56 s | on board fits: %s', ...
     c.tacBase.energyJ, c.tacBase.latency, c.tacRelay.energyJ, c.tacRelay.latency, c.tacEarth.energyJ, c.tacEarth.latency, mat2str(c.tacBoard.fits))
 sprintf('             deep reasoning: Earth Kimi K3 %.1f kJ %.0f s | base %s %.1f kJ %.1f s', ...
     c.deepEarth.energyJ/1e3, c.deepEarth.latency, res.deepBaseName, c.deepBase.energyJ/1e3, c.deepBase.latency)
 sprintf('Energy cost  base $%.0f/kWh -> $%.0f/day | relays $%.0f/kWh -> $%.0f/day | Earth $%.2f/kWh -> $%.1f/day   (launch: %s)', ...
     eco.moonUSDperKWh, eco.moonUSDperDay, eco.relayUSDperKWh, eco.relayUSDperDay, eco.earthUSDperKWh, eco.earthUSDperDay, cfg.launchPrice)
 sprintf('Thinking cost  robot $%.0f | relays $%.0f | base $%.0f | Earth $%.2f  per day  (marginal energy x tier $/kWh)', eco.tierUSDperDay)
 sprintf('Mass to Moon base %.0f kg (compute %.0f, power %.0f, battery %.0f, radiators %.0f) | relay edge nodes %.0f kg', ...
     eco.mass.total, eco.mass.compute, eco.mass.power, eco.mass.battery, eco.mass.radiators, eco.relayMassKg)
 };
text(ax, 0, 0.95, L, 'FontName','Menlo','FontSize',10,'VerticalAlignment','top','Interpreter','none');
end
