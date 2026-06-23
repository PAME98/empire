extends Control
## Main menu — lets the player pick a map size then launches the game.
## Attach this to a Control node that is your main_menu.tscn root.
##
## Expected scene tree:
##   Control  (this script)
##   └── VBoxContainer
##       ├── Label              "title_label"   — game title
##       ├── Label              "subtitle"      — "Select Map Size"
##       ├── Button             "small_btn"     — Small  (2560 × 1440)
##       ├── Button             "medium_btn"    — Medium (5120 × 2880)
##       ├── Button             "large_btn"     — Large  (8192 × 4608)
##       └── Button             "huge_btn"      — Huge   (12288 × 6912)
##
## NOTE: with the continent/ocean generator, roughly half of each map is open
## water, so the effective LAND area is about half these figures. Sizes were
## bumped accordingly so the playable landmass is still "vastly bigger" than
## the old solid-rectangle maps.

const GAME_SCENE := "res://scenes/core/main.tscn"

@onready var small_btn:  Button = $VBoxContainer/SmallButton
@onready var medium_btn: Button = $VBoxContainer/MediumButton
@onready var large_btn:  Button = $VBoxContainer/LargeButton
@onready var huge_btn:   Button = $VBoxContainer/HugeButton


func _ready() -> void:
	small_btn.pressed.connect(func():  _start(Vector2( 2560,  1440)))
	medium_btn.pressed.connect(func(): _start(Vector2( 5120,  2880)))
	large_btn.pressed.connect(func():  _start(Vector2( 8192,  4608)))
	huge_btn.pressed.connect(func():   _start(Vector2(12288,  6912)))


func _start(size: Vector2) -> void:
	MapSettings.map_size = size
	get_tree().change_scene_to_file(GAME_SCENE)
