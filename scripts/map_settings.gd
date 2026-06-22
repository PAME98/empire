extends Node
## Autoload singleton — carries the player's map-size choice from the
## main menu into the game scene.  Add this as an autoload in
## Project > Project Settings > Autoload  (name: MapSettings).

var map_size: Vector2 = Vector2(1280, 720)   # default / fallback
