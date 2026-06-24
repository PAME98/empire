extends Node3D

## 3D RTS camera rig + input layer (Empire-Earth-style angled top-down).
##
## This Node3D is the FOCUS POINT that slides across the ground (XZ). A child
## Camera3D sits up-and-back on a boom and looks down at the focus, so zooming
## just lengthens/shortens the boom and rotating spins the rig's yaw.
##
## Handles: WASD/arrow + edge pan (screen-relative), wheel zoom, Q/E rotate,
## left-click/drag box-select (projects unit positions to screen), right-click
## context commands (move/gather/attack/build via raycast), ghost-follow
## building placement, and artillery attack-position targeting.

@export var pan_speed: float = 600.0
@export var rotate_speed: float = 1.6
@export var zoom_step: float = 0.08
@export var boom_min: float = 350.0    # closest view (boom length)
@export var boom_max: float = 2200.0   # farthest view
@export var pitch_degrees: float = 55.0

@export var edge_pan_enabled: bool = true
@export var edge_pan_margin: float = 24.0

var _zoom: float = 0.35   # 0 = closest, 1 = farthest
var is_dragging: bool = false
var drag_start_screen: Vector2 = Vector2.ZERO

var _map_size: Vector2 = Vector2.ZERO

@onready var cam: Camera3D = $Camera3D
var selection_box: Control = null            # 2D overlay in the UI layer
var placement_ghost: Node3D = null           # world-space ghost (MeshInstance3D)
var attack_area_ghost: AttackAreaIndicator = null

const BUILDING_SCENES := {
	"house": "res://scenes/buildings/house.tscn",
	"farm": "res://scenes/buildings/farm.tscn",
	"lumber_camp": "res://scenes/buildings/lumber_camp.tscn",
	"quarry": "res://scenes/buildings/quarry.tscn",
	"mine": "res://scenes/buildings/mine.tscn",
	"barracks": "res://scenes/buildings/barracks.tscn",
}


func _ready() -> void:
	var scene := get_tree().current_scene
	selection_box = scene.get_node_or_null("UI/SelectionBox")
	placement_ghost = scene.get_node_or_null("PlacementGhost")
	attack_area_ghost = scene.get_node_or_null("AttackAreaGhost")
	if selection_box:
		selection_box.visible = false
	if placement_ghost:
		placement_ghost.visible = false
	if attack_area_ghost:
		attack_area_ghost.visible = false

	GameManager.placement_mode_changed.connect(_on_placement_mode_changed)
	GameManager.attack_targeting_mode_changed.connect(_on_attack_targeting_mode_changed)

	_map_size = MapSettings.map_size
	_apply_zoom()


# ---------------------------------------------------------------------------
# Per-frame: panning, rotation, and ghost-follow
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("ui_left", "ui_right")
	input_dir.y = Input.get_axis("ui_up", "ui_down")
	input_dir += _edge_pan_dir()
	if input_dir != Vector2.ZERO:
		# Screen-relative: rotate the raw input by the rig's yaw so "up" always
		# pans the way the camera faces. Pan faster when zoomed out.
		var move := Vector3(input_dir.x, 0.0, input_dir.y).rotated(Vector3.UP, rotation.y)
		var speed := pan_speed * lerpf(0.5, 2.2, _zoom)
		position += move.normalized() * speed * delta
		_clamp_to_bounds()

	if Input.is_action_pressed("ui_page_up") or Input.is_key_pressed(KEY_Q):
		rotation.y += rotate_speed * delta
	if Input.is_action_pressed("ui_page_down") or Input.is_key_pressed(KEY_E):
		rotation.y -= rotate_speed * delta

	if GameManager.is_placing_building and placement_ghost and placement_ghost.visible:
		var gp := _ground_point(_mouse())
		placement_ghost.global_position = gp
		var ok := GameManager.placement_building_id in ["quarry", "mine"] \
		or GameManager.can_place_building_at(gp)
		var gmat := placement_ghost.material_override as StandardMaterial3D
		if gmat == null:
			gmat = StandardMaterial3D.new()
			gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			placement_ghost.material_override = gmat
			gmat.albedo_color = Color(0.2, 0.9, 0.2, 0.45) if ok else Color(0.9, 0.15, 0.15, 0.45)

	if GameManager.is_targeting_attack_position and attack_area_ghost and attack_area_ghost.visible:
		attack_area_ghost.global_position = _ground_point(_mouse())


func _edge_pan_dir() -> Vector2:
	if not edge_pan_enabled or is_dragging:
		return Vector2.ZERO
	var vp := get_viewport().get_visible_rect().size
	var m := _mouse()
	if m.x < 0 or m.y < 0 or m.x > vp.x or m.y > vp.y:
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if m.x < edge_pan_margin: dir.x = -1.0
	elif m.x > vp.x - edge_pan_margin: dir.x = 1.0
	if m.y < edge_pan_margin: dir.y = -1.0
	elif m.y > vp.y - edge_pan_margin: dir.y = 1.0
	return dir


func _clamp_to_bounds() -> void:
	if _map_size == Vector2.ZERO:
		return
	position.x = clampf(position.x, 0.0, _map_size.x)
	position.z = clampf(position.z, 0.0, _map_size.y)
	position.y = 0.0


func _apply_zoom() -> void:
	# Boom: camera sits up and back, looking down at the rig origin.
	var boom := lerpf(boom_min, boom_max, _zoom)
	var pitch := deg_to_rad(pitch_degrees)
	cam.position = Vector3(0.0, boom * sin(pitch), boom * cos(pitch))
	cam.rotation = Vector3(-pitch, 0.0, 0.0)


# ---------------------------------------------------------------------------
# Picking helpers
# ---------------------------------------------------------------------------
func _mouse() -> Vector2:
	return get_viewport().get_mouse_position()


func _ground_point(screen_pos: Vector2) -> Vector3:
	# Intersect the camera ray with the y = 0 ground plane.
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	if absf(d.y) < 0.0001:
		return Vector3(position.x, 0.0, position.z)
	var t := -o.y / d.y
	if t < 0.0:
		return Vector3(position.x, 0.0, position.z)
	return o + d * t


func _raycast(screen_pos: Vector2):
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.create(o, o + d * 100000.0)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	return hit.get("collider") if hit else null


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		_toggle_attack_targeting()
		return

	if GameManager.is_placing_building:
		_handle_placement_input(event)
		return

	if GameManager.is_targeting_attack_position:
		_handle_attack_targeting_input(event)
		return

	if event is InputEventMouseButton:
		if _is_over_ui(event.position):
			return
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom - zoom_step, 0.0, 1.0); _apply_zoom()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom + zoom_step, 0.0, 1.0); _apply_zoom()
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					drag_start_screen = event.position
					is_dragging = true
					if selection_box:
						selection_box.visible = true
						selection_box.position = drag_start_screen
						selection_box.size = Vector2.ZERO
				else:
					is_dragging = false
					if selection_box:
						selection_box.visible = false
					_finish_left_drag(event.position)
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_handle_right_click()

	elif event is InputEventMouseMotion and is_dragging:
		_update_selection_box(event.position)

	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		GameManager.clear_selection()


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------
func _update_selection_box(current: Vector2) -> void:
	if selection_box == null:
		return
	var tl := Vector2(minf(drag_start_screen.x, current.x), minf(drag_start_screen.y, current.y))
	selection_box.position = tl
	selection_box.size = (current - drag_start_screen).abs()


func _finish_left_drag(end_screen: Vector2) -> void:
	if drag_start_screen.distance_to(end_screen) < 8.0:
		_handle_single_click(end_screen)
		return

	var rect := Rect2(
		Vector2(minf(drag_start_screen.x, end_screen.x), minf(drag_start_screen.y, end_screen.y)),
		(end_screen - drag_start_screen).abs())

	var found: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit) or not unit.is_selectable_by_player():
			continue
		# Skip anything behind the camera, then test its projected position.
		if cam.is_position_behind(unit.global_position):
			continue
		if rect.has_point(cam.unproject_position(unit.global_position)):
			found.append(unit)

	if found.is_empty():
		GameManager.clear_selection()
	else:
		GameManager.select_units(found)


func _handle_single_click(screen_pos: Vector2) -> void:
	var obj = _raycast(screen_pos)
	if obj == null:
		GameManager.clear_selection()
		return
	if obj is Unit and obj.is_selectable_by_player():
		GameManager.select_units([obj])
	elif obj is Building:
		GameManager.select_building(obj)
	elif obj is Mountain or obj is ResourceNode:
		GameManager.select_resource_node(obj)
	else:
		GameManager.clear_selection()


# ---------------------------------------------------------------------------
# Right-click context commands
# ---------------------------------------------------------------------------
func _handle_right_click() -> void:
	if GameManager.selected_units.is_empty():
		return
	var screen := _mouse()
	var target = _raycast(screen)
	var ground := _ground_point(screen)
	for unit in GameManager.selected_units:
		if is_instance_valid(unit) and unit.is_alive:
			_issue_order(unit, target, ground)


func _issue_order(unit, target, ground: Vector3) -> void:
	if target == null or target == unit:
		unit.command_move(ground)
		return
	if target.is_in_group("enemies"):
		unit.command_attack(target)
	elif target.is_in_group("village_centers") and unit.has_method("command_return_to_work"):
		unit.command_return_to_work()
	elif target.is_in_group("resources"):
		unit.command_gather(target)
	elif target.is_in_group("construction_sites"):
		unit.command_build(target)
	elif target.is_in_group("farms") or target.is_in_group("lumber_camps") or target.is_in_group("quarries") or target.is_in_group("mines"):
		unit.command_gather(target)
	else:
		unit.command_move(ground)


# ---------------------------------------------------------------------------
# Building placement
# ---------------------------------------------------------------------------
func _handle_placement_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not _is_over_ui(event.position):
			_confirm_placement()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			GameManager.cancel_building_placement()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		GameManager.cancel_building_placement()


func _confirm_placement() -> void:
	var building_id = GameManager.placement_building_id
	var scene_path = BUILDING_SCENES.get(building_id)
	var cost = GameManager.COSTS.get(building_id)
	if scene_path == null or cost == null:
		GameManager.cancel_building_placement()
		return
	if not GameManager.can_afford(cost):
		GameManager.notify("Not enough resources for that building.")
		GameManager.cancel_building_placement()
		return

	var placement_pos := _ground_point(_mouse())

	# Quarry/mine are deliberately exempt — they're SUPPOSED to sit on a
	# mountain deposit (checked below via bind_to_deposit). Every other
	# building must not overlap a river, mountain, or tree; previously
	# nothing checked this at all, so buildings could be dropped on rivers.
	var exempt_from_terrain_check :Variant = building_id in ["quarry", "mine"]
	if not exempt_from_terrain_check and not GameManager.can_place_building_at(placement_pos):
		GameManager.notify("Can't build there — blocked by terrain (river, mountain, or tree).")
		GameManager.cancel_building_placement()
		return

	var building = load(scene_path).instantiate()
	get_tree().current_scene.get_node("Buildings").add_child(building)
	building.global_position = placement_pos
	GameManager.clear_trees_at(placement_pos, 44.0)

	if building is ResourceBuilding and building.deposit_group != "":
		if not building.bind_to_deposit(64.0):
			var what = "a mountain" if building.deposit_group == "stone_sources" else "an iron-bearing mountain"
			GameManager.notify("A %s must be placed on %s." % [building_id, what])
			building.queue_free()
			GameManager.cancel_building_placement()
			return

	GameManager.spend(cost)

	# The navmesh only existed for map-gen obstacles until now — without
	# this, units would path straight through every player-placed building
	# (quarry/mine/farm/etc.) since it was never carved out of the mesh.
	var map_gen = get_tree().current_scene.get_node_or_null("MapGenerator")
	if map_gen and map_gen.has_method("rebake_navigation"):
		map_gen.rebake_navigation()

	var builder = GameManager.placement_builder
	if is_instance_valid(builder) and builder.has_method("command_build"):
		builder.command_build(building)
	elif not GameManager.selected_units.is_empty():
		for unit in GameManager.selected_units:
			if is_instance_valid(unit) and unit.has_method("command_build"):
				unit.command_build(building)

	GameManager.cancel_building_placement()


func _on_placement_mode_changed(active: bool, _building_id: String) -> void:
	if placement_ghost:
		placement_ghost.visible = active
	if active:
		is_dragging = false
		if selection_box:
			selection_box.visible = false


# ---------------------------------------------------------------------------
# Artillery attack-position targeting
# ---------------------------------------------------------------------------
func _toggle_attack_targeting() -> void:
	if GameManager.is_placing_building:
		return
	if GameManager.is_targeting_attack_position:
		GameManager.cancel_attack_position_targeting()
		return
	var radius := 0.0
	var any_artillery := false
	for unit in GameManager.selected_units:
		if is_instance_valid(unit) and unit.is_alive and unit is Artillery:
			any_artillery = true
			radius = maxf(radius, unit.splash_radius)
	if any_artillery:
		GameManager.start_attack_position_targeting(radius)
	else:
		GameManager.notify("Select an artillery unit to give it an attack-position order.")


func _handle_attack_targeting_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not _is_over_ui(event.position):
			_confirm_attack_position()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			GameManager.cancel_attack_position_targeting()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		GameManager.cancel_attack_position_targeting()


func _confirm_attack_position() -> void:
	var pos := _ground_point(_mouse())
	for unit in GameManager.selected_units:
		if is_instance_valid(unit) and unit.is_alive and unit is Artillery:
			unit.command_attack_position(pos)
	GameManager.cancel_attack_position_targeting()


func _on_attack_targeting_mode_changed(active: bool, radius: float) -> void:
	if attack_area_ghost:
		attack_area_ghost.visible = active
		if active:
			attack_area_ghost.set_mode("targeting")
			attack_area_ghost.set_radius(radius)
	if active:
		is_dragging = false
		if selection_box:
			selection_box.visible = false


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _is_over_ui(screen_pos: Vector2) -> bool:
	var ui = get_tree().current_scene.get_node_or_null("UI")
	if ui == null:
		return false
	for panel_name in ["TopBar", "SelectionPanel", "BuildMenu", "TimePanel"]:
		var panel = ui.get_node_or_null(panel_name)
		if panel and panel.visible and panel.get_global_rect().has_point(screen_pos):
			return true
	return false
