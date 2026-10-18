function lunar_animate(cfg, geo, res)
%LUNAR_ANIMATE 3D view of the Moon, the LCRNS relays and the base, with the
%   active link to Earth and a live panel of where the robots' inference runs.

RM = geo.RM; ts = res.ts;
nShow = min(geo.N, round(cfg.animDays*86400/cfg.dt));
idx = 1:cfg.frameStep:nShow;

fig = figure('Name','Lunar inference: 3D','Color',[0.04 0.05 0.09],'Position',[80 80 1350 760]);
try, theme(fig,'dark'); catch, end
ax3 = axes(fig,'Position',[0.02 0.06 0.58 0.88],'Color',[0.04 0.05 0.09]);
hold(ax3,'on'); axis(ax3,'equal','off'); view(ax3, 35, -18);

% Moon with a fixed random albedo pattern (repeatable)
rng(7); [X,Y,Z] = sphere(120);
alb = 0.62 + 0.08*imgaussfilt_safe(randn(size(X)), 3);
surf(ax3, RM*X, RM*Y, RM*Z, alb, 'EdgeColor','none','FaceColor','interp', ...
     'FaceLighting','gouraud','AmbientStrength',0.12,'DiffuseStrength',0.95,'SpecularStrength',0);
colormap(ax3, gray); caxis(ax3,[0 1]);
lt = light(ax3,'Style','infinite','Position',geo.sunDir(1,:));

% Orbits (one revolution from the start of the animation)
nRev = min(geo.N, round(geo.period_h*3600/cfg.dt)+1);
cols = lines(geo.nSat);
for k = 1:geo.nSat
    p = squeeze(geo.sat(k,1:nRev,:));
    plot3(ax3, p(:,1), p(:,2), p(:,3), '-', 'Color',[cols(k,:) 0.75], 'LineWidth',1.2);
end
hSat = gobjects(geo.nSat,1);
for k = 1:geo.nSat
    hSat(k) = plot3(ax3, nan, nan, nan, 'o', 'MarkerSize',9, 'MarkerFaceColor',cols(k,:), 'MarkerEdgeColor','w');
end
hBase  = plot3(ax3, nan,nan,nan, 's','MarkerSize',9,'MarkerFaceColor',[1 0.55 0.1],'MarkerEdgeColor','w');
hRelay = plot3(ax3, nan,nan,nan, '-','Color',[0.2 0.9 0.4],'LineWidth',2.5);
hView  = plot3(ax3, nan,nan,nan, ':','Color',[0.7 0.7 0.7],'LineWidth',0.8);
hDTE   = plot3(ax3, nan,nan,nan, '-','Color',[0.3 0.6 1],'LineWidth',2.5);
PU = [0.75 0.45 1.0];   % relay-constellation inference
hExp   = plot3(ax3, nan,nan,nan, '^','MarkerSize',9,'MarkerFaceColor',PU,'MarkerEdgeColor','w');
hRelC  = plot3(ax3, nan,nan,nan, '--','Color',PU,'LineWidth',2);
hEarth = quiver3(ax3,0,0,0,0,0,0,0,'Color',[0.3 0.6 1],'LineWidth',1.5,'MaxHeadSize',0.6);
hSun   = quiver3(ax3,0,0,0,0,0,0,0,'Color',[1 0.85 0.3],'LineWidth',1.5,'MaxHeadSize',0.6);
allp = reshape(geo.sat(:,1:nRev,:),[],3); pad = 1500;
xlim(ax3,[min(allp(:,1))-pad max(allp(:,1))+pad]); ylim(ax3,[min(allp(:,2))-pad max(allp(:,2))+pad]);
zlim(ax3,[min(allp(:,3))-pad max(allp(:,3))+pad]);
hTxtE = text(ax3,0,0,0,'Earth','Color',[0.4 0.7 1],'FontWeight','bold');
hTxtS = text(ax3,0,0,0,'Sun','Color',[1 0.85 0.3],'FontWeight','bold');
hLab = gobjects(geo.nSat,1);
for k = 1:geo.nSat, hLab(k) = text(ax3,0,0,0,sprintf(' SV%d',k),'Color',cols(k,:),'FontSize',9); end
hTitle = title(ax3,'','Color','w','FontSize',12);
annotation(fig,'textbox',[0.02 0.01 0.6 0.05],'String', ...
  'orange square: base | purple triangle: explorer in a crater | blue: base -> Earth direct | green: base -> relay -> Earth | purple dashed: explorer -> relay that runs its tactical model (ringed relays)', ...
  'Color',[0.85 0.85 0.85],'EdgeColor','none','FontSize',9);

% Inset: close-up of the south-polar base
axZ = axes(fig,'Position',[0.01 0.55 0.24 0.36],'Color','none'); hold(axZ,'on'); axis(axZ,'equal','off');
surf(axZ, RM*X, RM*Y, RM*Z, alb, 'EdgeColor','none','FaceColor','interp', ...
     'FaceLighting','gouraud','AmbientStrength',0.10,'DiffuseStrength',1,'SpecularStrength',0);
colormap(axZ, gray); caxis(axZ,[0 1]);
ltZ = light(axZ,'Style','infinite','Position',geo.sunDir(1,:));
zBase  = plot3(axZ,nan,nan,nan,'s','MarkerSize',10,'MarkerFaceColor',[1 0.55 0.1],'MarkerEdgeColor','w');
zRelay = plot3(axZ,nan,nan,nan,'-','Color',[0.2 0.9 0.4],'LineWidth',3);
zDTE   = plot3(axZ,nan,nan,nan,'-','Color',[0.3 0.6 1],'LineWidth',3);
zExp   = plot3(axZ,nan,nan,nan,'^','MarkerSize',9,'MarkerFaceColor',PU,'MarkerEdgeColor','w');
zRelC  = plot3(axZ,nan,nan,nan,'--','Color',PU,'LineWidth',2.5);
xlim(axZ,[-1.3 1.3]*RM); ylim(axZ,[-1.3 1.3]*RM); zlim(axZ,[-1.3 0.3]*RM);
title(axZ,'South pole close-up','Color','w');

% Right-hand panels
axL = axes(fig,'Position',[0.66 0.70 0.31 0.22]); styl(axL);
plot(axL, geo.t(1:nShow)'/86400, geo.linkMbps(1:nShow), 'Color',[0.3 0.6 1]); hold(axL,'on');
area(axL, geo.t(1:nShow)'/86400, 20*geo.sunlit(1:nShow), 'FaceColor',[1 0.85 0.3],'FaceAlpha',0.25,'EdgeColor','none');
cL = xline(axL, 0, 'w'); ylabel(axL,'Mbps to Earth'); title(axL,'Link to Earth and sunlight','Color','w');

axP = axes(fig,'Position',[0.66 0.40 0.31 0.22]); styl(axP);
P = [ts.tacBase(1:nShow); ts.tacRelay(1:nShow); ts.tacEarth(1:nShow); ts.tacMiss(1:nShow)]'/cfg.dt*3600;
ar = area(axP, geo.t(1:nShow)/86400, P, 'EdgeColor','none');
set(ar(1),'FaceColor',[0.2 0.7 0.35]); set(ar(2),'FaceColor',PU);
set(ar(3),'FaceColor',[0.3 0.5 0.9]);  set(ar(4),'FaceColor',[0.9 0.25 0.25]);
cP = xline(axP, 0, 'w'); ylabel(axP,'req/h');
legend(axP,{'lunar base','relays','Earth','missed'},'TextColor','w','Color','none','Location','southoutside','Orientation','horizontal');
title(axP,'Tactical reasoning: who thinks','Color','w');

axB = axes(fig,'Position',[0.66 0.10 0.31 0.22]); styl(axB);
D = [ts.deepEarth(1:nShow); ts.deepBase(1:nShow); ts.deepMiss(1:nShow)]'/cfg.dt*3600;
ar = area(axB, geo.t(1:nShow)/86400, D, 'EdgeColor','none');
set(ar(1),'FaceColor',[0.3 0.5 0.9]); set(ar(2),'FaceColor',[0.2 0.7 0.35]); set(ar(3),'FaceColor',[0.9 0.25 0.25]);
plot(axB, geo.t(1:nShow)/86400, ts.deepQueue(1:nShow), 'w:', 'LineWidth',1.2);
cB = xline(axB, 0, 'w'); xlabel(axB,'days'); ylabel(axB,'req/h, queue');
legend(axB,{'Earth (Kimi K3)','base fallback','missed','queued'},'TextColor','w','Color','none','Location','northeast');
title(axB,'Deep reasoning (can wait): store and forward to Earth','Color','w');

if cfg.saveVideo
    vw = VideoWriter('lunar_inference.mp4','MPEG-4'); vw.FrameRate = 24; open(vw);
end
for i = idx
    for k = 1:geo.nSat
        set(hSat(k),'XData',geo.sat(k,i,1),'YData',geo.sat(k,i,2),'ZData',geo.sat(k,i,3));
    end
    s = geo.site(i,:);
    set(hBase,'XData',s(1),'YData',s(2),'ZData',s(3));
    xp = geo.explorer(i,:);
    set(hExp,'XData',xp(1),'YData',xp(2),'ZData',xp(3)); set(zExp,'XData',xp(1),'YData',xp(2),'ZData',xp(3));
    busy = find(ts.relayLoad(:,i) > 0);
    if isempty(busy)
        set(hRelC,'XData',nan,'YData',nan,'ZData',nan); set(zRelC,'XData',nan,'YData',nan,'ZData',nan);
    else
        V = nan(3*numel(busy),3); VZ = V;
        for j = 1:numel(busy)
            sp = squeeze(geo.sat(busy(j),i,:))'; V(3*j-2,:) = xp; V(3*j-1,:) = sp;
            dd = sp - xp; VZ(3*j-2,:) = xp; VZ(3*j-1,:) = xp + 900*dd/norm(dd);
        end
        set(hRelC,'XData',V(:,1),'YData',V(:,2),'ZData',V(:,3));
        set(zRelC,'XData',VZ(:,1),'YData',VZ(:,2),'ZData',VZ(:,3));
    end
    for k = 1:geo.nSat
        if ts.relayLoad(k,i) > 0
            set(hSat(k),'MarkerSize',14,'MarkerEdgeColor',PU,'LineWidth',2.5);
        else
            set(hSat(k),'MarkerSize',9,'MarkerEdgeColor','w','LineWidth',0.5);
        end
    end
    vis = find(geo.satVis(:,i));
    if isempty(vis)
        set(hView,'XData',nan,'YData',nan,'ZData',nan);
    else
        V = nan(3*numel(vis),3);
        for j = 1:numel(vis), V(3*j-2,:) = s; V(3*j-1,:) = squeeze(geo.sat(vis(j),i,:))'; end
        set(hView,'XData',V(:,1),'YData',V(:,2),'ZData',V(:,3));
    end
    if geo.earthVis(i)
        e = s + 9000*geo.earthDir(i,:);
        set(hDTE,'XData',[s(1) e(1)],'YData',[s(2) e(2)],'ZData',[s(3) e(3)]);
        set(hRelay,'XData',nan,'YData',nan,'ZData',nan);
    elseif geo.relayPath(i)
        cand = find(geo.satVis(:,i) & geo.satEarth(:,i));
        [~,b] = max(geo.satEl(cand,i)); r = squeeze(geo.sat(cand(b),i,:))';
        set(hRelay,'XData',[s(1) r(1)],'YData',[s(2) r(2)],'ZData',[s(3) r(3)]);
        set(hDTE,'XData',nan,'YData',nan,'ZData',nan);
    else
        set(hRelay,'XData',nan,'YData',nan,'ZData',nan); set(hDTE,'XData',nan,'YData',nan,'ZData',nan);
    end
    E = 14000*geo.earthDir(i,:); Sd = 14000*geo.sunDir(i,:);
    set(hTxtE,'Position',1.08*E); set(hTxtS,'Position',1.08*Sd);
    for k = 1:geo.nSat, set(hLab(k),'Position',squeeze(geo.sat(k,i,:))'); end
    set(hEarth,'UData',E(1),'VData',E(2),'WData',E(3));
    set(hSun,'UData',Sd(1),'VData',Sd(2),'WData',Sd(3));
    lt.Position = geo.sunDir(i,:); ltZ.Position = geo.sunDir(i,:);
    set(zBase,'XData',s(1),'YData',s(2),'ZData',s(3));
    cam = s/norm(s); camtarget(axZ, cam*RM); campos(axZ, cam*RM*4.5 - 0.8*RM*geo.earthDir(i,:));
    camup(axZ, geo.earthDir(i,:)); camva(axZ, 38);
    if geo.earthVis(i)
        e2 = s + 900*geo.earthDir(i,:); set(zDTE,'XData',[s(1) e2(1)],'YData',[s(2) e2(2)],'ZData',[s(3) e2(3)]);
        set(zRelay,'XData',nan,'YData',nan,'ZData',nan);
    elseif geo.relayPath(i)
        rd = r - s; rd = rd/norm(rd); r2 = s + 900*rd;
        set(zRelay,'XData',[s(1) r2(1)],'YData',[s(2) r2(2)],'ZData',[s(3) r2(3)]);
        set(zDTE,'XData',nan,'YData',nan,'ZData',nan);
    else
        set(zRelay,'XData',nan,'YData',nan,'ZData',nan); set(zDTE,'XData',nan,'YData',nan,'ZData',nan);
    end
    tday = geo.t(i)/86400;
    set(cL,'Value',tday); set(cP,'Value',tday); set(cB,'Value',tday);
    if geo.sunlit(i), sunTxt = 'sunlit'; else, sunTxt = 'DARK'; end
    hTitle.String = sprintf('%s   %s   |  %s  |  link %g Mbps  |  relays in view %d', ...
        geo.siteInfo.name, datestr(cfg.epoch + seconds(geo.t(i)),'dd-mmm HH:MM'), ...
        sunTxt, geo.linkMbps(i), numel(vis));
    drawnow limitrate;
    if cfg.saveVideo
        im = getframe(fig).cdata;              % H.264 needs dimensions that are multiples of 16
        hh = 16*floor(size(im,1)/16); ww = 16*floor(size(im,2)/16);
        writeVideo(vw, im(1:hh,1:ww,:));
    end
end
if cfg.saveVideo, close(vw); end
end

function styl(a)
set(a,'Color',[0.08 0.09 0.14],'XColor',[0.8 0.8 0.8],'YColor',[0.8 0.8 0.8],'GridColor',[0.4 0.4 0.4]);
grid(a,'on'); hold(a,'on');
end

function B = imgaussfilt_safe(A, s)
% Gaussian smoothing without the Image Processing Toolbox
k = exp(-((-3*s:3*s).^2)/(2*s^2)); k = k/sum(k);
B = conv2(conv2(A, k, 'same'), k', 'same');
B = B/max(abs(B(:)));
end
