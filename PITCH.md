# Fast Moon, Slow Earth
**Distributed inference, distributed reasoning and distributed allocation across three AI data centers: the Moon, its relay constellation and Earth**

*Lunar and Earth data centers as one fleet: real-time AI on the Moon, the rest on Earth, 3.9x cheaper than putting it all on the Moon*

## The problem
By 2035, hundreds of robots will work at the lunar south pole, and they will need AI at very different speeds:
- avoiding a hazard in under a second;
- re-planning a route in seconds;
- reasoning about a mission over an hour.

Serving them all from Earth fails, because the round trip is 2.56 s and the links are narrow and intermittent. Serving them all from the Moon is very expensive, because every kilowatt-hour there means launching the power plant that produces it: about $480/kWh at a Starship price of $100,000/kg, against $0.06/kWh on Earth. That is 8,000 times more.

## The idea
The question is not where to put the data center, but which thought deserves a lunar joule. One fleet of three data centers, each serving the timescale it is best at:

| Data center | Hardware | Role | Timescale |
|---|---|---|---|
| **Lunar base** | 3 small servers (RTX PRO 6000 class, 800 W each) on a sunlit ridge | Real-time perception for robots in the base cell; fallback when the link fails | 1 s |
| **Lunar constellation** | 2 x Jetson Thor on each LCRNS relay satellite | Tactical reasoning for explorers when the link to Earth cannot carry it | 10 s |
| **Earth** | 2 x DGX B200 running Kimi K3, at the cheapest of three grid sites each hour | Everything that can wait: tactical reasoning while the link has room, deep reasoning, second opinions | 10 s – 1 h |

The robots keep only reflexes, a frame detector and a small 3B model on board.

## Three layers of distribution
1. **Distributed inference: one request flows through several nodes.**
   - The on-board detector screens every camera frame; only the frames that change (about 1 in 4) reach the 7B model at the base.
   - The base batches them up to the deadline.
   - Each relay runs a full replica of the 30B model. Splitting one model by layers across relays fails, as JARVIS shows: the relays are 4,000–22,000 km apart, which adds tens of milliseconds to every token.
2. **Distributed reasoning: the same decision is thought fast on the Moon and slow on Earth.**
   - Every tactical decision gets a fast answer on the Moon, and the robot acts on it.
   - The ~10 % the fast model is unsure about also go to Kimi K3 on Earth by store and forward. That share rises during hazards and in new terrain.
   - Kimi K3's answer arrives about a minute later and corrects the plan when the fast answer was wrong.
3. **Distributed allocation across data centers: each request goes to the cheapest node that meets its deadline, given the live link state.**
   - Real time stays on the Moon.
   - What can wait flies to Earth while the link has room.
   - The relays and the base take over only when the link does not allow it.
   - On Earth, work follows the cheapest grid site hour by hour.

## What we built
A MATLAB digital twin with:
- **real orbits:** the NASA LCRNS Reference Constellation 3.1 states;
- **real geometry:** terrain shadowing, the lunar day, link capacities and the light-time delay;
- **datasheet hardware:** per-request latency and energy from memory-bandwidth and FLOPS models;
- **dynamic power:** every 5 minutes, each data center draws what its work needs. The model covers operator shifts, hazard bursts and random arrivals; batch size; busy, idle and parked GPUs; cooling; the transmitter; the relay power budget; and hourly prices at three Earth sites;
- **costs:** launch-based $/kWh for each lunar data center, and a power plant sized to the measured peak.

It produces:
- a live video of the fleet's power (`lunar_fleet_power.mp4`);
- a 3D animation of the orbits;
- a robot's-eye video;
- every number below (`NUMBERS.md`).

## Results
100 robots, 40 % of them exploring craters, first relay only. Energy bill = all the energy the compute draws (work, idle GPUs, cooling, radio) times each tier's $/kWh.

| Strategy | Energy bill per robot-day | Perception / tactical on time | Lunar base peak load |
|---|---|---|---|
| All on Earth | ~$0 | **0** / 88 % | 1.0 kW |
| All on the Moon (Kimi K3 at the base, 2 x DGX) | ~$524 | 100 / **60** % | 11.3 kW |
| Moon-first (same small servers) | ~$238 | **87 / 83 %** | 3.6 kW |
| **Fast Moon, Slow Earth** | **~$135** | **100 / 100 %** | **3.3 kW** |

The coordinated fleet:
- is **3.9x cheaper** than running everything on the Moon;
- is **1.8x cheaper** than Moon-first and serves every robot on time, where the same small servers saturate under Moon-first;
- spends **74 % less energy on the Moon**;
- draws a **peak of 3.3 kW instead of 11.3 kW**, so the lunar power plant costs about $35 M to launch instead of $119 M;
- **halves wrong decisions** (8.9 % to 4.9 %) with Kimi K3's second opinions, which arrive in under a minute on average.

**What the architecture sweep shows** (`NUMBERS.md`, section 3):
- **Size the lunar data center to the fleet.**
  - For 100 robots, 3 small servers cost 40 % less than a DGX B200 ($132 vs $220 per robot-day), because a DGX idles most of the time.
  - For 500 robots, the DGX wins ($81 vs $94), because its batching pays off at high load.
- **More relays** are a communications asset first. For compute they help only when the link to Earth saturates: at 500 robots, wrong decisions fall from 6.6 % with the first relay to 4.6 % with five and 4.4 % with a denser constellation of 15; at 100 robots they change nothing.
- **An Earth-orbit data center** for the slow tier costs ~$0.27/kWh (launch to LEO at the deck's $1,200/kg), 5x the grid, with zero operational carbon. Next to lunar prices, that difference is invisible in the bill.

## How it fits Track 1
- **Where:** it uses the deck's Moon and orbit sites, and adds a lunar orbital data center.
- **Serving:** it applies the deck's serving levers (routing, batching, multi-model cascades, splitting work between sites) across three data centers.
- **Score:** it is scored the way the track scores, by service at deadline first, then dollars.

Our what-if: when the users live on the Moon, the cheapest AI data center is a fleet where the Moon thinks fast and Earth thinks slow.

---

## 3-minute pitch

**1. Hook (15 s).** "A kilowatt-hour on the Moon costs about $480, because you have to launch the power plant that makes it. On Earth it costs 6 cents. That's 8,000 times more."

**2. Problem (30 s).** "By 2035, hundreds of robots will work at the lunar south pole. They need AI at three speeds: dodge a hazard in a second, re-plan in ten seconds, reason about the mission in an hour. Earth is too far for the first, with a 2.56-second round trip. The Moon is too expensive for the rest."

**3. Insight (30 s).** "So we stopped asking where to put the data center and asked which thought deserves a lunar joule. We distribute three things:
- inference: one request flows through several nodes, from a detector on the robot to a model at the base;
- reasoning: every decision is thought fast on the Moon and, when the robot is unsure, slowly on Earth;
- allocation: each request goes to the cheapest data center that meets its deadline, given the live link."

**4. How we measured it (40 s).** "We built a MATLAB digital twin with:
- NASA's LCRNS relay orbits;
- terrain shadowing;
- real link capacities;
- datasheet hardware;
- power modelled every 5 minutes: operator shifts, hazard bursts, batching, idle GPUs, cooling, hourly Earth prices.

Same robots, same work, same orbits for five strategies; only the placement changes. We score it the way Track 1 scores: service at deadline first, then dollars, then peak kilowatts, because the peak sets the power plant you launch."

**5. Results (30 s).** "All on Earth is free but misses every real-time deadline. All on the Moon costs $524 per robot-day and serves only 60 % of tactical decisions on time. Fast Moon, Slow Earth serves 100 % on time for $135. That is 3.9 times cheaper, with a peak of 3.3 kilowatts instead of 11, and half the wrong decisions thanks to Kimi K3's second opinions."

**6. The surprise (30 s).** "On the Moon, efficiency isn't about faster chips. A DGX B200 at the base idles most of the time: for 100 robots, three small servers are 40 % cheaper. It's about not launching idle silicon, and sending the peaks to Earth."

**7. Close (15 s).** "When your users live on the Moon, the cheapest AI data center isn't one place. It's a fleet: the Moon thinks fast, Earth thinks slow."

### Prepared answers
- **Where does $480/kWh come from?** The Starship launch price (~$100k/kg) times the kg of power plant per kW, spread over 5 years. Lower launch prices shrink the saving, but the ranking of the strategies holds.
- **Why not split one model across data centers?** JARVIS: relays are 4,000–22,000 km apart, so each hop adds tens of milliseconds per token. We distribute whole requests, and chain models across nodes.
- **Are the error rates real?** They are assumptions in `lunar_config.m`: the 30B model is wrong 8 % of the time, the 3B 20 %; half of the escalated answers are wrong; Kimi K3 fixes 90 % of those. The mechanism and the timing come from the simulation.
- **Hardware purchase?** Not costed; only energy and launch are. That is conservative for us, because the coordinated fleet launches less hardware.
- **Why relays if they rarely compute?** They are the insurance for explorers when the link to Earth fails or saturates. At 500 robots they draw ~400 W and cut wrong decisions.
