function W = work_profile(cfg, geo)
%WORK_PROFILE Time-varying robot workload: operator shifts, hazard bursts, random arrivals.
%   Lunar surface operations are supervised from Earth in shifts. During a
%   shift most robots drive (perception at full rate) or work at science stops;
%   off shift they run slow autonomous tasks or charge. Each shift starts with a
%   planning burst of deep-reasoning requests. Hazard bursts (lander plumes,
%   dust, unexpected terrain) make the on-board detector forward more frames.
%   Request counts follow Poisson statistics around the mean.
%   Multipliers have mean 1 while the robots work, so daily totals match the
%   nominal rates in lunar_config.m.

N = geo.N; h = mod(geo.t(:)'/3600, 24);                  % hours UTC
rs = RandStream('mt19937ar','Seed',cfg.seed);

% operator shift (UTC), with one-hour ramps
on = cfg.shiftStartUTC; len = cfg.shiftHours;
x = mod(h - on, 24);
shift = min(1, max(0, min(x, len - x) + 0.5));          % 0 off shift, 1 on shift
drive = 0.10 + 0.55*shift;                               % share of robots driving
sci   = 0.30 + 0.05*shift;                               % share at science stops
W.drive = drive; W.shift = shift;
W.per   = (drive + 0.2*sci);                             % perception load
W.tac   = (drive + sci);                                 % tactical decisions
W.sci   = sci;                                           % science imaging
W.deep  = 0.6 + 2.5*exp(-((mod(h - on, 24) - 1)/0.8).^2);% shift-start planning burst

% hazard bursts: Poisson events, ~45 min each, detector forwards 3x the frames
W.trig = ones(1,N);
t = 0; T = cfg.days*86400;
while true
    t = t - 86400/cfg.hazardPerDay*log(rand(rs));           % exponential gaps between events
    if t >= T, break; end
    L = -cfg.hazardMin*60*log(rand(rs));                    % exponential duration
    i0 = max(1, round(t/cfg.dt)); i1 = min(N, i0 + max(1, round(L/cfg.dt)));
    W.trig(i0:i1) = cfg.hazardTriggerMul;
end

% normalise to mean 1 over working time
act = geo.sunlit(:)' | cfg.robotsWorkInDark; if ~any(act), act = true(1,N); end
for f = {'per','tac','sci','deep'}
    W.(f{1}) = W.(f{1})/mean(W.(f{1})(act));
end

% Poisson draws for request counts (normal approximation above 20)
W.pois = @(mu) pois(rs, mu);
end

function n = pois(rs, mu)
if mu <= 0, n = 0;
elseif mu > 20, n = max(0, round(mu + sqrt(mu)*randn(rs)));
else
    L = exp(-mu); n = 0; p = rand(rs);
    while p > L, n = n + 1; p = p*rand(rs); end
end
end
