# Where must lunar robots think?

MATLAB simulation for Sundai Hack 145, Track 1 ("Build the AI data center of 2035"), as the team's what-if: the users are robots on the Moon. Each robot request runs on one of four tiers:
- the robot itself;
- edge nodes on the lunar relay constellation;
- a data center at the lunar base;
- data centers on Earth.

Which tier serves a request depends on the real relay orbits, terrain shadowing, the lunar day, link capacity and datasheet GPU specs. The point is that each tier wins at a different cognitive load:

| Cognitive load | Model | Deadline | Best tier and why |
|---|---|---|---|
| Reflex / control | on-board policy | ms | **Robot**: no link can meet it |
| Perception | vision-language 7B, 1 Hz | 1 s | **Lunar base**: 8 ms there against 2.56 s round trip to Earth; the on-board Orin NX takes 3.9 s |
| Tactical reasoning with images | 30B-A3B MoE | 10 s | **Lunar base** in the cell; **relay constellation** for explorers out of the cell (7.6 s on a relay Thor, no Earth link needed) |
| Deep reasoning that can wait | Kimi K3 thinking (4,000 tokens) | 1 h, store and forward | **Earth**: the superior model at ~$0.06/kWh; the base runs a distilled model only when the deadline is about to expire |

![video](lunar_inference.mp4)

## Coordinated data centers: where the saving comes from

The design rule is that **models are combined across compute nodes, each working at its own timescale**:
- **The Moon keeps only what is real time.** Reflexes run on the robot. An on-board detector screens every frame, and only frames that change go to the 7B model at the lunar base (1 s deadline).
- **What can wait goes to Earth while the link has room.** That covers tactical reasoning (30B, 10 s) and deep reasoning (Kimi K3, 1 h, store and forward), where energy costs $0.06/kWh against ~$480/kWh on the Moon.
- **The Moon takes over only when the link does not allow it.** In contact gaps or under congestion, the relays run the 30B model for explorers, the base runs it for robots in the cell, and the robot's 3B model is the last resort.
- **The cascade escalates.** Hard requests go to Kimi K3 on Earth while the robot keeps acting on its own model.

This is the `Coordinated` policy. `lunar_savings.m` compares it with four other strategies using the same simulation (orbits, links, power). `lunar_robot_story.mp4` shows it from two robots' side.

![savings](figures/savings_1relay.png)

Per robot-day, Connecting Ridge, 100 robots (40 % exploring), first relay only, Starship launch price. Cost is marginal compute energy on each tier times that tier's $/kWh.

| Strategy | Thinking cost | Perception / tactical / deep by Kimi K3 | Lunar base peak |
|---|---|---|---|
| All on the robot (Thor each) | ~$1,450 | 0 / 100 / 0 % | — |
| All on Earth | ~$0 | **0** / 88 / 94 % | 2 kW |
| All on the Moon (K3 at the base) | ~$310 | 100 / **60** / 0 %* | 31 kW |
| Moon-first (base, relays, then Earth) | ~$134 | 100 / 92 / 94 % | 16 kW |
| **Coordinated** | **~$37** | **100 / 100 / 94 %** | 16 kW |

\* At the base, Kimi K3 answers but explorers are unserved.

The coordinated policy spends *more* joules than Moon-first, because Earth runs Kimi K3 on the escalations too. It spends 76 % fewer joules on the Moon, which makes it 3.6x cheaper while serving everything on time. The one cost it cannot remove is real-time perception at the base, which stays on the Moon by physics.

## Run

Open MATLAB in this folder and run:

```matlab
run_lunar_hack
```

The scenario knobs are at the top of `run_lunar_hack.m`. All defaults (workload, links, power, explorers, cognitive tiers) are in `lunar_config.m`.

| Knob | Options |
|---|---|
| `site` | `Malapert` (Earth always in view), `ConnectingRidge` (Earth on the horizon), `FarSide` (no Earth, 14.8-day night) |
| `nRobots`, `fracExploring` | Fleet size, and the share of robots outside the base cell (crater floors, 15° terrain mask) |
| `nRelays` | LCRNS relays deployed: 1 is the first relay (2027), 5 is the full constellation |
| `policy` | `EarthOnly`, `BaseOnly`, `Hierarchical` (Moon-first), `Coordinated` (cheapest node that meets each deadline with the current link; default) |
| `baseHW` | `Thor-cluster`, `DGX-B200`, `2xDGX-B200`, `GPU-2035x2` |
| `power` | `RidgeSolar` (VSAT-class arrays and battery), `Fission` (40 kWe units) |
| `launchPrice` | `Deck2035` ($1,200/kg), `Starship` (~$100,000/kg quote), `CLPS` (~$1M/kg) |

Set `cfg.saveVideo = true` to write `lunar_inference.mp4`. The included render shows the default scenario: Connecting Ridge, 5 relays, 100 robots, 4 days.

## Outputs

- **3D animation:**
  - the Moon with the five LCRNS relays on their orbits;
  - the base (orange square) and an explorer in a crater (purple triangle);
  - the active links: blue for direct to Earth, green through a relay, purple dashed from an explorer to the relays that run its tactical model (those relays are ringed);
  - a south-pole close-up;
  - live panels for "who thinks" on tactical and deep reasoning.
- **Dashboard:**
  - link and relays;
  - sunlight and battery;
  - tactical, deep and perception load by tier;
  - science backlog;
  - per-request latency and energy on each tier;
  - energy cost per tier;
  - mass to the Moon.
- **Sweep, 1 to 1,000 robots, three policies:** perception, tactical and deep-reasoning service, science returned, and energy cost (`figures/`).

## Results (Connecting Ridge, 40 % explorers, DGX B200 base, ridge solar)

On-time service against fleet size, first relay only (2027):

| Robots | Tactical on time (Earth only / Base only / Hierarchical) | Deep reasoning by Kimi K3 (same order) | Science returned (same order) |
|---|---|---|---|
| 10 | 88 / 60 / **92 %** | 94 / 0 / **94 %** | 95 / 100 / **100 %** |
| 100 | 88 / 60 / **92 %** | 94 / 0 / **94 %** | 28 / 100 / **100 %** |
| 500 | 61 / 60 / **84 %** | 54 / 0 / **94 %** | 3 / 81 / **81 %** |
| 1,000 | 46 / 60 / **72 %** | 54 / 0 / **94 %** | 1 / 63 / **63 %** |

With the full five-relay constellation, hierarchical tactical service is 100 % up to 500 robots and 85 % at 1,000, against 67 % and 50 % for Earth only.

**What each tier brings:**
- **Lunar base:** the only place that meets the 1 s perception deadline, and it triages science so the link to Earth is not saturated.
- **Relay constellation:** tactical reasoning for robots the base cannot reach. It does not need an Earth link, so it covers the contact gaps and the link congestion that make Earth-only service fail as the fleet grows.
- **Earth:** deep reasoning with the larger model at the cheapest energy (Kimi K3 needs two DGX B200 nodes, ~29 kW, which a lunar base cannot power cheaply). Store and forward fits within the 1 h deadline whenever a contact arrives in time.

**What it costs.** At the Starship price, lunar energy costs ~$570/kWh at the base and ~$210/kWh on the relays, against $0.06/kWh on Earth. Hence the rule: the Moon thinks only what latency, link capacity or contact gaps force it to.

**What does not work.** Splitting one model by layers across the relays, as JARVIS does, fails for interactive reasoning. The relays are 4,000–22,000 km apart, which adds tens of milliseconds per hop to every token. The constellation instead runs a full replica on each relay and spreads requests across the relays in view.

## Model

**Orbits.** The NASA LCRNS Reference Constellation 3.1 initial states (NTRS 20250002698, Moon principal-axis frame, epoch 2027-03-01) are propagated two-body. Node regression is about 1°/day, which matches the paper's 90-day GMAT run. Checked against that paper:
- period 30.0 h;
- per-relay visibility from the south pole 84 % (paper: 83 %);
- relay eclipses by the Moon are included.

**Site.** Optical libration, a synodic Sun, horizon dip and one obstructing massif give 93 % illumination with a ~2-day dark spell (paper: 92–96 %, 1.5–5 days). Explorers sit at 88.6° S, 60° W behind a 15° crater mask.

**Links** (tutorial paper):

| Path | Rate |
|---|---|
| X-band direct to Earth | 100 Mbps |
| Ka through a relay | 16 Mbps |
| Earth–Moon round trip | 2.56 s |
| Surface cell round trip | 20 ms |
| Surface to relay round trip | ~0.12 s |

**Inference cost** (`request_cost.m`):
- Prefill is compute-bound (40 % of dense FP8).
- Decode is memory-bound (70 % of bandwidth).
- For mixture-of-experts models, the experts touched per step grow with the batch.
- Single-module nodes (robot, relay) serve one request at a time.

**Hardware** (datasheets):

| Device | Specs |
|---|---|
| Jetson Orin NX 16 GB (robot) | 102 GB/s, 25 W |
| Jetson AGX Thor (2 per relay, 300 W of the relay bus) | 128 GB, 273 GB/s, ~517 FP8 TFLOPS, 130 W |
| DGX B200 (8 × B200) | 180 GB and 8 TB/s per GPU, 14.3 kW, ~142 kg |
| 2035 GPU, hackathon catalog | 3 TB, 120 TB/s, 5.5 kW; FLOPS assumed at 4× B200 |

**Energy on the Moon** is the launch cost of the power plant divided by the energy used over 5 years:
- base: arrays at 62.5 kg/kW (VSAT), a 4 h battery at 200 Wh/kg, radiators at 4 kg/kW, or 40 kWe fission units of ~6 t;
- relays: compute modules plus 5 kg/kW of arrays and 4 kg/kW of radiators.

## Simplifications

- Two-body orbits with a mean node regression.
- One terrain obstacle per site; explorers at a single representative location.
- Continuous Earth ground coverage.
- Tactical and deep tasks are independent of each other.
- Queueing within one 5-minute step is ignored.
- Hardware purchase and radiation mitigation are not costed.

## Sources

- NASA LCRNS Reference Constellation 3.1, NTRS 20250002698.
- E. Baena et al., *From Non-Terrestrial Networks to the Moon: A Tutorial and Roadmap*.
- M. Sirera Perelló et al., *JARVIS: Disjoint LLMs on Radio VLANs*, IEEE MILCOM 2024.
- NVIDIA Jetson Orin NX, Jetson AGX Thor and DGX B200 datasheets.
- Kimi K3 model card (Moonshot AI, 2026).
- NASA BEACON / VSAT reports.
- NASA Fission Surface Power.
- Sundai Hack 145 Track 1 deck.
