function fig = lunar_power(cfg, geo, res)
%LUNAR_POWER Dynamic power of the three data centers over the simulated period.
%   Lunar base: house load, compute (busy work plus warm and parked GPUs),
%   cooling (radiator sink hotter in sunlight) and transmitter duty, against the
%   solar generation and battery state. Batch size chosen by the scheduler.
%   Relays: power drawn by the Thor modules against the budget left on the bus.
%   Earth: hourly price x PUE at each site and the site the scheduler picked.

ts = res.ts; th = geo.t/3600; d = th/24;
fig = figure('Name','Dynamic power of the three data centers','Color','w','Position',[60 40 1500 950]);
try, theme(fig,'light'); catch, end
tl = tiledlayout(fig,4,1,'TileSpacing','compact','Padding','compact');
title(tl, sprintf('Dynamic power: %s policy, %s, %d robots, %d relays', cfg.policy, geo.siteInfo.name, cfg.nRobots, cfg.nRelays), ...
    'FontWeight','bold');

% 1. Lunar base load by component
ax = nexttile(tl); hold(ax,'on');
top = 1.6*max(ts.baseKW);
yyaxis(ax,'left'); shade_dark(ax, d, geo.sunlit, top);
a = area(ax, d, [ts.pHouseKW; ts.pCompKW; ts.pCoolKW; ts.pTxKW]', 'LineStyle','none');
cols = [0.6 0.6 0.6; 0.20 0.62 0.32; 0.30 0.70 0.90; 0.95 0.65 0.20];
for k = 1:4, a(k).FaceColor = cols(k,:); end
ylabel(ax,'kW'); ylim(ax,[0 top]);
yyaxis(ax,'right'); hb = plot(ax, d, 100*ts.soc, 'k-', 'LineWidth',1); ylabel(ax,'battery, %'); ylim(ax,[0 110]);
ax.YAxis(2).Color = 'k'; grid(ax,'on'); xlim(ax,[0 d(end)]);
legend(ax, [a(:)' hb], {'house','compute','cooling','transmitter','battery charge'}, 'Location','southwest','NumColumns',5);
title(ax, sprintf(['Lunar base: %.2f kW average, %.1f kW peak, %.0f kW solar array  ' ...
    '(grey = ridge in shadow: robots park, the battery carries the base)'], mean(ts.baseKW), max(ts.baseKW), res.arrayKW));

% 2. Utilisation and batch
ax = nexttile(tl); hold(ax,'on');
yyaxis(ax,'left'); plot(ax, d, 100*ts.util, 'LineWidth',1); ylabel(ax,'GPU busy, %');
act = ts.batchPer; act(~geo.sunlit) = NaN; tb = ts.batchTacE; tb(~geo.sunlit) = NaN;
yyaxis(ax,'right'); stairs(ax, d, act, 'LineWidth',1); stairs(ax, d, tb, '--', 'LineWidth',1);
ylabel(ax,'batch size'); ylim(ax,[0 1.3*max([act tb],[],'omitnan')]);
grid(ax,'on'); xlim(ax,[0 d(end)]);
legend(ax, {'base GPUs busy','perception batch','tactical batch (base)'}, 'Location','northeast','NumColumns',3);
j1 = res.batchTables.perBase.J(1);
title(ax, sprintf(['Deadline-aware batching: perception %.0f J/frame at batch %.0f vs %.0f J unbatched; ' ...
    'busy peaks = tactical falls back to the base when the Earth link is out'], ...
    mean(ts.jPer(geo.sunlit)), mean(act,'omitnan'), j1));

% 3. Relays
ax = nexttile(tl); hold(ax,'on');
yyaxis(ax,'left');
h1 = plot(ax, d, ts.relayBudgetW, '-', 'Color',[0.75 0.65 0.95], 'LineWidth',1);
h2 = area(ax, d, ts.relayW, 'FaceColor',[0.6 0.4 0.9], 'LineStyle','none');
ylabel(ax,'W'); ylim(ax,[0 1.3*max([ts.relayBudgetW 1])]);
yyaxis(ax,'right'); h3 = plot(ax, d, 100*ts.relayLinkUse, 'Color',[0.2 0.2 0.2 0.6], 'LineWidth',0.8);
ylabel(ax,'relay Ka link used, %'); ylim(ax,[0 130]); ax.YAxis(2).Color = 'k';
grid(ax,'on'); xlim(ax,[0 d(end)]);
legend(ax, [h1 h2 h3], {'compute budget left on the bus','Thor power drawn','explorer link to Earth used'}, 'Location','northeast','NumColumns',3);
if max(ts.relayW) > 0
    tt = sprintf('Lunar constellation: %.0f W average, %.0f W peak; Thors wake only when the link cannot carry the work', mean(ts.relayW), max(ts.relayW));
else
    tt = 'Lunar constellation: Thors stay parked, the relay link to Earth had room for every explorer request';
end
title(ax, tt);

% 4. Earth sites
ax = nexttile(tl); hold(ax,'on');
nS = numel(cfg.earthSites); P = zeros(nS, numel(th));
for i = 1:numel(th), [pr, pu] = earth_sites(cfg, th(i)); P(:,i) = 1e3*pr.*pu; end
sc = [0.30 0.50 0.90; 0.85 0.33 0.10; 0.47 0.67 0.19];
for k = 1:nS, plot(ax, d, P(k,:), 'Color', sc(k,:), 'LineWidth',1); end
pick = 1e3*ts.earthPrice.*ts.earthPUE; use = ts.earthJ > 0;
scatter(ax, d(use), pick(use), 6, sc(ts.earthSite(use),:), 'filled');
ylabel(ax,'$/MWh x PUE'); xlabel(ax,'day'); grid(ax,'on'); xlim(ax,[0 d(end)]);
share = accumarray(ts.earthSite(use)', ts.earthJ(use)', [nS 1])/max(sum(ts.earthJ),eps);
legend(ax, [arrayfun(@(k) sprintf('%s (%.0f%% of Earth energy)', cfg.earthSites(k).name, 100*share(k)), 1:nS, 'Uni',0) {'site chosen'}], ...
    'Location','northeast','NumColumns',4);
title(ax, sprintf('Earth: work follows the cheapest site each hour  (%.0f kWh, $%.0f, %.0f kg CO2 over %g days)', ...
    res.earthKWh, res.earthUSD, res.earthCO2kg, cfg.days));
end

function shade_dark(ax, d, sunlit, top)
dk = ~sunlit(:)'; if ~any(dk), return; end
e = diff([0 dk 0]); s = find(e == 1); f = find(e == -1) - 1;
for k = 1:numel(s)
    patch(ax, d([s(k) f(k) f(k) s(k)]), [0 0 top top], [0.85 0.85 0.85], 'EdgeColor','none', ...
        'HandleVisibility','off');
end
end
