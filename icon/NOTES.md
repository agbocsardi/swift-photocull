# PhotoCull app icon — concepts

All three: 1024x1024, full-bleed squircle r=228, vertical ink gradient, soft top sheen.
Every concept was rendered at 256/64/32/16 with scripts/svgrender.swift and inspected.

## Recommended: icon-a.svg — "Pinwheel Harvest"
Six-blade camera iris. Each blade is one solid tonal step from teal to green, so the
blades separate cleanly with no hairline seams. Blade 4 escapes the wheel: an amber
scythe that lifts off the ring and overhangs it with a sharp hooked tip. Camera first,
scythe second. At 16px the dark hexagonal iris, the ring silhouette and the amber
spike all survive.

## icon-b.svg — "Culled Disc" (rejected)
Solid teal->green disc; three ink comma voids spin as shutter blades and a scythe-shaped
slash cuts through the rim, edged with an amber glint. Rejected after rendering:
reads as a citrus slice / leaf, not a camera, and the silhouette is a plain circle.

## icon-c.svg — "One-Line Harvest" (rejected)
Single 58px monoline: ring spiralling into the iris, sickle hook curling off the ring.
Rejected after rendering: reads as a swirl/hook with no camera cue. Kept as exploration.

## Palette
- Squircle ink gradient: #2B322E -> #191F1C; top sheen #FFFFFF 10% -> 0 by 30% height.
- Blades (tonal steps teal->green): #7FBBB3 #87BDA9 #8FBE9E #97BF94 #A7C080.
- Amber scythe gradient: #E8D19B -> #CFA85A (accent maps to crop=amber).
