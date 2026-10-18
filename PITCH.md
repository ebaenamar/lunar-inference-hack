# Fast Moon, Slow Earth
**An AI data center fleet across the Moon, its relay constellation and Earth**

*Lunar and Earth data centers as one fleet: real-time AI on the Moon, the rest on Earth, 3x cheaper*

## The problem
By 2035, hundreds of robots will work at the lunar south pole, and they will need AI at very different speeds:
- avoiding a hazard in under a second;
- re-planning a route in seconds;
- reasoning about a mission over an hour.

Serving them all from Earth fails, because the round trip is 2.56 s and the links are narrow and intermittent. Serving them all from the Moon is very expensive, because every kilowatt-hour there means launching the power plant that produces it: about $480/kWh at a Starship price of $100,000/kg, against $0.06/kWh on Earth.

## The idea
One fleet of three data centers. Each one serves the timescale it is best at:

| Data center | Hardware | Role | Timescale |
|---|---|---|---|
| **Lunar base** | 1 x DGX B200 (14.3 kW) on a sunlit ridge | Real-time perception for robots in the base cell | 1 s |
| **Lunar constellation** | 2 x Jetson Thor (260 W) on each of the 5 LCRNS relay satellites | Tactical reasoning for explorers beyond the base cell; backup during link gaps | 10 s |
| **Earth** | 2 x DGX B200 running Kimi K3 | Everything that can wait: tactical reasoning while the link has room, deep reasoning, escalations | 10 s – 1 h |

The robots keep only reflexes and a small 3B model on board.

**Scheduler rule.** Each request goes to the cheapest data center that meets its deadline, given the link state at that moment. Real time stays on the Moon. Everything else flies to Earth while the link has capacity. The Moon's data centers take over only when the link does not allow it.

**Models are combined across nodes:**
- an on-board detector sends only the frames that change to the base, which cuts real-time load by 80 %;
- hard questions escalate from the 30B model to Kimi K3 on Earth by store-and-forward, while the robot keeps acting.

## What we built
A MATLAB digital twin with:
- **real orbits:** the NASA LCRNS Reference Constellation 3.1 states;
- **real geometry:** terrain shadowing, the lunar day, link capacities and the light-time delay;
- **datasheet hardware:** per-request latency and energy from memory-bandwidth and FLOPS models;
- **dynamic power:** every 5 minutes, each data center draws what its work needs: batch size, busy and parked GPUs, cooling, transmitter, relay power budget, and the hourly price of three Earth sites;
- **costs:** launch-based $/kWh for each lunar data center.

It produces a 3D animation of the fleet, a robot's-eye video of each thought travelling to its data center, and a comparison of five strategies.

## Results
100 robots, 40 % of them exploring craters, first relay only:

| Strategy | Thinking cost per robot-day | Perception / tactical on time | Lunar base peak load |
|---|---|---|---|
| All on Earth | ~$0 | **0** / 88 % | 1.0 kW |
| All on the Moon (Kimi K3 at the base) | ~$293 | 100 / **60** % | 11.3 kW |
| Moon-first | ~$137 | 100 / 92 % | 4.5 kW |
| **Fast Moon, Slow Earth** | **~$45** | **100 / 100 %** | **3.6 kW** |

The coordinated fleet:
- is **3x cheaper** than Moon-first and **7x cheaper** than running everything on the Moon;
- spends **70 % less energy on the Moon**;
- draws a **peak of 3.6 kW instead of 11.3 kW**, because the shift-start planning bursts go to Earth, so the lunar power plant is 68 % smaller and about $80 M cheaper to launch;
- serves every robot on time, with 94–100 % of deep reasoning answered by the frontier model.

## How it fits Track 1
- **Where:** it uses the deck's Moon site and extends it with a lunar orbital data center.
- **Serving:** it applies the deck's serving levers (routing, multi-agent cascades, splitting work between sites) across three data centers.
- **Score:** it is scored the way the track scores, by service at deadline and then dollars.

Our what-if: when the users live on the Moon, the cheapest AI data center is a coordinated fleet where the Moon thinks fast and Earth thinks slow.

---

## 3-minute pitch

**1. Hook (15 s).** "A kilowatt-hour on the Moon costs about $480, because you have to launch the power plant that makes it. On Earth it costs 6 cents. That's 8,000 times more."

**2. Problem (30 s).** "By 2035, hundreds of robots will work at the lunar south pole. They need AI at three speeds: dodge a hazard in a second, re-plan in ten seconds, reason about the mission in an hour. Earth is too far for the first, with a 2.56-second round trip. The Moon is too expensive for the rest."

**3. Insight (30 s).** "So we stopped asking where to put the data center and asked which thought deserves a lunar joule. Only the ones latency forces there." Three data centers act as one fleet: the lunar base for real time, the relay constellation as the backup for explorers, Earth for everything that can wait. Each request goes to the cheapest node that meets its deadline given the live link state.

**4. How we measured it (40 s).** A MATLAB digital twin with:
- NASA LCRNS relay orbits;
- terrain shadowing and the lunar day;
- real link capacities;
- datasheet hardware;
- power modelled every 5 minutes: operator shifts, hazard bursts, batching, idle GPUs, cooling, relay power budgets, hourly Earth prices.

Same robots, same work, same orbits for five strategies; only the placement changes. Scored as Track 1 scores: service at deadline first, then dollars, then peak kW, because the peak sets the mass of the power plant you launch.

**5. Results (30 s).** All on Earth is free but misses every real-time deadline. All on the Moon costs ~$293 per robot-day and serves only 60 % of tactical requests on time. Fast Moon, Slow Earth serves 100 % on time for ~$45: 3x cheaper than Moon-first and 6.5x cheaper than all on the Moon, with 70 % less lunar energy and a peak of 3.6 kW instead of 11.3 kW.

**6. The surprise (30 s).** "The lunar DGX is busy only 2 to 10 % of the time: the real-time load of 100 robots fits in one GPU. On the Moon, efficiency isn't about faster chips. It's about not launching idle silicon, and about sending the peaks to Earth." We get there by:
- batching up to the deadline: 21 J per frame instead of 62 J;
- parking unused GPUs;
- sizing the plant to the measured load: a 6 kW array instead of 21 kW.

**7. Close (15 s).** "When your users live on the Moon, the cheapest AI data center isn't one place. It's a fleet: the Moon thinks fast, Earth thinks slow."

### Prepared answers
- **Where does $480/kWh come from?** The Starship launch price (~$100k/kg) times the kg of power plant per kW, spread over 5 years. Lower launch prices shrink the saving, but the ranking of the strategies holds.
- **Hardware purchase?** Not costed; only energy is. That is conservative for us, because the coordinated fleet launches less hardware.
- **Why relays if they rarely compute?** They are the insurance for explorers when the link to Earth fails. Under Moon-first they draw ~120 W on average.
