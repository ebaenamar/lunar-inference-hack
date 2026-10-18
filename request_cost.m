function r = request_cost(h, m, B)
%REQUEST_COST Latency, busy time and energy of one request of model m on hardware h.
%   r = request_cost(h, m)     uses the model's nominal batch m.batch
%   r = request_cost(h, m, B)  uses an actual batch of B concurrent requests
%   Prefill is compute-bound (40% of dense FP8 peak) and draws ~100% of TDP;
%   decode is memory-bound (70% of HBM/LPDDR bandwidth) and draws ~65% of TDP.
%   For mixture-of-experts models the weights read per decode step grow with the
%   batch, because the batch touches more experts.
%   r.fits      : the model fits in the memory of one replica
%   r.latency   : wall time of one request [s] (grows with the batch)
%   r.replicaSec: replica busy time per request, amortized over the batch [s]
%   r.energyJ   : energy per request [J] (falls with the batch)

P_PREFILL = 1.00;   % fraction of TDP while compute-bound
P_DECODE  = 0.65;   % fraction of TDP while memory-bound

W    = m.total*m.bpp;                 % weight bytes
if nargin < 3, B = m.batch; end
if h.replica == 1, B = 1; end         % a single module (robot, relay, Thor cluster) serves one request at a time
B = max(1, round(B));
% smallest power-of-two set of chips that holds the model and its batch (a 7B
% model uses one GPU of a DGX, so the node holds eight replicas)
rc = 1;
while rc < h.replica && W + B*m.kvGB*1e9 > 0.85*rc*h.memGB*1e9, rc = 2*rc; end
rc = min(rc, h.replica);
r.fits = W + B*m.kvGB*1e9 <= 0.85*rc*h.memGB*1e9;
r.chips = rc;

prefill = 2*m.active*m.tin/(0.40*rc*h.tflops*1e12);
if m.experts > 1
    f = 1 - (1 - m.kAct/m.experts)^B;   % fraction of experts touched per step
else
    f = 1;
end
bytesStep = W*m.dense + f*W*(1-m.dense) + B*m.kvGB*1e9;
step      = bytesStep/(0.70*rc*h.bwGBs*1e9);
decodeAm  = step*m.tout/B;            % decode time per request, amortized over the batch

r.batch      = B;
r.gpuSec     = (prefill + decodeAm)*rc;   % chip-seconds consumed per request
r.latency    = prefill + step*m.tout;
r.replicaSec = prefill + decodeAm;
r.energyJ    = rc*h.watts*(P_PREFILL*prefill + P_DECODE*decodeAm);
r.stepMs     = 1e3*step;
r.tokPerSec  = B/step;
if ~r.fits
    r.latency = Inf; r.replicaSec = Inf; r.energyJ = Inf; r.gpuSec = Inf;
end
end
