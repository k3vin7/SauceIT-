# Production Sauce Tube S1

`Production_SauceTube_S1_empty.blend` is the supplied empty bottle. The build
script creates the game-ready `.blend` and `.glb`, adding `SauceFill` as a
separate, base-anchored mayonnaise mesh so Godot can show the live tank level.

Rebuild with Blender 5.2:

```text
blender --background --factory-startup --python assets/props/Production_SauceTube_S1/Production_SauceTube_S1_build.py
```

After rebuilding any playable character from its original character build
script, rerun the shared fitting pass for that character:

```text
blender --background --factory-startup --python assets/players/retarget_sauce_tube.py -- 1
```

Use `1`, `2`, `3`, or `4`. The fitting pass removes the former Character 1
canister, embeds exactly one production tube and one `SauceFill`, creates the
`SauceTubeSocket`/`SauceTubeMuzzle` bones, and rebakes the hands without changing
the gameplay capsule or movement scale.
