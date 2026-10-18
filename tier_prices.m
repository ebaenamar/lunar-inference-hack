function P = tier_prices(cfg, C)
%TIER_PRICES Cost of one kWh delivered on each compute tier [$ per kWh].
%   Moon tiers pay for energy by launching their power plant: kg of plant per kW
%   of peak, times the launch price, over the life hours times a load factor.
%   Earth pays the grid (the energy already includes the PUE).
%   Returns P.robot, P.relay, P.base, P.earth and P.vec = [robot relay base earth].

prices = struct('Deck2035',1200, 'Starship',1e5, 'CLPS',1e6);
pkg  = prices.(cfg.launchPrice);
life = cfg.lifeYears*8766;
kg.base  = cfg.solarKgPerKW*cfg.arrayMargin + 1e3*cfg.batteryHours/cfg.batteryWhPerKg + cfg.radiatorKgPerKW;
kg.robot = 150;                                         % rover arrays + battery
kg.relay = 5 + cfg.radiatorKgPerKW + C.hw.RelayEdge.mass/(C.hw.RelayEdge.Pmax/1e3);
P.robot = kg.robot*pkg/(life*0.6);
P.relay = kg.relay*pkg/(life*0.5);
P.base  = kg.base*pkg/(life*0.5);
P.earth = cfg.earthUSDperkWh;
P.kgPerKW = kg; P.usdPerKg = pkg;
P.vec = [P.robot P.relay P.base P.earth];
end
