# Where must lunar robots think?

MATLAB simulation for Sundai Hack 145, Track 1 ("Build the AI data center of 2035"), as the team's what-if: the users are robots on the Moon. It decides, minute by minute, whether each robot request runs on board, at a base node at the south pole, or in a data center on Earth. The decision depends on the real relay orbits, terrain shadowing, the lunar day, link capacity and datasheet GPU specs.

## Run

Open MATLAB in this folder and run:

```matlab
run_lunar_hack
```

The scenario knobs are at the top of `run_lunar_hack.m`. The full defaults, including workload, links and power, are in `lunar_config.m`.

| Knob | Options |
|---|---|
| `site` | `Malapert` (Earth always in view), `ConnectingRidge` (Earth on the horizon), `FarSide` (no Earth, 14.8-day night) |
| `nRobots` | Fleet size |
| `nRelays` | LCRNS relays deployed: 1 is the first relay (2027), 5 is the full constellation |
| `policy` | `EarthBrain` (everything on Earth), `MoonBrain` (everything at the base), `Adaptive` (perception and triage at the base, Kimi K3 planning on Earth when a link exists, distilled planner at the base otherwise) |
| `baseHW` | `Thor-cluster`, `DGX-B200`, `2xDGX-B200`, `GPU-2035x2` |
| `power` | `RidgeSolar` (VSAT-class arrays and battery), `Fission` (40 kWe units) |
| `launchPrice` | `Deck2035` ($1,200/kg), `Starship` (~$100,000/kg quote), `CLPS` (~$1M/kg) |

Set `cfg.saveVideo = true` to write `lunar_inference.mp4` for the pitch.

## Outputs

1. **Dashboard:** link to Earth, sunlight and battery, where perception and planning run, base power, science backlog, and the key figures (energy, mass, launch cost, $/kWh on the Moon against Earth).
2. **Sweep:** on-time perception, on-time planning and science delivered, against fleet size (1 to 2,000 robots) for the three policies.
3. **3D animation:** the Moon, the five LCRNS relays and their orbits, the base, the active link (blue: direct to Earth, green: through a relay), Earth and Sun directions, a close-up of the south pole, and live panels.

## Model

**Orbits.** The NASA LCRNS Reference Constellation 3.1 initial states (NTRS 20250002698, Moon principal-axis frame, epoch 2027-03-01) are propagated two-body. Node regression is about 1°/day, which matches the 90-day GMAT propagation of the tutorial paper. The model checks out against that paper:

| Quantity | This model | Paper |
|---|---|---|
| Period | 30.0 h | — |
| Per-relay visibility from the south pole | 84 % | 83 % |
| A relay path with 5 satellites | 100 % of the time | 100 % of the time |

**Site.** The model includes optical libration (±7.9°, ±6.7°), a synodic Sun, horizon dip from site height, and one obstructing massif. These give 93 % illumination and a ~2-day dark spell at the polar ridges (paper: 92–96 %, 1.5–5 days).

**Links** (tutorial paper values):

| Path | Rate |
|---|---|
| X-band direct to Earth | 100 Mbps |
| Ka through a relay | 16 Mbps |
| Earth–Moon round trip | 2.56 s |
| Surface cell round trip | 20 ms |

**Inference cost** (`request_cost.m`):
- Prefill is compute-bound (40 % of dense FP8 peak).
- Decode is memory-bound (70 % of bandwidth).
- For mixture-of-experts models, the experts touched per step grow with the batch.

**Hardware, per chip:**

| Chip | Memory | Bandwidth | FP8 dense | Power |
|---|---|---|---|---|
| Jetson AGX Thor T5000 | 128 GB | 273 GB/s | ~517 TFLOPS | 40–130 W |
| B200 (DGX B200: 8 GPUs, 14.3 kW, ~142 kg) | 180 GB | 8 TB/s | 4.5 PFLOPS | — |
| 2035 GPU, hackathon catalog | 3 TB | 120 TB/s | assumed 4× B200 | 5.5 kW |

**Models:**
- vision-language 7B (perception, 1 Hz, 1 s deadline; science-image triage);
- Kimi K3 (2.8T total, 104B active, 896 experts, 16 active, MXFP4; planning, 1 per 10 min, 60 s deadline);
- a distilled 30B-A3B planner.

**Energy on the Moon** is the launch cost of the power plant divided by the energy the base uses over 5 years. The plant is arrays at 62.5 kg/kW (VSAT, 10 kW in ≤625 kg), a battery at 200 Wh/kg sized for 4 h, and radiators at 4 kg/kW, or 40 kWe fission units of ~6 t.

## Results (100 robots, Connecting Ridge, DGX B200, ridge solar, Starship price)

- **Perception cannot run on Earth.** 0 % meets the 1 s deadline, because of the 2.56 s round trip. On board, a Thor takes 1.25 s and 163 J per request. At the base it takes 8 ms and 17 J.
- **Kimi K3 does not fit in one DGX B200.** It has 1.44 TB of HBM against ~1.5 TB of weights, so it needs two nodes (~29 kW). Planning on Earth works whenever a link exists. With only the first relay, the base's distilled planner covers the gaps, so Adaptive reaches 100 % against 93 % for EarthBrain.
- **Science return to Earth collapses without on-Moon triage.** At 100 robots, EarthBrain delivers ~19 % of the data and Adaptive ~100 %.
- **The base fails at about 1,000 robots.** One DGX B200 runs out of capacity there.
- **Lunar energy costs about $550/kWh at the Starship quote, against $0.06/kWh on Earth.** The Moon should only run what latency, link capacity or contact gaps force it to run.

## Simplifications

- Two-body orbits with a mean node regression (no full gravity field).
- One terrain obstacle per site.
- Continuous Earth ground coverage (three DSN-like complexes).
- Queueing beyond one 5-minute step is ignored.
- Hardware purchase and radiation mitigation are not costed.
- The 2035 GPU FLOPS are an assumption.

## Sources

- NASA LCRNS Reference Constellation 3.1, NTRS 20250002698.
- E. Baena et al., *From Non-Terrestrial Networks to the Moon: A Tutorial and Roadmap* (link budgets, LCRNS GMAT propagation, illumination, power table).
- NVIDIA Jetson AGX Thor and DGX/HGX B200 datasheets.
- Kimi K3 model card (Moonshot AI, 2026).
- NASA BEACON / VSAT reports (NTRS).
- NASA Fission Surface Power (40 kWe, <6 t).
- Sundai Hack 145 Track 1 deck (2035 catalog, launch prices).
