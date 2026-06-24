extends Control
## Main menu — now includes Host and Join buttons for multiplayer.
##
## Expected scene tree additions:
##   VBoxContainer
##   ├── ... (existing size buttons)
##   ├── HSeparator
##   ├── Label          "MultiplayerLabel"   "— Multiplayer —"
##   ├── Button         "HostButton"
##   ├── HBoxContainer  "JoinRow"
##   │   ├── LineEdit   "AddressEdit"        placeholder "Server IP"
##   │   └── Button     "JoinButton"
##   └── Label          "ErrorLabel"

const GAME_SCENE  := "res://scenes/core/main.tscn"
const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"

@onready var small_btn:   Button   = $VBoxContainer/SmallButton
@onready var medium_btn:  Button   = $VBoxContainer/MediumButton
@onready var large_btn:   Button   = $VBoxContainer/LargeButton
@onready var huge_btn:    Button   = $VBoxContainer/HugeButton
@onready var host_btn:    Button   = $VBoxContainer/HostButton
@onready var join_btn:    Button   = $VBoxContainer/JoinRow/JoinButton
@onready var address_edit: LineEdit = $VBoxContainer/JoinRow/AddressEdit
@onready var error_label: Label    = $VBoxContainer/ErrorLabel

@onready var name_edit: LineEdit   = $VBoxContainer/NameEdit


func _ready() -> void:
	# Single-player (direct launch)
	small_btn.pressed.connect(func():  _start_solo(Vector2( 1280,  720)))
	medium_btn.pressed.connect(func(): _start_solo(Vector2( 2560, 1440)))
	large_btn.pressed.connect(func():  _start_solo(Vector2( 4096, 2304)))
	huge_btn.pressed.connect(func():   _start_solo(Vector2( 6144, 3456)))

	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	error_label.visible = false


func _start_solo(size: Vector2) -> void:
	MapSettings.map_size = size
	MapSettings.rng_seed = randi()
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_host_pressed() -> void:
	NetworkManager.my_name = name_edit.text.strip_edges()
	if NetworkManager.my_name.is_empty():
		NetworkManager.my_name = "Host"
	var err := NetworkManager.host_game()
	if err != OK:
		_show_error("Failed to host: %s" % error_string(err))
		return
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_join_pressed() -> void:
	var address := address_edit.text.strip_edges()
	if address.is_empty(): address = "127.0.0.1"
	NetworkManager.my_name = name_edit.text.strip_edges()
	if NetworkManager.my_name.is_empty():
		NetworkManager.my_name = "Player"
	var err := NetworkManager.join_game(address)
	if err != OK:
		_show_error("Failed to connect: %s" % error_string(err))
		return
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _show_error(msg: String) -> void:
	error_label.text    = msg
	error_label.visible = true
