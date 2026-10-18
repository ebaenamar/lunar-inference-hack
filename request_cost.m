function r = request_cost(h, m)
%REQUEST_COST Latency, busy time and energy of one request of model m on hardware h.
%   Prefill is compute-bound (40% of dense FP8 peak); decode is memory-bound
%   (70% of HBM/LPDDR bandwidth). For mixture-of-experts models the weights read
%   per decode step grow with the batch, because the batch touches more experts.
%   r.fits      : the model fits in the memory of one replica
%   r.latency   : wall time of one request [s]
%   r.replicaSec: replica busy time per request, amortized over the batch [s]
%   r.energyJ   : energy per request at full power [J]

rc   = h.replica;
memB = 0.85*rc*h.memGB*1e9;
W    = m.total*m.bpp;                 % weight bytes
r.fits = W + m.batch*m.kvGB*1e9 <= memB;
B = m.batch;
if h.replica == 1 && h.n == 1, B = 1; end   % on-board module serves its own robot

prefill = 2*m.active*m.tin/(0.40*rc*h.tflops*1e12);
if m.experts > 1
    f = 1 - (1 - m.kAct/m.experts)^B;   % fraction of experts touched per step
else
    f = 1;
end
bytesStep = W*m.dense + f*W*(1-m.dense) + B*m.kvGB*1e9;
step      = bytesStep/(0.70*rc*h.bwGBs*1e9);

r.latency    = prefill + step*m.tout;
r.replicaSec = prefill + step*m.tout/B;
r.energyJ    = r.replicaSec*rc*h.watts;
r.stepMs     = 1e3*step;
r.tokPerSec  = B/step;
if ~r.fits
    r.latency = Inf; r.replicaSec = Inf; r.energyJ = Inf;
end
end
