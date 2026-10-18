function C = lunar_catalog()
%LUNAR_CATALOG Hardware and model specifications used by the simulation.
%   Hardware values are datasheet figures (dense FP8, no sparsity); the 2035
%   GPU is the hackathon catalog (3 TB, 120 TB/s, 792 kW / 144 chips) with an
%   assumed 4x B200 dense FP8 throughput.

% ---- Hardware: one "group" is the set of chips that hosts one model replica
%  memGB, bwGBs, tflops (FP8 dense), wattsMax and massKg are per chip;
%  idleFrac is the fraction of max power drawn when idle.
hw = struct();
hw.Thor        = mk('Jetson AGX Thor T5000', 1, 128, 273, 517, 130, 0.30, 1.5);
hw.Board       = mk('Jetson Orin NX 16 GB (on board)', 1, 16, 102, 50, 25, 0.30, 0.5);   % small-rover computer
hw.Thor_cluster= mk('16 x Jetson AGX Thor',  16, 128, 273, 517, 130, 0.30, 1.5);
hw.Thor_cluster.replica = 1;   % no NVLink: each module hosts its own replica
hw.DGX_B200    = mk('DGX B200 (8 x B200)',    8, 180, 8000, 4500, 14300/8, 0.30, 142/8);
hw.DGX_B200x2  = mk('2 x DGX B200 (16 x B200)',16,180, 8000, 4500, 14300/8, 0.30, 142/8);
hw.GPU2035x2   = mk('2 x 2035 GPU (deck)',    2, 3000, 120000, 18000, 5500, 0.30, 27.5);
hw.EarthB200   = hw.DGX_B200x2;     % Earth data center that hosts the large planner
hw.RelayEdge   = mk('Relay edge node (2 x Thor)', 2, 128, 273, 517, 130, 0.30, 1.5);
hw.RelayEdge.replica = 1;   % each Thor hosts a full replica of the tactical model

C.hw = hw;

% ---- Models: total params, active params, bytes/param, tokens in/out,
%      KV per session [GB], experts, active experts, dense fraction, batch
mdl = struct();
mdl.VLM7B  = mm('Vision-language 7B (FP8)',       7e9,   7e9, 1.00, 1088,   32, 0.05,   1,  1, 1.00, 64);
mdl.K3     = mm('Kimi K3 (2.8T MoE, MXFP4)',   2.8e12, 104e9, 0.53, 8000, 1000, 1.10, 896, 16, 0.05, 32);
mdl.Dist   = mm('Distilled planner 30B-A3B (FP8)', 30e9, 3e9, 1.00, 8000, 1000, 0.40, 128,  8, 0.10, 32);
% cognitive tiers
mdl.Tactical = mm('Tactical reasoner 30B-A3B (FP8)', 30e9, 3e9, 1.00, 2000,  300, 0.10, 128,  8, 0.10,  8);
mdl.DeepK3   = mm('Kimi K3 thinking',              2.8e12, 104e9, 0.53, 8000, 4000, 1.10, 896, 16, 0.05, 32);
mdl.DeepDist = mm('Distilled reasoner 30B-A3B',      30e9,   3e9, 1.00, 8000, 4000, 0.40, 128,  8, 0.10, 32);
C.mdl = mdl;
end

function h = mk(name,n,memGB,bwGBs,tflops,watts,idleFrac,massKg)
h = struct('name',name,'n',n,'memGB',memGB,'bwGBs',bwGBs,'tflops',tflops, ...
           'watts',watts,'idleFrac',idleFrac,'massKg',massKg);
h.Pmax = n*watts; h.Pidle = idleFrac*h.Pmax; h.mass = n*massKg;
h.replica = n;   % chips that pool memory for one model replica (NVLink domain)
end

function m = mm(name,T,A,bp,tin,tout,kvGB,E,k,dense,batch)
m = struct('name',name,'total',T,'active',A,'bpp',bp,'tin',tin,'tout',tout, ...
           'kvGB',kvGB,'experts',E,'kAct',k,'dense',dense,'batch',batch);
end
