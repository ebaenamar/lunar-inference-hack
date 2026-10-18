function A = reasoning_access(cfg, geo, r)
%REASONING_ACCESS Which models a robot can reach at each time step, by location.
%   Levels, from reflexes to the frontier model:
%     1 reflexes + frame detector (on board)
%     2 small 3B model (on board)
%     3 vision 7B at the lunar base (1 s deadline, base cell only)
%     4 tactical 30B within 10 s: at the base, on a relay, or on Earth through the link
%     5 Kimi K3 (2.8T) on Earth within the 1 h deadline, store and forward
%   A.base(level,i) / A.expl(level,i): reachable for a robot in the base cell / an
%   explorer in the crater. A.baseSrc / A.explSrc: where level 4 and 5 run
%   (0 none, 1 base, 2 relay, 3 Earth). A.maxB / A.maxE: largest level reachable
%   within 10 s.

ts = r.ts; N = geo.N; act = geo.sunlit(:)' | cfg.robotsWorkInDark;
baseOn  = ts.baseOn(:)';
linkB   = geo.linkMbps(:)' > 0;                          % base -> Earth (direct or relay)
linkE   = geo.expRelayPath(:)';                          % explorer -> relay -> Earth
relayC  = ts.relayBudgetW(:)' >= r.relayH.watts & any(geo.expVis,1);   % a sunlit relay in view can power a Thor
H = ceil(cfg.deepDeadline/cfg.dt);
soonB = movmax_fwd(linkB, H); soonE = movmax_fwd(linkE, H);  % a contact within the next hour

A.base = false(5,N); A.expl = false(5,N);
A.base(1,:) = act; A.expl(1,:) = act;
A.base(2,:) = act; A.expl(2,:) = act;
A.base(3,:) = act & baseOn;
A.base(4,:) = act & (baseOn | linkB);
A.expl(4,:) = act & (relayC | linkE);
A.base(5,:) = act & soonB;
A.expl(5,:) = act & soonE;
% where the 30B and Kimi K3 run (the coordinated rule: Earth first, then the Moon)
A.baseSrc = zeros(2,N); A.explSrc = zeros(2,N);
A.baseSrc(1,:) = 3*linkB + 1*(~linkB & baseOn);
A.explSrc(1,:) = 3*linkE + 2*(~linkE & relayC);
A.baseSrc(2,:) = 3*soonB; A.explSrc(2,:) = 3*soonE;
A.baseSrc(:,~act) = 0; A.explSrc(:,~act) = 0;
A.maxB = max((1:4)'.*A.base(1:4,:), [], 1);
A.maxE = max((1:4)'.*A.expl(1:4,:), [], 1);
A.names = {'reflexes + detector','3B on board','vision 7B','reasoning 30B','Kimi K3 2.8T'};
A.act = act;
end

function y = movmax_fwd(x, H)
% true if x is true now or within the next H steps
y = false(size(x)); n = numel(x);
nxt = inf;
for i = n:-1:1
    if x(i), nxt = i; end
    y(i) = nxt - i <= H;
end
end
