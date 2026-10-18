function fig = lunar_reasoning_slide(cfg, C)
%LUNAR_REASONING_SLIDE Where a robot is decides how much it can think (figures/reasoning_slide.png).
%   Left: share of the working time each level of reasoning is reachable, for a
%   robot in the base cell and an explorer in a crater with the first relay and
%   with the full LCRNS constellation, and which data center provides it.
%   Right: 30-day timelines of the largest model reachable within 10 s.

cfg.policy = 'Coordinated';
loc = {}; Acc = {}; R = {};
for nr = [1 5]
    c = cfg; c.nRelays = nr; g = lunar_geometry(c); r = lunar_dispatch(c, g, C);
    Acc{end+1} = reasoning_access(c, g, r); R{end+1} = r; G = g; %#ok<AGROW>
end
cols = {struct('A',Acc{1},'who','base','title',sprintf('Robot in the\nbase cell')), ...
        struct('A',Acc{1},'who','expl','title',sprintf('Explorer in a crater\nfirst relay (2027)')), ...
        struct('A',Acc{2},'who','expl','title',sprintf('Explorer in a crater\nfull LCRNS (5 relays)'))};
r = R{1}; k3lat = r.cost.deepEarth.latency;
cO = [0.95 0.65 0.20]; cBs = [0.20 0.62 0.32]; cR = [0.60 0.40 0.90]; cE = [0.30 0.50 0.90];

fig = figure('Color','w','Position',[30 30 1600 860]);
try, theme(fig,'light'); catch, end
annotation(fig,'textbox',[0.01 0.925 0.98 0.07],'String', ...
    'Where a robot is decides how much it can think', 'EdgeColor','none','FontSize',20,'FontWeight','bold','HorizontalAlignment','center');

% ---------------- ladder
ax = axes(fig,'Position',[0.01 0.10 0.56 0.80]); hold(ax,'on'); axis(ax,'off');
xlim(ax,[0 4]); ylim(ax,[0 6.3]);
lv = {sprintf('Kimi K3 2.8T\nwithin 1 h'), sprintf('Reasoning 30B\nwithin 10 s'), sprintf('Vision 7B\nwithin 1 s'), sprintf('Small 3B\non board'), sprintf('Reflexes +\ndetector')};
for L = 5:-1:1
    y = 0.6 + (L-1)*1.08;
    text(ax, 0.45, y, lv{6-L}, 'HorizontalAlignment','center','FontWeight','bold','FontSize',11);
end
for c = 1:3
    S = cols{c}; A = S.A; a = A.act;
    if strcmp(S.who,'base'), av = A.base(:,a); src = A.baseSrc(:,a); else, av = A.expl(:,a); src = A.explSrc(:,a); end
    x = 0.95 + (c-1)*1.02;
    text(ax, x+0.47, 6.05, S.title, 'HorizontalAlignment','center','FontWeight','bold','FontSize',11.5);
    for L = 1:5
        lev = L; y = 0.6 + (lev-1)*1.08;               % level 5 (Kimi K3) at the top
        p = mean(av(lev,:));
        switch lev
            case {1,2}, col = cO; wh = 'on board';
            case 3, col = cBs; wh = 'lunar base, 20 ms';
            case 4
                pe = mean(src(1,:) == 3); pb = mean(src(1,:) == 1); pr = mean(src(1,:) == 2);
                [~, m] = max([pb pr pe]); col = {cBs, cR, cE}; col = col{m};
                parts = {}; if pe > 0, parts{end+1} = sprintf('Earth %.0f%%', 100*pe); end
                if pb > 0, parts{end+1} = sprintf('base %.0f%%', 100*pb); end
                if pr > 0, parts{end+1} = sprintf('relay %.0f%%', 100*pr); end
                wh = strjoin(parts, ', ');
            case 5, col = cE; wh = sprintf('Earth, %.0f s + 2.6 s light', k3lat);
        end
        if p < 0.005, fc = [0.94 0.94 0.94]; tc = [0.5 0.5 0.5]; wh = 'not reachable';
        else, fc = 1 - (1 - col)*(0.35 + 0.65*p); tc = 'w'; if p < 0.5, tc = 'k'; end
        end
        rectangle(ax,'Position',[x y-0.48 0.94 0.96],'Curvature',0.12,'FaceColor',fc,'EdgeColor',[0.85 0.85 0.85]);
        text(ax, x+0.47, y+0.14, sprintf('%.0f %%', 100*p), 'HorizontalAlignment','center','FontWeight','bold','FontSize',15,'Color',tc);
        text(ax, x+0.47, y-0.24, wh, 'HorizontalAlignment','center','FontSize',9,'Color',tc);
    end
end
text(ax, 0.05, 0.02, 'Share of working time (sunlit, 30 days) each level is reachable. Colour = data center that provides it.', ...
    'FontSize',9.5,'Color',[0.35 0.35 0.35]);

% ---------------- timelines
d = G.t(:)'/86400;
ax2 = axes(fig,'Position',[0.69 0.47 0.29 0.40]); hold(ax2,'on');
lab = {'Robot in base cell','Explorer, 1 relay','Explorer, 5 relays'};
for c = 1:3
    S = cols{c}; A = S.A;
    if strcmp(S.who,'base'), m = A.maxB; else, m = A.maxE; end
    y = 3 - c;
    seg(ax2, d, y, m >= 4 & A.act, cE);
    seg(ax2, d, y, m < 4 & A.act, cO);
    seg(ax2, d, y, ~A.act, [0.75 0.75 0.75]);
end
set(ax2,'YTick',0:2,'YTickLabel',fliplr(lab),'FontSize',10.5); ylim(ax2,[-0.6 2.6]); xlim(ax2,[0 d(end)]);
xlabel(ax2,'day'); grid(ax2,'on'); box(ax2,'on');
title(ax2, 'Largest model a robot can use within 10 s, over 30 days');
patch(ax2, nan, nan, cE, 'DisplayName','30B (Earth, base or relay)');
patch(ax2, nan, nan, cO, 'DisplayName','own 3B only');
patch(ax2, nan, nan, [0.75 0.75 0.75], 'DisplayName','parked (ridge in shadow)');
legend(ax2, 'Location','southoutside','NumColumns',3,'FontSize',9.5);

% ---------------- messages
msg = { ...
  sprintf('\\bfReal-time thinking is bounded by what you launched.\\rm Within 1 s only the robot and the base can answer; within 10 s, the 30B model on Earth, the base or a relay, if a link or a relay is there.'), ...
  sprintf('\\bfSlow thinking is unbounded on Earth.\\rm Kimi K3 (2.8T) is never real time from the Moon: %.0f s of compute plus 2.6 s of light. It answers the second opinions and the deep plans within the hour.', k3lat), ...
  sprintf('\\bfThe constellation decides how far from the base a robot can think.\\rm With the first relay, explorers fall back to their own 3B %.0f %% of the time; with five relays, never.', 100*mean(Acc{1}.maxE(Acc{1}.act) < 4))};
annotation(fig,'textbox',[0.60 0.04 0.38 0.30],'String',strjoin(msg, newline), 'EdgeColor','none','FontSize',11.5, ...
    'Interpreter','tex','VerticalAlignment','top');
end

function seg(ax, d, y, on, col)
on = on(:)'; if ~any(on), return; end
e = diff([0 on 0]); s = find(e == 1); f = find(e == -1) - 1;
for k = 1:numel(s)
    patch(ax, d([s(k) f(k) f(k) s(k)]), y + [-0.35 -0.35 0.35 0.35], col, 'EdgeColor','none','HandleVisibility','off');
end
end
