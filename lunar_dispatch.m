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

% size the power plant to the load: a first pass with the nameplate plant measures
% the peak draw, the second pass runs with a plant sized to that peak plus margin
if cfg.sizeToLoad && ~isfield(cfg,'designKW')
    c1 = cfg; c1.sizeToLoad = false; r0 = lunar_dispatch(c1, geo, C);
    cfg.designKW = cfg.peakMargin*max(r0.ts.baseKW);
end
cfg = earth_tier(cfg);
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

% ---- Dynamic batching tables: latency and energy per request for every batch size
Tb.perBase   = batch_table(baseH,  M.VLM7B);
Tb.tacBase   = batch_table(baseH,  M.Tactical);
Tb.tacEarth  = batch_table(earthH, M.Tactical);
Tb.deepEarth = batch_table(earthH, M.DeepK3);
if strcmp(deepBaseName,'Kimi K3'), Tb.deepBase = batch_table(baseH, M.DeepK3);
else, Tb.deepBase = batch_table(baseH, M.DeepDist); end
c0 = c;

% ---- Deadlines met by each tier (latency only; capacity checked below)
okPerBase  = cfg.cellRTT + c.perBase.latency  <= cfg.perceptionDeadline;
okPerEarth = cfg.earthRTT + c.perEarth.latency <= cfg.perceptionDeadline;
okTacBase  = cfg.cellRTT + c.tacBase.latency  <= cfg.tacticalDeadline;
okTacRelay = relayRTT + c.tacRelay.latency    <= cfg.tacticalDeadline;
okTacEarth = cfg.earthRTT + c.tacEarth.latency <= cfg.tacticalDeadline;
deepCompute = cfg.earthRTT + c.deepEarth.latency;

% ---- Power system
houseKW = cfg.houseKW;
computeOn = ~strcmp(pol,'EarthOnly');
PmaxKW  = computeOn*baseH.Pmax/1000*(1 + cfg.moonCoolSun) + houseKW + cfg.dteTxW/1000;
PidleKW = computeOn*baseH.Pidle/1000 + houseKW;
nameKW  = PmaxKW;
if isfield(cfg,'designKW'), PmaxKW = cfg.designKW; end
arrayKW = cfg.arrayMargin*PmaxKW; battKWh = cfg.batteryHours*PmaxKW;
nFission = ceil(PmaxKW/cfg.fissionKWe); isFission = strcmp(cfg.power,'Fission');
capSec = computeOn*baseH.n*dt;                 % chip-seconds per step

% ---- Workload over time (shifts, bursts, random arrivals)
Wk = work_profile(cfg, geo); P = Wk.pois;

% ---- State
nBins = ceil(cfg.deepDeadline/dt);       % deep-reasoning queue, one bin per step of age
q = zeros(1,nBins); qE = q;              % qE: escalations inside the deep queue
z = zeros(1,N);
ts = struct('perBase',z,'perMiss',z,'perEarth',z, ...
    'tacBase',z,'tacRelay',z,'tacEarth',z,'tacMiss',z, ...
    'deepEarth',z,'deepBase',z,'deepMiss',z,'deepQueue',z, ...
    'relayLoad',zeros(geo.nSat,N),'sciRawMB',z,'sciSentMB',z,'backlogMB',z, ...
    'baseKW',z,'genKW',z,'soc',z,'baseOn',false(1,N),'util',z, ...
    'earthJ',z,'relayJ',z,'baseJ',z,'tacBoard',z,'boardJ',z,'baseReqJ',z,'escal',z, ...
    'pCompKW',z,'pIdleKW',z,'pWorkKW',z,'pCoolKW',z,'pTxKW',z,'pHouseKW',z,'batchPer',z,'batchTacE',z,'jPer',z,'jTacE',z, ...
    'escSent',z,'escQueue',z,'escK3',z,'escWait',z,'errFast',z,'errFix',z,'arrPer',z,'arrTac',z,'arrDeep',z,'shift',z,'hazard',z,'relayW',z,'relayLinkUse',z,'relayBudgetW',z,'earthUSD',z,'earthSite',z,'earthPrice',z,'earthPUE',z,'earthCO2g',z);
soc = battKWh; backlog = 0;

for i = 1:N
    active = geo.sunlit(i) || cfg.robotsWorkInDark;
    Nin  = cfg.nRobots*(1-cfg.fracExploring)*active;
    Nout = cfg.nRobots*cfg.fracExploring*active;

    if isFission, genKW = nFission*cfg.fissionKWe; baseOn = computeOn;
    else, genKW = arrayKW*geo.sunlit(i); baseOn = computeOn && (genKW > 0 || soc > PidleKW*dt/3600); end
    free = capSec*baseOn;

    % deadline-aware dynamic batching: the base holds requests while the deadline
    % allows and runs them together on as few GPUs as possible; the Earth fleet is
    % shared with other tenants and always runs at its nominal batch
    c = c0; trig = 1; if strcmp(pol,'Coordinated'), trig = min(1, cfg.perceptionTrigger*Wk.trig(i)); end
    c.perBase   = pick_batch(Tb.perBase,  Nin*cfg.perceptionHz*Wk.per(i)*trig, cfg.perceptionDeadline - cfg.cellRTT);
    c.triage    = pick_batch(Tb.perBase,  Nin*cfg.scienceImgHz*Wk.sci(i),      dt);
    c.tacBase   = pick_batch(Tb.tacBase,  Nin/cfg.tacticalPeriod*Wk.tac(i),    cfg.tacticalDeadline - cfg.cellRTT);
    c.deepBase  = pick_batch(Tb.deepBase, (Nin+Nout)/cfg.deepPeriod*Wk.deep(i), dt);
    okPerBase  = cfg.cellRTT + c.perBase.latency  <= cfg.perceptionDeadline;
    okTacBase  = cfg.cellRTT + c.tacBase.latency  <= cfg.tacticalDeadline;
    okTacEarth = cfg.earthRTT + c.tacEarth.latency <= cfg.tacticalDeadline;
    deepCompute = cfg.earthRTT + c.deepEarth.latency;

    % relay power budget: solar bus minus the transmitter when it relays traffic
    relaying = geo.expRelayPath(i) | (~geo.earthVis(i) & geo.relayPath(i));
    relW = zeros(geo.nSat,1); nThor = zeros(geo.nSat,1);
    for k = 1:geo.nSat
        if geo.satSun(k,i)
            relW(k) = cfg.relayBusW - (cfg.relayTxW*relaying + 10*~relaying)*geo.expVis(k,i);
            nThor(k) = min(relayH.n, floor(max(0,relW(k))/relayH.watts));
        end
    end
    baseMB = geo.linkMbps(i)*dt/8;                          % base -> Earth
    expMB  = cfg.relayMbps*dt/8*geo.expRelayPath(i);         % explorers -> relay -> Earth
    expCap = expMB;
    relOK  = geo.expVis(:,i) & geo.satSun(:,i);              % relays that can compute for explorers
    relSec = sum(nThor(relOK))*dt;                           % replica-seconds the relay power allows

    % ---------------- Perception (robots in the cell only)
    nPer = P(Nin*cfg.perceptionHz*dt*Wk.per(i)); pB = 0; pE = 0; gate = 0;
    if strcmp(pol,'Coordinated')
        % an on-board detector screens every frame; only frames that change go to the base model
        gate = nPer*(1 - trig); nPer = nPer*trig;
    end
    if strcmp(pol,'EarthOnly')
        pE = nPer*(okPerEarth && baseMB > 0);
    elseif okPerBase && baseOn
        pB = min(nPer, free/c.perBase.gpuSec); free = free - pB*c.perBase.gpuSec;
    end
    pM = nPer - pB - pE;          % explorers run reflexes on board and do not request perception
    pB = pB + gate;               % screened frames are answered on board within the deadline

    % ---------------- Tactical reasoning
    tIn = P(Nin*dt/cfg.tacticalPeriod*Wk.tac(i)); tOut = P(Nout*dt/cfg.tacticalPeriod*Wk.tac(i));
    tB = 0; tR = 0; tE = 0; tL = 0; esc = 0; escK3 = 0; escDist = 0; escWait = 0;
    if strcmp(pol,'Coordinated')
        % distributed reasoning: every request gets a fast answer on the Moon; the ones
        % the fast model is unsure about also go to Kimi K3 on Earth (store and forward)
        hz = 1 + (cfg.escalateHazardMul - 1)*(Wk.trig(i) > 1);
        esc = min(1, cfg.escalateBase*hz)*(tIn + min(1/cfg.escalateBase, cfg.escalateExplorerMul)*tOut);
    elseif strcmp(pol,'Hierarchical')
        esc = 0;
    end
    switch pol
        case 'EarthOnly'
            s1 = min(tIn,  okTacEarth*baseMB/cfg.tacticalMB); baseMB = baseMB - s1*cfg.tacticalMB;
            s2 = min(tOut, okTacEarth*expMB/cfg.tacticalMB);  expMB  = expMB  - s2*cfg.tacticalMB;
            tE = s1 + s2;
        case 'BaseOnly'
            if okTacBase && baseOn, tB = min(tIn, free/c.tacBase.gpuSec); free = free - tB*c.tacBase.gpuSec; end
        case 'Hierarchical'
            if okTacBase && baseOn, tB = min(tIn, free/c.tacBase.gpuSec); free = free - tB*c.tacBase.gpuSec; end
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
            if okTacBase && baseOn, tB = min(restIn, free/c.tacBase.gpuSec); free = free - tB*c.tacBase.gpuSec; end
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
    q  = [ P((Nin+Nout)*dt/cfg.deepPeriod*Wk.deep(i)) + esc, q(1:end-1) ];  % age by one step; escalations join the queue
    qE = [ esc, qE(1:end-1) ];
    expired = 0; dE = 0; dB = 0; q0 = q;
    if strcmp(pol,'BaseOnly')
        if baseOn, dB = min(sum(q), free/c.deepBase.gpuSec); free = free - dB*c.deepBase.gpuSec;
            q = take_oldest(q, dB); end
    else
        % send oldest first while the contact lasts
        sendable = (baseMB + expMB)/cfg.deepMB;
        latest = nBins - ceil(deepCompute/dt);              % older bins would miss the deadline
        qq = q; qq(latest+1:end) = 0;
        dE = min(sum(qq), sendable); q = take_oldest_upto(q, dE, latest);
        mb = dE*cfg.deepMB; u1 = min(baseMB, mb); baseMB = baseMB - u1; expMB = max(0, expMB - (mb - u1));
        % escalations answered by Kimi K3 this step, and how long they waited
        kept = q./max(q0,eps); kept(q0 <= 0) = 1; sE = qE.*(1 - kept); qE = qE - sE; q0 = q;
        escK3 = sum(sE); escWait = sum(sE.*(0:nBins-1))*dt + escK3*deepCompute;
        if any(strcmp(pol,{'Hierarchical','Coordinated'})) && baseOn   % fallback just before expiry
            last = q(end-1:end); nf = min(sum(last), free/c.deepBase.gpuSec);
            free = free - nf*c.deepBase.gpuSec; dB = nf; q = take_oldest(q, nf);
            kept = q./max(q0,eps); kept(q0 <= 0) = 1; sB = qE.*(1 - kept); qE = qE - sB; escDist = sum(sB);
        end
    end
    expired = q(end); q(end) = 0; qE(end) = 0;
    % decision quality: fast answers, then corrections by the slow reasoner
    errFast = (tB + tR + tE)*cfg.err30B + tL*cfg.err3B;
    fix = min(errFast, cfg.escPrecision*(cfg.k3Fix*escK3 + cfg.distFix*escDist));

    % ---------------- Science triage and downlink (robots in the cell)
    nImg = P(Nin*cfg.scienceImgHz*dt*Wk.sci(i)); tri = 0;
    if ~strcmp(pol,'EarthOnly') && baseOn
        tri = min(nImg, free/c.triage.gpuSec); free = free - tri*c.triage.gpuSec;
    end
    toSend = tri*cfg.scienceImgMB*cfg.triageKeep + (nImg - tri)*cfg.scienceImgMB;
    queue = backlog + toSend; sent = min(queue, baseMB); backlog = min(queue - sent, 2e6);

    % ---------------- Base power
    used = capSec*baseOn - free; u = 0; if baseOn && capSec > 0, u = used/capSec; end
    busyJ = (pB-gate)*c.perBase.energyJ + tB*c.tacBase.energyJ + dB*c.deepBase.energyJ + tri*c.triage.energyJ;
    % chips that are needed stay warm (30% TDP when idle), the rest are parked (5% TDP)
    usedChip = used/dt; warm = min(baseH.n, ceil(usedChip) + 1);
    idleW = baseH.idleFrac*baseH.watts*max(0, warm - usedChip) + 0.05*baseH.watts*(baseH.n - warm);
    pComp = baseOn*computeOn*(idleW + busyJ/dt)/1000;
    coolF = cfg.moonCoolDark + (cfg.moonCoolSun - cfg.moonCoolDark)*geo.sunlit(i);
    pCool = pComp*coolF;
    txW   = cfg.relayTxW; if geo.earthVis(i), txW = cfg.dteTxW; end
    linkTot = geo.linkMbps(i)*dt/8;
    pTx   = baseOn*txW/1000*min(1, ((linkTot - baseMB) + sent)/max(linkTot,eps));   % transmitter duty cycle
    loadKW = houseKW + pComp + pCool + pTx;
    if ~isFission, soc = min(battKWh, max(0, soc + (genKW - loadKW)*dt/3600)); end

    ts.perBase(i)=pB; ts.perEarth(i)=pE; ts.perMiss(i)=pM;
    ts.tacBase(i)=tB; ts.tacRelay(i)=tR; ts.tacEarth(i)=tE; ts.tacMiss(i)=tM;
    ts.deepEarth(i)=dE; ts.deepBase(i)=dB; ts.deepMiss(i)=expired; ts.deepQueue(i)=sum(q);
    ts.sciRawMB(i)=nImg*cfg.scienceImgMB; ts.sciSentMB(i)=sent; ts.backlogMB(i)=backlog;
    ts.baseKW(i)=loadKW; ts.genKW(i)=genKW; ts.soc(i)=soc/max(battKWh,eps);
    ts.baseOn(i)=baseOn; ts.util(i)=u;
    [pr, pu, bs] = earth_sites(cfg, geo.t(i)/3600);
    eJ = (tE*c.tacEarth.energyJ + dE*c.deepEarth.energyJ + pE*c.perEarth.energyJ)*pu(bs);
    ts.earthJ(i) = eJ; ts.earthUSD(i) = eJ/3.6e6*pr(bs); ts.earthSite(i) = bs;
    ts.earthPrice(i) = pr(bs); ts.earthPUE(i) = pu(bs); ts.earthCO2g(i) = eJ/3.6e6*cfg.earthSites(bs).gCO2;
    busyR = tR*c.tacRelay.replicaSec;                               % Thor-seconds of work
    onThor = min(sum(nThor(relOK)), ceil(busyR/dt));                % Thors powered this step
    ts.relayJ(i) = tR*c.tacRelay.energyJ + relayH.Pidle/relayH.n*max(0,onThor*dt - busyR);
    ts.relayW(i) = ts.relayJ(i)/dt; ts.relayLinkUse(i) = (expCap - expMB)/max(expCap,eps)*(expCap > 0); ts.relayBudgetW(i) = sum(max(0,relW(relOK)));
    ts.arrPer(i)=nPer+gate; ts.arrTac(i)=tIn+tOut+esc; ts.arrDeep(i)=q(1); ts.shift(i)=Wk.shift(i); ts.hazard(i)=Wk.trig(i)>1;
    ts.escSent(i)=esc; ts.escQueue(i)=sum(qE); ts.escK3(i)=escK3; ts.escWait(i)=escWait; ts.errFast(i)=errFast; ts.errFix(i)=fix;
    ts.tacBoard(i)=tL; ts.escal(i)=esc; ts.boardJ(i)=tL*c.small.energyJ + gate*cfg.detectorJ;
    ts.baseReqJ(i)=busyJ*(1+coolF);
    ts.pCompKW(i)=pComp; ts.pIdleKW(i)=baseOn*computeOn*idleW/1000; ts.pWorkKW(i)=baseOn*computeOn*busyJ/dt/1000; ts.pCoolKW(i)=pCool; ts.pTxKW(i)=pTx; ts.pHouseKW(i)=houseKW;
    ts.batchPer(i)=c.perBase.batch; ts.batchTacE(i)=c.tacBase.batch; ts.jPer(i)=c.perBase.energyJ; ts.jTacE(i)=c.tacEarth.energyJ;
    ts.baseJ(i)=loadKW*1e3*dt;
end

S = @(x) sum(x);
res.ts = ts; res.cost = c0; res.deepBaseName = deepBaseName; res.batchTables = Tb;
res.perOnTime  = S(ts.perBase+ts.perEarth)/max(S(ts.perBase+ts.perEarth+ts.perMiss),eps);
res.tacOnTime  = S(ts.tacBase+ts.tacRelay+ts.tacEarth+ts.tacBoard)/max(S(ts.tacBase+ts.tacRelay+ts.tacEarth+ts.tacBoard+ts.tacMiss),eps);
res.deepOnTime = S(ts.deepEarth+ts.deepBase)/max(S(ts.deepEarth+ts.deepBase+ts.deepMiss),eps);
res.deepSuperior = S(ts.deepEarth)/max(S(ts.deepEarth+ts.deepBase),eps);   % answered by Kimi K3
res.tacShare = [S(ts.tacBase) S(ts.tacRelay) S(ts.tacEarth) S(ts.tacMiss)]/max(S(ts.tacBase+ts.tacRelay+ts.tacEarth+ts.tacMiss),eps);
res.tacShare5 = [S(ts.tacBoard) S(ts.tacRelay) S(ts.tacBase) S(ts.tacEarth) S(ts.tacMiss)]/max(S(ts.tacBoard+ts.tacRelay+ts.tacBase+ts.tacEarth+ts.tacMiss),eps);
res.tierKWh = [S(ts.boardJ) S(ts.relayJ) S(ts.baseReqJ) S(ts.earthJ)]/3.6e6;   % marginal compute energy: robot relay base Earth
res.sciDelivered = min(1, S(ts.sciSentMB)/max(S(ts.sciRawMB)*(1-(~strcmp(pol,'EarthOnly'))*(1-cfg.triageKeep)),eps));
res.baseKWh = S(ts.baseJ)/3.6e6; res.earthKWh = S(ts.earthJ)/3.6e6; res.relayKWh = S(ts.relayJ)/3.6e6;
res.earthUSD = S(ts.earthUSD);
nDec = S(ts.tacBase+ts.tacRelay+ts.tacEarth+ts.tacBoard);
res.escRate   = S(ts.escSent)/max(nDec,eps);                 % share of decisions sent to Kimi K3
res.errFast   = S(ts.errFast)/max(nDec,eps);                 % wrong fast answers
res.errFinal  = (S(ts.errFast) - S(ts.errFix))/max(nDec,eps);% after the slow reasoner's corrections
res.fixPerRobotDay = S(ts.errFix)/cfg.nRobots/cfg.days;
res.corrMin   = S(ts.escWait)/max(S(ts.escK3),eps)/60;      % mean time to the Kimi K3 answer [min]
res.earthSiteNames = {cfg.earthSites.name}; res.earthCO2kg = S(ts.earthCO2g)/1e3;
res.baseAvgKW = mean(ts.baseKW); res.baseUptime = mean(ts.baseOn);
res.baseH = baseH; res.relayH = relayH; res.computeMass = computeOn*baseH.mass;
res.PmaxKW = PmaxKW; res.nameplateKW = nameKW; res.arrayKW = arrayKW; res.battKWh = battKWh; res.nFission = nFission*isFission;
% kept for the summary panel
res.planBaseName = deepBaseName; res.planOnTime = res.deepOnTime;
end

function T = batch_table(h, m)
% latency, busy time and energy for batch sizes 1..m.batch
Bmax = max(1, m.batch); if ~h.canBatch, Bmax = 1; end
T.B = 1:Bmax; T.lat = zeros(1,Bmax); T.sec = T.lat; T.J = T.lat; T.g = T.lat; T.fits = true;
for b = 1:Bmax
    r = request_cost(h, m, b); T.lat(b) = r.latency; T.sec(b) = r.replicaSec; T.J(b) = r.energyJ; T.g(b) = r.gpuSec; T.fits = r.fits;
end
end

function r = pick_batch(T, lambda, slack)
% largest batch whose fill time plus run time fits in the slack before the
% deadline: (B-1)/lambda + latency(B) <= slack. Above Bmax the load spreads
% over more replicas at Bmax each.
B = 1;
if lambda > 0
    ok = (T.B - 1)/lambda + T.lat <= slack;
    if any(ok), B = find(ok, 1, 'last'); end
end
r = struct('batch',B,'latency',T.lat(B),'replicaSec',T.sec(B),'energyJ',T.J(B),'gpuSec',T.g(B),'fits',T.fits);
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
    case '3xRTX-PRO',    h = C.hw.RTX3;
    case 'GPU-2035x2',   h = C.hw.GPU2035x2;
    otherwise
        tk = regexp(name, '^(\d+)xRTX-PRO$', 'tokens', 'once');   % any number of small servers
        if isempty(tk), error('Unknown base hardware %s', name); end
        h = C.hw.RTX3; n = str2double(tk{1});
        h.n = n; h.Pmax = n*h.watts; h.Pidle = h.idleFrac*h.Pmax; h.mass = n*h.massKg;
        h.name = sprintf('%d x RTX PRO 6000 server', n);
end
end
