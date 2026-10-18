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
eco.earthUSDperDay = cfg.earthUSDperkWh*res.earthKWh/cfg.days;
end
