# MAYO MAN — Step 1 prototype

Godot 4 3D prototype for validating one continuous viscous mayonnaise strand, per-point ballistic drop, wall attachment, and persistent grid contamination.

## Run

1. Open this directory in Godot 4.4 or newer.
2. Run the project (`F6`/`F5`). The main scene is already configured.
3. Move with `WASD`, hold `Shift` to run, `Space` to jump, aim with the mouse, and hold the left mouse button to fire. `R` wipes sauce off your screen. `F1` switches between first person and the over-the-shoulder third-person camera. `Esc` exits.
4. `E` at one of the blue stalls fills the sauce bottle. Fire runs about a second on a full bottle, then pauses half a second and goes again on its own if you are still holding; each squirt is shorter than the last, so the stalls are where you go when they stop reaching.
5. Spray the floor, then run across your own mayo. Running over a painted cell knocks you down; walking over it does not.
6. `F2` opens the LAN panel; without it the game is the single-player one it has always been.

The mouse is captured and there is no on-screen cursor: aiming accumulates yaw and pitch from relative mouse motion, FPS-style, and a fixed crosshair marks the centre of the screen. `WASD` moves relative to where you are facing. Both camera modes run the same aim code and differ only in where the camera sits, so switching does not change how the weapon points.

## Tune

Select the root `MayoPrototype` node in `main.tscn`. Its Inspector groups expose the reference stream values, per-point time/distance lifetime switches, gravity, inertial bend, grid bridge settings, and third-person camera angle/distance.

All requested baseline values are under **Mayo Stream — Reference Values** and **Landing and Grid**.

`Stream Range` and `Point Time Lifetime` both cut the stream's powered phase, and whichever comes first wins, so they are kept matched at `extend_speed`: 2.94 m and 0.21 s at 14 m/s. Changing one alone does nothing — the other still cuts at the old distance. The generated `FloorContamination` node and each `ContaminableObject` wall expose the same cell/brush settings, and `MayoPrototype` pushes its `Landing and Grid` values into all of them on ready.

**Weapon Hold** places the sauce bottle: right, up and forward offsets from the eye, plus its radius and length. The bottle is a first-person viewmodel — in third person it would sit inside the capsule, so it is hidden. `Aim Convergence Distance` is the distance along the view axis where the strand crosses the crosshair; without it an off-centre nozzle fires parallel to the view and misses the reticle by the full hold offset (measured: 0.267 m).

### The tutorial street

`scripts/street_map.gd` builds the level off the Haapsalu *maitsete promenaad* festival map. It is generated rather than authored, and the whole thing is one lattice: a cell is one person wide (the capsule's 1.28 m diameter) times `SCALE`, and every street is declared as `ROAD_CELLS = 8` of them. That is why "the road is eight people wide" stays true — it is the literal statement in the code, not a metre figure copied into six rectangles that drift apart when one is edited. `SCALE` is 3.6, so a cell is 4.61 m and a street is 36.86 m across; the promenade covers 295 × 382 m. **Wall height no longer rides on it** — the streets have been widened twice without the walls being asked to grow with them, so `WALL_HEIGHT` is now stated outright at 12.6 m. The trade is worth knowing: a wider street is a longer sightline over a wall of fixed height, so at some width the far side of the map starts showing above them.

The layout is six overlapping lattice rectangles, and they **overlap rather than abut** — the overlap is the junction, so no crossing is a special case and the whole map falls out of their union:

* **Ehte tänav** along the top, the full width of the map
* **Karja tänav** down the middle: the promenade, and where most of the stalls are
* the **round place** where Karja leaves Ehte, a circle about twice the width of the street running into it
* the **festival square** hanging off Karja's east side, holding the stage and the tower
* **Saue tänav** crossing the promenade lower down
* the run from Saue down to **Kalda tänav**, which is where the player starts

**What was traced, and what was not.** The festival map is stylised: its streets are drawn far narrower than eight people relative to its blocks, so tracing it at true proportions would need a map several times this area — and a floor mask to match, which is the binding constraint below. The *topology* is what is reproduced, with the streets opened out to the width the game is built around. The blocks between them come out correspondingly thinner than on the drawing.

**The round place is generated separately, because a circle is not a `Rect2i`.** Approximating one out of stacked rectangles gives a staircase you can feel underfoot and that the wall merger turns into a dozen boxes, so `CIRCLES` carries centre and radius and `floor_cells` fills the disc directly. It is a filled circle rather than a ring around an island, and that is read off the drawing rather than assumed: the circle there is about twice the width of the street feeding it, so at the drawing's own proportions a ring road would leave an island of nothing. It is a place that happens to be round, not a roundabout. Its centre is set so the rim just meets Ehte tänav rather than on the drawing's own centre — the streets here are opened out to eight people and the circle is sized to keep that same two-to-one, so a circle left at the original centre is swallowed whole by the widened Ehte and reads as a bulge. `probe_map` walks 32 headings out of the middle, separates the ones that leave through a street from the ones that meet a rim, and fails if the rim wanders more than a cell and a half — which is what a polygon would do.

The walls are not authored either. Any cell within two of the street that is not street becomes wall, the adjacency test is Chebyshev so a diagonal corner is sealed rather than left as a gap a strand could fly through, and the result is greedily merged into maximal rectangles: 780 wall cells come out as **21 boxes**, because a street wall is one long run. Without the merge this map would be several hundred separate bodies.

**The stalls place themselves.** Every one of the 51 numbered markers on the drawing is a food or drink vendor, so every one of them gets a stall, anchored by its pixel position — but unlike the hand-sketch version the anchors carry no direction. Fifty-one hand-written facings is fifty-one chances to be quietly wrong, and a wrong one used to make a stall vanish without a word. Instead each anchor is snapped to the nearest street cell (markers on the drawing sit on the buildings as often as on the road), and the nearest wall from there is the one it backs onto. Where two would stand on the same ground — the markers cluster more tightly than a frontage allows — the second is moved to the nearest free frontage rather than being dropped, by a **breadth-first walk over the street** with the wall re-derived at each candidate. Marching along the original wall instead, which is what this did first, only reaches what lies on the two axes from where it started: a stall whose own wall was full could not cross the street or turn a corner, and on a crowded stretch the last markers had nowhere to go. A vendor whose pitch is too short for a double falls back to a single rather than losing the vendor. `probe_map` fails unless all 51 place, none share a cell, and all but at most two of the cooking vendors get their second gazebo.

**A stall is a 3 m × 3 m pop-up gazebo**, which is what a market pitch actually is — four legs, a canopy at about 2.2 m, a peak at 3.27 m, and a serving counter at waist height. Vendors that cook on the pitch get **two** of them, because the standard catering layout is one tent over the cooking and a second over the serving counter, which is why 3 × 6 m is a stock size next to 3 × 3 m; `DOUBLE_BAY_MARKERS` lists them by marker number so it reads against the legend — the food trucks, the grills, the burger and kebab stands.

The rendered stalls are now the four authored `food_booth_s1`–`s4` models: cocoa, garden, coastal, and sunset street-food designs. A fixed-seed shuffle uses every design and prevents consecutive pitches from repeating while remaining identical on every multiplayer peer. The models were authored at the human-scale dimensions (4.267 m square by 4.651 m high), then receive only `PROP_SCALE` in Godot to land on the existing 5.33 m pitch and 5.81 m peak. The old generated counter, legs, and roof remain as hidden gameplay volumes, so cover, sauce collision/replication, and refill reach do not change with the art swap.

One to three of the two-bay pitches are deterministically replaced by the authored food-truck model. Restricting the 6.4 m truck to an existing double pitch keeps it inside already reserved frontage instead of letting it overlap its neighbours. It retains that pitch's hidden gameplay volumes and refill station, so it serves sauce exactly like the booth it replaced.

Those are real metres and this world is not built in them, so they go through two conversions, and it is worth keeping them apart. The first is arithmetic: the player capsule is 2.56 m and is taken to be a **1.80 m** person, so a real metre is 2.56/1.80 of a metre here. The second is not. Game architecture is deliberately built larger than its real counterpart — a fixed field of view makes a space read tighter than it measures, and a player who cannot judge depth needs room the real user of the space does not — and the published guidance on how much larger is uniformly "build it, stand in it, and trust what it looks like". So `PROP_SCALE` is a knob rather than a derivation, at 1.25.

There is a concrete reason for it beyond taste. At 1.0 the canopy eaves sit 3.13 m up and the player is 2.56 m: 57 cm of headroom, which the over-the-shoulder camera cannot fit through. At 1.25 it is 1.35 m. What to watch when tuning it is the counter, which the same multiplier lifts from 53% of the player's height to 66% — waist-high to chest-high — and that changes what the counter is as cover. Together they put the pitch at 5.33 m square and the peak at 5.81 m.

The **counter** takes sauce and is registered as a wall: it is at the height things get sprayed at and the part you duck behind. The legs get collision but no grid — four more masks a few cells across, for a stain nobody can see.

**The roof gameplay volume is pointed, and it is that shape that stops the sauce.** It was a flat slab at eaves height with a decorative pyramid sitting on top, which made a shot arcing over a stall stop dead on a lid. The hidden collision/contamination shell is still built from one `CylinderMesh`, and `probe_map` drops rays onto it at three distances from the middle and fails unless they land progressively lower, which a lid would not do.

Being a cone rather than a box is also why the roof carries its own `RoofContamination`. `ContaminableObject` unwraps a box — six flat faces with a grid each. `BodyContamination` wraps about an axis, which is right for a capsule and **wrong for a cone**: every angle meets at the apex, so a splat came out as a wedge that was the right width at the base and tapered to nothing at the point. Measured, a 0.40 m brush landed 0.45 m wide at the base and 0.15 m a third of the way up; a roof with a few shots on it rendered as a sunburst of spokes.

A cone is *developable* — it lays out flat with no distortion at all, unlike a sphere or a capsule's caps — so there is an exact answer and no reason to settle for less. `RoofContamination` uses the classic net: cut the cone up one side and flatten it into a sector, where a point at slant distance `s` from the apex and angle `t` lands at polar `(s, t·R/L)`. Distances survive that exactly. Measured again, the same brush now lands 0.40–0.50 m across at every height from the base to a tenth off the apex, and `probe_map` fails if any of them falls below 0.8× or above 1.6× the brush. The cost is one seam at the back where a splat straddling the cut is seen off, against a distortion that covered the whole roof.

It also cut the world's contaminable bodies from 151 to 89, because a roof is one grid where a slab was six.

**And the roof is four faces with nothing underneath them.** `CylinderMesh` caps both ends by default, so the first version of it had a flat square sealing the base: stand under a stall, look up, and there is a ceiling where the four sloping faces should be. That cap was not only an eyesore — every point of it sits at the same height, so the unwrap sends the whole of it to a single circle at the rim of the net, a second smear on top of the one it was drawn into. With the caps off the mesh is four faces (eight triangles, four of them with no area, because `CylinderMesh` builds each side as a quad even when it has collapsed to a triangle — `probe_map` counts distinct planes rather than triangles for exactly that reason). **The collider is those four faces and nothing else — a shell, not a solid.** A convex hull of the same points closes the base, and that flat underside is what a player standing under a stall shoots at: every point of it sits at one height, so the unwrap sent all of it to the rim of the net and a shot aimed anywhere under the canopy came out as a stain along the eaves. As a shell the shot carries on through where the base would be and lands on the inside of a sloping face, which is a point the net has a place for, so the canopy is marked where it was aimed — measured, 1.79 m from the apex against a 4.29 m rim. `backface_collision` is what lets it be hit from the inside at all, and `probe_map` fires a ray up from under the canopy and fails if the hit comes back at the rim distance. The shader turns culling off, because a canopy is a sheet and the side a player stands under is the side with no faces pointing at them.

One roof per bay rather than one long one, so a double reads as two tents pushed together, which is what it is; the legs run down each bay division, so a double gets six rather than four and the span between them stays one tent wide. The counter being waist-high is the point of the change: the solid block that stood here while the street was being laid out was cover you could hide behind completely, and a counter is cover you shoot *over*, which is the more interesting half of what a market stall is for.

**LAVA** is the festival stage in the square, a low contaminable platform you can walk onto and spray off. **Kodanike torn** — the Citizens' Tower — is the one landmark tall enough to steer by: the promenade is long and every junction looks like the last, so something has to be visible over the rooftops that says which way the square is. It is a landmark rather than cover, which is why it is round and thin. Two vending machines are kept off the promenade; they hand nothing out, but `MayoEnemy` is sized as a multiple of one, so `VENDING_SIZE` is load-bearing even where the props are not.

**One grid still covers the whole map, and it has to.** The slip test, the network snapshot and the determinism hash all read `_floor` and nothing else, so a map stitched out of per-street floors would be a rewrite of the sync rather than a level. ### Thickness, and only deep mayo trips you

**A mask cell holds how thick the mayo is, 0 to 255, not whether there is any.** A splat *adds* to every cell it covers rather than flagging it, which matters because the stream lands every frame: counting splats would put a single sweep over any threshold worth having. Running trips you only where the thickness has passed `slip_thickness`; below it, mayo is a stain you can sprint across.

**A cell takes one layer per `coat_seconds` the stream is on it, not one per splat.** That one rule is what makes the threshold a plain number of passes rather than a measured compromise.

The stream does not spread its sauce evenly. Measured on a standing burst: of 111 splats, the cell the stream sat over took **100** while the far end of the same trail took **one to three**, and during the burst the landing point marches back toward the player (3.2 m to 2.4 m) as the bottle's pressure drops — so it lingers where it started and skims everything after. Counting splats made the head of a trail slippery inside a second and the tail of the same trail never, and left a threshold trying to straddle a hundredfold spread:

| passes | median | p90 | peak |
|---|---|---|---|
| 1 | 9 | 18 | 49 |
| 2 | 17 | 36 | 97 |
| 3 | 25 | 54 | 145 |

One pass's peak was twice three passes' median, so "one pass is slippery nowhere" and "three passes are slippery mostly" wanted numbers a hundred apart. 50 left three passes 16% slippery; 22 was the least bad point between the two.

Putting both ends on the same clock removes the spread instead of splitting it. A coat opens per trigger pull and reopens every `coat_seconds` (0.35 s) it stays open, so a cell brushed in passing takes one layer and a cell the stream sits on takes one per interval:

| | thickest cell | slippery |
|---|---|---|
| 1 pass, walking | 2 | 0% |
| 4 passes, walking | 8 | 99% of the stain |
| stream parked ~1 s | 4 | yes |

`slip_thickness` is 3, and both halves hold at once. A single pass is slippery nowhere on its length, three overlapping passes are slippery along all of it, and holding the stream on a chokepoint still puddles it — about a second, deliberately, at a rate you can watch arrive through the stain's steps. What a parked stream no longer does is get there a hundred times faster than the same stream sweeping, which is what made the head of a trail slippery while its own tail stayed clean.

The coat is numbered by the server and rides along in the field a floor splat was not using, so the wire is the same size and every peer groups the same splats into the same layer. A coat's cells are a set, not a byte per cell — a byte per cell is 13.9 MB on this floor, and a coat only ever touches a few thousand.

### Two branches, two answers

The stream does not spread its sauce evenly — measured on a standing burst, of 111 splats the cell it sat over took **100** while the far end of the same trail took **one to three**. That is a real property of the weapon, and there are two honest things to do about it. Both are kept, so they can be played against each other:

| | `mayo-trail1` | `mayo-trail2` (this one) |
|---|---|---|
| a cell counts | every splat | one layer per `coat_seconds` (0.35 s) |
| threshold | 150 | 3 |
| one walking pass | slippery nowhere | slippery nowhere |
| three overlapping passes | still almost nothing | slippery along all of it |
| stream held on a spot | puddle at 1.00 s, and only then | puddle at about 1 s |
| what it is about | aiming | covering ground |

### The stain is drawn in steps

A cell used to be drawn white on its first pass and yellow on the one that tripped, with nothing in between, so the mayo piling up was invisible until the frame it flipped. The stain has a band per pass instead, each a hard edge on a cell boundary:

| passes | drawn as |
|---|---|
| 1 | white — the stain |
| 2 | heavy cream — *one more pass and this is dangerous* |
| 3 | yellow and wet |

The boundaries are `stain_mid_thickness`, `stain_thick_thickness` and `slip_thickness`, and the floor orders them before pushing them at the shader: a step at or past the deep band would never be drawn at all. At three passes to slip there is only room for three bands; `mayo_color_mid` is the fourth and draws only if the deep band is moved out to four passes or more.

Not a gradient, for the same reason the deep band never was one: it has to be readable at a glance at a run, and a hard edge is what reads. `probe_thickness` checks each boundary from both sides and that a cell piling up passes through every band the configuration can reach.

**"Is this spot slippery" is asked of the floor**, not of the thing standing on it. `FloorContamination.is_slippery_at` has nothing player-shaped in it, so when the enemies are meant to slip they call the same function and get the same answer off the same data the shader draws.

**The deep band is drawn from the cell, unfiltered.** The outline is still a hard cut on a filtered sample — that is what makes it marching squares, and the outermost cells of a stain are the single-deposit case the property is claimed for, so the silhouette keeps it. The deep band instead uses `texelFetch`, which reads the cell's own value with no interpolation, so the cells drawn as slippery are exactly the cells the slip test calls slippery. Filtering it would put the drawn edge between two cells and let what you see disagree with what trips you. Blocky is also the right answer: it has to read at a glance while running, and deep mayo gets its own colour and a wet shine rather than a darker shade of the same cream — a gradient cannot be judged at a run.

Thickness never goes down. There is no drying.

### Uploading only what changed

The floor is uploaded **as tiles, and only the tiles that changed are sent**.

*Why tiles and not a dirty rectangle*, which is the obvious answer: Godot's public API has no partial update for a 2D texture. `ImageTexture.update` and `RenderingServer.texture_2d_update` both replace the whole thing, so knowing precisely which cells changed buys nothing on its own — the upload is all-or-nothing per texture. Making the textures smaller is the only lever there is, and that is what a tile is. The **data** does not tile: `cells` stays one array over the whole floor, because the slip test, the network snapshot and the determinism hash all read it and all want one.

Measured by `probe_upload`, which counts bytes because headless cannot time an upload (no GPU, so `texture.update` is a no-op):

| | before | now |
|---|---|---|
| a frame with sauce landing | 13.3 MB | **256 KB** |
| an idle frame | 0 | 0 |

**53× less**, and splats in opposite corners touch different tiles. Tile size is exported; larger tiles were tried and make almost no difference to the frame (19.5 / 19.3 / 18.8 ms at 512 / 1024 / 2048 cells) while sending 4× and 16× more, so 512 stands.

Two things fell out of this. The `cells` array now **is** the texture's bytes — a thickness is already exactly what an R8 texture wants, so the parallel 0/255 array kept beside it is gone, which is 13.9 MB on this floor and halved the script time per tick (4.17 → 2.00 ms). And the debug readout for "how much of this floor is dangerous" scanned all 13.9 M cells *twice*, twice a second; it cost 3 ms a tick on its own, more than everything else the floor does put together. The counts are kept as cells cross the threshold now, and `probe_thickness` checks the running numbers against the scan they replaced, because a running count that drifts is invisible — it just reports the wrong number forever.

The cost is that the floor mask is 3318 × 4193 cells — **13.9 M of them, about 27 MB resident** between the cell array and the image data — and `upload_if_dirty` rebuilds and re-uploads **the whole 13 MB image** on any frame where sauce lands, which at a sustained 60 Hz is around 0.8 GB/s of upload for a stripe of cells a few metres across. Doubling the map's width and length quadrupled all of that.

Script time per tick is 5.05 ms, up from 3.33. The upload itself is **not measurable here**: headless has no GPU, so `texture.update` is a no-op and `Image.create_from_data` does not copy, and the probe that tries to time it reports 0.01 ms — which is a measurement of nothing, not a clean bill of health. That was the number before tiling, and it is why tiling was done: a painting frame now sends 256 KB of it. See above.

**Moving the world off the origin broke the strand's culling, which is worth recording because nothing failed loudly.** The ribbons and the droplet pool are dynamic meshes written straight into their GPU buffers, which does not recalculate the resource AABB, so both set one by hand — and both had a fixed box centred on the world origin, 48 m for the strand and 24 m for the droplets. That was the entire world when the world was one 48 m floor. On a map this size the box sits nowhere near the player, so the renderer culls a stream that is directly in front of them: it blinks out as the view turns and the stale box leaves the frustum, while the stains keep landing, because painting is driven by the points and not by the mesh. Both now recompute their bounds each frame from the vertices and droplets actually written. `probe_visible.gd` checks the bounds against the very segments `_update_visuals` handed each ribbon, at both ends of the map, and also that the box stays strand-sized — a box big enough to cover the map would pass a containment test and defeat the purpose of having one.

`probe_map.gd` checks what a generated level does not get for free: that every street is at least the road width, that the festival square is reachable on foot from the start zone by flood fill, that no cell touching a street — diagonals included — is neither street nor wall, that the stage and the tower stand on open ground, that the square is wider than the stream reaches in both directions (the strand probes fire across it), that every prop faces a street with its back past the street's edge and leaves enough road to get past, that the round place is round and is a place rather than a wide spot in the road, that all 51 markers became stalls and none share ground, that the canopy clears a player's head and the counter does not, that the cooking vendors got their second gazebo, and that all four spawns stand on open ground.

### Getting there

`scripts/street_nav.gd` routes across the street. The enemies used to walk the straight line between themselves and the player, which works right up until a wall is on that line — and then they lean on it, which is most corners on a street map.

Feeler rays were the obvious reach, and they are the wrong tool for finding the way here: this map is full of concave corners — stalls backed against walls, L-shaped junctions — and a body steering off whiskers gets wedged in them. A navigation mesh is the other standard answer and is redundant, because the geometry it would be baked from was *generated from a lattice of walkable cells in the first place*. So `AStarGrid2D` runs on those cells directly and what comes back is a real route round the corner rather than a guess that gets stuck in one.

Rays still earn their keep, just not for finding the way: a route made of cells hugs the middle of them, which reads as a body pacing out every square it crosses, so a chaser that can **see** the player skips the route entirely and walks straight. **How close counts as reaching a waypoint is measured in cells, not metres**, and finding that out cost a debugging session. 1.6 m was about seven tenths of a cell when a cell was 2.30 m; the street was then doubled and a cell became 4.61 m, leaving the same 1.6 m at barely a third of one. A body could stand between two waypoints, be "not yet at" either, and be handed back one it had already walked past every time the route was redrawn — so it orbited, **at full walking speed**, never getting closer, which looks exactly like being stuck on a wall and is not. Routes are recomputed on `repath_interval` or the moment the player leaves the part of the street the current one was drawn to, and diagonals are off — a diagonal step between two cells that share only a corner cuts that corner, and a body as wide as a cell clips the wall going through.

**Two more things had to be true before any of that worked on the actual street.**

The first: an enemy is 4.10 m tall and the canopy eaves were at 3.91 m, so they could not walk under a stall at all. `PROP_SCALE` went to 1.45, which puts the eaves at 4.54 m. The counter did *not* come up with it — its height is a relationship to the player rather than a prop dimension, and scaling it took it to shoulder height and stopped it being cover you shoot over, so the real figure behind it was trimmed to hold it at about two thirds of a player. Now that enemies fit under a stall, only the **counter** blocks the ground: the canopy is overhead and the legs are a hand wide. Shutting the whole footprint had made every stall a pillar and a third of the street into wall.

The second was the actual bug, and it was invisible in most cases. The builder pushed the counter out by half the stall's **frontage** where it wanted half its **depth** — the same number on a single bay, and three metres out on a double. So a double-bay counter stood three metres from where the router believed it was, and enemies routed confidently into one and leaned on it. Both now read `StreetMap.counter_box`, and `probe_chase` compares every built counter against it and fails on a centimetre, because the version of this that could go wrong quietly already did.

**And the test for "can I walk straight there" was a chest-high raycast**, which is a different question from the one being asked: a ray at that height passes **under every canopy and over every counter**, so it reported a clear road through a stall, the route was thrown away, and the body walked into something it was never going to fit through. It asks the router now — the router already knows exactly which cells a body fits in, and walking the line through them is both exact and cheaper than a physics query.

**What the router has to know about is everything standing on the road, not just the walls.** The stalls back onto the walls but their footprints sit on the street: a third of the street's cells are under something. Leaving the stage and the tower out of that list — they are built separately from the marker list the stalls come from — is exactly how an enemy routed straight through the tower and then leaned on it, which is the bug this was supposed to fix, reappearing one prop later. `probe_chase` puts a corner between the two and fails unless the gap closes, checks the route is longer than the straight line (a route that is not cannot be one), that every waypoint is somewhere a body may stand, that a clear line is taken straight, and that an enemy handed no router at all still chases badly rather than stopping.

Doubling the map also broke three checks in `probe_enemy` and `probe_chase`, all the same way: they had fixed distances and fixed time windows baked in, so a chase that worked perfectly read as a stuck one the moment the walk got longer. They take their windows from the distance and the walking speed now. A fourth asserted the enemy *faces the player*, which was the same thing back when it walked straight at them — it routes now, so rounding a corner puts its front ninety degrees off the player quite correctly. What that check is really guarding is a yaw half a turn out, so it compares the body's front against the direction it is actually travelling, which the route supplies and which cannot be wrong in the same way the body's own axes can.

**Three probes had to be told to clear the enemies**, and `probe_whip` was the third: it stands the player in the festival square to whip the strand around, which is where one of them spawns, and a shove goes into `frame_movement` — which is the thing that bends the strand. That *is* the measurement. Anything measuring a body over several seconds wants an empty street; `debug_clear_enemies()` is one line.

### The enemy

The visible body is `assets/enemies/hamburger_monster/hamburger_monster.glb`, scaled and grounded against the 4.10 m gameplay height. Its `Idle`, `Walk`, biting `Attack`, and `Death` clips are selected by the existing chase, contact-hit, and death states. `BodyContamination` remains the deterministic record used by damage and network splat replay, its welded mesh hidden behind the authored visual, so replacing presentation did not change hit accounting, packet contents, or saved contamination state.

**Its shape is measured off the model, and for a while it was not.** The colliders were a humanoid stick figure left over from the mock enemy the burger replaced — head, torso, hips, two arms, two legs — so the monster was drawn 4.2 m across and solid over 1.9 m of it. Sauce aimed anywhere but straight down its middle went through it. Every number in `_bones()` is now the real extent of the part it stands for, read out of the GLB **in the body's own space**:

| part | y | radius |
|---|---|---|
| bottom bun | −0.82 … 0.63 | 1.49 |
| patty, cheese, salad | −0.18 … 0.86 | 1.71 |
| top bun and face | 0.42 … 2.04 | 1.56 |
| arms, shoulder to hand | −2.08 … 0.65 | 0.46, at x ±1.52 |

That last part is not a detail. Measured in **world** space an axis-aligned box grows with the body's yaw, so a collider that fits exactly reads half a metre too wide — which is how the first attempt at this fix was written, and it looked wrong when it was right.

Three discs, because that is what a burger is and because the tiers are what a player aims at: the sauce should land on the bun or on the patty and be seen to have. A tier needs a cylinder rather than a capsule — a capsule wide enough to be a bun is also that tall. The arms are capsules and are not decoration: the monster has no legs, it walks on its hands, so they carry every low shot. The burger also sits a third of a metre back of its own origin, which is why the discs are offset in z rather than centred.

The same measurements build the sauce mask, so a stain lands where the sauce hit rather than on a humanoid ghost, and `_body_radius()` — the patty, the widest it gets — is what the unwrap wraps around and what `contact_reach` is measured beyond. That makes the monster 3.42 m wide rather than the 2.30 m the old figure claimed, so it reaches you from further than it used to.

`probe_enemy` checks the shape three ways: that the solid envelope covers at least three quarters of the drawn one on every axis, that it is as deep as it is wide (a burger, not a body), and that a point on each bun, on the patty's rim and on an arm is actually solid — an envelope can be the right size and still be hollow where it counts. It also reads the facing off the face rather than off the silhouette, since a disc has no front: the mouth and eyes have to sit forward, on −Z, and square rather than over a shoulder.

`probe_enemy` continues to check that the same world-space brush is recorded at the same scale on an enemy and a player. `enemy_contamination_overlay.gdshader` projects that mask over every independently rigged hamburger mesh as a material overlay, preserving the imported food colours underneath while keeping the gameplay grid and network protocol unchanged.

Every part is a fraction of the one height, so the monster scales with whatever size it is told to be. Its height is still taken off the sauce refill station rather than written in metres — twice `StreetMap.VENDING_SIZE`'s — but its width now comes from the model, because the burger is very nearly as wide as it is tall and no station measurement was going to predict that.

It faces where it is going with `atan2(-x, -z)`, the same form `debug_aim_at` uses, because a body's front is its `-z`. Facing `atan2(x, z)` instead turns its *back* to the target: it walks at you backwards, and then topples onto that back, which looks for all the world like falling forwards. The figure was symmetric front to back at the time, so there was nothing on screen to say which way it was pointing, and every check in `probe_enemy` measured the fall against the body's own `-z` — wrong in exactly the same way as the bug, so it confirmed it. The checks now measure facing and fall direction **against the player it is chasing**, which its own axes cannot fake.

**Killed, it goes over backwards about its own feet.** The soles stay planted on the spot it died on and everything above them swings up and back over that line, so it lands on its back where it stood — rather than rotating about its middle, which drives the head through the floor and slides the feet out behind it. Measured: the soles move under a centimetre, the crown ends a full body-length behind them. The pose is kept as a yaw and a topple angle rather than read back off the node, because a body part way over is turned about two axes and the yaw is no longer recoverable from it; the topple travels over the wire as its angle rather than as a "it died" flag, so a peer that joins or drops a packet mid-fall picks it up where it is instead of snapping it upright or flat. The body stays on the street afterwards, and still takes sauce — `take_sauce_hit` is what refuses to hurt it twice. It moves at half the player's walking speed, taken from `MayoPlayer.walk_speed` when the world builds one so it stays half of whatever that becomes rather than half of what it was the day it was written. It turns toward you rather than snapping: running past one should leave it briefly pointed at where you were, and the stain on its back is worth seeing.

**Damage and stain come off the same hit.** The nozzle emits `extend_speed / point_spacing` points a second — about 187 — so `sauce_damage_per_hit` is 0.4 rather than a number that reads like damage: that is still about 75 a second of accurate fire and roughly three and a half seconds to put one down. Its own attack is deliberately weak and on a cooldown rather than per frame: 6 damage every 0.8 s, so standing inside one costs a full bar in about thirteen seconds.

There are three of them, spread up the route — on the run from Kalda, halfway along Karja, and waiting in the festival square — so the walk north meets them one at a time. They move at `enemy_speed_fraction` (0.7) of the player's walking speed, stored as the fraction rather than a speed because the interesting number is how it compares to the player. Under 1 means they can always be walked away from, which makes a chase a decision rather than a fight you cannot leave; running is twice their speed on top of that.

**Three of them broke four checks that are not about enemies** — how a body moves relative to its aim, whether two screens agree on a fall, a contact-damage cooldown — all by the same mechanism: those checks measure something over several seconds with the player standing still or walking a fixed line, and an enemy that walks up and shoves them mid-measurement produces a real failure about something the check was not asking after. It is intermittent, too, depending on how far away the nearest one happened to spawn. `debug_clear_enemies()` is the answer, one line in the checks that want an empty street.

An emptied player bar puts them back at the start zone, clean and whole. There is no death or respawn system to hook into and inventing one is a bigger decision than this is — but a player left alive at zero with nothing happening would make the bar a decoration, so they lose their ground instead.

Everything that decides anything runs on the authority. A client simulates no enemies at all, exactly as it simulates no bodies: it gets position, yaw and health in a packet alongside the player state, and the splat that marks an enemy travels as the same centre cell every other surface's does, addressed by the enemy's index in a list every peer builds in the same order. **Player health now travels in the state packet too** — a client that decided its own would disagree with the bar everyone else is watching — which took `STATE_STRIDE` from 12 to 13.

### The minimap

`scripts/minimap.gd` puts the street map in the top-right corner, scrolling under the player, who sits as a red dot dead centre. It shows about 41 m around them — far enough to see the next junction and the stalls on the way to it, close enough that a single stall is still a distinct mark.

The streets are baked into a texture once, **one pixel per lattice cell**, and each frame draws a window of it centred on where the player is standing. Drawing the cells themselves would be a couple of thousand `draw_rect` calls a frame for a picture that never changes; the only things that move are the handful of markers on top. The texture is padded by a full window on every side so the region drawn is always inside it — without that, walking into a corner of the map samples off the edge. Stall positions are worked out at bake time too, because rebuilding the stall list walks the whole map.

**North is up rather than the map turning with the player.** This is a street map of a real place with named streets running north–south and east–west, and a map that spins loses that: which way the promenade runs stops being a fact you can learn. The wedge on the player's dot carries which way they are facing instead.

Marks: the stalls in their own blue, because they are also where the sauce comes from and so the thing most worth finding; the stage and the tower in amber; living enemies in the colour of their bodies. A mark outside the window is not drawn rather than pinned to the rim, since a mark on the edge reads as a stall that is actually there.

`probe_minimap.gd` checks it by arithmetic rather than by looking at it — a HUD element that lands in the wrong place is invisible rather than visibly wrong, which is how the enemy health bars spent a while not appearing at all. It checks the box sits inside the view frame and in the right corner, that every street cell and only street cells are in the picture, that the padding covers the window, that the window stays inside the texture from three corners of the map, that the cell under the player is street and is drawn, and that half a cell of walking slides the map half a cell rather than stepping it a whole one.

The two health bars are drawn in `scripts/health_hud.gd`, the player's pinned to the bottom of the view and one floating over each living enemy. An enemy's bar is worked out by `enemy_bar_rect` rather than inside the drawing call, because a bar that ends up in the wrong place is invisible rather than wrong-looking and a draw call answers nothing about where it went — which is exactly how the bars spent a while not appearing at all. `unproject_position` gives window pixels and the view frame is in window pixels, but the projection was being scaled by `size / window` first: a `Control` under a `CanvasLayer` reports `size` as zero, so every enemy bar was multiplied to `(0, 0)` and drawn in the screen corner. The player's bar is laid out from the frame and never went through that, which is why it was the only one showing. They are Control drawing rather than 3D sprites over the enemies, because a sprite in the world takes sauce, gets occluded by a stall and turns edge-on with the body — all of which are right for a monster and wrong for its health bar. The enemies are asked of the world, not of the tree: groups are tree-wide, and the two-player harness runs four whole worlds side by side in one tree, so a group lookup hangs every world's enemies over every screen. The same trap caught the chase code — `get_nodes_in_group("mayo_players")` had this world's enemies walking at the other worlds' players and knocking them about, which the harness caught as peers disagreeing about who was in the session.

`probe_enemy` measures the figure off the built mesh rather than off the numbers it was given, checks the bar lands over the enemy and inside the view, and checks the fall keeps its feet and finishes on its back resting on its own torso.

The three sandbox slabs that used to stand in the start plaza are gone. `probe_wall`, `probe_geom` and `smoke_test` fired at one of them and now build their own where they want it, which also stops a level change from moving a test's target.

### The tank, and how long one press lasts

Holding the trigger no longer runs forever. A press gets an allowance in seconds, and when it is up the squirt runs itself out whether the button is still down or not — then `spent_burst_cooldown` (0.5 s) of nothing, and the trigger comes back **on its own**. Holding the button through the pause starts the next squirt without letting go, so leaning on it settles into a duty cycle: a second on, half a second off, with the on half shrinking as the tank drains. A squirt the player ends themselves costs the much shorter `fire_cooldown_time` (0.15 s) instead, which is what keeps hammering and holding different things.

The allowance comes off the tank, as a curve pinned at three points: `full_burst_seconds` (1.00 s) at the top, `half_burst_seconds` (0.45 s) at the half mark, and `empty_burst_seconds` (0.20 s) on the last of it, with straight lines between them. **It keeps falling the whole way down** — there is no level at which it settles, so every press is shorter than the one before it. Two segments rather than one because the curve bends at the middle: the drop from full to half is steeper than the drop from half to empty, which keeps the dregs usable while still making them worse. The last squirt is deliberately longer than `minimum_fire_time`, which every press is owed anyway, so it is still a squirt rather than a puff the minimum swallows. Measured end to end: 1.10 s of sauce on a full tank, 0.57 s on a half one, 0.33 s on a nearly dry one, the extra tenth being that minimum. There is only 0.1 s of daylight between `empty_burst_seconds` and the minimum now, so shortening the curve much further would hand the whole bottom of it to the minimum instead.

**The allowance is fixed when the press starts**, not re-derived each frame. The tank is draining *during* the press, so a live reading would shorten the allowance as the squirt spent it and a press promised three seconds would cut at about two and a half.

`sauce_capacity_seconds` (12) is the whole tank in seconds of fire, which at these lengths is about twenty-two squirts: 1.10 s, then 1.00, 0.91, 0.82, 0.75, 0.68 and down — and then a walk to a stall. Held down without pause that is roughly half a minute of wall time, the cooldowns included.

**Nothing goes over the wire for any of it.** The drain is driven by the firing flag every peer already has for every shooter, so it stays in step by exactly the argument the squirt's own `fire_hold` and `fire_cooldown` timers are already made on — these are the same class of per-peer float, and `STATE_STRIDE` is unchanged.

**A bottle that is nearly empty stops being dependable, and that is the only thing it stops being.** Damage is never reduced by a low bottle — `low_sauce_reduces_damage` exists as `false` to say so where anyone tuning the numbers will read it. What a low bottle costs is delivery:

* **Steady**, above `steady_level` (20%): the stream starts the instant the trigger does and does not break.
* **Spluttering**, down to `spluttering_level` (5%): the nozzle catches. It is put to the test every `catch_roll_interval` while the trigger is down, a failed roll holds the sauce back for `catch_delay_min`..`catch_delay_max`, and the first roll of a press happens immediately — which is what makes a press at a low bottle start late rather than straight away, and mid-press reads as the stream breaking up. No more than `max_consecutive_catches` rolls in a row may fail; the cap is checked *before* the die rather than after, so a run is broken by the rule and cannot come out longer than it says.
* **Bottom band**, at or below `spluttering_level`: air and nothing else. No sauce, no damage, and `air_shot_fired` for each puff — its own signal rather than a flag on the shot, because knockback is going to hang off it later and wants a single place to hang off. It carries where the shot came from and which way it went, for exactly that.

The drain is a flow: `sauce_flow_per_second` of a tank per second while sauce is leaving it, so what is left lasts `sauce_seconds_left()` = level ÷ flow. Air counts as spending, since the last of a bottle still coughs its way out.

**The nozzle is the host's, and it is the one part of firing that could not stay derived.** Everything else about a squirt follows from the trigger flag every peer already has — which is why none of it was ever sent. A catch is a coin toss, and a coin tossed separately on each machine gives every player a different fight: B's stream would break at moments A never saw, and the sauce that did or did not land would differ. So the authority decides and the answer travels: the state packet grew from 13 floats to 15, carrying the bottle level and what its nozzle is doing. Every peer, the authority included, then emits off that answer rather than off its own reading. `probe_network` parks a client's bottle in the spluttering band and fails unless both screens agree — measured, 150 of 150 frames including 31 caught ones, with the level identical to four decimal places.

The catch has **its own random source**, kept apart from the shooter's `rng`. That one is fixed-seeded, because the strand's jitter has to be reproducible for `probe_determinism`; drawing the catch rolls from it would have made the pattern of catches identical in every session, and coupled it to how many strand points happened to be emitted first, since emission draws from the same stream. Neither had to be true — only the host rolls and the answer is sent — so `catch_rng` is randomized.

**The level is the sauce in the bottle.** The body is translucent — genuinely, which took two goes: `StandardMaterial3D` ignores an alpha in the albedo colour until `transparency` is switched on, so the first version set the body see-through and drew it solid, with the gauge sealed inside it. Nothing failed; the bottle simply told you nothing, which is why `probe_reliability` now checks the transparency *mode* and not just the alpha. Back faces stay culled, since only the near wall belongs between the eye and the contents, and the wall does not write depth, so it cannot occlude the opaque sauce it is meant to be blending over. There is a column of sauce standing in it, shrinking from the nozzle end down toward the base as it empties — which is where sauce sits in a bottle held nozzle-forward — and changing colour at each band. It replaced a little gauge strip stuck on the outside, which read as an instrument bolted to a prop when the prop was already a see-through bottle with the answer in it. It is drawn on every player's bottle rather than only the viewmodel: the people who most need to know how you are doing are the other three, and they cannot see your HUD. Your own is still hidden in third person, because it is held at eye height and would sit inside your own capsule. The HUD keeps the bar as the secondary readout, with the two thresholds marked on it and the band and seconds-left written beside it.

**The viewmodel is placed at the rendered frame rate, not the physics rate.** It was written only in `_physics_process` while the camera was placed in `_process`, so on any machine drawing faster than 60 Hz the view turned smoothly with the mouse and the bottle hanging in it stepped along at 60 — which reads as the bottle juddering against a steady world. A viewmodel has to be exactly where the camera says on the same frame the camera says it. `_place_viewmodel` is visual only; `attack_direction` is still settled in the physics tick, so what the strand does and where the server thinks the body is are untouched.

**Crossing a threshold is silent, and the sputtering is the signal instead.** A tone at the boundary announced the band once and then left the player with nothing — and it announced it at the moment the bottle was still working fine, so it read as an alarm about something that had not happened yet. `air_shot_fired` now fires on a **catch** as well as on an empty bottle, so in the unreliable band the puff of air is heard *between* the squirts rather than instead of them. That is what a nearly empty squeeze bottle actually does, and unlike a beep it starts when the band does, keeps saying so, and gets worse in step with the thing it is reporting. `sauce_stage_changed` still exists, because the bottle's gauge and the HUD ride on it.

Sound hangs off `sauce_stage_changed` and `air_shot_fired` rather than off the state, so it lands on every peer at the moment the authority said it did. **The tones are placeholders** — generated, so the three bands can be told apart while tuning — and are marked as such in the code along with the bottle gauge's meshes and colours.

**The stalls fill it.** `E` at one of the blue stalls fills the bottle and clears the trigger lock, and `sauce_refill_per_second` is 0 — the tank does not quietly fill itself while you stand around, so it is a thing you walk back to. There are dozens of them and they line the whole route, which is what makes the map's shape mean something: how far you can push on is how far you are willing to be from the last counter. The knob stays exported because turning it up is the one-line way to play without the walk. The red vending machines hand nothing out; they are scenery until there is something else worth dispensing.

Reach is `refill_reach` (2.6 m), measured flat from the middle of the stall's **front face** rather than its centre — a stall is 2.56 m deep, so a reach taken from the centre would spend half of itself inside the stall and leave a standing band barely wider than the player. Plus a front test, or a stall could serve you through its own back wall. A prompt appears over the tank while one is in reach, which doubles as the feedback saying you are close enough; without it a stall is a blue box that silently does nothing until you happen to be in the right spot with the right key down.

The limit reaches further than the trigger. `profile_runtime.gd` used to hold fire for its whole run, because sustained fire was a thing; left alone it measured a mean of 6.8 live points against the 220 it used to, which is a profiler quietly reporting almost nothing — worse than no profiler, since a regression would read as an improvement. It now just holds the trigger down and keeps the tank full — a spent squirt comes back by itself, so that is the busiest the nozzle ever is, and the heaviest the strand can legitimately get (205 peak points, 3.13 ms a tick). `smoke_test` went the other way: its strand checks need one unbroken two-second press to show the trail retracting on release, which the bottle no longer permits, so it opens the allowance up for its own run — the limit is `probe_sauce`'s subject, the strand pipeline is that file's. `probe_network` lays a stripe of mayo down for a player to slip on, and used to do it by holding fire for two seconds — which paints the first stretch and then only what the cooldowns let through. It sprays in four deliberate presses instead, which is what a player does; that is the shape of every spraying task in the game now. And `probe_burst` asserted that holding the trigger gave exactly one burst, which was true while the stream ran for as long as the button was held: two seconds of holding is now a squirt, a pause, and the start of the next. What that check is really about survives the change — holding and hammering are different things, and the burst boundaries come from the nozzle rather than from the button — so it now bounds the count by what the allowance and cooldown allow instead of pinning it at one.

Over a session it goes the way the wipe does: a client asks, the host decides. **Where the player is standing is the host's own copy of them, never something the packet claims** — a client pressing `E` in the middle of the street gets nothing, which `probe_network` checks by asking from across the road before asking at the machine. The result is then broadcast as an event rather than added to the state packet, because unlike the drain — which every peer works out from the firing flag it already has — a refill is not something a peer can see coming. Rate-limited per peer like the wipe and the view report.

**An empty bottle puts out nothing at all.** `minimum_fire_time` is what every press is owed, not what it is owed out of an empty bottle — without a tank check where the press starts, a dry one coughed out a tenth of a second every time the trigger went down. The last of the tank still fires: at 2% left a press still puts out 0.35 s, so "empty" means empty rather than "nearly empty".

The tank is drawn under the health bar, with a notch at `burst_midpoint` where the curve bends. Without it the limit is invisible: a press cuts and there is nothing on screen saying why, or how much shorter the next one will be.

### Slipping

`MayoPlayer` walks at 5.2 m/s and runs at 10.4 while `Shift` is held; acceleration is scaled with them, so reaching the top speed still takes the time it did. Both speeds are exported, along with the four beats of going down: a stumble spent catching your balance, the fall, the pause spent flat on the floor, and pushing back up. Stepping on mayo starts the stumble, not the fall — controls are already locked there while the capsule sways side to side and the view shakes, and it is where an arm-flailing animation would go once there is a character model. There is no grace period afterwards. Slipping already requires the run key and a direction to be held, so a player who keeps sprinting across mayo goes straight back down on the frame they stand up — and with no run-up there is no speed left to skid with, so they are pinned in place until they let go of the key. Letting go makes the same patch harmless. Running onto a painted cell trips the player: the test is a plain cell lookup on the same grid the floor draws, with no probability in it. Walking never trips, and standing still with `Shift` held is not running, so it cannot trip you either. The player keeps the speed they slipped at and skids forward while going over backwards, landing on their back looking up; `Slip Slide Friction` sets how far that skid runs, about 0.5 m at run speed. Going down again inside `Recovery Window` (0.7 s from standing up) is a different fall: sprinting the instant you are upright means your feet never take the weight, so there is no balance to catch and the player pitches straight forward with no stumble, landing face down. `Forward Slip Slide Friction` scrubs that one harder, since a forward skid runs under the body rather than out from under it and a long one reads as a slide tackle. Standing up clears the direction, so the next fall is a backwards one again. While down, movement and firing are both locked out, and input cannot steer the skid. The shoulder camera stays upright through all of it, so the fall can be watched; only the first-person view goes over with the player.

### LAN multiplayer (2 players)

`F2` opens the connection panel: one player presses **호스트 시작**, the other types the host's IP and presses **접속**. Port 24565 by default. No lobby and no matchmaking — the first peer to connect is the second player, and the panel closes straight back into the game. Nothing about this changes the offline game: with no session, the world is its own authority and runs exactly the code it ran before.

The split is server-authoritative, with one deliberate exception:

* **Movement is the server's.** Clients send their keys and their aim and nothing else; the server runs both bodies and sends back where they ended up. There is no client-side prediction — on a LAN the round trip is a frame or two.
* **Aim is local.** The one exception. The mouse moves the view immediately and the packet follows, because a view that lags the hand by the round trip is unusable. The body's yaw still comes back from the server, which derives it from that same aim.
* **The strand is not synchronised.** Only the firing flag and the aim pitch travel; every peer emits and simulates every shooter's strand itself, from the aim it already has for them. Two machines' strands differ by centimetres, which is fine — the strand is decoration, and what it leaves behind is not.
* **The grid is the server's, exactly.** When a strand lands, only the server paints, and it broadcasts the splat's **centre cell** — two ints. Every peer replays that cell through the same `paint_cell`, which depends on nothing but the cell coordinates and the radius (`_cell_noise` is a pure function of the cell), so the grids come out byte-identical rather than approximately alike. Sending the cell *list* instead would be ~15,000 cells a second at the reference fire rate, for a worse guarantee. A peer that joins mid-game is handed the whole mask first.
* **Client input is validated, always.** Nothing a client sends is trusted. The keyboard path bounds itself — `Input.get_vector` never returns more than a full stick, the aim clamps to the pitch limit as the mouse moves — but a packet carries no such guarantee, and its values go straight into a body the server simulates. Every client RPC runs its floats through `MayoNet.all_finite` and drops the whole packet if any is NaN or infinite, then clamps each one to what the keys could have produced: `clamp_direction` for the move vector, `clamp_angle` for the pitch, `wrap_angle` for the yaw. Unbounded, a move vector is a speed hack; a single NaN is worse, because the server writes it into the next state packet and both screens follow it. **Any client input added later goes through the same helpers** — those are the only doors into the simulation from outside.
* **Slipping is the server's.** It tests its own grid against its own bodies, and the fall state travels with its timer, so the stumble, the fall, the skid and standing up play out in the same order on both screens, the client trailing by the latency and nothing more. `probe_network` used to demand they read the same state on the *identical physics frame*, which is not a claim about correctness but about latency: state is sent once a physics frame and delivered once a *rendered* frame, so a level heavy enough to run several physics steps per rendered frame puts the client further behind and the check failed. It now allows the client to trail by up to three frames and fails if it ever shows a state the host has not just been in — lagging is the network, inventing or skipping one is a bug — and separately that the client went through every state the host did, so it cannot pass by sitting on a stale one.

The session is not otherwise hardened, and is not meant to be: ENet here is unencrypted and unauthenticated, so anyone on the same LAN can take the second slot. The validation above is about not letting a client corrupt the simulation, not about keeping strangers out.

`probe_determinism.gd` is what holds the grid claim up, and `probe_network.gd` runs an actual two-peer session in one process and checks the four things that matter: both screens' grids hash the same, A's mayo trips B, A sees B go down, and the fall states agree on every frame.

### Bodies

Players are contaminable too, and the grid on a body is the same `ContaminationGrid` the floor and the walls use. A body is a capsule, which is a cylinder with rounded ends, so unwrapping it about its own axis gives a rectangle — u is the angle about Y times the circumference, v is the height — and the grid, the deterministic paint and the two-int network splat all apply unchanged. That is the reason for doing it this way rather than per polygon: a stain on a player costs the same as a stain on the floor, and `probe_determinism` already covers the mechanism. Per polygon would mean a trimesh collider that does not follow a skinned mesh's animation, and a resolution set by the model rather than by the brush.

Every surface that can take sauce uses the world's brush, so a splat is the same size on all of them: `contamination_brush_radius` in metres for the floor, walls, bodies and lenses. They differ enormously in what that amounts to — a patch on a wall, a large mark on a player, and much of a pair of glasses. A hit in the face can seriously obscure your view, and `R` is what you do about it.

The splat's edge wanders in metres rather than by a fixed number of cells, so every surface's stains keep the same physical edge scale. The body and lenses now use the same 0.1 m cells as each other, while every surface shares the same metre-sized brush.

Two things differ from a flat face. The u axis is a loop, so the body's grid sets `wrap_x` and a splat near the seam carries on round the far side instead of being clipped. And the shader (`body_contamination.gdshader`) derives its texture coordinate from the surface position rather than from the mesh's own UVs, using the same maths the CPU paints with — a capsule's UVs distribute v across the caps, which would slide every splat toward the middle.

One impact marks two surfaces on purpose: the lenses have no collider, so the ray hits the capsule and the hit is then projected onto the lenses in front of it. Giving them a collider would be truer and would also shield the body and the floor behind the head, which costs more than the doubling does. Hits that are level with the lenses or behind them, and hits that project outside the physical lens, mark nothing — measured, a hit on the back, the back of the head, a shoulder, the chest or the belly all reach the glasses not at all; the forehead, the eyes and the chin do, and the neck clips the bottom edge.

Bodies carry their own cell size (`Body Cell Size`, 0.1 m), independently of the floor and walls, but not their own brush. A splat is the same size in metres on a person as on a wall. The stain is stored in the body's own space, so it travels with the player as they walk and turn.

### Glasses

Players wear lenses, and sauce landing in front of their eyes goes on them. `VisorContamination` is another metre-based `ContaminationGrid`, configured with the body's cell size and the world's brush radius. The physical lens and the screen are both 16:9, so the screen is a straight 1:1 sample of the same mask. There is no blob cap or separate screen effect that could drift from what everyone else sees: the mask that blinds you *is* the mask on your face.

The lenses everyone else sees are as wide as the head is at eye height and shaped 16:9, the same shape as the mask, so what shows on the face is the wearer's view rather than a squashed copy of it. Being a flat pane on a round head, its corners stand proud of the capsule.

It hangs off the `AimPivot`, which already carries the aim pitch, so it moves exactly with the camera — sauce stays where it landed on screen as you look around, the way sauce on glasses does. In first person your own lenses are hidden and reach you as the overlay instead; everyone else's are visible on their faces in both camera modes. A hit that is level with the lenses or behind them paints nothing: it is not in front of your eyes, so it does not blind you.

Your own sauce counts. A point cannot hit the player who fired it until it has travelled `Self Hit Distance` (0.6 m) — the muzzle sits inside its owner's own capsule, so without that every point would hit them as it left — and past that it is fair game. Fired straight up it drifts about a metre before it lands, so what actually happens is walking into your own falling stream, and then it marks you and blinds you exactly as an opponent's would.

**`R` wipes them**, and it is a shared action rather than a private one. A client asks and the server decides — whether the lenses are dirty enough to be worth it, and whether the player is in a state to do it (going over backwards is not the moment). The wipe takes `Wipe Duration` (0.7 s), its timer travels in the state packet the way the fall timer does, and **firing is locked while it runs** — movement and aim are not, so being blinded costs you the shot rather than the fight. Everyone watches the lenses tip up and the mask disappear at the end of it, so an opponent can see the opening and take it. Wiping the glasses does not wash the body.

**The stain is cosmetic and nothing reads it back.** Slipping is decided by the floor grid and the floor grid alone. Over the network a body is painted exactly like a wall — only the server marks it, and it broadcasts the centre cell — and a peer joining a session that is already messy is handed each body's mask along with the floor's.

### The unwrap turns about the burger, not about its node

The stain is placed by the angle a hit makes about the body's axis. The burger sits a third of a metre back of its own node, so measuring that angle about the node skewed a stain by up to **ten degrees** around the flanks — which is exactly where anyone aims. `BodyContamination.axis_offset` is that offset, shared by the painter and by both overlay shaders so all three agree; a player is centred on their own node and leaves it at zero. `probe_enemy` fires at four azimuths through the real paint path and compares the stain's angle with the hit's: worst case is now 1.5°, against 10° before.

**What the unwrap still cannot do is a top or a bottom.** Every point on the crown of the bun at the same angle shares one texel whatever its radius, so a stain up there draws as a radial streak rather than a blob. It does not show while the monster is upright and you are looking at its side. It shows when it topples and the crown turns to face you. Fixing it properly means a projection that is not cylindrical — triplanar, or a per-part atlas — and that is a bigger change than the mask it would replace.

### One splat has to be visible

The mask holds a **thickness**, 0 to 255, where it used to hold a painted flag that was either 0 or 255. Every shader that cut at `0.5` went on compiling the day that changed and quietly started needing about **128 hits on a cell** before it drew any of them. The floor was moved over; the body, the glasses, the stall roofs and the monster overlay were not, so sauce on a player or a monster looked like it was going straight through.

All five now cut at `paint_threshold`, half a deposit — 0.00196 — and `probe_body` reads the number out of each shader's source and fails if one deposit would not clear it. Off a material is no good (a material only reports parameters somebody explicitly set) and off the rendering server is no good either (a headless run has no compiled shader to ask), but the value written in the file is the thing that matters anyway.

### Contamination grid

`ContaminationGrid` is one rectangular mask — cells, texture and material. The floor owns one; each wall face owns one of its own, so walls and floor share the same grid code, shader and brush. Cells are 0.1 m and the brush radius is exported **in metres**, converted to cells internally, so changing the cell size does not change how big a splat is.

The mask stores one byte per cell and `contamination.gdshader` samples it with bilinear filtering, then cuts at exactly 0.5. That cut is the marching-squares contour: between a painted and an unpainted cell centre the value falls 1 to 0, so the 0.5 crossing lands on the cell boundary and corners come out diagonal. `step()` keeps it one pixel wide, so there is no blur or alpha ramp anywhere and the drawn edge cannot drift from the cell the slip test reads. The sampler is `filter_linear, repeat_disable` and the mask image carries no mipmaps — mipmaps would soften the boundary at distance and repeating would wrap the far edge.

Measured: the 0.5 crossing sits on the cell boundary to within 0.000000 m, and over 160,000 floor samples the drawn coverage and `is_mayo_at` disagree on 0.595% of them, all within 0.02 m of a cell edge — the corner bevels that marching squares exists to make.

Each trigger press starts a new **burst**. `_points` stays one array, but every point carries the index of the burst that emitted it, and array-adjacent points from different bursts are never treated as one strand. `Strand Break Spacing` catches ruptures *inside* a burst: adjacent points further apart than that many `point_spacing`s also break. This applies to the burst leaving the nozzle too, so whipping the aim tears the stream — a fast turn fans consecutive points sideways, and the spacing constraint only corrects the gap projected *along* the strand, so it cannot close a lateral fan. The tear is permanent, because the same check stops the constraint pulling that pair back together. This is intended: exempting the active burst keeps it in one piece and was tried and rejected. A released strand stretches on its own as its leading points fall faster — measured, the largest adjacent gap grows to about 5.7x spacing before it lands — so the default of 6.0 sits above normal stretch and only cuts genuinely torn sauce. The burst index is what separates two presses regardless of how short the pause was.

**Aim** holds `Mouse Sensitivity` (degrees per pixel) and `Pitch Limit Degrees` (85° up and down). **Camera** holds the eye height used by both modes plus the third-person shoulder offset — right, up, and distance behind. The strand always leaves along the camera forward axis, vertical aim included.

**Emission Shape** carries two independent jitters: `Yaw Angle Jitter` fans the strand across its axis, while `Speed Magnitude Jitter` (±10%) varies each point's launch speed so points run out of pressure at different distances and land along the axis instead of stacking on one spot.

**Release Pressure** governs what happens when the trigger is let go. `Release Pressure Loss` is the fraction of speed removed at the muzzle end; `Release Pressure Curve` shapes the falloff between the front tip (which keeps its speed) and the muzzle. Every airborne point also stops being powered at that instant, so the trail that lands afterwards begins at full range and is dragged back toward the player.

`Maximum Point Count` is the nozzle's limit rather than a reaper: at the cap the stream stops until some of what is already out lands. It used to keep emitting and throw away the oldest point to make room, which is the one furthest along the strand, so sauce fired upward lost its leading end in mid-air instead of coming down. Firing up is what reaches the cap — a level spray lands in about a second, an arc stays out for three — and holding off reads as running out of pressure. It is also cheaper than emitting a point and deleting one every frame: two players firing upward went from 28 ms a frame to 10.

Performance controls are under **Collision Budget**. `Raycast Frame Stride` defaults to 1: staggering casts across frames saved only ~0.27 ms per physics tick and let a point sit up to one frame (117 mm at the reference speed, wider than the strand) inside a wall before being snapped out, so it is not worth the artifact. Walls and players are landed on the way the floor is: the point settles against the surface and fades over `Landing Transition Time`, rather than hanging there in a phase of its own. The stain is written at collision time either way, so what changed is how many points a wall-facing strand keeps alive — measured, 239 down to 78 for one player, 463 down to 141 for two. Droplets are the one thing that does not follow: they are static beads with no fall, which reads as spatter on a floor and as beads hanging in mid-air on a wall or a player, so `Droplets On Floor` is on and `Droplets On Surfaces` is off.

## Testing a session on your own

A real session wants two machines, and the things that actually go wrong in one — a player's aim reading correctly on their own screen and wrongly on the other — are awkward to see when you can only look at one screen at a time. `dev_two_player.tscn` runs both ends in one process:

```sh
godot --path . res://dev_two_player.tscn
```

From the editor it is **not** `F5` — that always runs the project's main scene, which is the normal single-player game. Open `dev_two_player.tscn` in the editor first and press `F6`, which runs the scene you are looking at.

Host and client each get their own `SubViewport`, and so their own 3D world — sharing one would put both floors and all four capsules in the same physics space — and their own `MultiplayerAPI`, talking over the loopback exactly as two machines would. Both screens are shown side by side at the same brightness, which is the point: you are comparing what they draw. `Tab` moves the keyboard and mouse between them, or `1` and `2` pick a side outright, and the label says which one you are driving. The side you are not driving has its keys held at zero rather than reading the same keyboard, since `Input` is global and both worlds can see it.

It is a development harness, not a game mode. The shipped scene is untouched.

## Verification

Run the headless checks with a Godot 4 executable.

**On a fresh clone, import the assets once first.** `--script` does not run an import pass, so the stall meshes have no imported form yet and `mayo_prototype.gd` fails to parse on the `preload` of the first one — which does not read as a missing import, it reads as a probe hanging:

```sh
godot --headless --path . --import   # once per clone, and after deleting .godot/
```

Then:

```sh
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --script res://tests/profile_baseline.gd

# Measurement harness
godot --headless --path . --script res://tests/profile_runtime.gd -- full      # as shipped
godot --headless --path . --script res://tests/profile_runtime.gd -- noscript  # engine-only floor
godot --headless --path . --script res://tests/profile_runtime.gd -- stride1
godot --headless --path . --script res://tests/probe_aim.gd                    # aim, camera modes, jitter axes
godot --headless --path . --script res://tests/probe_whip.gd                   # fast turns must tear the strand
godot --headless --path . --script res://tests/probe_slip.gd                   # walk/run, fall timings, lockout, forward re-fall
godot --headless --path . --script res://tests/probe_grid.gd                   # shader cut, boundary vs slip test
godot --headless --path . --script res://tests/probe_burst.gd                  # burst separation, drag, per-burst bend
godot --headless --path . --script res://tests/probe_wall.gd                   # wall stain outlives its points
godot --headless --path . --script res://tests/probe_landing.gd -- full        # landing spread and release retract
godot --headless --path . --script res://tests/probe_landing.gd -- nojitter    # controls: jitter off
godot --headless --path . --script res://tests/probe_landing.gd -- noloss      #           pressure loss off
godot --headless --path . --script res://tests/probe_geom.gd                   # wall face/cell mapping
godot --headless --path . --script res://tests/probe_map.gd                    # street width, reachability, sealed walls, props
godot --headless --path . --script res://tests/probe_visible.gd                # strand/droplet mesh bounds follow the player
godot --headless --path . --script res://tests/probe_enemy.gd                  # enemy size, chase, sauce damage, contact damage, splat replay
godot --headless --path . --script res://tests/probe_sauce.gd                  # squirt length limit, the allowance curve, tank drain
godot --headless --path . --script res://tests/probe_reliability.gd            # the three bands, the catch cap, the air event
godot --headless --path . --script res://tests/probe_chase.gd                  # routing round corners, props on the road, straight-line shortcut
godot --headless --path . --script res://tests/probe_thickness.gd              # thickness piles up, thin is safe, deep trips, counts hold
godot --headless --path . --script res://tests/probe_upload.gd                 # bytes sent per painting frame
godot --headless --path . --script res://tests/probe_minimap.gd                # minimap placement, the baked street picture, centring
godot --headless --path . --script res://tests/probe_determinism.gd            # paint() depends on the centre cell alone
godot --headless --path . --script res://tests/probe_network.gd                # two peers: grids, slipping, fall states, hostile input
godot --headless --path . --script res://tests/probe_panel.gd                  # the F2 panel is on screen and centred
godot --headless --path . --script res://tests/probe_harness.gd                # the two-player harness swaps controls correctly
godot --headless --path . --script res://tests/probe_body.gd                   # body stains, glasses, and the wipe
```

`probe_determinism.gd` prints `MAYO_GRID_HASH`; run it twice and compare, since a difference between two processes is exactly what would break the grid sync.

The profile covers the whole physics tick, the frame's splat and state send included — that last stage (`net_send`) used to fall outside the total, which made a session's cost look like the offline one.

`profile_runtime.gd` reports the wall-clock tick interval, which is the tick period in every mode; read `script_ms` and the per-stage figures for actual cost, or wrap the run in `/usr/bin/time` and difference `full` against `noscript`.

The runtime profiler reports the per-stage CPU time, raycast count, grid paint/upload count, point high-water mark, and droplet-pool node count.

## Performance implementation

- Each of the four ribbon meshes owns one fixed-capacity dynamic `ArrayMesh`; only its dirty vertex prefix is uploaded each frame.
- Floor and wall cell edits are accumulated in an `Image` and uploaded to the texture at most once per rendered frame.
- Each wall face is its own quad with its own grid, rather than six faces packed into one atlas. The atlas kept a wall at one draw call, but bilinear sampling would have bled across the packed face boundaries; per-face quads remove that failure mode and let walls reuse the floor's grid code unchanged. Measured cost: 20 to 37 draw calls for the whole scene.
- Every cast covers the full path accumulated since that point's previous cast.
- The seven landing droplets use one fixed 512-instance `MultiMesh` pool instead of creating particle nodes and materials per landing.
- Strand continuity is decided per adjacent pair, by burst index and by gap. The spacing constraint, the ribbon builders, the inertial bend and the release pressure loss all honour it, so a burst still falling from an earlier press is never joined to, dragged by, or re-decayed alongside the one being fired.
- The inertial bend and the release pressure loss weight each point by its position *within its own burst*. Measured against the whole array instead, a new burst fired while an older one is still falling bows only 0.066 m instead of 0.266 m, because every new point lands at the high end of the weighting.
- Emission jitter is taken from the aim's own axes, not the world up axis, which collapses near vertical aim: at 85° of pitch the world-axis version shrinks the fan from 1.03° to 0.09°.
- Two guards keep the strand root from breaking up close to the camera in first person: points within `Strand Near Cull Distance` are dropped from the ribbon, and inside `min_view_distance` the billboard uses the fixed view axis instead of the point-to-camera vector, which swings violently there. With the current rig neither engages — the root stays 0.73 m from the eye — so they are insurance against a closer muzzle, not active work.

Measured headless on an M-series MacBook Air (`/usr/bin/time`, 618 physics ticks, Godot 4.7.1, interleaved runs per mode), the whole prototype costs roughly **3.6 ms of CPU per physics tick** against a 16.67 ms budget, of which about 0.6 ms is the empty-scene engine floor. Absolute numbers drift by 30% or more between sessions on this machine, so treat them as an order of magnitude and compare versions only by interleaving them in one run: on that basis the burst-boundary work cost a median +0.34 ms per tick, and the 0.1 m grid a further +0.42 ms — quartering the cell size while holding the splat radius at 0.4 m means each paint touches 81 cells instead of 25. Run-to-run spread is wider than most changes worth making here, so compare medians of interleaved runs, not single runs — neither the speed jitter nor the release pressure loss moved the number measurably. `ribbon_update` is ~50% of the script time and is the only real hot spot; the raycasts are not.

Note that the debugger's *Frame Time* reads ~16.6 ms even with the scene entirely disabled — that is the fixed 60 Hz tick period, not a cost.

## Scope

This step intentionally contains only WASD movement, FPS mouse-look aiming with a first/third-person camera toggle, one mayonnaise strand, static wall collision, flat-floor and wall contamination, ribbon shadow, and the seven-droplet landing accent. There is no UI, sound, inventory, recharge, extra sauce, enemy, or networking code.
