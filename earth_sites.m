function [price, pue, best] = earth_sites(cfg, tUTC)
%EARTH_SITES Hourly electricity price and PUE of each Earth data center.
%   tUTC: hours since the epoch (UTC). Price follows a time-of-use curve with an
%   evening peak; West Texas adds a midday solar dip. PUE rises in the afternoon
%   heat. best is the site with the lowest price x PUE at that hour.

S = cfg.earthSites; n = numel(S);
price = zeros(1,n); pue = zeros(1,n);
for k = 1:n
    h = mod(tUTC + S(k).utc, 24);
    shape = cos(2*pi*(h - 18)/24);                         % +1 at 18 h, -1 at 6 h
    if strcmp(S(k).name,'West Texas')
        shape = shape - 1.2*exp(-((h - 13)/2.5)^2);       % solar surplus at midday
    end
    price(k) = S(k).usd*(1 + S(k).touAmp*shape);
    pue(k)   = S(k).pueMin + (S(k).pueMax - S(k).pueMin)*(0.5 + 0.5*cos(2*pi*(h - 15)/24));
end
[~, best] = min(price.*pue);
end
