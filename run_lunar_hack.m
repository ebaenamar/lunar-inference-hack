%% Where must lunar robots think?  (Sundai Hack 145, Track 1 what-if)
% Lunar robots served by on-board computers, a base node at the south pole, or
% data centers on Earth, with the real LCRNS relay orbits, terrain shadowing,
% the lunar day, and datasheet GPU specs. Run this script from its folder.

clear; close all; clc;
cfg = lunar_config();

% ---- Scenario knobs (override the defaults in lunar_config.m) -------------
cfg.site        = 'ConnectingRidge';   % 'Malapert' | 'ConnectingRidge' | 'FarSide'
cfg.nRobots     = 100;
cfg.nRelays     = 5;                   % 1 = first LCRNS relay only, 5 = full constellation
cfg.policy      = 'Coordinated';       % 'EarthOnly' | 'BaseOnly' | 'Hierarchical' | 'Coordinated'
cfg.baseHW      = 'DGX-B200';          % 'Thor-cluster' | 'DGX-B200' | '2xDGX-B200' | 'GPU-2035x2'
cfg.power       = 'RidgeSolar';        % 'RidgeSolar' | 'Fission'
cfg.launchPrice = 'Starship';          % 'Deck2035' | 'Starship' | 'CLPS'
cfg.saveVideo   = false;
% ---------------------------------------------------------------------------

C   = lunar_catalog();
geo = lunar_geometry(cfg);
fprintf('LCRNS period %.2f h | per-relay visibility %.1f%% | relay path %.1f%% | Earth in view %.1f%% | sunlit %.1f%%\n', ...
    geo.period_h, 100*mean(geo.satVis(:)), 100*mean(geo.relayPath), 100*mean(geo.earthVis), 100*geo.illumFrac);

res = lunar_dispatch(cfg, geo, C);
eco = lunar_economics(cfg, res);
fprintf('On time: perception %.1f%% | tactical %.1f%% | deep %.1f%% (Kimi K3 share %.1f%%) | science %.1f%%\n', ...
    100*res.perOnTime, 100*res.tacOnTime, 100*res.deepOnTime, 100*res.deepSuperior, 100*res.sciDelivered);
fprintf('Tactical served by base %.0f%% | relays %.0f%% | Earth %.0f%% | missed %.0f%%\n', 100*res.tacShare);
fprintf('Base %.1f kW avg | mass %.0f kg | launch $%.1f M (%s) | lunar energy $%.2f/kWh\n', ...
    res.baseAvgKW, eco.mass.total, eco.launchUSD/1e6, cfg.launchPrice, eco.moonUSDperKWh);

lunar_dashboard(cfg, geo, res, eco);
lunar_power(cfg, geo, res);                 % dynamic power of the three data centers
if cfg.runSweep, lunar_sweep(cfg, geo, C); end
if cfg.animate,  lunar_animate(cfg, geo, res); end

% ---- Coordinated data centers: savings per robot-day and the robot's-eye story
lunar_savings(cfg, C, true);
lunar_robot_story(cfg, C, cfg.saveVideo);
