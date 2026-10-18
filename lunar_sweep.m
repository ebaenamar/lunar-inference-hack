function S = lunar_sweep(cfg, geo, C)
%LUNAR_SWEEP Service and cost versus fleet size for the three policies.
%   Shows where each tier pays off: the base for perception, the relay
%   constellation for tactical reasoning away from the base, Earth for deep
%   reasoning with the superior model at the cheapest energy.

Ns = [1 2 5 10 20 50 100 200 500 1000];
pols = {'EarthOnly','BaseOnly','Hierarchical','Coordinated'};
S.Ns = Ns; S.pols = pols;
z = zeros(numel(pols),numel(Ns));
S.per = z; S.tac = z; S.deepK3 = z; S.sci = z; S.usd = z;
for p = 1:numel(pols)
    for j = 1:numel(Ns)
        c = cfg; c.policy = pols{p}; c.nRobots = Ns(j);
        r = lunar_dispatch(c, geo, C); e = lunar_economics(c, r);
        S.per(p,j) = r.perOnTime; S.tac(p,j) = r.tacOnTime;
        S.deepK3(p,j) = r.deepOnTime*r.deepSuperior; S.sci(p,j) = r.sciDelivered;
        S.usd(p,j) = e.thinkUSDperDay/max(Ns(j),1);   % $ per robot-day
    end
end

fig = figure('Name','Tiers vs fleet size','Color','w','Position',[80 80 1500 430]);
try, theme(fig,'light'); catch, end
tl = tiledlayout(fig,1,5,'TileSpacing','compact');
title(tl, sprintf('%s | %d relays | base %s | %s | %.0f%% of robots exploring', geo.siteInfo.name, ...
      cfg.nRelays, cfg.baseHW, cfg.power, 100*cfg.fracExploring), 'FontWeight','bold');
mk = {'-o','--s','-^','-d'}; lw = [1.5 2.5 2 3];
col = [0.30 0.50 0.90; 0.20 0.62 0.32; 0.55 0.35 0.85; 0.95 0.55 0.10];
panels = {S.per, S.tac, S.deepK3, S.sci, S.usd};
ttl = {sprintf('Perception on time (%.1f s)', cfg.perceptionDeadline), ...
       sprintf('Tactical on time (%d s)', cfg.tacticalDeadline), ...
       'Deep reasoning answered by Kimi K3', 'Science returned to Earth', ...
       sprintf('Thinking energy cost, $/robot-day (%s)', cfg.launchPrice)};
for k = 1:5
    nexttile(tl); hold on;
    for p = 1:numel(pols)
        y = panels{k}(p,:); if k < 5, y = 100*y; end
        plot(Ns, y, mk{p}, 'Color',col(p,:), 'LineWidth',lw(p), 'MarkerSize',6, 'MarkerFaceColor','w');
    end
    set(gca,'XScale','log'); grid on; xlabel('robots'); title(ttl{k});
    if k < 5, ylim([0 105]); ylabel('%'); else, ylim([0 1.1*max(S.usd(:))]); ylabel('$ per robot-day'); end
    if k == 1, legend(pols,'Location','southwest'); end
end
end
