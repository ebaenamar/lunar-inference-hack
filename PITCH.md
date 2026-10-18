# Fast Moon, Slow Earth
**An AI data center fleet across the Moon, its relay constellation and Earth**

*Lunar and Earth data centers as one fleet: real-time AI on the Moon, the rest on Earth, 3.6x cheaper*

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
- **costs:** launch-based $/kWh for each lunar data center.

It produces a 3D animation of the fleet, a robot's-eye video of each thought travelling to its data center, and a comparison of five strategies.

## Results
100 robots, 40 % of them exploring craters, first relay only:

| Strategy | Thinking cost per robot-day | Perception / tactical on time | Lunar base peak |
|---|---|---|---|
| All on Earth | ~$0 | **0** / 88 % | 2 kW |
| All on the Moon (Kimi K3 at the base) | ~$310 | 100 / **60** % | 31 kW |
| Moon-first | ~$134 | 100 / 92 % | 16 kW |
| **Fast Moon, Slow Earth** | **~$37** | **100 / 100 %** | **16 kW** |

The coordinated fleet:
- is **3.6x cheaper** than Moon-first and **8x cheaper** than running everything on the Moon;
- spends **76 % less energy on the Moon**;
- needs a **lunar power plant half the size**, which saves about $150 M in launch;
- serves every robot on time, with 94–100 % of deep reasoning answered by the frontier model.

## How it fits Track 1
- **Where:** it uses the deck's Moon site and extends it with a lunar orbital data center.
- **Serving:** it applies the deck's serving levers (routing, multi-agent cascades, splitting work between sites) across three data centers.
- **Score:** it is scored the way the track scores, by service at deadline and then dollars.

Our what-if: when the users live on the Moon, the cheapest AI data center is a coordinated fleet where the Moon thinks fast and Earth thinks slow.
