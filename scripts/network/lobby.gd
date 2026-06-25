extends Control
## Lobby — attach to a Control root node (lobby.tscn).
## Shows connected players, lets host pick map size and start.
##
## Expected scene tree:
##   Control  (this script)
##   └── VBoxContainer
##       ├── Label          "StatusLabel"
##       ├── ItemList       "PlayerList"
##       ├── HBoxContainer  "MapSizeRow"
##       │   ├── Label      "Map Size:"
##       │   └── OptionButton "MapSizeOption"
##       ├── Button         "StartButton"    (host only)
##       ├── Button         "ReadyButton"    (clients)
##       └── Button         "LeaveButton"

@onready var status_label:    Label        = $VBoxContainer/StatusLabel
@onready var player_list:     ItemList     = $VBoxContainer/PlayerList
@onready var map_size_option: OptionButton = $VBoxContainer/MapSizeRow/MapSizeOption
@onready var start_button:    Button       = $VBoxContainer/StartButton
@onready var ready_button:    Button       = $VBoxContainer/ReadyButton
@onready var leave_button:    Button       = $VBoxContainer/LeaveButton

const MAP_SIZES := [
	Vector2(1280,  720),
	Vector2(2560, 1440),
	Vector2(4096, 2304),
	Vector2(6144, 3456),
]
const MAP_LABELS := ["Small", "Medium", "Large", "Huge"]

const HOST_PEER_ID := 1


func _ready() -> void:
	NetworkManager.lobby_updated.connect(_refresh_ui)
	NetworkManager.player_disconnected.connect(func(_id): _refresh_ui())
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	# Populate map size dropdown (host only)
	for label in MAP_LABELS:
		map_size_option.add_item(label)
	map_size_option.selected = 0

	start_button.visible    = NetworkManager.is_hosting
	ready_button.visible    = not NetworkManager.is_hosting
	map_size_option.visible = NetworkManager.is_hosting

	start_button.pressed.connect(_on_start_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	_refresh_ui()


func _refresh_ui() -> void:
	player_list.clear()
	for pid in NetworkManager.players:
		var p    :Variant = NetworkManager.players[pid]
		var text := "%s  (Team %d)" % [p["name"], p["team"]]
		if pid == HOST_PEER_ID:
			text += "  [host]"
		elif p.get("ready", false):
			text += "  ✓"
		player_list.add_item(text)

	status_label.text = "Players: %d / %d" % [NetworkManager.players.size(), 4]

	if NetworkManager.is_hosting:
		# The host decides when to start and never readies up, so gate Start on
		# every NON-host player being ready. With no other players yet (solo
		# testing) the loop finds none and Start is enabled immediately.
		var others_ready := true
		for pid in NetworkManager.players:
			if pid == HOST_PEER_ID:
				continue
			if not NetworkManager.players[pid].get("ready", false):
				others_ready = false
				break
		start_button.disabled = not others_ready


func _on_start_pressed() -> void:
	var size :Variant = MAP_SIZES[map_size_option.selected]
	NetworkManager.server_start_game(size)


func _on_ready_pressed() -> void:
	# Tell host we're ready
	_set_self_ready.rpc_id(1, true)
	ready_button.disabled = true


@rpc("any_peer", "reliable")
func _set_self_ready(value: bool) -> void:
	if not multiplayer.is_server(): return
	var pid := multiplayer.get_remote_sender_id()
	if NetworkManager.players.has(pid):
		NetworkManager.players[pid]["ready"] = value
		NetworkManager._sync_player_list.rpc(NetworkManager.players)


func _on_leave_pressed() -> void:
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/core/main_menu.tscn")


func _on_server_disconnected() -> void:
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/core/main_menu.tscn")
