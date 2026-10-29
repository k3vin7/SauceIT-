# Hamburger monster asset

`hamburger_monster.glb` is exported from the user-supplied
`Stage1_TripoBurgerCrawler_Animated.blend` with Blender 5.2, Y-up conversion,
and all actions enabled. The source measures 5.0 x 1.35 x 2.27 m (wide, tall,
deep); at runtime it is scaled uniformly so that it stands `MayoEnemy.BURGER_WIDTH`
wide (4.1 m), and the gameplay body is derived from the same measurements so
the colliders are the mesh. It binds `Crawl` and `Attack_GroundSlam`. The Crawl action uses enlarged reaches, pulls, lifted hand
arcs, wrist rotation, and body sway. The revised slam holds a high two-hand
anticipation through frame 14, snaps down over two frames, applies damage on its
frame 16 palm-contact pose, and finishes with both hands grounded.

Editable source and the deterministic validation/export script live in
`../Stage1_TripoBurgerCrawler_Animated/`.
