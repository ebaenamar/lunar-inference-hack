function fig = lunar_power(cfg, geo, res, win)
%LUNAR_POWER Dynamic power of the three data centers.
%   Top: the power of the lunar base, the relay constellation and the Earth data
%   center over the whole run (log scale), with the dark spell shaded.
%   Below, a zoom window (default days 4-7) shows what drives the power:
%   operator shifts, hazard bursts and link gaps; the base load split into
%   house, idle GPUs, useful work, cooling and transmitter; the batch the
%   scheduler picks; the relay power budget; and the Earth site chosen each hour.

if nargin < 4, win = [4 7]; end
cfg = earth_tier(cfg);
ts = res.ts; th = geo.t(:)'/3600; d = th/24;
w = d >= win(1) & d <= win(2);
fig = figure('Name','Dynamic power of the three data centers','Color','w','Position',[50 30 1550 1000]);
try, theme(fig,'light'); catch, end
tl = tiledlayout(fig,4,2,'TileSpacing','compact','Padding','compact');
title(tl, sprintf('Dynamic power of the fleet: %s policy, %s, %d robots, %d relay(s)', ...
    cfg.policy, geo.siteInfo.name, cfg.nRobots, cfg.nRelays), 'FontWeight','bold','FontSize',13);
cB = [0.20 0.62 0.32]; cR = [0.60 0.40 0.90]; cE = [0.30 0.50 0.90];

% ---------- 1. Three data centers, whole run
ax = nexttile(tl,[1 2]); hold(ax,'on');
pB = ts.baseKW; pR = ts.relayW/1000; pE = ts.earthJ/cfg.dt/1000;
lo = 0.3; hi = 1.5*max([pB pE]);
nz = @(x) x./(x > 0);                          % no line where a data center draws nothing
shade(ax, d, ~geo.sunlit, lo, hi, [0.85 0.85 0.85]);
patch(ax, [win(1) win(2) win(2) win(1)], [lo lo hi hi], [1 0.93 0.6], 'FaceAlpha',0.35, 'EdgeColor','none','HandleVisibility','off');
h1 = plot(ax, d, nz(pB), 'Color',cB, 'LineWidth',1.2);
h2 = plot(ax, d, nz(pR), 'Color',cR, 'LineWidth',1.0);
h3 = plot(ax, d, nz(pE), 'Color',cE, 'LineWidth',0.8);
set(ax,'YScale','log'); ylim(ax,[lo hi]); xlim(ax,[0 d(end)]); grid(ax,'on'); ylabel(ax,'kW');
legend(ax, [h1 h2 h3], {sprintf('lunar base (%.2f kW avg)', mean(pB)), ...
    sprintf('relay constellation (%.0f W avg)', 1e3*mean(pR)), ...
    sprintf('Earth data center share (%.2f kW avg)', mean(pE))}, 'Location','southwest','NumColumns',3);
text(ax, mean(win), hi/1.3, 'zoom below', 'HorizontalAlignment','center','FontSize',9);
dk = find(~geo.sunlit(:)', 1);
if ~isempty(dk), text(ax, d(dk), hi/1.3, 'ridge in shadow: robots park, battery carries the base ', ...
        'HorizontalAlignment','right','FontSize',9); end
title(ax, 'Three data centers, one fleet: power drawn every 5 minutes (Earth peaks = store-and-forward backlog after a link gap)');

% ---------- 2. Base power by component (zoom)
ax = nexttile(tl,[1 2]); hold(ax,'on');
top = 1.35*max(ts.baseKW(w));
yyaxis(ax,'left');
shade(ax, d(w), ts.shift(w) > 0.5, 0, top, [0.92 0.95 1.0]);
shade(ax, d(w), geo.linkMbps(w) == 0, 0, top, [1.0 0.88 0.88]);
a = area(ax, d(w), [ts.pHouseKW(w); ts.pIdleKW(w); ts.pWorkKW(w); ts.pCoolKW(w); ts.pTxKW(w)]', 'LineStyle','none');
cols = [0.62 0.62 0.62; 0.72 0.86 0.72; cB; 0.30 0.70 0.90; 0.95 0.65 0.20];
for k = 1:5, a(k).FaceColor = cols(k,:); end
hz = d(w); hz = hz(ts.hazard(w) > 0);
if ~isempty(hz), plot(ax, hz, 0.96*top*ones(size(hz)), 'v', 'Color',[0.8 0.2 0.1], ...
        'MarkerFaceColor',[0.8 0.2 0.1], 'MarkerSize',4, 'HandleVisibility','off'); end
ylabel(ax,'kW'); ylim(ax,[0 top]);
yyaxis(ax,'right'); hb = plot(ax, d(w), 100*ts.util(w), 'k-', 'LineWidth',0.8); ylabel(ax,'GPU busy, %');
ylim(ax,[0 max(10, 1.3*max(100*ts.util(w)))]); ax.YAxis(2).Color = 'k';
xlim(ax, win); grid(ax,'on');
legend(ax, [a(:)' hb], {'house','GPUs idle (warm 30% / parked 5%)','GPUs working','cooling','transmitter','GPU busy (right)'}, ...
    'Location','northwest','NumColumns',6);
title(ax, ['Lunar base (zoom): blue bands = operator shift, red bands = no link to Earth ' ...
    '(tactical falls back to the base), red marks = hazard bursts']);

% ---------- 3. Arrivals (zoom)
ax = nexttile(tl); hold(ax,'on');
yyaxis(ax,'left'); plot(ax, d(w), ts.arrPer(w)/cfg.dt, 'LineWidth',0.8);
plot(ax, d(w), (ts.perBase(w) - 0)/cfg.dt, ':', 'LineWidth',0.5, 'HandleVisibility','off');
ylabel(ax,'camera frames / s');
yyaxis(ax,'right'); plot(ax, d(w), 60*ts.arrTac(w)/cfg.dt, 'LineWidth',1);
plot(ax, d(w), 60*ts.arrDeep(w)/cfg.dt, '-', 'Color',[0.15 0.15 0.15], 'LineWidth',1.4);
ylabel(ax,'requests / min'); xlim(ax, win); grid(ax,'on');
legend(ax, {'camera frames (screened on board)','tactical requests','deep requests (shift-start planning)'}, 'Location','northwest');
title(ax,'Work arriving: shifts, planning bursts, random arrivals');

% ---------- 4. Batching (zoom)
ax = nexttile(tl); hold(ax,'on');
act = geo.sunlit(:)'; bp = ts.batchPer; bp(~act) = NaN; jp = ts.jPer; jp(~act) = NaN;
yyaxis(ax,'left'); stairs(ax, d(w), bp(w), 'LineWidth',1.2); ylabel(ax,'perception batch');
ylim(ax,[0 1.3*max(bp(w),[],'omitnan')]);
yyaxis(ax,'right'); plot(ax, d(w), jp(w), 'LineWidth',1.2); ylabel(ax,'J per frame');
j1 = res.batchTables.perBase.J(1);
yline(ax, j1, ':', sprintf('%.0f J unbatched', j1), 'LabelHorizontalAlignment','left');
ylim(ax,[0 1.15*j1]); xlim(ax, win); grid(ax,'on');
title(ax, sprintf('Deadline-aware batching: busier hours, bigger batches, fewer J/frame (%.0f J avg)', mean(jp,'omitnan')));

% ---------- 5. Relays (zoom)
ax = nexttile(tl); hold(ax,'on');
yyaxis(ax,'left');
h1 = plot(ax, d(w), ts.relayBudgetW(w), '-', 'Color',[0.75 0.65 0.95], 'LineWidth',1);
h2 = area(ax, d(w), ts.relayW(w), 'FaceColor',cR, 'LineStyle','none');
ylabel(ax,'W'); ylim(ax,[0 1.4*max([ts.relayBudgetW 1])]);
yyaxis(ax,'right'); h3 = plot(ax, d(w), 100*ts.relayLinkUse(w), 'Color',[0.2 0.2 0.2], 'LineWidth',0.8);
ylabel(ax,'Ka link used, %'); ylim(ax,[0 140]); ax.YAxis(2).Color = 'k'; xlim(ax, win); grid(ax,'on');
legend(ax, [h1 h2 h3], {'compute budget on the bus','Thor power drawn','explorer link to Earth used'}, ...
    'Location','northwest','NumColumns',3);
if max(ts.relayW) > 0
    tt = sprintf('Relays: Thors wake only when the link cannot carry the work (%.0f W avg)', mean(ts.relayW));
else
    tt = 'Relays: Thors stay parked, the link to Earth had room for every explorer request';
end
title(ax, tt);

% ---------- 6. Earth sites (zoom)
ax = nexttile(tl); hold(ax,'on');
nS = numel(cfg.earthSites); Pz = zeros(nS, numel(th));
for i = 1:numel(th), [pr, pu] = earth_sites(cfg, th(i)); Pz(:,i) = 1e3*pr.*pu; end
sc = [0.30 0.50 0.90; 0.85 0.33 0.10; 0.47 0.67 0.19];
for k = 1:nS, plot(ax, d(w), Pz(k,w), 'Color', sc(k,:), 'LineWidth',1.2); end
use = w & ts.earthJ > 0; pick = 1e3*ts.earthPrice.*ts.earthPUE;
scatter(ax, d(use), pick(use), 8 + 70*ts.earthJ(use)/max(ts.earthJ), sc(ts.earthSite(use),:), 'filled', 'MarkerEdgeColor',[0.3 0.3 0.3]);
e = ts.earthJ > 0;
share = accumarray(ts.earthSite(e)', ts.earthJ(e)', [nS 1])/max(sum(ts.earthJ),eps);
legend(ax, [arrayfun(@(k) sprintf('%s (%.0f%% of energy)', cfg.earthSites(k).name, 100*share(k)), 1:nS, 'Uni',0) ...
    {'work sent (size = energy)'}], 'Location','northwest','NumColumns',2);
ylabel(ax,'$/MWh x PUE'); xlabel(ax,'day'); xlim(ax, win); grid(ax,'on');
title(ax, sprintf('Earth: work follows the cheapest site each hour ($%.0f, %.0f kg CO2 in %g days)', ...
    res.earthUSD, res.earthCO2kg, cfg.days));
end

function shade(ax, d, on, lo, hi, col)
on = on(:)'; d = d(:)'; if ~any(on), return; end
e = diff([0 on 0]); s = find(e == 1); f = find(e == -1) - 1;
for k = 1:numel(s)
    patch(ax, d([s(k) f(k) f(k) s(k)]), [lo lo hi hi], col, 'EdgeColor','none', 'HandleVisibility','off');
end
end
