function cfg = earth_tier(cfg)
%EARTH_TIER Slow tier on the ground (three grid sites) or in Earth orbit.
%   'Ground': Nordics, West Texas, N. Virginia with hourly prices (lunar_config).
%   'Orbit' : a dawn-dusk sun-synchronous constellation of orbital data centers,
%             always sunlit, radiative cooling (PUE 1.0), no grid. Its energy is
%             paid for by launching arrays and radiators to LEO (deck: 5 t/MW of
%             solar, 4 t/MW of radiators) at cfg.leoUSDperKg over the life.
if ~isfield(cfg,'earthTier') || strcmp(cfg.earthTier,'Ground'), return; end
kgPerKW = cfg.orbitSolarKgPerKW + cfg.radiatorKgPerKW;
usd = kgPerKW*cfg.leoUSDperKg/(cfg.lifeYears*8766*cfg.orbitLoadFactor);
cfg.earthSites = struct('name','Earth-orbit constellation','usd',usd,'touAmp',0,'utc',0, ...
    'pueMin',1.0,'pueMax',1.0,'gCO2',0);
cfg.earthUSDperkWh = usd;
end
