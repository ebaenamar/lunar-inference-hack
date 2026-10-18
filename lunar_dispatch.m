function res = lunar_dispatch(cfg, geo, C)
%LUNAR_DISPATCH Cognitive tiers: robot, relay constellation, lunar base, Earth.
%   Each robot issues four kinds of work with growing cognitive load:
%     reflex control (on board, always), perception (vision-language 7B, 1 s),
%     tactical reasoning (30B-A3B with images, 10 s) and deep reasoning
%     (Kimi K3 thinking, 1 h, store-and-forward allowed).
%   Robots near the base reach it through the surface cell; explorers in craters
%   reach only the LCRNS relays. Policies:
%     'EarthOnly'    everything off board goes to Earth
%     'BaseOnly'     everything off board goes to the lunar base
%     'Hierarchical' perception at the base, tactical at the base or on the relay
%                    constellation (each relay hosts its own replica), deep
%                    reasoning on Earth when a contact exists, base fallback
%                    only when the deadline is about to expire.

M = C.mdl; dt = cfg.dt; N = geo.N;
baseH  = pick_hw(C, cfg.baseHW);
board  = C.hw.Board; relayH = C.hw.RelayEdge; earthH = C.hw.EarthB200;
pol = cfg.policy;

% ---- Per-request costs on each tier
c.perBase   = request_cost(baseH,  M.VLM7B);
c.perBoard  = request_cost(board,  M.VLM7B);
c.perEarth  = request_cost(earthH, M.VLM7B);
c.tacBase   = request_cost(baseH,  M.Tactical);
c.tacRelay  = request_cost(relayH, M.Tactical);
c.tacEarth  = request_cost(earthH, M.Tactical);
c.tacBoard  = request_cost(board,  M.Tactical);
c.deepEarth = request_cost(earthH, M.DeepK3);
c.deepBase  = request_cost(baseH,  M.DeepK3);
if ~c.deepBase.fits, c.deepBase = request_cost(baseH, M.DeepDist); deepBaseName = 'distilled 30B-A3B';
else, deepBaseName = 'Kimi K3'; end
c.triage = c.perBase;
c.small  = request_cost(board, M.Small3B);   % on-board first stage of the cascade
relayRTT = 0.12;    % surface <-> relay at ~17,000 km, both ways

% ---- Deadlines met by each tier (latency only; capacity checked below)
okPerBase  = cfg.cellRTT + c.perBase.latency  <= cfg.perceptionDeadline;
okPerEarth = cfg.earthRTT + c.perEarth.latency <= cfg.perceptionDeadline;
okTacBase  = cfg.cellRTT + c.tacBase.latency  <= cfg.tacticalDeadline;
okTacRelay = relayRTT + c.tacRelay.latency    <= cfg.tacticalDeadline;
okTacEarth = cfg.earthRTT + c.tacEarth.latency <= cfg.tacticalDeadline;
deepCompute = cfg.earthRTT + c.deepEarth.latency;

% ---- Power system
houseKW = 2;
computeOn = ~strcmp(pol,'EarthOnly');
PmaxKW  = computeOn*baseH.Pmax/1000 + houseKW;
PidleKW = computeOn*baseH.Pidle/1000 + houseKW;
arrayKW = cfg.arrayMargin*PmaxKW; battKWh = cfg.batteryHours*PmaxKW;
nFission = ceil(PmaxKW/cfg.fissionKWe); isFission = strcmp(cfg.power,'Fission');
capSec = computeOn*(baseH.n/baseH.replica)*dt;

% ---- State
nBins = ceil(cfg.deepDeadline/dt);       % deep-reasoning queue, one bin per step of age
q = zeros(1,nBins);
z = zeros(1,N);
ts = struct('perBase',z,'perMiss',z,'perEarth',z, ...
    'tacBase',z,'tacRelay',z,'tacEarth',z,'tacMiss',z, ...
    'deepEarth',z,'deepBase',z,'deepMiss',z,'deepQueue',z, ...
    'relayLoad',zeros(geo.nSat,N),'sciRawMB',z,'sciSentMB',z,'backlogMB',z, ...
    'baseKW',z,'genKW',z,'soc',z,'baseOn',false(1,N),'util',z, ...
    'earthJ',z,'relayJ',z,'baseJ',z,'tacBoard',z,'boardJ',z,'baseReqJ',z,'escal',z);
soc = battKWh; backlog = 0;

for i = 1:N
    active = geo.sunlit(i) || cfg.robotsWorkInDark;
    Nin  = cfg.nRobots*(1-cfg.fracExploring)*active;
    Nout = cfg.nRobots*cfg.fracExploring*active;

    if isFission, genKW = nFission*cfg.fissionKWe; baseOn = computeOn;
    else, genKW = arrayKW*geo.sunlit(i); baseOn = computeOn && (genKW > 0 || soc > PidleKW*dt/3600); end
    free = capSec*baseOn;

    baseMB = geo.linkMbps(i)*dt/8;                          % base -> Earth
    expMB  = cfg.relayMbps*dt/8*geo.expRelayPath(i);         % explorers -> relay -> Earth
    relOK  = geo.expVis(:,i) & geo.satSun(:,i);              % relays that can compute for explorers
    relSec = sum(relOK)*relayH.n*dt;                         % replica-seconds on the constellation

    % ---------------- Perception (robots in the cell only)
    nPer = Nin*cfg.perceptionHz*dt; pB = 0; pE = 0; gate = 0;
    if strcmp(pol,'Coordinated')
        % an on-board detector screens every frame; only frames that change go to the base model
        gate = nPer*(1 - cfg.perceptionTrigger); nPer = nPer*cfg.perceptionTrigger;
    end
    if strcmp(pol,'EarthOnly')
        pE = nPer*(okPerEarth && baseMB > 0);
    elseif okPerBase && baseOn
        pB = min(nPer, free/c.perBase.replicaSec); free = free - pB*c.perBase.replicaSec;
    end
    pM = nPer - pB - pE;          % explorers run reflexes on board and do not request perception
    pB = pB + gate;               % screened frames are answered on board within the deadline

    % ---------------- Tactical reasoning
    tIn = Nin*dt/cfg.tacticalPeriod; tOut = Nout*dt/cfg.tacticalPeriod;
    tB = 0; tR = 0; tE = 0; tL = 0; esc = 0;
    if strcmp(pol,'Coordinated')
        % hard requests escalate to Kimi K3 on Earth (store and forward); the robot keeps
        % acting on its own small model meanwhile
        esc = cfg.escalateDeep*(tIn + tOut);
        tIn = (1-cfg.escalateDeep)*tIn; tOut = (1-cfg.escalateDeep)*tOut;
    end
    switch pol
        case 'EarthOnly'
            s1 = min(tIn,  okTacEarth*baseMB/cfg.tacticalMB); baseMB = baseMB - s1*cfg.tacticalMB;
            s2 = min(tOut, okTacEarth*expMB/cfg.tacticalMB);  expMB  = expMB  - s2*cfg.tacticalMB;
            tE = s1 + s2;
        case 'BaseOnly'
            if okTacBase && baseOn, tB = min(tIn, free/c.tacBase.replicaSec); free = free - tB*c.tacBase.replicaSec; end
        case 'Hierarchical'
            if okTacBase && baseOn, tB = min(tIn, free/c.tacBase.replicaSec); free = free - tB*c.tacBase.replicaSec; end
            pend = (tIn - tB) + tOut;                         % rest goes to the relays
            if okTacRelay, tR = min(pend, relSec/c.tacRelay.replicaSec); end
            pend = pend - tR;
            s2 = min(pend, okTacEarth*expMB/cfg.tacticalMB); expMB = expMB - s2*cfg.tacticalMB;
            tE = s2;
        case 'Coordinated'
            % cheapest node that meets the deadline: Earth while the link has room,
            % then the relays (explorers) or the base (robots in the cell)
            e1 = min(tIn,  okTacEarth*baseMB/cfg.tacticalMB); baseMB = baseMB - e1*cfg.tacticalMB;
            e2 = min(tOut, okTacEarth*expMB/cfg.tacticalMB);  expMB  = expMB  - e2*cfg.tacticalMB;
            tE = e1 + e2;
            restIn = tIn - e1; restOut = tOut - e2;
            if okTacRelay, tR = min(restOut, relSec/c.tacRelay.replicaSec); relSec = relSec - tR*c.tacRelay.replicaSec; end
            if okTacBase && baseOn, tB = min(restIn, free/c.tacBase.replicaSec); free = free - tB*c.tacBase.replicaSec; end
            r2 = restIn - tB;
            if okTacRelay && r2 > 0, x = min(r2, relSec/c.tacRelay.replicaSec); tR = tR + x; end
            % last resort: the on-board 3B model of the cascade
            pendAll = tIn + tOut - tE - tR - tB;
            if c.small.latency <= cfg.tacticalDeadline, tL = pendAll; end
    end
    tM = tIn + tOut - tB - tR - tE - tL;
    if any(relOK) && tR > 0
        ts.relayLoad(relOK,i) = tR/sum(relOK);
    end

    % ---------------- Deep reasoning: store-and-forward queue
    q = [ (Nin+Nout)*dt/cfg.deepPeriod + esc, q(1:end-1) ];  % age by one step; escalations join the queue
    expired = 0; dE = 0; dB = 0;
    if strcmp(pol,'BaseOnly')
        if baseOn, dB = min(sum(q), free/c.deepBase.replicaSec); free = free - dB*c.deepBase.replicaSec;
            q = take_oldest(q, dB); end
    else
        % send oldest first while the contact lasts
        sendable = (baseMB + expMB)/cfg.deepMB;
        latest = nBins - ceil(deepCompute/dt);              % older bins would miss the deadline
        qq = q; qq(latest+1:end) = 0;
        dE = min(sum(qq), sendable); q = take_oldest_upto(q, dE, latest);
        baseMB = max(0, baseMB - dE*cfg.deepMB);
        if any(strcmp(pol,{'Hierarchical','Coordinated'})) && baseOn   % fallback just before expiry
            last = q(end-1:end); nf = min(sum(last), free/c.deepBase.replicaSec);
            free = free - nf*c.deepBase.replicaSec; dB = nf; q = take_oldest(q, nf);
        end
    end
    expired = q(end); q(end) = 0;

    % ---------------- Science triage and downlink (robots in the cell)
    nImg = Nin*cfg.scienceImgHz*dt; tri = 0;
    if ~strcmp(pol,'EarthOnly') && baseOn
        tri = min(nImg, free/c.triage.replicaSec); free = free - tri*c.triage.replicaSec;
    end
    toSend = tri*cfg.scienceImgMB*cfg.triageKeep + (nImg - tri)*cfg.scienceImgMB;
    queue = backlog + toSend; sent = min(queue, baseMB); backlog = min(queue - sent, 2e6);

    % ---------------- Base power
    used = capSec*baseOn - free; u = 0; if baseOn && capSec > 0, u = used/capSec; end
    loadKW = (PidleKW - (~baseOn)*computeOn*baseH.Pidle/1000) + baseOn*(PmaxKW - PidleKW)*u;
    if ~isFission, soc = min(battKWh, max(0, soc + (genKW - loadKW)*dt/3600)); end

    ts.perBase(i)=pB; ts.perEarth(i)=pE; ts.perMiss(i)=pM;
    ts.tacBase(i)=tB; ts.tacRelay(i)=tR; ts.tacEarth(i)=tE; ts.tacMiss(i)=tM;
    ts.deepEarth(i)=dE; ts.deepBase(i)=dB; ts.deepMiss(i)=expired; ts.deepQueue(i)=sum(q);
    ts.sciRawMB(i)=nImg*cfg.scienceImgMB; ts.sciSentMB(i)=sent; ts.backlogMB(i)=backlog;
    ts.baseKW(i)=loadKW; ts.genKW(i)=genKW; ts.soc(i)=soc/max(battKWh,eps);
    ts.baseOn(i)=baseOn; ts.util(i)=u;
    ts.earthJ(i)=(tE*c.tacEarth.energyJ + dE*c.deepEarth.energyJ + pE*c.perEarth.energyJ)*cfg.earthPUE;
    ts.relayJ(i)=tR*c.tacRelay.energyJ;
    ts.tacBoard(i)=tL; ts.escal(i)=esc; ts.boardJ(i)=tL*c.small.energyJ + gate*cfg.detectorJ;
    ts.baseReqJ(i)=(pB-gate)*c.perBase.energyJ + tB*c.tacBase.energyJ + dB*c.deepBase.energyJ + tri*c.triage.energyJ;
    ts.baseJ(i)=loadKW*1e3*dt;
end

S = @(x) sum(x);
res.ts = ts; res.cost = c; res.deepBaseName = deepBaseName;
res.perOnTime  = S(ts.perBase+ts.perEarth)/max(S(ts.perBase+ts.perEarth+ts.perMiss),eps);
res.tacOnTime  = S(ts.tacBase+ts.tacRelay+ts.tacEarth+ts.tacBoard)/max(S(ts.tacBase+ts.tacRelay+ts.tacEarth+ts.tacBoard+ts.tacMiss),eps);
res.deepOnTime = S(ts.deepEarth+ts.deepBase)/max(S(ts.deepEarth+ts.deepBase+ts.deepMiss),eps);
res.deepSuperior = S(ts.deepEarth)/max(S(ts.deepEarth+ts.deepBase),eps);   % answered by Kimi K3
res.tacShare = [S(ts.tacBase) S(ts.tacRelay) S(ts.tacEarth) S(ts.tacMiss)]/max(S(ts.tacBase+ts.tacRelay+ts.tacEarth+ts.tacMiss),eps);
res.tacShare5 = [S(ts.tacBoard) S(ts.tacRelay) S(ts.tacBase) S(ts.tacEarth) S(ts.tacMiss)]/max(S(ts.tacBoard+ts.tacRelay+ts.tacBase+ts.tacEarth+ts.tacMiss),eps);
res.tierKWh = [S(ts.boardJ) S(ts.relayJ) S(ts.baseReqJ) S(ts.earthJ)]/3.6e6;   % marginal compute energy: robot relay base Earth
res.sciDelivered = min(1, S(ts.sciSentMB)/max(S(ts.sciRawMB)*(1-(~strcmp(pol,'EarthOnly'))*(1-cfg.triageKeep)),eps));
res.baseKWh = S(ts.baseJ)/3.6e6; res.earthKWh = S(ts.earthJ)/3.6e6; res.relayKWh = S(ts.relayJ)/3.6e6;
res.baseAvgKW = mean(ts.baseKW); res.baseUptime = mean(ts.baseOn);
res.baseH = baseH; res.relayH = relayH; res.computeMass = computeOn*baseH.mass;
res.PmaxKW = PmaxKW; res.arrayKW = arrayKW; res.battKWh = battKWh; res.nFission = nFission*isFission;
% kept for the summary panel
res.planBaseName = deepBaseName; res.planOnTime = res.deepOnTime;
end

function q = take_oldest(q, n)
for b = numel(q):-1:1
    if n <= 0, break; end
    d = min(q(b), n); q(b) = q(b) - d; n = n - d;
end
end

function q = take_oldest_upto(q, n, latest)
for b = latest:-1:1
    if n <= 0, break; end
    d = min(q(b), n); q(b) = q(b) - d; n = n - d;
end
end

function h = pick_hw(C, name)
switch name
    case 'Thor-cluster', h = C.hw.Thor_cluster;
    case 'DGX-B200',     h = C.hw.DGX_B200;
    case '2xDGX-B200',   h = C.hw.DGX_B200x2;
    case 'GPU-2035x2',   h = C.hw.GPU2035x2;
    otherwise, error('Unknown base hardware %s', name);
end
end
