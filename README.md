# MAYO MAN — Step 1 prototype

Godot 4 3D prototype for validating one continuous viscous mayonnaise strand, per-point ballistic drop, wall attachment, and persistent grid contamination.

## Run

1. Open this directory in Godot 4.4 or newer.
2. Run the project (`F6`/`F5`). The main scene is already configured.
3. Move with `WASD`, hold `Shift` to run, `Space` to jump, aim with the mouse, and hold the left mouse button to fire. `R` wipes sauce off your screen. `F1` switches between first person and the over-the-shoulder third-person camera. `Esc` exits.
4. Spray the floor, then run across your own mayo. Running over a painted cell knocks you down; walking over it does not.
5. `F2` opens the LAN panel; without it the game is the single-player one it has always been.

The mouse is captured and there is no on-screen cursor: aiming accumulates yaw and pitch from relative mouse motion, FPS-style, and a fixed crosshair marks the centre of the screen. `WASD` moves relative to where you are facing. Both camera modes run the same aim code and differ only in where the camera sits, so switching does not change how the weapon points.

## Tune

Select the root `MayoPrototype` node in `main.tscn`. Its Inspector groups expose the reference stream values, per-point time/distance lifetime switches, gravity, inertial bend, grid bridge settings, and third-person camera angle/distance.

All requested baseline values are under **Mayo Stream — Reference Values** and **Landing and Grid**.

`Stream Range` and `Point Time Lifetime` both cut the stream's powered phase, and whichever comes first wins, so they are kept matched at `extend_speed`: 2.94 m and 0.21 s at 14 m/s. Changing one alone does nothing — the other still cuts at the old distance. The generated `FloorContamination` node and each `ContaminableObject` wall expose the same cell/brush settings, and `MayoPrototype` pushes its `Landing and Grid` values into all of them on ready.

**Weapon Hold** places the sauce bottle: right, up and forward offsets from the eye, plus its radius and length. The bottle is a first-person viewmodel — in third person it would sit inside the capsule, so it is hidden. `Aim Convergence Distance` is the distance along the view axis where the strand crosses the crosshair; without it an off-centre nozzle fires parallel to the view and misses the reticle by the full hold offset (measured: 0.267 m).

### The tutorial street

`scripts/street_map.gd` builds the level off the hand sketch. It is generated rather than authored, and the whole thing is one lattice: a cell is one person wide (the capsule's 1.28 m diameter) times `SCALE`, and every corridor is declared as `ROAD_CELLS = 8` of them. That is why "the road is eight people wide" stays true — it is the literal statement in the code, not a metre figure copied into nine rectangles that drift apart when one is edited. `SCALE` is 1.5, so a cell is 1.92 m and the road is 15.36 m across; the street runs 86 × 186 m from the start zone to the arena's far wall.

The route is nine overlapping lattice rectangles, south to north: the start plaza, the long run north, east along the bottom, north again, east across the middle, the zigzag's two steps, the neck, and the arena. They **overlap rather than abut**, and the overlap is the corner — so no junction is a special case and the whole street falls out of their union.

The walls are not authored either. Any cell within two of the street that is not street becomes wall, the adjacency test is Chebyshev so a diagonal corner is sealed rather than left as a gap a strand could fly through, and the result is greedily merged into maximal rectangles: 616 wall cells come out as **23 boxes**, because a corridor wall is one long run. Without the merge this map would be several hundred separate bodies.

Stalls and vending machines are anchored by the **sketch pixel coordinates of the cyan and red marks**, which is what keeps them traceable to the drawing. Their size is in fixed metres and is deliberately *not* scaled with the map: they are furniture at a real size, and leaving them alone is what makes a bigger street read as bigger rather than as the same street seen closer. Each one is snapped to its wall by walking out from the anchor until the street runs out, so a traced pixel that is a cell off still lands the prop flat against the wall instead of floating in the road or buried behind it.

The stalls are solid boxes for now. A box is already a thing to stand behind and a thing to get mayo on, which is most of what a stall does. The vending machines are a contaminable chassis plus a lit display and a delivery slot, so which way one faces reads from across the street; they dispense nothing, because there is nothing yet to hand out. **The arena is walled and empty — the boss is deliberately not in it.**

The three slabs from the original sandbox (`ImpactWall`, `LeftGuide`, `RightBlock`) still stand in the start plaza, which is why the plaza is wider than the road it feeds: they are what several probes fire at, and they are also the first thing to spray in a tutorial. They are built *before* the street so their indices in `_walls` — which is what the splat protocol puts on the wire — stay 0, 1 and 2 whatever the map does.

**One grid still covers the whole street, and it has to.** The slip test, the network snapshot and the determinism hash all read `_floor` and nothing else, so a street stitched out of per-segment floors would be a rewrite of the sync rather than a map. The cost is that the floor mask is now 1018 × 2016 cells — about 2 MB, up from 230 KB — and `upload_if_dirty` rebuilds and re-uploads the whole image on any frame where sauce lands. Script time per tick is unchanged (measured: 3.84 ms against 4.03 ms on the old sandbox floor); the upload is GPU bandwidth, which the headless profiler cannot see. If it turns out to matter, the fix is a dirty-rectangle upload inside `ContaminationGrid`, not a second floor.

**Moving the world off the origin broke the strand's culling, which is worth recording because nothing failed loudly.** The ribbons and the droplet pool are dynamic meshes written straight into their GPU buffers, which does not recalculate the resource AABB, so both set one by hand — and both had a fixed box centred on the world origin, 48 m for the strand and 24 m for the droplets. That was the entire world when the world was one 48 m floor. On a street that runs 186 m the box sits nowhere near the player, so the renderer culls a stream that is directly in front of them: it blinks out as the view turns and the stale box leaves the frustum, while the stains keep landing, because painting is driven by the points and not by the mesh. Both now recompute their bounds each frame from the vertices and droplets actually written. `probe_visible.gd` checks the bounds against the very segments `_update_visuals` handed each ribbon, at both ends of the map, and also that the box stays strand-sized — a box big enough to cover the map would pass a containment test and defeat the purpose of having one.

`probe_map.gd` checks what a generated level does not get for free: that every segment is at least the road width, that the arena is reachable on foot from the start zone by flood fill, that no cell touching the street — diagonals included — is neither street nor wall, that every prop faces the street with its back past the street's edge and leaves enough road to get past, and that all four spawns stand on open ground.

### The enemy

`scripts/enemy.gd` builds a figure out of capsules — head, torso, hips, two arms, two legs — and **welds them into a single mesh**, which is the whole trick. `BodyContamination` unwraps a body about its own axis, and the shader derives the same coordinate from `VERTEX`, which is the mesh's own space; the two agree only while there is one mesh whose vertices are in the body's space. Six separate `MeshInstance3D`s would each unwrap about their own centre and slide every stain off where it landed. So each bone's capsule has its placement folded into its vertices and the lot is appended into one `ArrayMesh`, and the grid, the shader and the two-int network splat all carry on working exactly as they do on a player. Sauce sticking to it is not decoration: the stain is how you see what you have already hit.

Each bone gets its own collider too, rather than one capsule around the lot: a capsule wide enough to cover the outstretched arms is a fat pill nothing could walk past, and sauce aimed at a hand would land on thin air a metre outside it. Per bone, the silhouette you can see is the silhouette you can hit.

The skeleton is all fractions of the one height, so the figure scales with whatever size it is told to be, and the hands reach exactly to the half-width — the silhouette really is as wide as the size it claims rather than that wide plus whatever a cuff added. That size is taken off the sauce refill station rather than written in metres — twice `StreetMap.VENDING_SIZE`'s width and height, so the two cannot drift apart — which makes it 2.30 m across and 4.10 m tall, and 0.74 m deep: a person, not a pillar.

It faces where it is going with `atan2(-x, -z)`, the same form `debug_aim_at` uses, because a body's front is its `-z`. Facing `atan2(x, z)` instead turns its *back* to the target: it walks at you backwards, and then topples onto that back, which looks for all the world like falling forwards. The figure was symmetric front to back at the time, so there was nothing on screen to say which way it was pointing, and every check in `probe_enemy` measured the fall against the body's own `-z` — wrong in exactly the same way as the bug, so it confirmed it. The checks now measure facing and fall direction **against the player it is chasing**, which its own axes cannot fake, and the arms reach forward far enough to give the silhouette a front to read.

**Killed, it goes over backwards about its own feet.** The soles stay planted on the spot it died on and everything above them swings up and back over that line, so it lands on its back where it stood — rather than rotating about its middle, which drives the head through the floor and slides the feet out behind it. Measured: the soles move under a centimetre, the crown ends a full body-length behind them. The pose is kept as a yaw and a topple angle rather than read back off the node, because a body part way over is turned about two axes and the yaw is no longer recoverable from it; the topple travels over the wire as its angle rather than as a "it died" flag, so a peer that joins or drops a packet mid-fall picks it up where it is instead of snapping it upright or flat. The body stays on the street afterwards, and still takes sauce — `take_sauce_hit` is what refuses to hurt it twice. It moves at half the player's walking speed, taken from `MayoPlayer.walk_speed` when the world builds one so it stays half of whatever that becomes rather than half of what it was the day it was written. It turns toward you rather than snapping: running past one should leave it briefly pointed at where you were, and the stain on its back is worth seeing.

**Damage and stain come off the same hit.** The nozzle emits `extend_speed / point_spacing` points a second — about 187 — so `sauce_damage_per_hit` is 0.4 rather than a number that reads like damage: that is still about 75 a second of accurate fire and roughly three and a half seconds to put one down. Its own attack is deliberately weak and on a cooldown rather than per frame: 6 damage every 0.8 s, so standing inside one costs a full bar in about thirteen seconds.

An emptied player bar puts them back at the start zone, clean and whole. There is no death or respawn system to hook into and inventing one is a bigger decision than this is — but a player left alive at zero with nothing happening would make the bar a decoration, so they lose their ground instead.

Everything that decides anything runs on the authority. A client simulates no enemies at all, exactly as it simulates no bodies: it gets position, yaw and health in a packet alongside the player state, and the splat that marks an enemy travels as the same centre cell every other surface's does, addressed by the enemy's index in a list every peer builds in the same order. **Player health now travels in the state packet too** — a client that decided its own would disagree with the bar everyone else is watching — which took `STATE_STRIDE` from 12 to 13.

The two health bars are drawn in `scripts/health_hud.gd`, the player's pinned to the bottom of the view and one floating over each living enemy. An enemy's bar is worked out by `enemy_bar_rect` rather than inside the drawing call, because a bar that ends up in the wrong place is invisible rather than wrong-looking and a draw call answers nothing about where it went — which is exactly how the bars spent a while not appearing at all. `unproject_position` gives window pixels and the view frame is in window pixels, but the projection was being scaled by `size / window` first: a `Control` under a `CanvasLayer` reports `size` as zero, so every enemy bar was multiplied to `(0, 0)` and drawn in the screen corner. The player's bar is laid out from the frame and never went through that, which is why it was the only one showing. They are Control drawing rather than 3D sprites over the enemies, because a sprite in the world takes sauce, gets occluded by a stall and turns edge-on with the body — all of which are right for a monster and wrong for its health bar. The enemies are asked of the world, not of the tree: groups are tree-wide, and the two-player harness runs four whole worlds side by side in one tree, so a group lookup hangs every world's enemies over every screen. The same trap caught the chase code — `get_nodes_in_group("mayo_players")` had this world's enemies walking at the other worlds' players and knocking them about, which the harness caught as peers disagreeing about who was in the session.

`probe_enemy` measures the figure off the built mesh rather than off the numbers it was given, checks the bar lands over the enemy and inside the view, and checks the fall keeps its feet and finishes on its back resting on its own torso.

The three sandbox slabs that used to stand in the start plaza are gone. `probe_wall`, `probe_geom` and `smoke_test` fired at one of them and now build their own where they want it, which also stops a level change from moving a test's target.

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
* **Slipping is the server's.** It tests its own grid against its own bodies, and the fall state travels with its timer, so the stumble, the fall, the skid and standing up line up frame for frame on both screens.

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

Run the headless checks with a Godot 4 executable:

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
