function eco = lunar_economics(cfg, res)
%LUNAR_ECONOMICS Mass delivered to the Moon, launch cost and cost per kWh.
%   Lunar energy is paid for by launching the power plant: the cost per kWh is
%   the launch cost of arrays, batteries, radiators (or fission units) divided by
%   the energy the base consumes over its life. Hardware purchase is excluded.

prices = struct('Deck2035',1200, 'Starship',1e5, 'CLPS',1e6);   % $/kg to the surface
usdPerKg = prices.(cfg.launchPrice);

m.compute   = res.computeMass;
m.radiators = cfg.radiatorKgPerKW*res.PmaxKW;
if strcmp(cfg.power,'Fission')
    m.power = res.nFission*cfg.fissionKg;   m.battery = 0;
else
    m.power = cfg.solarKgPerKW*res.arrayKW; m.battery = 1e3*res.battKWh/cfg.batteryWhPerKg;
end
m.total = m.compute + m.radiators + m.power + m.battery;

lifeKWh = res.baseAvgKW*cfg.lifeYears*8766;
eco.mass = m;
eco.usdPerKg = usdPerKg;
eco.launchUSD = m.total*usdPerKg;
eco.powerLaunchUSD = (m.power + m.battery + m.radiators)*usdPerKg;
eco.moonUSDperKWh = eco.powerLaunchUSD/max(lifeKWh,eps);
eco.earthUSDperKWh = cfg.earthUSDperkWh;
eco.moonUSDperDay  = eco.moonUSDperKWh*res.baseKWh/cfg.days;

% Relay edge nodes: compute modules plus extra solar (deck: 5 t/MW) and radiators per relay
relayKg = res.relayH.mass + 5*cfg.relayComputeW/1000 + cfg.radiatorKgPerKW*cfg.relayComputeW/1000;
eco.relayMassKg  = relayKg*cfg.nRelays;
eco.relayLaunchUSD = eco.relayMassKg*usdPerKg;
relayLifeKWh = max(res.relayKWh,eps)/cfg.days*365.25*cfg.lifeYears;
eco.relayUSDperKWh = eco.relayLaunchUSD/relayLifeKWh;
eco.relayUSDperDay = eco.relayUSDperKWh*res.relayKWh/cfg.days;
eco.earthUSDperDay = cfg.earthUSDperkWh*res.earthKWh/cfg.days;
end
