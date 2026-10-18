function res = lunar_dispatch(cfg, geo, C)
%LUNAR_DISPATCH Places every robot request on board, at the base or on Earth.
%   Time-stepped over the geometry in geo. Each step: robot demand, link capacity
%   to Earth (direct or through an LCRNS relay), base power state (solar ridge with
%   battery, or fission), and the policy decide where each request runs and
%   whether it meets its deadline.

baseH  = pick_hw(C, cfg.baseHW);
board  = C.hw.Thor;
earthH = C.hw.EarthB200;
M = C.mdl;

% ---- Per-request costs
cPerBase  = request_cost(baseH, M.VLM7B);
cPerBoard = request_cost(board, M.VLM7B);
cPerEarth = request_cost(earthH, M.VLM7B);
cK3Base   = request_cost(baseH, M.K3);
cDistBase = request_cost(baseH, M.Dist);
cPlanEarth= request_cost(earthH, M.K3);
if cK3Base.fits, cPlanBase = cK3Base; planBaseName = 'Kimi K3';
else,            cPlanBase = cDistBase; planBaseName = 'distilled 30B-A3B';
end
cTriage = cPerBase;   % one vision-language pass per science image

% ---- Power system
houseKW = 2;                              % thermal, comms, avionics
computeOn = ~strcmp(cfg.policy,'EarthBrain');   % EarthBrain flies no compute node
PmaxKW  = computeOn*baseH.Pmax/1000 + houseKW;
PidleKW = computeOn*baseH.Pidle/1000 + houseKW;
arrayKW = cfg.arrayMargin*PmaxKW;
battKWh = cfg.batteryHours*PmaxKW;
nFission = ceil(PmaxKW/cfg.fissionKWe);
isFission = strcmp(cfg.power,'Fission');

N  = geo.N; dt = cfg.dt;
capSec = computeOn*(baseH.n/baseH.replica)*dt;   % replica-seconds available per step

z = zeros(1,N);
ts = struct('perBase',z,'perBoard',z,'perEarth',z,'perMiss',z, ...
            'planBase',z,'planEarth',z,'planMiss',z, ...
            'sciRawMB',z,'sciSentMB',z,'backlogMB',z,'linkUse',z, ...
            'baseKW',z,'genKW',z,'soc',z,'baseOn',false(1,N),'util',z, ...
            'earthJ',z,'boardJ',z,'baseJ',z,'active',z);
soc = battKWh; backlog = 0; maxBacklogMB = 2e6;   % 2 TB of on-surface storage

for i = 1:N
    active = geo.sunlit(i) || cfg.robotsWorkInDark;
    Na = cfg.nRobots*active;
    nPer  = Na*cfg.perceptionHz*dt;
    nPlan = Na*dt/cfg.planPeriod;
    nImg  = Na*cfg.scienceImgHz*dt;
    rawMB = nImg*cfg.scienceImgMB;
    linkMB = geo.linkMbps(i)*dt/8;
    hasLink = geo.linkMbps(i) > 0;

    % Base availability
    if isFission
        genKW = nFission*cfg.fissionKWe; baseOn = true;
    else
        genKW = arrayKW*geo.sunlit(i);
        baseOn = genKW > 0 || soc > PidleKW*dt/3600;
    end

    free = capSec*baseOn;
    pB = 0; pO = 0; pE = 0; pM = 0; lB = 0; lE = 0; lM = 0; tri = 0;

    % ---- Perception (deadline-critical)
    switch cfg.policy
        case 'EarthBrain'
            okE = hasLink && (cfg.earthRTT + cPerEarth.latency <= cfg.perceptionDeadline);
            pE = nPer*okE; pM = nPer - pE;
        otherwise
            okB = cfg.cellRTT + cPerBase.latency <= cfg.perceptionDeadline;
            if okB && baseOn
                pB = min(nPer, free/cPerBase.replicaSec); free = free - pB*cPerBase.replicaSec;
            end
            rest = nPer - pB;
            okO = cPerBoard.latency <= cfg.perceptionDeadline;
            pO = rest*okO; pM = rest - pO;
    end

    % ---- Planning
    okEplan = hasLink && (cfg.earthRTT + cPlanEarth.latency <= cfg.planDeadline);
    okBplan = baseOn && (cfg.cellRTT + cPlanBase.latency <= cfg.planDeadline);
    switch cfg.policy
        case 'EarthBrain'
            lE = nPlan*okEplan; lM = nPlan - lE;
        case 'MoonBrain'
            if okBplan, lB = min(nPlan, free/cPlanBase.replicaSec); free = free - lB*cPlanBase.replicaSec; end
            lM = nPlan - lB;
        case 'Adaptive'
            if okEplan
                lE = nPlan;
            elseif okBplan
                lB = min(nPlan, free/cPlanBase.replicaSec); free = free - lB*cPlanBase.replicaSec;
            end
            lM = nPlan - lE - lB;
    end

    % ---- Science: triage on the Moon (Moon/Adaptive) then downlink
    if ~strcmp(cfg.policy,'EarthBrain') && baseOn
        tri = min(nImg, free/cTriage.replicaSec); free = free - tri*cTriage.replicaSec;
    end
    toSend  = tri*cfg.scienceImgMB*cfg.triageKeep + (nImg - tri)*cfg.scienceImgMB;
    queue   = backlog + toSend;
    sent    = min(queue, linkMB);
    backlog = min(queue - sent, maxBacklogMB);

    % ---- Base power and battery
    used = capSec*baseOn - free;
    u = 0; if baseOn && capSec > 0, u = used/capSec; end
    loadKW = baseOn*(PidleKW + (PmaxKW - PidleKW)*u);
    if ~isFission
        soc = min(battKWh, max(0, soc + (genKW - loadKW)*dt/3600));
    end

    ts.perBase(i)=pB; ts.perBoard(i)=pO; ts.perEarth(i)=pE; ts.perMiss(i)=pM;
    ts.planBase(i)=lB; ts.planEarth(i)=lE; ts.planMiss(i)=lM;
    ts.sciRawMB(i)=rawMB; ts.sciSentMB(i)=sent; ts.backlogMB(i)=backlog;
    ts.linkUse(i)=sent/max(linkMB,eps)*hasLink;
    ts.baseKW(i)=loadKW; ts.genKW(i)=genKW; ts.soc(i)=soc/max(battKWh,eps);
    ts.baseOn(i)=baseOn; ts.util(i)=u; ts.active(i)=Na;
    ts.earthJ(i)=(lE*cPlanEarth.energyJ + pE*cPerEarth.energyJ)*cfg.earthPUE;
    ts.boardJ(i)=pO*cPerBoard.energyJ;
    ts.baseJ(i)=loadKW*1e3*dt;
end

tot = @(x) sum(x);
res.ts = ts;
res.perOnTime  = (tot(ts.perBase)+tot(ts.perBoard)+tot(ts.perEarth))/max(tot(ts.perBase)+tot(ts.perBoard)+tot(ts.perEarth)+tot(ts.perMiss),eps);
res.planOnTime = (tot(ts.planBase)+tot(ts.planEarth))/max(tot(ts.planBase)+tot(ts.planEarth)+tot(ts.planMiss),eps);
res.sciDelivered = tot(ts.sciSentMB)/max(tot(ts.sciRawMB)*(1 - (~strcmp(cfg.policy,'EarthBrain'))*(1-cfg.triageKeep)),eps);
res.sciDelivered = min(res.sciDelivered,1);
res.baseKWh  = tot(ts.baseJ)/3.6e6;
res.earthKWh = tot(ts.earthJ)/3.6e6;
res.boardKWh = tot(ts.boardJ)/3.6e6;
res.baseAvgKW = mean(ts.baseKW);
res.baseUptime = mean(ts.baseOn);
res.days = cfg.days;
res.baseH = baseH; res.computeMass = computeOn*baseH.mass; res.PmaxKW = PmaxKW; res.arrayKW = arrayKW; res.battKWh = battKWh;
res.nFission = nFission*isFission; res.planBaseName = planBaseName;
res.cost = struct('perBase',cPerBase,'perBoard',cPerBoard,'perEarth',cPerEarth, ...
                  'planBase',cPlanBase,'planEarth',cPlanEarth,'K3Base',cK3Base);
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
