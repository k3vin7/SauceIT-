# MAYO MAN — Step 1 prototype

Godot 4 3D prototype for validating one continuous viscous mayonnaise strand, per-point ballistic drop, wall attachment, and persistent grid contamination.

## Run

1. Open this directory in Godot 4.4 or newer.
2. Run the project (`F6`/`F5`). The main scene is already configured.
3. Move with `WASD`, aim with the mouse, and hold the left mouse button to fire. `F1` switches between first person and the over-the-shoulder third-person camera. `Esc` exits.

The mouse is captured and there is no on-screen cursor: aiming accumulates yaw and pitch from relative mouse motion, FPS-style. Both camera modes run the same aim code and differ only in where the camera sits, so switching does not change how the weapon points.

## Tune

Select the root `MayoPrototype` node in `main.tscn`. Its Inspector groups expose the reference stream values, per-point time/distance lifetime switches, gravity, inertial bend, grid bridge settings, and third-person camera angle/distance.

All requested baseline values are under **Mayo Stream — Reference Values** and **Landing and Grid**. The generated `FloorContamination` node and each `ContaminableObject` wall expose the same cell/brush settings, and `MayoPrototype` pushes its `Landing and Grid` values into all of them on ready.

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
- Each wall packs its six face grids into one atlas image on a custom box `ArrayMesh`, so a wall still costs one draw call.
- Every cast covers the full path accumulated since that point's previous cast.
- The seven landing droplets use one fixed 512-instance `MultiMesh` pool instead of creating particle nodes and materials per landing.
- Emission jitter is taken from the aim's own axes, not the world up axis, which collapses near vertical aim: at 85° of pitch the world-axis version shrinks the fan from 1.03° to 0.09°.
- Two guards keep the strand root from breaking up close to the camera in first person: points within `Strand Near Cull Distance` are dropped from the ribbon, and inside `min_view_distance` the billboard uses the fixed view axis instead of the point-to-camera vector, which swings violently there. With the current rig neither engages — the root stays 0.73 m from the eye — so they are insurance against a closer muzzle, not active work.

Measured headless on an M-series MacBook Air (`/usr/bin/time`, 618 physics ticks, Godot 4.7.1, five interleaved runs per mode), the whole prototype costs a median **2.35 ms of CPU per physics tick** (range 2.14–2.91) against a 16.67 ms budget, of which 0.70 ms is the empty-scene engine floor. Run-to-run spread is wider than most changes worth making here, so compare medians of interleaved runs, not single runs — neither the speed jitter nor the release pressure loss moved the number measurably. `ribbon_update` is ~50% of the script time and is the only real hot spot; the raycasts are not.

Note that the debugger's *Frame Time* reads ~16.6 ms even with the scene entirely disabled — that is the fixed 60 Hz tick period, not a cost.

## Scope

This step intentionally contains only WASD movement, FPS mouse-look aiming with a first/third-person camera toggle, one mayonnaise strand, static wall collision, flat-floor and wall contamination, ribbon shadow, and the seven-droplet landing accent. There is no UI, sound, inventory, recharge, extra sauce, enemy, or networking code.
