extends Control
## Main menu — lets the player pick a map size then launches the game.
## Attach this to a Control node that is your main_menu.tscn root.
##
## Expected scene tree:
##   Control  (this script)
##   └── VBoxContainer
##       ├── Label              "title_label"   — game title
##       ├── Label              "subtitle"      — "Select Map Size"
##       ├── Button             "small_btn"     — Small  (1280 × 720)
##       ├── Button             "medium_btn"    — Medium (2560 × 1440)
##       ├── Button             "large_btn"     — Large  (4096 × 2304)
##       └── Button             "huge_btn"      — Huge   (6144 × 3456)

const GAME_SCENE := "res://scenes/main.tscn"

@onready var small_btn:  Button = $VBoxContainer/SmallButton
@onready var medium_btn: Button = $VBoxContainer/MediumButton
@onready var large_btn:  Button = $VBoxContainer/LargeButton
@onready var huge_btn:   Button = $VBoxContainer/HugeButton


func _ready() -> void:
	small_btn.pressed.connect(func():  _start(Vector2(1280,  720)))
	medium_btn.pressed.connect(func(): _start(Vector2(2560, 1440)))
	large_btn.pressed.connect(func():  _start(Vector2(4096, 2304)))
	huge_btn.pressed.connect(func():   _start(Vector2(6144, 3456)))


func _start(size: Vector2) -> void:
	MapSettings.map_size = size
	get_tree().change_scene_to_file(GAME_SCENE)
