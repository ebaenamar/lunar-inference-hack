function S = lunar_sweep(cfg, geo, C)
%LUNAR_SWEEP Robots served versus fleet size for the three placement policies.
%   Answers the pitch question: above how many robots does the Moon have to
%   think for itself, and how much power does that take?

Ns = [1 2 5 10 20 50 100 200 500 1000 2000];
pols = {'EarthBrain','MoonBrain','Adaptive'};
S.Ns = Ns; S.pols = pols;
S.per = zeros(numel(pols),numel(Ns)); S.plan = S.per; S.sci = S.per; S.kw = S.per;
for p = 1:numel(pols)
    for j = 1:numel(Ns)
        c = cfg; c.policy = pols{p}; c.nRobots = Ns(j);
        r = lunar_dispatch(c, geo, C);
        S.per(p,j) = r.perOnTime; S.plan(p,j) = r.planOnTime;
        S.sci(p,j) = r.sciDelivered; S.kw(p,j) = r.baseAvgKW;
    end
end

fig = figure('Name','Robots served vs fleet size','Color','w','Position',[100 100 1250 420]);
try, theme(fig,'light'); catch, end
tl = tiledlayout(fig,1,3,'TileSpacing','compact');
title(tl, sprintf('%s | base %s | %s', geo.siteInfo.name, cfg.baseHW, cfg.power), 'FontWeight','bold');
mk = {'-o','--s',':^'}; lw = [1.5 3 1.8];
nexttile(tl); hold on;
for p = 1:3, semilogx(Ns, 100*S.per(p,:), mk{p}, 'LineWidth',lw(p), 'MarkerSize',7); end
set(gca,'XScale','log'); ylim([0 105]); grid on; xlabel('robots'); ylabel('% on time');
title(sprintf('Perception (deadline %.1f s)', cfg.perceptionDeadline)); legend(pols,'Location','southwest');
nexttile(tl); hold on;
for p = 1:3, semilogx(Ns, 100*S.plan(p,:), mk{p}, 'LineWidth',lw(p), 'MarkerSize',7); end
set(gca,'XScale','log'); ylim([0 105]); grid on; xlabel('robots'); ylabel('% on time');
title(sprintf('Planning (deadline %d s)', cfg.planDeadline));
nexttile(tl); hold on;
for p = 1:3, semilogx(Ns, 100*S.sci(p,:), mk{p}, 'LineWidth',lw(p), 'MarkerSize',7); end
set(gca,'XScale','log'); ylim([0 105]); grid on; xlabel('robots'); ylabel('% delivered');
title('Science data returned to Earth');
end
