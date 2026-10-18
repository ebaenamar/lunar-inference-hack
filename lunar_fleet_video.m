function lunar_fleet_video(cfg, C, win, saveVideo)
%LUNAR_FLEET_VIDEO Live view of the fleet's power, step by step (lunar_fleet_power.mp4).
%   Left: the real LCRNS relay orbits seen from the side, Earth's data centers on
%   top, the south-pole base with its servers and robots below, and the links in
%   use. Middle: the reasoning each robot can reach right now (in the base cell or
%   in a crater), which data center provides it, and Kimi K3's second opinions.
%   Right: base power by component, relay and Earth power, and the energy bill so
%   far against putting everything on the Moon.

if nargin < 3, win = [4 7]; end
if nargin < 4, saveVideo = true; end
cfg = earth_tier(cfg); cfg.policy = 'Coordinated';
geo = lunar_geometry(cfg);
r  = lunar_dispatch(cfg, geo, C);
cm = cfg; cm.policy = 'BaseOnly'; cm.baseHW = '2xDGX-B200';
rm = lunar_dispatch(cm, geo, C);
P  = tier_prices(cfg, C);
ts = r.ts; d = geo.t(:)'/86400; dt = cfg.dt;
bill = @(x) cumsum((x.ts.pCompKW + x.ts.pCoolKW + x.ts.pTxKW)*dt/3600*P.base + x.ts.relayJ/3.6e6*P.relay + ...
                   x.ts.boardJ/3.6e6*P.robot + x.ts.earthUSD);
cB = bill(r); cM = bill(rm);
idx = find(d >= win(1) & d <= win(2)); i0 = idx(1);
cB = cB - cB(i0); cM = cM - cM(i0);
nSrv = r.baseH.n; S = cfg.earthSites; nS = numel(S);
Acc = reasoning_access(cfg, geo, r);

fig = figure('Color','w','Position',[0 0 1920 1080],'Visible','off');
try, theme(fig,'light'); catch, end
V = struct();

% ---------- orbit view
a1 = axes(fig,'Position',[0.005 0.38 0.35 0.60]); hold(a1,'on'); axis(a1,'equal','off');
xlim(a1,[-24 24]); ylim(a1,[-6 31]);
th = linspace(0,2*pi,100); RM = 1.7374;
fill(a1, RM*cos(th), RM*sin(th), [0.80 0.80 0.80], 'EdgeColor',[0.5 0.5 0.5]);
text(a1, 0, -RM-1.2, 'Moon (south pole up)', 'HorizontalAlignment','center','FontSize',9,'Color',[0.4 0.4 0.4]);
X = squeeze(geo.sat(:,:,1))/1e3; Z = -squeeze(geo.sat(:,:,3))/1e3;      % side view, south up
if geo.nSat == 1, X = X(:)'; Z = Z(:)'; end
for k = 1:geo.nSat, V.trail(k) = plot(a1, nan, nan, '-', 'Color',[0.85 0.82 0.95]); end   % last orbit of each relay
ex = linspace(-16, 16, max(nS,1)); if nS == 1, ex = 0; end
for k = 1:nS
    V.site(k) = rectangle(a1,'Position',[ex(k)-5 27 10 3.2],'Curvature',0.2,'FaceColor',[0.9 0.93 1],'EdgeColor',[0.3 0.5 0.9]);
    V.siteT(k) = text(a1, ex(k), 28.6, '', 'HorizontalAlignment','center','FontSize',8.5);
end
text(a1, 0, 31, 'Earth data centers (2.56 s round trip)', 'HorizontalAlignment','center','FontWeight','bold','FontSize',10);
V.dte  = plot(a1, [0 0], [RM 27], '-', 'Color',[0.30 0.50 0.90], 'LineWidth',2);
V.rel1 = plot(a1, nan, nan, '-', 'Color',[0.20 0.65 0.35], 'LineWidth',2);
V.rel2 = plot(a1, nan, nan, '-', 'Color',[0.20 0.65 0.35], 'LineWidth',2);
V.expl = plot(a1, nan, nan, '--', 'Color',[0.60 0.40 0.90], 'LineWidth',1.5);
V.sat  = scatter(a1, X(:,1), Z(:,1), 80, repmat([0.6 0.4 0.9],geo.nSat,1), 'filled', 'MarkerEdgeColor','k');
V.satT = text(a1, nan, nan, '', 'FontSize',8, 'Color',[0.45 0.3 0.75]);
plot(a1, 0, RM, 's', 'MarkerSize',8, 'MarkerFaceColor',[0.95 0.55 0.1], 'MarkerEdgeColor','k');
V.clock = text(a1, -24, 24.5, '', 'FontSize',12, 'FontWeight','bold', 'VerticalAlignment','top');
V.state = text(a1, -24, 22.6, '', 'FontSize',9.5, 'VerticalAlignment','top');
legend(a1, [V.dte V.rel1 V.expl], {'base direct to Earth','through a relay','explorer to relay'}, 'Location','southwest','FontSize',8);

% ---------- south-pole surface
a2 = axes(fig,'Position',[0.01 0.02 0.34 0.34]); hold(a2,'on'); axis(a2,'off');
xlim(a2,[0 100]); ylim(a2,[0 40]);
V.ground = patch(a2,[0 100 100 0],[0 0 40 40],[0.93 0.93 0.90],'EdgeColor','none');
text(a2, 2, 38, sprintf('Lunar base: %s', r.baseH.name), 'FontWeight','bold','FontSize',10);
sw = min(8, 40/nSrv);
for j = 1:nSrv
    x0 = 4 + (j-1)*(sw+1.2);
    rectangle(a2,'Position',[x0 18 sw 14],'FaceColor','w','EdgeColor',[0.3 0.3 0.3]);
    V.srv(j) = rectangle(a2,'Position',[x0 18 sw 0.01],'FaceColor',[0.2 0.62 0.32],'EdgeColor','none');
    V.srvT(j) = text(a2, x0+sw/2, 16, '', 'HorizontalAlignment','center','FontSize',7.5);
end
V.baseT = text(a2, 4, 10, '', 'FontSize',9.5);
rng(3); nIn = 30; nOut = 20;
V.pin  = [55 + 20*rand(nIn,1), 6 + 28*rand(nIn,1)];
V.pout = [80 + 18*rand(nOut,1), 4 + 14*rand(nOut,1)];
patch(a2, [78 100 100 78], [2 2 20 20], [0.85 0.85 0.82], 'EdgeColor','none', 'FaceAlpha',0.7);
text(a2, 89, 21.5, 'crater (explorers)', 'HorizontalAlignment','center','FontSize',8);
V.rin  = scatter(a2, V.pin(:,1), V.pin(:,2), 22, zeros(nIn,3), 'filled');
V.rout = scatter(a2, V.pout(:,1), V.pout(:,2), 22, zeros(nOut,3), 'filled');
text(a2, 55, 37, 'robots in the base cell', 'FontSize',8);
V.haz  = text(a2, 50, 2.5, '', 'FontSize',10, 'FontWeight','bold', 'Color',[0.8 0.15 0.1]);
V.dark = patch(a2,[0 100 100 0],[0 0 40 40],[0.2 0.2 0.25],'FaceAlpha',0,'EdgeColor','none');

% ---------- strip charts
w = idx;
a3 = axes(fig,'Position',[0.68 0.71 0.30 0.25]); hold(a3,'on');
h0 = plot(a3, nan, nan); delete(h0);
ar = area(a3, d(w), [ts.pHouseKW(w); ts.pIdleKW(w); ts.pWorkKW(w); ts.pCoolKW(w)+ts.pTxKW(w)]', 'LineStyle','none');
cols = [0.62 0.62 0.62; 0.72 0.86 0.72; 0.20 0.62 0.32; 0.30 0.70 0.90];
for k = 1:4, ar(k).FaceColor = cols(k,:); end
hm = plot(a3, d(w), rm.ts.baseKW(w), 'r-', 'LineWidth',1);
ylabel(a3,'kW'); grid(a3,'on'); ylim(a3,[0 1.1*max(rm.ts.baseKW(w))]);
legend(a3, [ar(:)' hm], {'house','GPUs idle','GPUs working','cooling + radio','all on the Moon (2 x DGX)'}, 'Location','northwest','NumColumns',3,'FontSize',8,'AutoUpdate','off');
title(a3, 'Lunar base power, last 24 h');
V.cur3 = xline(a3, d(i0), 'k-');
a4 = axes(fig,'Position',[0.68 0.40 0.30 0.24]); hold(a4,'on');
yyaxis(a4,'left'); plot(a4, d(w), ts.earthJ(w)/dt/1e3, '-', 'Color',[0.3 0.5 0.9], 'LineWidth',1); ylabel(a4,'Earth, kW');
yyaxis(a4,'right'); plot(a4, d(w), ts.relayW(w), '-', 'Color',[0.6 0.4 0.9], 'LineWidth',1.2); ylabel(a4,'relays, W');
ylim(a4,[0 max(50, 1.2*max(ts.relayW(w)))]); grid(a4,'on');
title(a4, 'Earth data center and relay constellation, last 24 h');
V.cur4 = xline(a4, d(i0), 'k-');
a5 = axes(fig,'Position',[0.68 0.06 0.30 0.25]); hold(a5,'on');
V.bM = plot(a5, nan, nan, 'r-', 'LineWidth',2);
V.bC = plot(a5, nan, nan, '-', 'Color',[0.2 0.62 0.32], 'LineWidth',2.5);
xlim(a5, win); ylim(a5, [0 1.05*cM(idx(end))/1e3]); grid(a5,'on');
ylabel(a5,'energy bill, k$'); xlabel(a5,'day');
legend(a5, {'everything on the Moon','Fast Moon, Slow Earth'}, 'Location','northwest');
V.bT = text(a5, win(1)+0.03*diff(win), 0.55*cM(idx(end))/1e3, '', 'FontSize',11, 'FontWeight','bold');
title(a5, sprintf('Energy bill of %d robots since day %g', cfg.nRobots, win(1)));

V = reasoning_panel(fig, V);
V.i0 = i0;
% caption bar along the bottom: shrink every panel to make room
for ax = findall(fig,'Type','axes')'
    p = ax.Position; ax.Position = [p(1) 0.075 + 0.925*p(2) p(3) 0.925*p(4)];
end
V.cap = annotation(fig,'textbox',[0 0 1 0.068],'String','','BackgroundColor',[0.11 0.13 0.19],'Color','w', ...
    'FontSize',16,'EdgeColor','none','VerticalAlignment','middle','HorizontalAlignment','left','Margin',14,'FitBoxToText','off');
fps = 30; pauseF = round(1.3*fps);
if saveVideo
    vw = VideoWriter('lunar_fleet_power.mp4','MPEG-4'); vw.FrameRate = fps; vw.Quality = 60; open(vw);
end
% ---- intro: what is on screen
update_frame(V, idx(1), r, rm, geo, cfg, X, Z, ex, d, cB, cM, a3, a4, nSrv, nIn, nOut);
update_reasoning(V, idx(1), r, Acc);
G = guide_overlay(fig);
set(V.cap,'String',sprintf(['What you are watching: %d robots at the lunar south pole served by three data centers (the lunar base, ' ...
    'the LCRNS relay constellation, Earth), simulated every 5 minutes with real orbits and links.'], cfg.nRobots));
if saveVideo, write_n(vw, fig, 5*fps); end
delete(G);
caption = 'Normal operation: real time stays on the Moon (detector on the robot, 7B at the base); tactical reasoning runs on Earth while the link has room.';
set(V.cap,'String',caption);
for i = idx(1):cfg.frameStep:idx(end)
    update_frame(V, i, r, rm, geo, cfg, X, Z, ex, d, cB, cM, a3, a4, nSrv, nIn, nOut);
    update_reasoning(V, i, r, Acc);
    ev = events_at(i, r, geo, Acc, cfg);
    if ~isempty(ev), set(V.cap,'String',ev); end
    if saveVideo
        write_n(vw, fig, 1 + pauseF*~isempty(ev));        % hold the frame so the caption can be read
    end
end
% ---- closing card
w = idx(1):idx(end); ts = r.ts;
set(V.cap,'String',sprintf(['In %.0f days: %.0f Kimi K3 second opinions, %.0f wrong decisions fixed, every deadline met. ' ...
    'Energy bill $%s vs $%s with everything on the Moon (%.1fx cheaper).'], d(idx(end)) - d(idx(1)), sum(ts.escK3(w)), ...
    sum(ts.errFix(w)), commas(cB(idx(end))), commas(cM(idx(end))), cM(idx(end))/max(cB(idx(end)),eps)));
if saveVideo, write_n(vw, fig, 4*fps); close(vw); fprintf('Wrote lunar_fleet_power.mp4\n'); end
exportgraphics(fig, fullfile('figures','fleet_power_frame.png'), 'Resolution', 100);
end

function update_frame(V, i, r, rm, geo, cfg, X, Z, ex, d, cB, cM, a3, a4, nSrv, nIn, nOut)
ts = r.ts; dt = cfg.dt; RM = 1.7374;
% clock and state
hUTC = mod(geo.t(i)/3600, 24);
set(V.clock, 'String', sprintf('Day %.0f  %02d:%02d UTC', floor(d(i)), floor(hUTC), floor(mod(hUTC,1)*60)));
st = {}; if ts.shift(i) > 0.5, st{end+1} = 'operator shift'; else, st{end+1} = 'off shift (autonomy)'; end
if ~geo.sunlit(i), st{end+1} = 'ridge in shadow'; end
if geo.linkMbps(i) == 0, st{end+1} = 'NO LINK TO EARTH'; end
set(V.state, 'String', strjoin(st, '  |  '));
% relays
nTr = round(30*3600/dt); j0 = max(1, i - nTr);
for k = 1:geo.nSat, set(V.trail(k), 'XData', X(k,j0:i), 'YData', Z(k,j0:i)); end
sun = geo.satSun(:,i); work = ts.relayLoad(:,i) > 0;
col = repmat([0.75 0.75 0.75], geo.nSat, 1); col(sun,:) = repmat([0.70 0.60 0.95], sum(sun), 1);
col(work,:) = repmat([0.45 0.15 0.85], sum(work), 1);
set(V.sat, 'XData', X(:,i), 'YData', Z(:,i), 'CData', col, 'SizeData', 60 + 140*work);
if ts.relayW(i) > 0, set(V.satT, 'Position', [X(find(work,1),i)+1, Z(find(work,1),i)], 'String', sprintf('Thor %.0f W', ts.relayW(i)));
else, set(V.satT, 'String', ''); end
% links
k = ts.earthSite(i); toEarth = ts.tacEarth(i) + ts.deepEarth(i) > 0;
if geo.earthVis(i) && toEarth, set(V.dte, 'XData', [0 ex(k)], 'YData', [RM 27], 'Visible','on'); else, set(V.dte,'Visible','off'); end
rp = find(geo.satVis(:,i) & geo.satEarth(:,i), 1);
if ~geo.earthVis(i) && ~isempty(rp) && toEarth
    set(V.rel1, 'XData', [0 X(rp,i)], 'YData', [RM Z(rp,i)]); set(V.rel2, 'XData', [X(rp,i) ex(k)], 'YData', [Z(rp,i) 27]);
else, set([V.rel1 V.rel2], 'XData', nan, 'YData', nan); end
ep = find(geo.expVis(:,i), 1);
if ~isempty(ep), set(V.expl, 'XData', [0.6 X(ep,i)], 'YData', [RM Z(ep,i)]); else, set(V.expl, 'XData', nan, 'YData', nan); end
% Earth sites
[pr, pu] = earth_sites(cfg, geo.t(i)/3600);
for s = 1:numel(V.site)
    on = s == k && ts.earthJ(i) > 0;
    set(V.site(s), 'FaceColor', [0.9 0.93 1] - on*[0.35 0.25 0], 'LineWidth', 0.5 + 2.5*on);
    set(V.siteT(s), 'String', sprintf('%s\n$%.0f/MWh  %s', cfg.earthSites(s).name, 1e3*pr(s)*pu(s), ...
        ternary(on, sprintf('%.1f kW', ts.earthJ(i)/dt/1e3), 'idle')));
end
% servers
used = ts.util(i)*nSrv; warm = min(nSrv, ceil(used) + 1)*ts.baseOn(i);
for j = 1:nSrv
    f = min(1, max(0, used - (j-1)));
    p = get(V.srv(j), 'Position'); p(4) = max(0.01, 14*f); set(V.srv(j), 'Position', p);
    if ~ts.baseOn(i), lab = 'off'; elseif f > 0, lab = sprintf('%.0f%%', 100*f); elseif j <= warm, lab = 'warm'; else, lab = 'parked'; end
    set(V.srvT(j), 'String', lab);
end
set(V.baseT, 'String', sprintf('%.2f kW  (work %.2f, idle %.2f, cooling+radio %.2f, house %.1f)\nperception batch %d, %.0f J/frame', ...
    ts.baseKW(i), ts.pWorkKW(i), ts.pIdleKW(i), ts.pCoolKW(i)+ts.pTxKW(i), ts.pHouseKW(i), ts.batchPer(i), ts.jPer(i)));
% robots
drive = (0.10 + 0.55*ts.shift(i))*geo.sunlit(i); act = geo.sunlit(i);
ci = repmat([0.55 0.55 0.55], nIn, 1); ci(1:round(drive*nIn),:) = repmat([0.15 0.6 0.25], round(drive*nIn), 1);
co = repmat([0.55 0.55 0.55], nOut, 1); co(1:round(drive*nOut),:) = repmat([0.5 0.3 0.85], round(drive*nOut), 1);
jit = 0.6*act*randn(nIn,2); jo = 0.6*act*randn(nOut,2);
set(V.rin, 'XData', V.pin(:,1)+jit(:,1), 'YData', V.pin(:,2)+jit(:,2), 'CData', ci);
set(V.rout, 'XData', V.pout(:,1)+jo(:,1), 'YData', V.pout(:,2)+jo(:,2), 'CData', co);
set(V.haz, 'String', ternary(ts.hazard(i) > 0, 'HAZARD BURST: detector forwards 3x frames, more escalations', ''));
set(V.dark, 'FaceAlpha', 0.35*~geo.sunlit(i));
% strips
xlim(a3, [d(i)-1 d(i)]); xlim(a4, [d(i)-1 d(i)]); set([V.cur3 V.cur4], 'Value', d(i));
w = V.i0:i;
set(V.bM, 'XData', d(w), 'YData', cM(w)/1e3); set(V.bC, 'XData', d(w), 'YData', cB(w)/1e3);
set(V.bT, 'String', sprintf('saved so far: $%s  (%.1fx cheaper)', commas(cM(i) - cB(i)), cM(i)/max(cB(i),eps)));
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function s = commas(x)
s = regexprep(sprintf('%.0f', x), '\d(?=(\d{3})+$)', '$0,');
end

function im = grab_frame(fig)
try
    im = getframe(fig).cdata;
catch
    im = print(fig, '-RGBImage', '-r0');
end
end

function V = reasoning_panel(fig, V)
% Reasoning ladder for a robot in the base cell and an explorer in a crater
a6 = axes(fig,'Position',[0.36 0.02 0.30 0.96]); hold(a6,'on'); axis(a6,'off');
xlim(a6,[0 10]); ylim(a6,[0 20]);
text(a6, 5, 19.6, 'Reasoning available right now', 'HorizontalAlignment','center','FontWeight','bold','FontSize',15);
text(a6, 5, 18.9, 'depends on where the robot is and on the links at that moment', 'HorizontalAlignment','center','FontSize',10,'Color',[0.35 0.35 0.35]);
text(a6, 2.45, 18.1, 'Robot in the base cell', 'HorizontalAlignment','center','FontWeight','bold','FontSize',11.5);
text(a6, 7.55, 18.1, 'Explorer in a crater', 'HorizontalAlignment','center','FontWeight','bold','FontSize',11.5);
yl = [15.3 12.5 9.7 6.9 4.1];                                  % levels 5 (top) .. 1
for c = 1:2
    x0 = 0.15 + (c-1)*5.1;
    for L = 1:5
        y = yl(6-L);
        V.cell(c,L) = rectangle(a6,'Position',[x0 y 4.6 2.4],'Curvature',0.12,'FaceColor',[0.94 0.94 0.94],'EdgeColor',[0.8 0.8 0.8]);
        V.cellT(c,L) = text(a6, x0+2.3, y+1.55, '', 'HorizontalAlignment','center','FontWeight','bold','FontSize',11);
        V.cellS(c,L) = text(a6, x0+2.3, y+0.65, '', 'HorizontalAlignment','center','FontSize',9.5);
    end
    V.brain(c) = text(a6, x0+2.3, 3.35, '', 'HorizontalAlignment','center','FontSize',10.5,'FontWeight','bold');
end
text(a6, 0.15, 2.45, 'Kimi K3 second opinions (Earth)', 'FontWeight','bold','FontSize',11);
V.k3 = text(a6, 0.15, 1.35, '', 'FontSize',10.5, 'VerticalAlignment','middle');
text(a6, 0.15, 0.25, 'colour = data center that answers:  orange robot   green lunar base   purple relay   blue Earth;  bold border = answering decisions now', ...
    'FontSize',8.5,'Color',[0.35 0.35 0.35]);
V.a6 = a6;
end

function update_reasoning(V, i, r, A)
ts = r.ts;
cO = [0.95 0.65 0.20]; cBs = [0.20 0.62 0.32]; cR = [0.60 0.40 0.90]; cE = [0.30 0.50 0.90]; off = [0.94 0.94 0.94];
srcCol = {cBs, cR, cE}; srcTxt = {'lunar base, 0.8 s','relay Thor, 7.7 s','Earth, 2.6 s round trip'};
names = {'Reflexes + detector','Small 3B','Vision 7B','Reasoning 30B','Kimi K3 2.8T'};
for c = 1:2
    if c == 1, av = A.base(:,i); src = A.baseSrc(:,i); else, av = A.expl(:,i); src = A.explSrc(:,i); end
    use = 2; if av(4), use = 4; end
    for L = 1:5
        col = off; sub = ''; tc = [0.55 0.55 0.55];
        if ~A.act(i)
            sub = 'parked: ridge in shadow';
        elseif av(L)
            tc = 'w';
            switch L
                case 1, col = cO; sub = 'on board, 10 ms';
                case 2, col = cO; sub = 'on board, 4.5 s';
                case 3, col = cBs; sub = 'lunar base, 20 ms + batch';
                case 4, col = srcCol{src(1)}; sub = srcTxt{src(1)};
                case 5, col = cE; sub = 'Earth, store and forward, < 1 h';
            end
        else
            switch L
                case 3, sub = ternary(c == 2, 'out of the base cell', 'base off (battery empty)');
                case 4, sub = ternary(c == 2, 'no relay link, no relay compute', 'no link and base off');
                case 5, sub = 'no contact within the hour';
            end
        end
        lw = 0.5; ec = [0.8 0.8 0.8];
        if A.act(i) && L == use, lw = 3.5; ec = 'k'; end
        set(V.cell(c,L), 'FaceColor', col, 'LineWidth', lw, 'EdgeColor', ec);
        set(V.cellT(c,L), 'String', names{L}, 'Color', tc); set(V.cellS(c,L), 'String', sub, 'Color', tc);
    end
    if ~A.act(i), b = 'robots parked';
    elseif av(4), b = 'decides with a 30B model within 10 s';
    else, b = 'decides with its own 3B model only';
    end
    set(V.brain(c), 'String', b, 'Color', ternary(A.act(i) && ~av(4), [0.8 0.2 0.1], [0.15 0.15 0.15]));
end
w = V.i0:i;
set(V.k3, 'String', sprintf(['in flight %3.0f   |   answered %5.0f   |   wrong decisions fixed %4.0f\n' ...
    'robots act on the fast answer now; Kimi K3''s answer arrives later and corrects the plan'], ...
    ts.escQueue(i), sum(ts.escK3(w)), sum(ts.errFix(w))));
end

function write_n(vw, fig, n)
im = grab_frame(fig); hh = 16*floor(size(im,1)/16); ww = 16*floor(size(im,2)/16); im = im(1:hh,1:ww,:);
for k = 1:n, writeVideo(vw, im); end
end

function G = guide_overlay(fig)
% numbered labels over the four zones of the screen
z = {[0.005 0.42 0.35 0.55], '1  Orbits and links: the real LCRNS relay orbits seen from the side, the Earth data centers on top (lit = in use, with its price), the links in use'
     [0.01 0.08 0.34 0.32],  '2  Lunar base and robots: the servers fill up, stay warm or park; robots drive (colour) or idle with the operator shifts'
     [0.36 0.08 0.30 0.89],  '3  Reasoning available right now, for a robot in the base cell and an explorer in a crater: which models it can reach and which data center answers'
     [0.68 0.08 0.30 0.89],  '4  Power and money: lunar base power vs everything on the Moon, Earth and relay power, and the energy bill so far'};
G = gobjects(0);
for k = 1:size(z,1)
    G(end+1) = annotation(fig,'rectangle',z{k,1},'Color',[0.95 0.45 0.1],'LineWidth',3); %#ok<AGROW>
    p = z{k,1};
    G(end+1) = annotation(fig,'textbox',[p(1)+0.01 p(2)+p(4)/2-0.06 p(3)-0.02 0.12],'String',z{k,2}, ...
        'BackgroundColor',[1 1 1],'FaceAlpha',0.92,'EdgeColor',[0.95 0.45 0.1],'LineWidth',1.5,'FontSize',14,'FontWeight','bold', ...
        'HorizontalAlignment','center','VerticalAlignment','middle'); %#ok<AGROW>
end
end

function txt = events_at(i, r, geo, A, cfg)
% caption for anything that changes at step i (empty when nothing new happens)
txt = ''; if i < 2, return; end
ts = r.ts; h = mod(geo.t(i)/3600, 24);
act = A.act(i); actP = A.act(i-1);
if ~act && actP
    txt = 'The ridge goes into shadow. Robots park; the base keeps its servers on battery until it runs out.'; return; end
if act && ~actP
    txt = 'Sunrise on the ridge. Arrays recharge the battery, robots wake up and the base servers come back.'; return; end
if ts.baseOn(i-1) && ~ts.baseOn(i)
    txt = 'Battery empty: the base shuts down. With robots parked, only reflexes and the link to Earth remain.'; return; end
if ~act, return; end
lb = geo.linkMbps(i) > 0; lbP = geo.linkMbps(i-1) > 0;
if ~lb && lbP
    txt = ['The base loses its link to Earth (Earth below the horizon, relay out of view). Tactical decisions for robots ' ...
           'in the cell fall back to the base servers; second opinions wait in the queue.']; return; end
if lb && ~lbP
    txt = sprintf(['Link to Earth restored. The %.0f queued second opinions fly to Kimi K3; Earth power spikes ' ...
           'while the backlog drains.'], ts.escQueue(i-1)); return; end
le = A.expl(4,i); leP = A.expl(4,i-1);
if ~le && leP
    txt = ['The relay drops out of view of the crater. Explorers lose the 30B model and decide with their own 3B; ' ...
           'their hard questions wait for the next contact.']; return; end
if le && ~leP
    txt = 'The relay is back over the crater: explorers reach the 30B model on Earth again (2.6 s round trip).'; return; end
if ts.hazard(i) && ~ts.hazard(i-1)
    txt = sprintf(['Hazard burst near the base (dust, a lander plume). The on-board detector forwards 3x more frames; ' ...
           'the base batches them (batch %d, %.0f J per frame) and more decisions get a Kimi K3 second opinion.'], ...
           ts.batchPer(i), ts.jPer(i)); return; end
if ts.shift(i) > 0.5 && ts.shift(i-1) <= 0.5
    txt = sprintf(['%02.0f:00 UTC: the operator shift starts. Robots start driving, perception and tactical load rise ' ...
           'about 2.5x, and a burst of planning requests goes to Kimi K3 on Earth.'], floor(h)); return; end
if ts.shift(i) <= 0.5 && ts.shift(i-1) > 0.5
    txt = 'The shift ends. Robots switch to slow autonomous work; load drops and the base parks a server.'; return; end
if ts.earthJ(i) > 0 && ts.earthSite(i) ~= ts.earthSite(i-1) && ts.earthJ(i-1) > 0
    S = cfg.earthSites(ts.earthSite(i));
    txt = sprintf('Earth work moves to %s: the lowest price x PUE this hour ($%.0f/MWh).', S.name, ...
        1e3*ts.earthPrice(i)*ts.earthPUE(i)); return; end
end
