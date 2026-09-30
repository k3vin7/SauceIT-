# Fry Stalker

The `source/` directory preserves the user-supplied `Production_FryStalker.blend`
and its Blender build script unchanged. The local machine does not expose a
Blender executable, so the game presentation is rebuilt at runtime by
`res://scripts/fry_stalker_visual.gd` from the source script's authored
dimensions, colours, eight three-piece fry legs, sequential gait, and front-pair
slam.

Gameplay integration lives in `MayoEnemy.build_fry_stalker`:

- speed: 1.10 times player walk speed (between hamburger 0.70 and toast 1.65)
- sight / give-up: 26 m / 44 m, matching the hamburger
- solo health: 240, matching the hamburger and using normal heavy scaling
- height: 6.4 m, exactly 2.5 times the 2.56 m player gameplay capsule
- attack: two front claws slam and remain planted for a 1.4 second movement lock
- spawn: map pixel `(290, 850)`, on the opening road before the first existing group

`res://tests/probe_fry_stalker.gd` verifies those relationships, the first-encounter
placement, all-eight-leg gait, and the planted attack window.
