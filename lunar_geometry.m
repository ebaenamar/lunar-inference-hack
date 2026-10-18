function geo = lunar_geometry(cfg)
%LUNAR_GEOMETRY Orbits of the LCRNS reference constellation and site geometry.
%   Two-body Keplerian propagation of the NASA LCRNS Reference Constellation 3.1
%   initial states (Moon principal-axis frame at J2000, epoch 2027-03-01), with a
%   node regression of about 1 deg/day that reproduces the 90-day GMAT result.
%   The Moon rotates synchronously; Earth and Sun directions include optical
%   libration and the synodic month. Units: km, s, deg.

MU  = 4902.800066;      % km^3/s^2
RM  = 1737.4;           % km
d2r = pi/180;
WS  = 2*pi/(27.321661*86400);   % lunar sidereal rotation [rad/s]

t  = (0:cfg.dt:cfg.days*86400-cfg.dt)';   % N x 1
N  = numel(t);

% ---- LCRNS RC 3.1: [SMA ECC INC RAAN AOP TA] (NTRS 20250002698, Table 1)
EL = [11315.936501 0.691982 59.373229 321.019197 92.494031   0.000000
      11317.948675 0.691982 58.951732 320.997768 92.505016 180.000000
      11305.413654 0.691982 52.733096  81.148790 92.062891 140.049207
      11326.302154 0.691982 52.513419  81.138818 92.068945 195.992393
      11307.882863 0.691982 56.310396 204.889626 85.444071 164.007607];
% deployment phase: 1-5 relays of RC 3.1; beyond 5, a denser constellation adds
% copies of the five orbits phased by a fraction of the period
nSat = max(1, cfg.nRelays); nCopy = ceil(nSat/5);
idx  = mod(0:nSat-1, 5) + 1; copyOf = floor((0:nSat-1)/5);
EL   = EL(idx,:);
Tper = 2*pi*sqrt(EL(:,1).^3/MU);
shiftT = copyOf(:).*Tper/(2*nCopy);              % 1/4 period apart for 10 relays, 1/6 for 15
sat  = zeros(nSat,N,3);
for k = 1:nSat
    a = EL(k,1); e = EL(k,2); inc = EL(k,3)*d2r; w = EL(k,5)*d2r; nu = EL(k,6)*d2r;
    RA = EL(k,4)*d2r - 1.0*d2r*t/86400;          % node regression (Earth third body)
    E0 = 2*atan(sqrt((1-e)/(1+e))*tan(nu/2)); M0 = E0 - e*sin(E0);
    n  = sqrt(MU/a^3); M = M0 + n*(t + shiftT(k)); E = M;
    for it = 1:30, E = E - (E - e*sin(E) - M)./(1 - e*cos(E)); end
    xo = a*(cos(E)-e); yo = a*sqrt(1-e^2)*sin(E);
    P = [cos(RA)*cos(w)-sin(RA)*sin(w)*cos(inc), sin(RA)*cos(w)+cos(RA)*sin(w)*cos(inc), sin(w)*sin(inc)*ones(N,1)];
    Q = [-cos(RA)*sin(w)-sin(RA)*cos(w)*cos(inc), -sin(RA)*sin(w)+cos(RA)*cos(w)*cos(inc), cos(w)*sin(inc)*ones(N,1)];
    sat(k,:,:) = reshape(xo.*P + yo.*Q, [1 N 3]);
end
geo.period_h = 2*pi*sqrt(mean(EL(:,1))^3/MU)/3600;

% ---- Site (body-fixed -> inertial)
S = site_params(cfg.site);
rs = (RM + S.h)*[cosd(S.lat)*cosd(S.lon), cosd(S.lat)*sind(S.lon), sind(S.lat)];
site = rotz_rows(WS*t, repmat(rs,N,1));

% ---- Earth direction (optical libration) and Sun direction (synodic month)
lo = 7.9*d2r*sin(2*pi*t/(27.554*86400));
la = 6.7*d2r*sin(2*pi*t/(27.212*86400) + 1.0);
earthDir = rotz_rows(WS*t, [cos(la).*cos(lo), cos(la).*sin(lo), sin(la)]);
lam = -2*pi*t/(29.530589*86400) + S.sunPhase;
dec = S.sunDec*d2r;
sunDir = rotz_rows(WS*t, [cos(dec)*cos(lam), cos(dec)*sin(lam), sin(dec)*ones(N,1)]);

% ---- Local frame at the site
up    = site./vecnorm(site,2,2);
east  = cross(repmat([0 0 1],N,1), up, 2); east = east./vecnorm(east,2,2);
north = cross(up, east, 2);
[sunEl, sunAz]     = el_az(sunDir, up, east, north);
[earthEl, ~]       = el_az(earthDir, up, east, north);

% Terrain: horizon dip from site height plus one obstructing massif
inSector = mod(sunAz - S.obsAz0, 360) < S.obsWidth;
sunlit   = sunEl > (S.obsHeight*inSector - S.dip);
earthVis = earthEl > (0.5 - S.dip);

% ---- Relay visibility and relay-to-Earth occultation by the Moon
satVis = false(nSat,N); satEarth = false(nSat,N); satEl = zeros(nSat,N);
for k = 1:nSat
    r  = squeeze(sat(k,:,:));
    d  = r - site; dn = d./vecnorm(d,2,2);
    satEl(k,:)  = asind(sum(up.*dn,2))';
    satVis(k,:) = satEl(k,:) > cfg.relayMinEl;
    p    = sum(r.*earthDir,2);
    perp = vecnorm(r - p.*earthDir,2,2);
    satEarth(k,:) = ~((p < 0) & (perp < RM))';
end
relayPath = any(satVis & satEarth, 1);

% ---- Link capacity to Earth [Mbps]
linkMbps = zeros(1,N);
linkMbps(relayPath) = cfg.relayMbps;
linkMbps(earthVis') = cfg.dteMbps;

% ---- Exploring robots: outside the base cell, inside a crater (higher terrain mask)
re = (RM + 0)*[cosd(cfg.exploreLat)*cosd(cfg.exploreLon), cosd(cfg.exploreLat)*sind(cfg.exploreLon), sind(cfg.exploreLat)];
xpl = rotz_rows(WS*t, repmat(re,N,1)); upE = xpl./vecnorm(xpl,2,2);
expVis = false(nSat,N);
for k = 1:nSat
    d = squeeze(sat(k,:,:)) - xpl; dn = d./vecnorm(d,2,2);
    expVis(k,:) = (asind(sum(upE.*dn,2)) > cfg.exploreMaskDeg)';
end

% ---- Relay eclipses by the Moon (relay compute runs on its solar bus)
satSun = false(nSat,N);
for k = 1:nSat
    r = squeeze(sat(k,:,:)); p = sum(r.*sunDir,2); perp = vecnorm(r - p.*sunDir,2,2);
    satSun(k,:) = ~((p < 0) & (perp < RM))';
end
geo.explorer = xpl; geo.expVis = expVis; geo.satSun = satSun;
geo.expRelayPath = any(expVis & satEarth, 1);

geo.t = t; geo.N = N; geo.RM = RM; geo.sat = sat; geo.nSat = nSat; geo.site = site;
geo.siteInfo = S; geo.earthDir = earthDir; geo.sunDir = sunDir;
geo.sunEl = sunEl'; geo.earthEl = earthEl'; geo.sunlit = sunlit'; geo.earthVis = earthVis';
geo.satVis = satVis; geo.satEarth = satEarth; geo.satEl = satEl;
geo.relayPath = relayPath; geo.linkMbps = linkMbps;
geo.illumFrac = mean(sunlit);
end

% ------------------------------------------------------------------------
function S = site_params(name)
switch name
    case 'Malapert'          % Malapert Peak, ~5 km high, Earth always in view
        S = struct('name','Malapert Peak','lat',-86.0,'lon',0,'h',5,'dip',4.35, ...
                   'obsAz0',200,'obsWidth',25,'obsHeight',12,'sunDec',-1.0,'sunPhase',0.3);
    case 'ConnectingRidge'   % near Shackleton, Earth low on the horizon
        S = struct('name','Connecting Ridge','lat',-89.45,'lon',-137,'h',1,'dip',1.9, ...
                   'obsAz0',200,'obsWidth',25,'obsHeight',8,'sunDec',-1.0,'sunPhase',0.3);
    case 'FarSide'           % mid-latitude far side: no Earth, 14.8-day night
        S = struct('name','Far side (45S,180E)','lat',-45,'lon',180,'h',0,'dip',0, ...
                   'obsAz0',0,'obsWidth',0,'obsHeight',0,'sunDec',-1.0,'sunPhase',0.3);
    otherwise
        error('Unknown site %s', name);
end
end

function v = rotz_rows(th, u)
c = cos(th); s = sin(th);
v = [c.*u(:,1) - s.*u(:,2), s.*u(:,1) + c.*u(:,2), u(:,3)];
end

function [el, az] = el_az(d, up, east, north)
el = asind(max(-1,min(1,sum(up.*d,2))));
az = mod(atan2d(sum(east.*d,2), sum(north.*d,2)), 360);
end
