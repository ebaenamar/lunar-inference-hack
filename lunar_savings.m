function L = lunar_savings(cfg, C, doPlot)
%LUNAR_SAVINGS Thinking cost per robot-day for five strategies, from the simulation.
%   Same fleet, same work, same orbits and links; only the placement changes:
%     AllOnRobot   a Thor-class computer on every robot (analytic)
%     AllOnEarth   everything off board goes to Earth            ('EarthOnly')
%     AllOnMoon    a base big enough for Kimi K3 (2 x DGX B200)  ('BaseOnly')
%     MoonFirst    base, then relays, then Earth                  ('Hierarchical')
%     Coordinated  cheapest node that meets each deadline with the current link,
%                  on-board detector gating perception, model cascade ('Coordinated')
%   Cost = marginal compute energy on each tier x that tier's $/kWh (tier_prices).

if nargin < 3, doPlot = true; end
P = tier_prices(cfg, C);
geo = lunar_geometry(cfg);
S  = {'AllOnRobot','AllOnEarth','AllOnMoon','MoonFirst','Coordinated'};
pol = {'', 'EarthOnly', 'BaseOnly', 'Hierarchical', 'Coordinated'};
hwSel = {'', cfg.baseHW, '2xDGX-B200', cfg.baseHW, cfg.baseHW};
nS = numel(S);
USD = zeros(nS,4); kWh = zeros(nS,4); served = zeros(nS,4); peakKW = zeros(nS,1);
R = cell(nS,1);
for s = 2:nS
    c = cfg; c.policy = pol{s}; c.baseHW = hwSel{s};
    r = lunar_dispatch(c, geo, C); R{s} = r;
    kWh(s,:) = r.tierKWh/cfg.days/cfg.nRobots;               % per robot-day
    USD(s,:) = kWh(s,:).*P.vec;
    served(s,:) = [r.perOnTime r.tacOnTime r.deepOnTime r.deepOnTime*r.deepSuperior];
    peakKW(s) = r.PmaxKW;
end
% All on the robot: a Thor per robot runs perception, tactical and a distilled deep model
H = C.hw; M = C.mdl; act = mean(geo.sunlit); day = 86400*act;
cp = request_cost(H.Thor, M.VLM7B); ct = request_cost(H.Thor, M.Tactical); cd = request_cost(H.Thor, M.DeepDist);
J = day*cfg.perceptionHz*(1-cfg.fracExploring)*cp.energyJ + day/cfg.tacticalPeriod*ct.energyJ + day/cfg.deepPeriod*cd.energyJ;
kWh(1,:) = [J/3.6e6 0 0 0]; USD(1,:) = kWh(1,:).*P.vec;
served(1,:) = [cp.latency <= cfg.perceptionDeadline, ct.latency <= cfg.tacticalDeadline, 1, 0];
peakKW(1) = 0;
plantUSD = peakKW*P.kgPerKW.base*P.usdPerKg;
L = struct('strategies',{S},'kWh',kWh,'USD',USD,'served',served,'peakKW',peakKW, ...
           'plantUSD',plantUSD,'price',P.vec,'res',{R});
if ~doPlot, return; end

% ======================= Figure =======================
tiers = {'robot','relays','lunar base','Earth'};
col = [0.95 0.65 0.20; 0.60 0.40 0.90; 0.20 0.62 0.32; 0.30 0.50 0.90];
fig = figure('Name','Coordinated lunar data centers: savings','Color','w','Position',[70 50 1550 880]);
try, theme(fig,'light'); catch, end
tl = tiledlayout(fig,2,3,'TileSpacing','compact','Padding','compact');
title(tl, sprintf(['Models combined across nodes at their timescales: real time stays on the Moon, what can wait goes to Earth  ' ...
      '(%s, %d robots, %d relays, %s launch)'], geo.siteInfo.name, cfg.nRobots, cfg.nRelays, cfg.launchPrice), 'FontWeight','bold');

% 1. Timescale x tier map for the coordinated policy
ax = nexttile(tl,1,[1 2]); hold(ax,'on');
r = R{5}; ts = r.ts; cc = r.cost; nd = cfg.days*cfg.nRobots;
detJ = sum(ts.boardJ) - sum(ts.tacBoard)*cc.small.energyJ;      % on-board detector energy
dots = { ...   % timescale [s], tier, label, kWh per robot-day
  0.01, 1, 'on-board detector screens every frame', detJ/3.6e6/nd; ...
  1,    3, 'perception 7B (changed frames only)',   sum(ts.baseReqJ)/3.6e6/nd; ...
  10,   4, 'tactical 30B on Earth (link up)',       sum(ts.tacEarth)*cc.tacEarth.energyJ*cfg.earthPUE/3.6e6/nd; ...
  10,   2, 'tactical 30B on relays (gaps)',         sum(ts.relayJ)/3.6e6/nd; ...
  10,   1, 'tactical 3B on board (last resort)',    sum(ts.tacBoard)*cc.small.energyJ/3.6e6/nd; ...
  3600, 4, 'deep reasoning, Kimi K3 (+ escalations)', sum(ts.deepEarth)*cc.deepEarth.energyJ*cfg.earthPUE/3.6e6/nd};
ek = cell2mat(dots(:,4)); emax = max(ek);
for k = 1:size(dots,1)
    t = dots{k,1}; y = dots{k,2}; e = dots{k,4};
    if e <= 0, continue; end
    scatter(ax, t, y, 150 + 3500*sqrt(e/emax), col(y,:), 'filled','MarkerFaceAlpha',0.75,'MarkerEdgeColor','k');
    if t >= 1000 || (y == 4 && t < 1000), xt = t/1.8; ha = 'right'; else, xt = t*1.8; ha = 'left'; end
    text(ax, xt, y, sprintf('%s\n%.3f kWh -> $%.2f per robot-day', dots{k,3}, e, e*P.vec(y)), ...
        'FontSize',9,'HorizontalAlignment',ha,'BackgroundColor','w','Margin',1);
end
set(ax,'XScale','log','YTick',1:4,'YTickLabel',{sprintf('robot  ($%.0f/kWh)',P.robot), sprintf('relays  ($%.0f/kWh)',P.relay), ...
    sprintf('lunar base  ($%.0f/kWh)',P.base), sprintf('Earth  ($%.2f/kWh)',P.earth)});
xlim(ax,[3e-3 4e4]); ylim(ax,[0.4 4.6]); grid(ax,'on');
xticks(ax,[0.01 0.1 1 10 60 600 3600]); xticklabels(ax,{'10 ms','100 ms','1 s','10 s','1 min','10 min','1 h'});
xlabel(ax,'timescale of the decision (deadline)');
title(ax,'Coordinated policy: who thinks what (bubble = energy per robot-day)');

% 2. Service
ax = nexttile(tl,3);
bar(ax, 100*served); grid(ax,'on'); ylim(ax,[0 115]); set(ax,'XTickLabel',S,'XTickLabelRotation',20); ylabel(ax,'%');
legend(ax,{'perception on time','tactical on time','deep answered','deep by Kimi K3'},'Location','southoutside','NumColumns',2);
title(ax,'Service delivered');

% 3. Thinking cost per robot-day
ax = nexttile(tl,4);
bh = bar(ax, USD, 'stacked'); for k = 1:4, bh(k).FaceColor = col(k,:); end
set(ax,'XTickLabel',S,'XTickLabelRotation',20); ylabel(ax,'$ per robot-day'); grid(ax,'on');
tot = sum(USD,2); ylim(ax,[0 1.15*max(tot)]);
for s = 1:nS, text(ax, s, tot(s)+0.04*max(tot), sprintf('$%.0f', tot(s)), 'HorizontalAlignment','center','FontWeight','bold'); end
legend(ax,fliplr(bh),fliplr(tiers),'Location','northeast');
title(ax, sprintf('Thinking cost: coordinated %.1fx cheaper than Moon-first', tot(4)/tot(5)));

% 4. Energy per robot-day
ax = nexttile(tl,5);
bh = bar(ax, kWh, 'stacked'); for k = 1:4, bh(k).FaceColor = col(k,:); end
set(ax,'XTickLabel',S,'XTickLabelRotation',20); ylabel(ax,'kWh per robot-day'); grid(ax,'on');
title(ax,'Energy by tier (Earth joules are ~8,000x cheaper)');

% 5. Moon-side kWh and plant
ax = nexttile(tl,6);
moonKWh = sum(kWh(:,1:3),2);
yyaxis(ax,'left'); bar(ax, moonKWh, 0.5, 'FaceColor',[0.5 0.5 0.55]); ylabel(ax,'kWh per robot-day spent on the Moon');
yyaxis(ax,'right'); plot(ax, 1:nS, peakKW, 'o-','LineWidth',2,'MarkerFaceColor','w'); ylabel(ax,'lunar base peak, kW');
set(ax,'XTick',1:nS,'XTickLabel',S,'XTickLabelRotation',20); grid(ax,'on');
title(ax, sprintf('Moon-side energy: coordinated %.0f%% below Moon-first', 100*(1 - moonKWh(5)/moonKWh(4))));
end
