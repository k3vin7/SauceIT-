# Sauce combat feel — 2026-10-01

- Travel speed: 14 → 20 m/s. A separate 14 m/s emission reference preserves point delivery and tank consumption. Powered lifetime, strand spacing and break distances scale with the travel/reference ratio.
- Bottle: 6.5 cm / 2° recoil settings, 35 ms attack and 130 ms settle, with a separate 2.2 cm full-pressure offset. The sustained offset retains at least 45% while delivering, then returns over the 160 ms release constant. Rotational wander is reduced to 0.6–1.2° so backward motion dominates. Mesh motion stays independent of the camera, aim and collision muzzle.
- First contact: larger splash, short liquid impact and brief reticle accent. Per-enemy 220 ms contact grace prevents retriggering on every stream point.
- Sustained contact: smaller paced splashes, denser loop, irregular liquid impacts, and a 2.5° pressure lean; no stun. First contact adds a short 5° recoil.
- Threshold: 12° flinch, one accent per threshold crossing. Defeat: larger splash, lower sound and a distinct reticle confirmation. Reliable multiplayer events identify the accent independently of enemy health snapshots.
- Bundled audio is original procedural prototype foley; the exported streams remain replaceable.

Validation: existing feel, connection, flinch, impact, whip and burst probes; new combat-feel and feedback-network probes. Visual captures inspected for idle, firing recoil and contact. A half-second delivery comparison produced 86 points and 0.95833 tank remaining at both speeds, with first-point velocity rising from 14.23 to 20.33 m/s (same random seed).

The broad network probe has an existing floor-depth fixture failure, reproduced against HEAD before this change. One current run also failed the random nozzle-catch coverage check; the baseline caught 22 frames. The focused feedback-network probe isolates the new reliable event routing from those scenarios.

## Range correction

The first change preserved only the powered range, not the falling trajectory. At 1.3 m launch height with a level, full-pressure single point, the old 14 m/s shot landed at 12.93 m, while the uncorrected 20 m/s shot landed at 15.80 m. Gravity now scales by the square of the travel-speed ratio, and inherited player velocity by the ratio, compressing the same arc in time. The corrected 20 m/s shot lands at 12.71 m in 0.650 s versus 12.93 m in 0.933 s at 14 m/s. The small difference comes from 60 Hz integration. `probe_flight_range.gd` checks 24 combinations of aim angle, pressure, release and movement against a physical floor, within one fast physics step of distance.

## Nozzle attachment

A four-point tapered visual connection now joins the recoiling nozzle tip to the freshest point in the current spray. The local connection follows the viewmodel at render rate; the full ribbons retain their physics-rate updates. Releasing the nozzle, switching bursts or an aged/distant point prevents a tether. The physical muzzle, projectile positions and range are unchanged. Combat-feel, visibility and whip probes passed, and firing/contact captures show a continuous connection at the tip.
