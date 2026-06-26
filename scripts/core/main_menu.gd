extends Control
## Main menu — single-player launch buttons plus Host and Join for multiplayer.
##
## Expected scene tree:
##   VBoxContainer
##   ├── NameEdit       (LineEdit)
##   ├── SmallButton / MediumButton / LargeButton / HugeButton
##   ├── HSeparator
##   ├── Label          "MultiplayerLabel"   "— Multiplayer —"
##   ├── Button         "HostButton"
##   ├── HBoxContainer  "JoinRow"
##   │   ├── LineEdit   "AddressEdit"        placeholder "Server IP"
##   │   └── Button     "JoinButton"
##   └── Label          "ErrorLabel"

const GAME_SCENE  := "res://scenes/core/main.tscn"
const LOBBY_SCENE := "res://scenes/network/lobby.tscn"

@onready var small_btn:    Button   = $VBoxContainer/SmallButton
@onready var medium_btn:   Button   = $VBoxContainer/MediumButton
@onready var large_btn:    Button   = $VBoxContainer/LargeButton
@onready var huge_btn:     Button   = $VBoxContainer/HugeButton
@onready var host_btn:     Button   = $VBoxContainer/HostButton
@onready var join_btn:     Button   = $VBoxContainer/JoinRow/JoinButton
@onready var address_edit: LineEdit = $VBoxContainer/JoinRow/AddressEdit
@onready var error_label:  Label    = $VBoxContainer/ErrorLabel
@onready var name_edit:    LineEdit = $VBoxContainer/NameEdit


func _ready() -> void:
	# Single-player (direct launch) — each starts a local host session.
	small_btn.pressed.connect(func():  _start_solo(MapSettings.SIZE_SMALL))
	medium_btn.pressed.connect(func(): _start_solo(MapSettings.SIZE_MEDIUM))
	large_btn.pressed.connect(func():  _start_solo(MapSettings.SIZE_LARGE))
	huge_btn.pressed.connect(func():   _start_solo(MapSettings.SIZE_HUGE))

	if host_btn:
		host_btn.pressed.connect(_on_host_pressed)
	else:
		push_error("main_menu: HostButton not found at $VBoxContainer/HostButton")
	if join_btn:
		join_btn.pressed.connect(_on_join_pressed)
	else:
		push_error("main_menu: JoinButton not found at $VBoxContainer/JoinRow/JoinButton")

	if error_label:
		error_label.visible = false

	# Surface any error carried over from a rejected/failed connection or a host
	# disconnect, then clear it so it doesn't reappear on the next visit.
	if not NetworkManager.last_error.is_empty():
		_show_error(NetworkManager.last_error)
		NetworkManager.last_error = ""


func _resolved_name(fallback: String) -> String:
	var n := name_edit.text.strip_edges() if name_edit else ""
	return n if not n.is_empty() else fallback


func _start_solo(size: Vector2) -> void:
	NetworkManager.my_name = _resolved_name("Player")
	MapSettings.map_size = size
	MapSettings.rng_seed = randi()
	NetworkManager.start_solo()
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_host_pressed() -> void:
	NetworkManager.my_name = _resolved_name("Host")
	var err := NetworkManager.host_game()
	if err != OK:
		_show_error("Failed to host: %s" % error_string(err))
		return
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_join_pressed() -> void:
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	NetworkManager.my_name = _resolved_name("Player")
	var err := NetworkManager.join_game(address)
	if err != OK:
		_show_error("Failed to connect: %s" % error_string(err))
		return
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _show_error(msg: String) -> void:
	if error_label:
		error_label.text    = msg
		error_label.visible = true
