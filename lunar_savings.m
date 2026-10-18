function L = lunar_savings(cfg, C, doPlot)
%LUNAR_SAVINGS Energy and cost per robot-day for four placement strategies.
%   Coordinated data centers: each tier serves the timescale it is good at.
%     robot  : reflexes (ms)          lunar base : perception (1 s), tactical (10 s)
%     relays : tactical away from base  Earth    : deep reasoning that can wait (1 h)
%   Strategies compared, for one robot over one working day:
%     'AllOnRobot'   a Thor-class computer on every robot
%     'AllOnEarth'   everything off board goes to Earth
%     'AllOnMoon'    a lunar base large enough to host Kimi K3 (2 x DGX B200)
%     'Coordinated'  the hierarchical policy (1 x DGX B200 at the base)
%   Cost of energy per tier = launch cost of its power plant per kWh delivered
%   (5-year life), with the launch price of cfg.launchPrice; Earth pays the grid.

if nargin < 3, doPlot = true; end
M = C.mdl; H = C.hw;
active = 0.93;                          % fraction of the day the robot works (sunlit ridge)
day = 86400*active;
n.per  = day*cfg.perceptionHz;
n.tac  = day/cfg.tacticalPeriod;
n.deep = day/cfg.deepPeriod;
reflexW = 25;                           % on-board reflex policy on the Orin NX, all strategies

% ---- $/kWh of each tier: (power-plant kg per kW of peak) x ($/kg) / (life hours x load factor)
prices = struct('Deck2035',1200, 'Starship',1e5, 'CLPS',1e6);
pkg = prices.(cfg.launchPrice); life = cfg.lifeYears*8766;
kgkW.base  = cfg.solarKgPerKW*cfg.arrayMargin + 1e3*cfg.batteryHours/cfg.batteryWhPerKg + cfg.radiatorKgPerKW;
kgkW.robot = 150;                       % rover arrays + battery for its own computer
kgkW.relay = 5 + cfg.radiatorKgPerKW + H.RelayEdge.mass/(H.RelayEdge.Pmax/1e3);
usd.base  = kgkW.base*pkg/(life*0.5);
usd.robot = kgkW.robot*pkg/(life*0.6);
usd.relay = kgkW.relay*pkg/(life*0.5);
usd.earth = cfg.earthUSDperkWh;      % Earth energy already includes the PUE

% ---- Per-request costs
c.perBase = request_cost(H.DGX_B200, M.VLM7B);   c.perThor = request_cost(H.Thor, M.VLM7B);
c.perEarth = request_cost(H.EarthB200, M.VLM7B);
c.tacBase = request_cost(H.DGX_B200, M.Tactical); c.tacRelay = request_cost(H.RelayEdge, M.Tactical);
c.tacThor = request_cost(H.Thor, M.Tactical);     c.tacEarth = request_cost(H.EarthB200, M.Tactical);
c.deepEarth = request_cost(H.EarthB200, M.DeepK3); c.deepMoonK3 = request_cost(H.DGX_B200x2, M.DeepK3);
c.deepThor = request_cost(H.Thor, M.DeepDist);

ok = @(rtt, r, dl) (rtt + r.latency) <= dl;
fx = cfg.fracExploring;
S = {'AllOnRobot','AllOnEarth','AllOnMoon','Coordinated'};
tiers = {'robot','relays','lunar base','Earth'};
E = zeros(4,4);  served = zeros(4,3); superior = zeros(4,1); peakKW = zeros(4,1);
for s = 1:4
    e = zeros(1,4); sv = zeros(1,3);
    % reflexes run on every robot in every strategy (reflexW): a common baseline, left out of the comparison
    switch S{s}
        case 'AllOnRobot'
            e(1) = n.per*c.perThor.energyJ + n.tac*c.tacThor.energyJ + n.deep*c.deepThor.energyJ;
            sv = [ok(0,c.perThor,cfg.perceptionDeadline), ok(0,c.tacThor,cfg.tacticalDeadline), 1];
            superior(s) = 0; peakKW(s) = 0;
        case 'AllOnEarth'
            e(4) = (n.tac*c.tacEarth.energyJ + n.deep*c.deepEarth.energyJ)*cfg.earthPUE;
            sv = [ok(cfg.earthRTT,c.perEarth,cfg.perceptionDeadline), ok(cfg.earthRTT,c.tacEarth,cfg.tacticalDeadline), 1];
            superior(s) = 1; peakKW(s) = 2;
        case 'AllOnMoon'
            e(3) = n.per*c.perBase.energyJ + n.tac*c.tacBase.energyJ + n.deep*c.deepMoonK3.energyJ;
            sv = [1, 1-fx, 1-fx];                             % explorers cannot reach the base
            superior(s) = 1; peakKW(s) = H.DGX_B200x2.Pmax/1e3 + 2;
        case 'Coordinated'
            e(3) = n.per*c.perBase.energyJ + (1-fx)*n.tac*c.tacBase.energyJ;
            e(2) = fx*n.tac*c.tacRelay.energyJ;
            e(4) = n.deep*c.deepEarth.energyJ*cfg.earthPUE;
            sv = [1, 1, 1];
            superior(s) = 1; peakKW(s) = H.DGX_B200.Pmax/1e3 + 2;
    end
    E(s,:) = e; served(s,:) = sv;
end
kWh = E/3.6e6;
price = [usd.robot usd.relay usd.base usd.earth];
USD = kWh.*price;
plantKg = peakKW*kgkW.base; plantUSD = plantKg*pkg;

L = struct('strategies',{S},'tiers',{tiers},'kWh',kWh,'USD',USD,'served',served, ...
           'superior',superior,'peakKW',peakKW,'plantUSD',plantUSD,'usdPerKWh',price,'cost',c,'n',n);
if ~doPlot, return; end

% ======================= Figure =======================
col = [0.95 0.65 0.20; 0.60 0.40 0.90; 0.20 0.62 0.32; 0.30 0.50 0.90];
fig = figure('Name','Coordinated lunar data centers: savings','Color','w','Position',[70 60 1500 860]);
try, theme(fig,'light'); catch, end
tl = tiledlayout(fig,2,3,'TileSpacing','compact','Padding','compact');
title(tl, sprintf('Coordinated data centers: each tier at its timescale  (per robot-day, %s launch price; reflex control on board, common to all, excluded)', cfg.launchPrice), ...
      'FontWeight','bold','FontSize',13);

% 1. Timescale x tier map
ax = nexttile(tl,1,[1 2]); hold(ax,'on');
yt = 1:4;
for k = 1:4, yline(ax, yt(k), ':', 'Color',[0.85 0.85 0.85]); end
co = L.kWh(4,:);                                   % coordinated energy per tier
dots = { ...                                        % timescale [s], tier, label, energy kWh/day
  0.01, 1, 'reflex control',          reflexW*day/3.6e6; ...
  1,    3, 'perception 7B',           n.per*c.perBase.energyJ/3.6e6; ...
  10,   3, 'tactical 30B (in cell)',  (1-fx)*n.tac*c.tacBase.energyJ/3.6e6; ...
  10,   2, 'tactical 30B (explorers)',fx*n.tac*c.tacRelay.energyJ/3.6e6; ...
  3600, 4, 'deep reasoning, Kimi K3', n.deep*c.deepEarth.energyJ*cfg.earthPUE/3.6e6};
for k = 1:size(dots,1)
    t = dots{k,1}; y = dots{k,2}; ekwh = dots{k,4};
    sz = 300 + 4000*sqrt(ekwh/max(co));
    scatter(ax, t, y, sz, col(y,:), 'filled', 'MarkerFaceAlpha',0.75, 'MarkerEdgeColor','k');
    if t == 1, xt = t/1.8; ha = 'right'; else, xt = t*1.8; ha = 'left'; end
    text(ax, xt, y, sprintf('%s\n%.2f kWh/day  ->  $%.2f/day', dots{k,3}, ekwh, ekwh*price(y)), ...
         'FontSize',9, 'HorizontalAlignment',ha, 'VerticalAlignment','middle', 'BackgroundColor','w', 'Margin',1);
end
set(ax,'XScale','log','YTick',yt,'YTickLabel',{sprintf('robot  ($%.0f/kWh)',usd.robot), ...
    sprintf('relays  ($%.0f/kWh)',usd.relay), sprintf('lunar base  ($%.0f/kWh)',usd.base), ...
    sprintf('Earth  ($%.2f/kWh)',usd.earth)});
xlim(ax,[3e-3 4e4]); ylim(ax,[0.4 4.8]); grid(ax,'on');
xticks(ax,[0.01 0.1 1 10 60 600 3600]); xticklabels(ax,{'10 ms','100 ms','1 s','10 s','1 min','10 min','1 h'});
xlabel(ax,'timescale of the decision (deadline)');
title(ax,'Who thinks what: bubbles sized by daily energy, label = energy and cost per robot-day');

% 2. Served
ax = nexttile(tl,3);
b = bar(ax, 100*[served superior]); grid(ax,'on'); ylim(ax,[0 110]);
set(ax,'XTickLabel',S); ylabel(ax,'%');
legend(ax,{'perception on time','tactical on time','deep answered','by superior model'},'Location','southoutside','NumColumns',2);
title(ax,'Service delivered');

% 3. Energy per robot-day
ax = nexttile(tl,4);
bh = bar(ax, kWh, 'stacked'); for k = 1:4, bh(k).FaceColor = col(k,:); end
set(ax,'XTickLabel',S); ylabel(ax,'kWh per robot-day'); grid(ax,'on'); ylim(ax,[0 1.1*max(sum(kWh,2))]);
legend(ax,fliplr(bh),fliplr(tiers),'Location','northeast'); title(ax,'Energy by tier');

% 4. Cost per robot-day
ax = nexttile(tl,5);
bh = bar(ax, USD, 'stacked'); for k = 1:4, bh(k).FaceColor = col(k,:); end
set(ax,'XTickLabel',S); ylabel(ax,'$ per robot-day'); grid(ax,'on');
tot = sum(USD,2);
ylim(ax,[0 1.15*max(tot)]);
for s = 1:4, text(ax, s, tot(s) + 0.04*max(tot), sprintf('$%.0f', tot(s)), 'HorizontalAlignment','center','FontWeight','bold'); end
title(ax, sprintf('Energy cost: coordinated is %.1fx cheaper than all-on-Moon', tot(3)/tot(4)));

% 5. Lunar power plant
ax = nexttile(tl,6);
yyaxis(ax,'left'); bar(ax, peakKW, 0.5, 'FaceColor',[0.55 0.55 0.55]); ylabel(ax,'lunar base peak power, kW');
yyaxis(ax,'right'); plot(ax, 1:4, plantUSD/1e6, 'o-', 'LineWidth',2, 'MarkerFaceColor','w'); ylabel(ax,'power plant launch, $M');
set(ax,'XTick',1:4,'XTickLabel',S); grid(ax,'on');
title(ax, sprintf('Power plant on the Moon: %.0f kW vs %.0f kW', peakKW(3), peakKW(4)));
end
