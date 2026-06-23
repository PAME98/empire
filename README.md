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

The game is **3D** (an angled, Empire-Earth-style top-down camera over a flat
ground plane; units and buildings are primitive meshes for now).

| Action                          | Input                       |
|---------------------------------|-----------------------------|
| Select unit/building/resource   | Left click                  |
| Box select (multiple units)     | Left click + drag           |
| Move / gather / attack / build  | Right click                 |
| Pan camera                      | WASD / Arrows / screen edge |
| Rotate camera                   | Q / E                       |
| Zoom                            | Mouse wheel                 |
| Artillery area strike           | T, then left-click ground   |
| Cancel placement / targeting    | Right click / Esc           |
| Deselect                        | Esc                         |

Panning is **screen-relative** — it follows whichever way the camera is
rotated. Selection and orders use a ray from the cursor into the world (objects
are picked by their colliders; empty ground is the ray's hit on the y=0 plane).

Box-select grabs **any mix of citizens and soldiers** at once — right-click
afterward and every selected unit gets a context-appropriate order:

- right-click empty ground → everyone moves there
- right-click a tree → selected citizens go chop it; soldiers ignore it
- right-click a farm/lumber camp/quarry/mine → citizens join it as a worker
- right-click a construction site → citizens help build it
- right-click an enemy → soldiers attack it; citizens ignore it

## The economy loop (Kingdom Reborn side)

- **Citizens** are the only economic unit. They're born at houses (when
  there's free housing and a food surplus), grow from **Child → Adult →
  Elder**, and can die of **starvation** (not enough food at year-end) or
  **old age**.
- Adult citizens auto-assign themselves to open jobs at **Farms**, **Lumber
  Camps**, **Quarries**, and **Mines** if you haven't given them a direct
  order. Each building has a small number of worker slots and a stockpile that
  workers draw from and carry back to the **Village Center**.
- **Mountains** are solid terrain holding two independent mineral pools: every
  mountain has **stone**, and some also have **iron** (shown by a darker vein).
  You don't mine a mountain by hand — you build a **Quarry** on it for stone
  and/or a **Mine** on it for iron. Because the pools are separate, one mountain
  can host both at once, each building draining only its own pool.
- **Trees** and **water** are depletable resources citizens gather directly
  (no building): trees give **wood**, river tiles give **water**. Water is
  spent recruiting citizens; iron is spent training **artillery**.
- The six tracked resources are **food, wood, stone, iron, water, gold**.
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

Scripts and scenes are grouped by **domain**, and `scenes/` mirrors
`scripts/`. The folders also read as the game's layering, roughly in the order
a frame flows through them:

```
core/       Boot + shared state
  game_manager.gd   Autoload — the single source of truth: resources,
                    population, time/seasons, selection, placement. Everything
                    else talks to the game THROUGH this.
  map_settings.gd   Autoload — carries the chosen map size from menu to game.
  main.gd           Registers the hand-placed starting citizens on boot.
  main_menu.gd      Map-size picker (the project's main scene).

world/      The map and its raw resources
  map_generator.gd  Builds ground, rivers, mountain ranges and forests on load.
  mountain.gd       Solid terrain holding separate stone + iron pools; a
                    quarry and/or mine is built on it to extract them.
  resource_node.gd  Depletable, hand-gathered world resource (trees, water).

units/      Everything that moves
  unit.gd           Base class: movement, selection, health, combat.
  citizen.gd        Economy unit — aging, jobs, gather/build/move orders.
  soldier.gd        Melee RTS unit (auto-defends when idle).
  artillery.gd      Siege RTS unit (area strikes; fires only on command).

buildings/  Everything you construct
  building.gd            Base class: construction progress, health, selection.
  resource_building.gd   Worker slots + stockpile + mountain-deposit binding.
  farm/lumber_camp/quarry/mine.gd   Thin subclasses — just tuning numbers.
  house.gd               Adds housing capacity.
  village_center.gd      Recruits citizens; resource drop-off point.
  barracks.gd            Trains soldiers and artillery.

input/      Turning mouse/keys into orders
  camera_controller.gd   RTS input: pan/zoom/edge-pan, box-select, right-click
                         commands, building placement.

ui/         Reflecting state back to the player
  ui_controller.gd       Binds GameManager signals to the HUD.

effects/    Throwaway visuals
  explosion_effect.gd / attack_area_indicator.gd
```

`scenes/` uses the same folders (e.g. `scenes/units/citizen.tscn` pairs with
`scripts/units/citizen.gd`).

**To understand any feature, start at `GameManager` and follow the signal.**
Units and buildings never mutate each other's resources or population
directly — they call `GameManager`, which emits `resources_changed` /
`selection_changed` / `notification` / etc., and `ui_controller` turns those
into what you see on screen.

`Farm`, `LumberCamp`, `Quarry`, and `Mine` are thin subclasses of
`ResourceBuilding` that only set tuning numbers (worker cap, production rate,
group name, yielded resource) — the shared worker-slot/stockpile/deposit logic
lives in one place instead of being copied per building.

## Extending it

- Add a tech tree on top of `GameManager.COSTS` / `BUILD_TIMES`.
- Add enemy AI that spawns units into the `"enemies"` group — soldiers and
  citizens already react to that group correctly with zero extra wiring.
- Add a Market building for converting one resource into another (gold
  trading), following the same pattern as `ResourceBuilding`.
- Add fog of war or multiplayer — the selection/command system doesn't
  assume a single human player, so it should extend cleanly.
