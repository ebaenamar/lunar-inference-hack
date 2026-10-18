function lunar_robot_story(cfg, C, saveVideo)
%LUNAR_ROBOT_STORY Two robots' thoughts flowing to the tier that fits each timescale.
%   A robot in the base cell and an explorer in a crater. Every second the
%   in-cell robot sends perception to the lunar base; every two minutes each
%   robot asks for tactical reasoning (base for the in-cell robot, a relay for
%   the explorer); every half hour each sends deep reasoning to Earth, where
%   Kimi K3 answers. Running energy cost is compared with the same work done
%   all on the Moon or all on the robot. Schematic, not to scale.

if nargin < 3, saveVideo = false; end
L = lunar_savings(cfg, C, false); c = L.cost; P = L.usdPerKWh;   % [robot relay base earth]
usd = @(J, tier) J/3.6e6*P(tier);
fx = cfg.fracExploring;

T = 2*3600; dtv = 8; tt = 0:dtv:T;          % two hours, 8 s of mission per frame
nF = numel(tt);

% ---- Running cost of the same work under three strategies [$]
perHz = cfg.perceptionHz;
ev.tacIn  = 0:cfg.tacticalPeriod:T;  ev.tacOut = 30:cfg.tacticalPeriod:T;
ev.deepIn = 300:cfg.deepPeriod:T;    ev.deepOut = 900:cfg.deepPeriod:T;
cum = zeros(3,nF);   % rows: Coordinated, AllOnMoon, AllOnRobot
for f = 1:nF
    t = tt(f);
    nPer = t*perHz; nTi = sum(ev.tacIn<=t); nTo = sum(ev.tacOut<=t);
    nD = sum(ev.deepIn<=t) + sum(ev.deepOut<=t);
    cum(1,f) = nPer*usd(c.perBase.energyJ,3) + nTi*usd(c.tacBase.energyJ,3) + nTo*usd(c.tacRelay.energyJ,2) + nD*usd(c.deepEarth.energyJ*cfg.earthPUE,4); % energy at the meter
    cum(2,f) = nPer*usd(c.perBase.energyJ,3) + nTi*usd(c.tacBase.energyJ,3) + nD*usd(c.deepMoonK3.energyJ,3);
    cum(3,f) = nPer*usd(c.perThor.energyJ,1) + (nTi+nTo)*usd(c.tacThor.energyJ,1) + nD*usd(c.deepThor.energyJ,1);
end

% ---- Scene
bg = [0.03 0.04 0.08];
fig = figure('Name','Coordinated lunar data centers','Color',bg,'Position',[60 60 1400 780]);
try, theme(fig,'dark'); catch, end
ax = axes(fig,'Position',[0.02 0.08 0.58 0.84],'Color',bg); hold(ax,'on'); axis(ax,[0 100 0 60]); daspect(ax,[1 1 1]); axis(ax,'off');
fill(ax,[0 100 100 0],[0 0 14 14],[0.32 0.32 0.34],'EdgeColor','none');                       % regolith
fill(ax,[52 60 72 80],[14 6 6 14],[0.18 0.18 0.2],'EdgeColor','none');                          % crater
fill(ax,[8 14 20],[14 22 14],[0.45 0.45 0.47],'EdgeColor','none');                              % ridge
th = linspace(0,pi,40); fill(ax,26+6*cos(th),14+5*sin(th),[0.75 0.75 0.78],'EdgeColor','none'); % base dome
rectangle(ax,'Position',[30 14 6 4],'FaceColor',[0.2 0.62 0.32],'EdgeColor','none');
text(ax,26,24,{'Lunar base','DGX B200','perception + tactical'},'Color','w','HorizontalAlignment','center','FontSize',9);
plot(ax,[14 14],[22 27],'w'); plot(ax,14,27.5,'o','MarkerFaceColor',[0.95 0.65 0.2],'MarkerEdgeColor','none');
text(ax,14,30,'cell','Color',[0.8 0.8 0.8],'HorizontalAlignment','center','FontSize',8);
rIn  = [38 16]; rOut = [66 8];
robot(ax, rIn, [0.95 0.65 0.2]); text(ax,rIn(1),rIn(2)-4,'robot in cell','Color','w','HorizontalAlignment','center','FontSize',9);
robot(ax, rOut,[0.95 0.65 0.2]); text(ax,rOut(1),rOut(2)-4,'explorer in crater','Color','w','HorizontalAlignment','center','FontSize',9);
rel = [70 42];
fill(ax,rel(1)+[-1.5 1.5 1.5 -1.5],rel(2)+[-1 -1 1 1],[0.6 0.4 0.9],'EdgeColor','w');
fill(ax,rel(1)+[-6 -1.8 -1.8 -6],rel(2)+[-0.5 -0.5 0.5 0.5],[0.3 0.4 0.7],'EdgeColor','none');
fill(ax,rel(1)+[1.8 6 6 1.8],rel(2)+[-0.5 -0.5 0.5 0.5],[0.3 0.4 0.7],'EdgeColor','none');
text(ax,rel(1),rel(2)+4,{'LCRNS relay','edge node (2 x Thor)'},'Color','w','HorizontalAlignment','center','FontSize',9);
ear = [92 54]; th2 = linspace(0,2*pi,60);
fill(ax,ear(1)+5*cos(th2),ear(2)+5*sin(th2),[0.25 0.45 0.85],'EdgeColor','none');
text(ax,ear(1)-1,ear(2)-8,{'Earth data center','Kimi K3, $0.07/kWh'},'Color','w','HorizontalAlignment','center','FontSize',9);
hClock = text(ax,2,57,'','Color','w','FontSize',12,'FontWeight','bold');
% perception stream (pulsing) and packets
hPer = plot(ax,[rIn(1) 33],[rIn(2) 17],'-','Color',[0.2 0.85 0.4],'LineWidth',2);
pk = gobjects(0); pkData = zeros(0,7);   % [t0 dur x0 y0 x1 y1 kind]
cols = {[0.2 0.85 0.4],[0.75 0.5 1.0],[0.35 0.6 1.0],[1 1 1]};
legendTxt = {'every 1 s: perception -> base', 'every 2 min: tactical -> base / relay', ...
             'every 30 min: deep reasoning -> Earth (store and forward)', 'answer returns'};
for k = 1:4
    plot(ax, 3, 52-3*k, 'o','MarkerFaceColor',cols{k},'MarkerEdgeColor','none','MarkerSize',7);
    text(ax, 5, 52-3*k, legendTxt{k}, 'Color',[0.85 0.85 0.85],'FontSize',9);
end

% ---- Cost panel
ax2 = axes(fig,'Position',[0.66 0.45 0.31 0.45]); hold(ax2,'on'); grid(ax2,'on');
set(ax2,'Color',[0.08 0.09 0.14],'XColor',[0.8 0.8 0.8],'YColor',[0.8 0.8 0.8]);
cc = [0.75 0.5 1.0; 0.2 0.75 0.4; 0.95 0.65 0.2];
h1 = plot(ax2,nan,nan,'-','Color',cc(1,:),'LineWidth',3);
h2 = plot(ax2,nan,nan,'-','Color',cc(2,:),'LineWidth',2);
h3 = plot(ax2,nan,nan,'-','Color',cc(3,:),'LineWidth',2);
xlim(ax2,[0 T/60]); ylim(ax2,[0 1.05*max(cum(:))]);
xlabel(ax2,'mission minutes'); ylabel(ax2,'energy cost, $ (two robots)');
legend(ax2,{'coordinated','all on the Moon (K3 at base)','all on the robot'},'TextColor','w','Color','none','Location','northwest');
title(ax2,sprintf('Energy cost of the same thinking (%s launch)', cfg.launchPrice),'Color','w');
ax3 = axes(fig,'Position',[0.66 0.08 0.31 0.28]); axis(ax3,'off');
hTxt = text(ax3,0,1,'','Color','w','FontSize',11,'VerticalAlignment','top','FontName','Menlo','Interpreter','none');

if saveVideo
    vw = VideoWriter('lunar_robot_story.mp4','MPEG-4'); vw.FrameRate = 30; open(vw);
end
for f = 1:nF
    t = tt(f);
    % new packets
    newp = [];
    if any(abs(ev.tacIn - t) < dtv/2),  newp = [newp; t 60  rIn  33 17 2]; end
    if any(abs(ev.tacOut - t) < dtv/2), newp = [newp; t 80  rOut rel 2]; newp(end,5:6) = rel; end
    if any(abs(ev.deepIn - t) < dtv/2), newp = [newp; t 260 rIn ear 3]; end
    if any(abs(ev.deepOut - t) < dtv/2),newp = [newp; t 260 rOut ear 3]; end
    for k = 1:size(newp,1)
        pkData(end+1,:) = newp(k,:); %#ok<AGROW>
        pk(end+1) = plot(ax,nan,nan,'o','MarkerSize',10,'MarkerFaceColor',cols{newp(k,7)},'MarkerEdgeColor','w'); %#ok<AGROW>
    end
    % move packets; deep answers come back after Earth thinks
    keep = true(size(pkData,1),1);
    for k = 1:size(pkData,1)
        a = (t - pkData(k,1))/pkData(k,2);
        if a > 1
            if pkData(k,7) == 3          % Earth answered: send the reply back
                pkData(k,:) = [t+120 260 pkData(k,5:6) pkData(k,3:4) 4];
                set(pk(k),'MarkerFaceColor',cols{4},'XData',nan,'YData',nan);
            else
                keep(k) = false; delete(pk(k));
            end
            continue
        end
        if a < 0, set(pk(k),'XData',nan,'YData',nan); continue; end
        x = pkData(k,3) + a*(pkData(k,5)-pkData(k,3)); y = pkData(k,4) + a*(pkData(k,6)-pkData(k,4));
        if pkData(k,7) >= 3, y = y + 6*sin(pi*a); end
        set(pk(k),'XData',x,'YData',y);
    end
    pkData = pkData(keep,:); pk = pk(keep);
    set(hPer,'LineWidth',1.5 + 1.5*abs(sin(t/3)));
    set(hClock,'String',sprintf('t = %3d min', round(t/60)));
    set(h1,'XData',tt(1:f)/60,'YData',cum(1,1:f)); set(h2,'XData',tt(1:f)/60,'YData',cum(2,1:f)); set(h3,'XData',tt(1:f)/60,'YData',cum(3,1:f));
    set(hTxt,'String',{ ...
        sprintf('coordinated        $%7.2f', cum(1,f)), ...
        sprintf('all on the Moon    $%7.2f  (%.1fx)', cum(2,f), cum(2,f)/max(cum(1,f),eps)), ...
        sprintf('all on the robot   $%7.2f  (%.1fx)', cum(3,f), cum(3,f)/max(cum(1,f),eps)), '', ...
        sprintf('lunar power plant: %.0f kW vs %.0f kW', L.peakKW(4), L.peakKW(3)), ...
        sprintf('launch saved: $%.0f M', (L.plantUSD(3)-L.plantUSD(4))/1e6), ...
        sprintf('explorer served: yes (relay) vs no (all on Moon)')});
    drawnow limitrate;
    if saveVideo
        im = getframe(fig).cdata; hh = 16*floor(size(im,1)/16); ww = 16*floor(size(im,2)/16);
        writeVideo(vw, im(1:hh,1:ww,:));
    end
end
if saveVideo, close(vw); end
end

function robot(ax, p, col)
rectangle(ax,'Position',[p(1)-2 p(2)-1 4 2],'FaceColor',col,'EdgeColor','none','Curvature',0.2);
plot(ax,p(1)+[-1.5 1.5],p(2)-[1.3 1.3],'o','MarkerFaceColor',[0.2 0.2 0.2],'MarkerEdgeColor','w','MarkerSize',5);
plot(ax,p(1)+[1 1.6],p(2)+[1 2.6],'w-','LineWidth',1);
end
