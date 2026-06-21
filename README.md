# RTS Prototype - Empire Dawn Style

A Godot 4.x RTS prototype inspired by Empire Earth / Dawn of the Modern World.

## Setup Instructions

1. **Create a new Godot 4.x project**
2. **Copy the `scripts/` folder** into your project
3. **Set up Autoload:**
   - Go to Project → Project Settings → Autoload
   - Add `scripts/game_manager.gd` as "GameManager"
4. **Create scenes** (see Scene Setup below)
5. **Configure Input Map:**
   - Project → Project Settings → Input Map
   - `ui_left`, `ui_right`, `ui_up`, `ui_down` (or use WASD)

## Scene Setup

### Village Center (village_center.tscn)
```
StaticBody2D (script: village_center.gd)
├── Sprite2D (building texture)
├── CollisionShape2D (RectangleShape2D)
├── Area2D (for mouse input)
│   └── CollisionShape2D
├── SelectionRing (Sprite2D, circle outline, modulate green, visible=false)
└── HealthBar (ProgressBar)
```

### Worker (worker.tscn)
```
CharacterBody2D (script: worker.gd, add to group "units")
├── Sprite2D (worker texture)
├── CollisionShape2D (CircleShape2D)
├── SelectionRing (Sprite2D, visible=false)
├── HealthBar (ProgressBar)
└── InteractRange (Area2D)
    └── CollisionShape2D (larger circle for gathering)
```

### Soldier (soldier.tscn)
```
CharacterBody2D (script: soldier.gd, add to group "units")
├── Sprite2D (soldier texture)
├── CollisionShape2D (CircleShape2D)
├── SelectionRing (Sprite2D, visible=false)
└── HealthBar (ProgressBar)
```

### Tree (tree.tscn)
```
StaticBody2D (script: tree.gd, add to group "resources")
├── Sprite2D (tree texture, name: Sprite2D)
└── CollisionShape2D
```

### Farm (farm.tscn)
```
StaticBody2D (script: farm.gd)
├── ConstructionSprite (Sprite2D, semi-transparent)
├── FinishedSprite (Sprite2D, visible=false)
├── CollisionShape2D
├── SelectionRing (Sprite2D, visible=false)
└── HealthBar (ProgressBar)
```

### Main Scene (main.tscn)
```
Node2D (script: main.gd)
├── Camera2D (script: camera_controller.gd)
│   └── SelectionBox (ColorRect, color: semi-transparent blue, visible=false)
├── TileMap (ground tiles)
├── VillageCenter (instance)
├── Trees (multiple instances)
└── UI (CanvasLayer, script: ui_controller.gd)
    ├── Resources (VBoxContainer)
    │   ├── FoodLabel (Label)
    │   ├── WoodLabel (Label)
    │   └── PopLabel (Label)
    ├── UnitPanel (Panel, visible=false)
    └── BuildingPanel (Panel, visible=false)
        ├── SpawnWorkerButton (Button)
        └── SpawnSoldierButton (Button)
```

## Controls

| Action | Input |
|--------|-------|
| Select unit/building | Left Click |
| Box select | Left Click + Drag |
| Move/Gather/Attack | Right Click |
| Pan camera | WASD / Arrow Keys |
| Zoom | Mouse Wheel |

## Game Mechanics

- **Workers**: Gather wood from trees, food from farms. Auto-return resources to Village Center.
- **Soldiers**: Right-click enemies to attack.
- **Village Center**: Select it and click buttons to spawn workers/soldiers.
- **Resources**: Food and wood required for units. Population cap limits unit count.

## Costs

| Unit/Building | Food | Wood |
|--------------|------|------|
| Worker | 50 | 0 |
| Soldier | 75 | 25 |
| Farm | 0 | 75 |

## Extending the Game

- Add more building types (Barracks, House for pop cap)
- Add tech tree / research
- Add combat AI for enemies
- Add fog of war
- Add multiplayer with Godot's multiplayer API
