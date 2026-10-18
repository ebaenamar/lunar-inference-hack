function fig = lunar_strategies_slide(cfg, C, L)
%LUNAR_STRATEGIES_SLIDE One slide: where each thought runs, by latency and energy price,
%   and what each strategy gets in service and cost (figures/strategies_slide.png).
%   Left: the four compute tiers with their latency to the robot and their energy
%   price, and the share of each kind of work the coordinated fleet puts there.
%   Right: energy bill per robot-day against requests served on time, for the five
%   strategies (bubble = lunar base peak load).

if nargin < 3, L = lunar_savings(cfg, C, false); end
P = tier_prices(cfg, C); r = L.res{5}; ts = r.ts;
fig = figure('Color','w','Position',[30 30 1600 860]);
try, theme(fig,'light'); catch, end
annotation(fig,'textbox',[0.01 0.93 0.98 0.06],'String', ...
    'Fast Moon, Slow Earth: each thought runs on the cheapest data center that meets its deadline', ...
    'EdgeColor','none','FontSize',18,'FontWeight','bold','HorizontalAlignment','center');

% ---------------- left: latency x price matrix
ax = axes(fig,'Position',[0.01 0.06 0.55 0.84]); hold(ax,'on'); axis(ax,'off');
xlim(ax,[0 5]); ylim(ax,[0 4.6]);
tiers = {'Robot','Lunar base','Relay constellation','Earth'};
lat   = [0 cfg.cellRTT 0.12 cfg.earthRTT];
price = [P.robot P.base P.relay P.earth];
tcol  = [0.95 0.65 0.20; 0.20 0.62 0.32; 0.60 0.40 0.90; 0.30 0.50 0.90];
for k = 1:4
    x = k + 0.5;
    rectangle(ax,'Position',[x-0.47 3.55 0.94 0.95],'Curvature',0.15,'FaceColor',tcol(k,:),'EdgeColor','none');
    if k == 4, ps = sprintf('$%.2f/kWh', price(k)); else, ps = sprintf('$%.0f/kWh', price(k)); end
    if lat(k) == 0, ls = 'on board'; elseif lat(k) < 1, ls = sprintf('%.0f ms', 1e3*lat(k)); else, ls = sprintf('%.2f s', lat(k)); end
    text(ax, x, 4.22, tiers{k}, 'HorizontalAlignment','center','FontWeight','bold','Color','w','FontSize',12);
    text(ax, x, 3.92, sprintf('latency %s', ls), 'HorizontalAlignment','center','Color','w','FontSize',10.5);
    text(ax, x, 3.70, ps, 'HorizontalAlignment','center','Color','w','FontSize',10.5,'FontWeight','bold');
end
% work kinds
frames = sum(ts.arrPer);
nFwd = frames - (sum(ts.boardJ - ts.tacBoard*r.cost.small.energyJ)/cfg.detectorJ);
per = [1 - nFwd/frames, nFwd/frames, 0, 0];
dec = [sum(ts.tacBoard) sum(ts.tacBase) sum(ts.tacRelay) sum(ts.tacEarth)]; tac = dec/sum(dec);
dp  = [0 sum(ts.deepBase) 0 sum(ts.deepEarth)]; deep = dp/sum(dp);
rows = {sprintf('Perception\ndeadline %.0f s', cfg.perceptionDeadline), sprintf('Tactical decision\ndeadline %.0f s', cfg.tacticalDeadline), ...
        sprintf('Deep reasoning +\nsecond opinions\ndeadline %.0f h', cfg.deepDeadline/3600)};
share = [per; tac; deep];
note = {{'detector screens','7B model, batched','—','2.56 s > 1 s'}, ...
        {'3B, last resort','30B, link gaps','30B, explorers in gaps','30B while link has room'}, ...
        {'','distilled 30B, before expiry','','Kimi K3, store & forward'}};
dl = [cfg.perceptionDeadline cfg.tacticalDeadline cfg.deepDeadline];
for j = 1:3
    y = 2.92 - (j-1)*1.0;
    text(ax, 0.48, y, rows{j}, 'HorizontalAlignment','center','FontSize',11,'FontWeight','bold');
    for k = 1:4
        x = k + 0.5; s = share(j,k);
        feasible = lat(k) + 0.05 < dl(j) || k == 1;
        if ~feasible
            fc = [0.96 0.90 0.90]; txt = sprintf('too far\n%s', note{j}{k});
        elseif s > 0.005
            fc = 1 - (1 - tcol(k,:))*min(1, 0.25 + 0.75*sqrt(s)); txt = sprintf('%.0f %%\n%s', 100*s, note{j}{k});
        elseif k == 3 && j == 2
            fc = [0.97 0.97 0.97]; txt = sprintf('%.0f %%\nstandby: the link\nto Earth had room', 100*s);
        else
            fc = [0.97 0.97 0.97]; txt = '';
        end
        rectangle(ax,'Position',[x-0.47 y-0.42 0.94 0.84],'Curvature',0.1,'FaceColor',fc,'EdgeColor',[0.8 0.8 0.8]);
        tc = 'k'; if s > 0.5 && feasible, tc = 'w'; end
        text(ax, x, y, txt, 'HorizontalAlignment','center','FontSize',9.5,'Color',tc,'FontWeight','bold');
    end
end
text(ax, 0.05, 0.42, sprintf(['Distributed inference: one frame flows robot detector -> 7B at the base.\n' ...
    'Distributed reasoning: %.0f %% of decisions get a Kimi K3 second opinion %.1f min later; wrong decisions %.1f %% -> %.1f %%.\n' ...
    'Distributed allocation: cheapest data center whose latency meets the deadline, given the live link.'], ...
    100*r.escRate, r.corrMin, 100*r.errFast, 100*r.errFinal), 'FontSize',10,'Color',[0.2 0.2 0.2],'VerticalAlignment','top');
text(ax, 2.75, 3.46, 'Share of each kind of work per data center (coordinated fleet, 30 days)', ...
    'HorizontalAlignment','center','FontSize',10,'FontAngle','italic');

% ---------------- right: cost vs service
ax = axes(fig,'Position',[0.64 0.50 0.34 0.38]); hold(ax,'on'); grid(ax,'on');
tot = sum(L.USD,2); sv = mean(L.served(:,1:3),2)*100;
names = {'All on robot','All on Earth','All on Moon','Moon-first','Fast Moon, Slow Earth'};
cc = [0.95 0.65 0.20; 0.30 0.50 0.90; 0.85 0.20 0.15; 0.55 0.55 0.55; 0.20 0.62 0.32];
for s = 1:5
    y = max(tot(s), 1);
    scatter(ax, sv(s), y, 120 + 120*L.peakKW(s), cc(s,:), 'filled', 'MarkerEdgeColor','k', 'MarkerFaceAlpha',0.85);
    lab = sprintf('%s\n$%s/robot-day', names{s}, num2str(round(tot(s))));
    if s == 2, lab = sprintf('%s\n~$0, but perception 0 %%', names{s}); end
    off = {[-1.5 1.4 1], [2 1 2], [-4 1.1 1], [-2.5 0.45 1], [1.5 0.42 1]};   % [dx, y factor, align]
    al = {'right','left','center'}; o = off{s};
    text(ax, sv(s) + o(1), y*o(2), lab, 'FontSize',9.5, 'HorizontalAlignment',al{o(3)}, 'FontWeight', ternary(s==5,'bold','normal'));
end
set(ax,'YScale','log'); ylim(ax,[0.5 3e3]); xlim(ax,[45 104]);
xlabel(ax,'requests served on time, % (perception, tactical, deep)'); ylabel(ax,'energy bill, $ per robot-day');
title(ax,'Better service AND cheaper (bubble = lunar base peak kW)');

ax = axes(fig,'Position',[0.71 0.08 0.27 0.30]); hold(ax,'on');
v = [tot(3) tot(4) tot(5)]; b = barh(ax, v, 0.6); b.FaceColor = 'flat'; b.CData = cc([3 4 5],:);
set(ax,'YTick',1:3,'YTickLabel',{'All on the Moon','Moon-first','Fast Moon, Slow Earth'},'FontSize',10.5);
for k = 1:3, text(ax, v(k) + 8, k, sprintf('$%d   peak %.1f kW', round(v(k)), L.peakKW(k+2)), 'FontSize',10.5, 'FontWeight','bold'); end
xlim(ax,[0 1.45*max(v)]); grid(ax,'on'); xlabel(ax,'$ per robot-day');
title(ax, sprintf('%.1fx cheaper than all on the Moon, %.1fx than Moon-first\n%.0f %% less energy spent on the Moon', ...
    tot(3)/tot(5), tot(4)/tot(5), 100*(1 - sum(L.kWh(5,1:4))/sum(L.kWh(3,1:4)))));
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
