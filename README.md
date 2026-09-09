# MAYO MAN — Step 1 prototype

Godot 4 3D prototype for validating one continuous viscous mayonnaise strand, per-point ballistic drop, wall attachment, and persistent grid contamination.

## Run

1. Open this directory in Godot 4.4 or newer.
2. Run the project (`F6`/`F5`). The main scene is already configured.
3. Move with `WASD`, hold `Shift` to run, aim with the mouse, and hold the left mouse button to fire. `F1` switches between first person and the over-the-shoulder third-person camera. `Esc` exits.
4. Spray the floor, then run across your own mayo. Running over a painted cell knocks you down; walking over it does not.

The mouse is captured and there is no on-screen cursor: aiming accumulates yaw and pitch from relative mouse motion, FPS-style, and a fixed crosshair marks the centre of the screen. `WASD` moves relative to where you are facing. Both camera modes run the same aim code and differ only in where the camera sits, so switching does not change how the weapon points.

## Tune

Select the root `MayoPrototype` node in `main.tscn`. Its Inspector groups expose the reference stream values, per-point time/distance lifetime switches, gravity, inertial bend, grid bridge settings, and third-person camera angle/distance.

All requested baseline values are under **Mayo Stream — Reference Values** and **Landing and Grid**.

`Stream Range` and `Point Time Lifetime` both cut the stream's powered phase, and whichever comes first wins, so they are kept matched at `extend_speed`: 2.94 m and 0.42 s at 7 m/s. Changing one alone does nothing — the other still cuts at the old distance. The generated `FloorContamination` node and each `ContaminableObject` wall expose the same cell/brush settings, and `MayoPrototype` pushes its `Landing and Grid` values into all of them on ready.

**Weapon Hold** places the sauce bottle: right, up and forward offsets from the eye, plus its radius and length. The bottle is a first-person viewmodel — in third person it would sit inside the capsule, so it is hidden. `Aim Convergence Distance` is the distance along the view axis where the strand crosses the crosshair; without it an off-centre nozzle fires parallel to the view and misses the reticle by the full hold offset (measured: 0.267 m).

### Slipping

`MayoPlayer` walks by default and runs while `Shift` is held. Both speeds are exported, along with the three beats of going down — the fall, the pause spent flat on the floor, and pushing back up — and the immunity granted after standing up. Running onto a painted cell trips the player: the test is a plain cell lookup on the same grid the floor draws, with no probability in it. Walking never trips, and standing still with `Shift` held is not running, so it cannot trip you either. The player keeps the speed they slipped at and skids forward while going over backwards, landing on their back looking up; `Slip Slide Friction` sets how far that skid runs, about 0.5 m at run speed. While down, movement and firing are both locked out, and input cannot steer the skid. The shoulder camera stays upright through all of it, so the fall can be watched; only the first-person view goes over with the player.

### Contamination grid

`ContaminationGrid` is one rectangular mask — cells, texture and material. The floor owns one; each wall face owns one of its own, so walls and floor share the same grid code, shader and brush. Cells are 0.1 m and the brush radius is exported **in metres**, converted to cells internally, so changing the cell size does not change how big a splat is.

The mask stores one byte per cell and `contamination.gdshader` samples it with bilinear filtering, then cuts at exactly 0.5. That cut is the marching-squares contour: between a painted and an unpainted cell centre the value falls 1 to 0, so the 0.5 crossing lands on the cell boundary and corners come out diagonal. `step()` keeps it one pixel wide, so there is no blur or alpha ramp anywhere and the drawn edge cannot drift from the cell the slip test reads. The sampler is `filter_linear, repeat_disable` and the mask image carries no mipmaps — mipmaps would soften the boundary at distance and repeating would wrap the far edge.

Measured: the 0.5 crossing sits on the cell boundary to within 0.000000 m, and over 160,000 floor samples the drawn coverage and `is_mayo_at` disagree on 0.595% of them, all within 0.02 m of a cell edge — the corner bevels that marching squares exists to make.

Each trigger press starts a new **burst**. `_points` stays one array, but every point carries the index of the burst that emitted it, and array-adjacent points from different bursts are never treated as one strand. `Strand Break Spacing` catches ruptures *inside* a burst: adjacent points further apart than that many `point_spacing`s also break. This applies to the burst leaving the nozzle too, so whipping the aim tears the stream — a fast turn fans consecutive points sideways, and the spacing constraint only corrects the gap projected *along* the strand, so it cannot close a lateral fan. The tear is permanent, because the same check stops the constraint pulling that pair back together. This is intended: exempting the active burst keeps it in one piece and was tried and rejected. A released strand stretches on its own as its leading points fall faster — measured, the largest adjacent gap grows to about 5.7x spacing before it lands — so the default of 6.0 sits above normal stretch and only cuts genuinely torn sauce. The burst index is what separates two presses regardless of how short the pause was.

**Aim** holds `Mouse Sensitivity` (degrees per pixel) and `Pitch Limit Degrees` (85° up and down). **Camera** holds the eye height used by both modes plus the third-person shoulder offset — right, up, and distance behind. The strand always leaves along the camera forward axis, vertical aim included.

**Emission Shape** carries two independent jitters: `Yaw Angle Jitter` fans the strand across its axis, while `Speed Magnitude Jitter` (±10%) varies each point's launch speed so points run out of pressure at different distances and land along the axis instead of stacking on one spot.

**Release Pressure** governs what happens when the trigger is let go. `Release Pressure Loss` is the fraction of speed removed at the muzzle end; `Release Pressure Curve` shapes the falloff between the front tip (which keeps its speed) and the muzzle. Every airborne point also stops being powered at that instant, so the trail that lands afterwards begins at full range and is dragged back toward the player.

Performance controls are under **Collision Budget**. `Raycast Frame Stride` defaults to 1: staggering casts across frames saved only ~0.27 ms per physics tick and let a point sit up to one frame (117 mm at the reference speed, wider than the strand) inside a wall before being snapped out, so it is not worth the artifact. `Wall Fixed Hold Time` bounds fixed-point buildup; the wall stain is written at collision time and is unaffected by it.

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
godot --headless --path . --script res://tests/probe_slip.gd                   # walk/run, fall timings, lockout, immunity
godot --headless --path . --script res://tests/probe_grid.gd                   # shader cut, boundary vs slip test
godot --headless --path . --script res://tests/probe_burst.gd                  # burst separation, drag, per-burst bend
godot --headless --path . --script res://tests/probe_wall.gd                   # wall stain outlives its points
godot --headless --path . --script res://tests/probe_landing.gd -- full        # landing spread and release retract
godot --headless --path . --script res://tests/probe_landing.gd -- nojitter    # controls: jitter off
godot --headless --path . --script res://tests/probe_landing.gd -- noloss      #           pressure loss off
godot --headless --path . --script res://tests/probe_geom.gd                   # wall face/cell mapping
```

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
