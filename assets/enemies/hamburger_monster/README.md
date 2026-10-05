# Hamburger monster asset

`hamburger_monster.glb` is exported from the user-supplied
`Stage1_TripoBurgerCrawler_Animated.blend` with Blender 5.2, Y-up conversion,
and all actions enabled. This revised source is authored at roughly 5 m wide
and receives a uniform 2× runtime presentation scale to preserve the existing
10 m gameplay size without distorting its proportions, then binds `Crawl` and
`Attack_GroundSlam`. The Crawl action uses enlarged reaches, pulls, lifted hand
arcs, wrist rotation, and body sway. The revised slam holds a high two-hand
anticipation through frame 14, snaps down over two frames, applies damage on its
frame 16 palm-contact pose, and finishes with both hands grounded.

Editable source and the deterministic validation/export script live in
`../Stage1_TripoBurgerCrawler_Animated/`.
