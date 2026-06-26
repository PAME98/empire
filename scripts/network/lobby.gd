extends Control
## Lobby — attach to a Control root node (lobby.tscn).
## FIXED: _set_self_ready RPC moved to NetworkManager (persistent autoload)
## so it never targets a freed node after scene change.
##
## LOBBY LOCKOUT: if the host has already started the match, a joining client is
## rejected by NetworkManager (_register_player -> _join_rejected) and this lobby
## bounces straight back to the menu with the reason shown. Pressing Start also
## disables the lobby controls so the host can't double-launch.

@onready var status_label:    Label        = $VBoxContainer/StatusLabel
@onready var player_list:     ItemList     = $VBoxContainer/PlayerList
@onready var map_size_option: OptionButton = $VBoxContainer/MapSizeRow/MapSizeOption
@onready var start_button:    Button       = $VBoxContainer/StartButton
@onready var ready_button:    Button       = $VBoxContainer/ReadyButton
@onready var leave_button:    Button       = $VBoxContainer/LeaveButton

const MAP_SIZES  := MapSettings.SIZE_PRESETS
const MAP_LABELS := MapSettings.SIZE_LABELS

const HOST_PEER_ID := 1

var _starting := false


func _ready() -> void:
	NetworkManager.lobby_updated.connect(_refresh_ui)
	NetworkManager.player_disconnected.connect(func(_id): _refresh_ui())
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.join_rejected.connect(_on_join_rejected)

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
		var p    : Variant = NetworkManager.players[pid]
		var text := "%s  (Team %d)" % [p["name"], p["team"]]
		if pid == HOST_PEER_ID:
			text += "  [host]"
		elif p.get("ready", false):
			text += "  ✓"
		player_list.add_item(text)

	status_label.text = "Players: %d / %d" % [NetworkManager.players.size(), NetworkManager.MAX_PEERS]

	# Once we're launching, freeze the controls and don't re-enable Start.
	if _starting or NetworkManager.game_started:
		start_button.disabled = true
		ready_button.disabled = true
		return

	if NetworkManager.is_hosting:
		var others_ready := true
		for pid in NetworkManager.players:
			if pid == HOST_PEER_ID:
				continue
			if not NetworkManager.players[pid].get("ready", false):
				others_ready = false
				break
		start_button.disabled = not others_ready


func _on_start_pressed() -> void:
	if _starting:
		return
	_starting = true
	start_button.disabled = true
	map_size_option.disabled = true
	status_label.text = "Starting…"
	var size: Variant = MAP_SIZES[map_size_option.selected]
	NetworkManager.server_start_game(size)


func _on_ready_pressed() -> void:
	# FIX: call NetworkManager's RPC instead of an RPC on this node.
	# NetworkManager is an autoload — it exists on both peers for the entire
	# session, so the RPC can never arrive at a freed node.
	NetworkManager.client_set_ready.rpc_id(1, true)
	ready_button.disabled = true


func _on_leave_pressed() -> void:
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/core/main_menu.tscn")


func _on_server_disconnected() -> void:
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/core/main_menu.tscn")


## Host refused our join (game already started / lobby full). The reason is
## already stored in NetworkManager.last_error for the menu to display.
func _on_join_rejected(_reason: String) -> void:
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/core/main_menu.tscn")
