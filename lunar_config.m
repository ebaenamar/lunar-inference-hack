function cfg = lunar_config()
%LUNAR_CONFIG Default scenario for the lunar inference simulation.
%   Edit the fields below (or override them in run_lunar_hack.m).

% ---------------- Scenario ----------------
cfg.site        = 'ConnectingRidge'; % 'Malapert' | 'ConnectingRidge' | 'FarSide'
cfg.nRobots     = 100;               % robots operating around the base
cfg.policy      = 'Coordinated';     % 'EarthOnly' | 'BaseOnly' | 'Hierarchical' | 'Coordinated'
cfg.baseHW      = 'DGX-B200';        % 'Thor-cluster' | 'DGX-B200' | '2xDGX-B200' | 'GPU-2035x2'
cfg.power       = 'RidgeSolar';      % 'RidgeSolar' | 'Fission'
cfg.launchPrice = 'Starship';        % 'Deck2035' | 'Starship' | 'CLPS'

% ---------------- Time ----------------
cfg.days = 30;          % simulated days
cfg.dt   = 300;         % time step [s]
cfg.epoch = datetime(2027,3,1,0,0,0); % LCRNS RC 3.1 reference epoch

% ---------------- Robot workload (per active robot) ----------------
cfg.perceptionHz       = 1;      % scene-understanding requests per second
cfg.perceptionDeadline = 1.0;    % [s] hazard detection at ~0.2 m/s
cfg.planPeriod         = 600;    % [s] one planning request every 10 min
cfg.planDeadline       = 60;     % [s]
cfg.scienceImgHz       = 0.1;    % science images per second
cfg.scienceImgMB       = 4;      % [MB] per raw image
cfg.triageKeep         = 0.05;   % fraction kept after on-Moon triage
cfg.robotsWorkInDark   = false;  % solar robots hibernate when the site is dark

% ---------------- Explorers and cognitive tiers ----------------
cfg.fracExploring  = 0.4;    % robots outside the base cell (crater floors, distant sites)
cfg.exploreLat     = -88.6;  % explorer location (crater near the base)
cfg.exploreLon     = -60;
cfg.exploreMaskDeg = 15;     % crater walls hide low relays
cfg.tacticalPeriod = 120;    % [s] one tactical reasoning request per robot
cfg.tacticalDeadline = 10;   % [s]
cfg.tacticalMB     = 2;      % [MB] two images + text per tactical request
cfg.deepPeriod     = 1800;   % [s] one deep-reasoning request per robot
cfg.deepDeadline   = 3600;   % [s] store-and-forward allowed
cfg.deepMB         = 0.1;    % [MB] text context per deep request
cfg.relayComputeW  = 300;    % [W] of the relay bus given to compute (2 x Thor)
% Model cascade (Coordinated policy): small on-board model first, escalate when unsure
cfg.perceptionTrigger = 0.2; % share of frames the on-board detector sends to the base model
cfg.detectorJ      = 0.25;   % [J] on-board detector per frame (Orin NX, ~10 ms at 25 W)
cfg.escalateDeep   = 0.1;    % share of tactical requests that escalate to Kimi K3 on Earth

% ---------------- Links (from the tutorial paper) ----------------
cfg.cellRTT    = 0.02;   % [s] surface 5G cell round trip
cfg.earthRTT   = 2.56;   % [s] Earth-Moon round trip
cfg.dteMbps    = 100;    % X-band direct-to-Earth cap (50 MHz allocation)
cfg.relayMbps  = 16;     % Ka 0.5 m / 0.5 m pair at LCRNS apolune, 3 dB margin
cfg.relayMinEl = 5;      % [deg] elevation mask toward relays
cfg.nRelays    = 5;      % LCRNS relays deployed: 1 = first relay (2027), 5 = full constellation

% ---------------- Power system ----------------
cfg.batteryHours   = 4;     % battery sized to finish in-flight work
cfg.arrayMargin    = 1.3;   % array peak / base peak load
cfg.solarKgPerKW   = 62.5;  % VSAT-class: 10 kW, <=625 kg landed (NASA BEACON)
cfg.batteryWhPerKg = 200;   % space Li-ion pack level
cfg.radiatorKgPerKW = 4;    % 4 t/MW (hackathon deck, orbit radiators)
cfg.fissionKWe     = 40;    % NASA FSP unit
cfg.fissionKg      = 6000;  % <6 t per unit (2022 FSP contracts)
cfg.lifeYears      = 5;

% ---------------- Earth side ----------------
cfg.earthPUE      = 1.1;
cfg.earthUSDperkWh = 0.06;

% ---------------- Visuals ----------------
cfg.animate     = true;
cfg.animDays    = 4;      % days shown in the 3D animation
cfg.frameStep   = 2;      % animate every N time steps
cfg.saveVideo   = false;  % true -> lunar_inference.mp4
cfg.runSweep    = true;   % robots-served sweep over N
end
