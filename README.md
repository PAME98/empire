# Empire: Settlers at War

A Godot 4.6 prototype that merges **solid RTS unit control** with a
**Kingdom-Reborn-style population economy**: citizens are born, grow up,
work jobs, and die of old age or starvation, while soldiers give you a real
RTS army layered on top of that economy.

## Fixes in this revision

I don't have a Godot binary in my own environment, so the first version of
this was reviewed by reading the code, not by playing it — and that wasn't
good enough. This pass fixes three concrete, confirmed bugs found by
tracing every state transition by hand, plus adds the two requested
feedback features:

1. **Gathering looked broken because delivery trips kept getting
   cancelled.** Once a citizen filled up and started walking back to the
   Village Center, the very next frame's gather-logic tick would see
   "I'm now far from my workplace" and call `move_to(workplace)` again —
   yanking the citizen back before it ever dropped resources off. Fixed by
   giving delivery its own explicit `is_delivering` state that gather logic
   can no longer interrupt.
2. **Citizens couldn't physically reach the Village Center or Barracks.**
   Every citizen movement target used one fixed 44px "close enough" radius,
   but the Village Center (84px wide) and Barracks (74px wide) are big
   enough that a citizen collides with their walls before getting that
   close — it would walk up, get stopped by the wall, and never register
   as "arrived". This is the actual reason wood/stone/food never got turned
   in, barracks construction never progressed, and right-click build
   assignment looked like it didn't do anything: the order was being issued
   correctly, the citizen just could never reach the site. Replaced the
   fixed number with `_interaction_range()`, which computes the real
   reachable distance from each target's actual collision shape (using the
   half-diagonal so it's correct from any approach angle).
3. **Click/right-click targeting relied on a 2D physics point query fired
   from `_input()`**, which has known edge cases in Godot 4 (see
   godotengine/godot#105068, #103712). Replaced it with direct,
   debuggable node-distance/rect checks in `camera_controller.gd`.

New this pass:

- **Construction progress feedback.** Every building under construction now
  shows a percentage label and progress bar floating above it, generated in
  code on the shared `Building` base so every building type gets it
  automatically (this also surfaced and fixed a real bug: `Barracks`,
  `ResourceBuilding`, and `VillageCenter` all overrode `_process()` without
  calling `super._process()`, which would have silently swallowed the new
  bar for every building type except plain `House`).
- **Resource tooltips.** Clicking a tree (or any world resource node) now
  shows its remaining amount (`42 / 120 wood remaining`) in the selection
  panel, with a green selection ring on the tree itself for visual
  confirmation of what you clicked. Resource *buildings* (Farm/Lumber
  Camp/Quarry) already showed their stockpile and worker count when
  selected — that didn't need a separate tooltip.

I still haven't been able to launch this in an actual Godot editor to
visually confirm it. If something is still off, telling me exactly what
you see (or don't see) on screen will make the next round of fixes a lot
more precise than guessing again.

This version replaces two earlier, incompatible prototypes:

- one had working box-select / right-click RTS controls, but no real economy
  loop;
- the other added aging citizens and jobs, but had duplicate/broken classes,
  worker/soldier scenes that were never wired into the actual level, and a
  selection system that only worked for one unit at a time.

Everything here has been rebuilt on a single, consistent unit/building model
so the two halves are actually one game instead of two prototypes glued
together.

## Setup

1. Open this folder as a Godot 4.6 project (`project.godot` is already
   configured — `GameManager` autoload and WASD/arrow input are wired up).
2. Press Play. `scenes/main.tscn` is the main scene.

## Controls

| Action                         | Input              |
|---------------------------------|--------------------|
| Select unit/building/resource    | Left click         |
| Box select (multiple units)     | Left click + drag  |
| Move / gather / attack / build  | Right click        |
| Pan camera                      | WASD / Arrow keys  |
| Zoom                            | Mouse wheel        |
| Cancel building placement       | Right click / Esc  |
| Deselect                        | Esc                |

Box-select grabs **any mix of citizens and soldiers** at once — right-click
afterward and every selected unit gets a context-appropriate order:

- right-click empty ground → everyone moves there
- right-click a tree → selected citizens go chop it; soldiers ignore it
- right-click a farm/lumber camp/quarry → citizens join it as a worker
- right-click a construction site → citizens help build it
- right-click an enemy → soldiers attack it; citizens ignore it

## The economy loop (Kingdom Reborn side)

- **Citizens** are the only economic unit. They're born at houses (when
  there's free housing and a food surplus), grow from **Child → Adult →
  Elder**, and can die of **starvation** (not enough food at year-end) or
  **old age**.
- Adult citizens auto-assign themselves to open jobs at **Farms**, **Lumber
  Camps**, and **Quarries** if you haven't given them a direct order. Each
  building has a small number of worker slots and a stockpile that workers
  draw from and carry back to the **Village Center**.
- **Trees** are a separate, depletable world resource — citizens chop them
  directly (no building required) and the tree shrinks and disappears as
  it's harvested.
- A direct player order (right-click) always overrides the autonomous job
  AI. Selecting a citizen and giving it an order is exactly as direct as
  commanding a soldier — that uniformity is the core fix from the old
  prototype, where "selecting" a citizen just flipped a flag instead of
  feeding into a real command system.
- Time passes in **seasons** (4 per year); at the turn of each year,
  citizens eat, age up, and new children may be born if there's housing and
  a food surplus.

## The RTS loop (military side)

- **Barracks** train **Soldiers** using food + gold the economy produced —
  the two halves of the game are economically linked, not just visually
  adjacent.
- Soldiers are pure RTS units: no auto-job AI, ever. Idle soldiers with no
  player order will engage nearby enemies on their own (so a garrison
  actually defends itself), but will never wander off to gather or build.
- All combat (citizens defending themselves, soldiers fighting) runs through
  the same `take_damage()` / `die()` path on the shared `Unit` base class.

## Project structure

```
scripts/
  game_manager.gd     Autoload: resources, population, time/seasons, selection state
  unit.gd              Base class: movement, selection, health, combat
  citizen.gd           extends Unit — the economy unit (aging, jobs, gather/build/move orders)
  soldier.gd           extends Unit — the military unit (attack/move orders, auto-aggro)
  building.gd          Base class: construction progress, health, selection
  resource_building.gd extends Building — shared worker-slot + stockpile logic
  farm.gd / lumber_camp.gd / quarry.gd   extend ResourceBuilding (one-liners now — see below)
  resource_node.gd     Depletable world resource (trees)
  house.gd             extends Building — adds housing capacity
  village_center.gd    extends Building — recruits citizens, resource drop-off
  barracks.gd          extends Building — trains soldiers
  camera_controller.gd RTS input layer: pan/zoom/box-select/right-click commands/placement
  ui_controller.gd     Wires GameManager signals to the HUD
  main.gd              Registers hand-placed starting citizens on boot
```

`Farm`, `LumberCamp`, and `Quarry` are now thin subclasses of
`ResourceBuilding` that just set tuning numbers (worker cap, production
rate, group name) — the worker-slot/stockpile logic that used to be copied
three times with slightly different bugs now lives in one place.

## Extending it

- Add a tech tree on top of `GameManager.COSTS` / `BUILD_TIMES`.
- Add enemy AI that spawns units into the `"enemies"` group — soldiers and
  citizens already react to that group correctly with zero extra wiring.
- Add a Market building for converting one resource into another (gold
  trading), following the same pattern as `ResourceBuilding`.
- Add fog of war or multiplayer — the selection/command system doesn't
  assume a single human player, so it should extend cleanly.
