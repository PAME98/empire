extends Node
## Autoload singleton — carries the player's map-size choice into the game scene.
## Add as an autoload in Project > Project Settings > Autoload (name: MapSettings).
##
## SINGLE SOURCE OF TRUTH for map sizes. The main menu and the multiplayer lobby
## now read these presets instead of hard-coding their own (they used to top out
## at 6144x3456 — which is why a huge world never appeared no matter what the
## generator did). Change a size here and both menus follow.
##
## The generator scales to any size (tiled/streamed navmesh, map-relative
## continents/islands, scaled ocean & land-mask resolution, capped feature
## counts), so these can be large. Reminder for the big ones: apply the camera
## scaling and consider unit-speed scaling (see scaling_up_remaining.md), or the
## world will be navigable by the engine but a slog for the player.

## World presets, in world units (square). These map 1:1 to the menu's four
## buttons (Small / Medium / Large / Huge).
const SIZE_SMALL  := Vector2(8000, 8000)
const SIZE_MEDIUM := Vector2(20000, 20000)
const SIZE_LARGE  := Vector2(40000, 40000)
const SIZE_HUGE   := Vector2(80000, 80000)

## Convenience list in menu order, so menus can index by button.
const SIZE_PRESETS := [SIZE_SMALL, SIZE_MEDIUM, SIZE_LARGE, SIZE_HUGE]
const SIZE_LABELS  := ["Small", "Medium", "Large", "Huge"]

## Default / fallback when no menu choice was made (e.g. launching main.tscn
## directly from the editor).
var map_size: Vector2 = SIZE_HUGE
var rng_seed: int     = 0                     # 0 = unseeded; main menu sets via randi()
