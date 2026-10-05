# Tripo burger crawler source

- `Stage1_TripoBurgerCrawler_Animated.blend`: editable rigged source.
- `Stage1_TripoBurgerCrawler_Animated_build.py`: deterministic Blender 5.2
  validation and GLB export script; it preserves the user-authored actions.
- `source/hamburger.blend`: archived original Tripo input retained for provenance.

The authored actions are `Crawl`, `Attack_GroundSlam`, and `Death`. `Crawl`
contains the revised high recovery, rearward/inward hand pull, and evaluated
palm-ground contact. `Attack_GroundSlam` uses the revised high held anticipation,
two-frame downstroke, frame-16 palm impact, and grounded terminal hold. Gameplay
uses the first two; death remains the network-safe procedural body fall.
