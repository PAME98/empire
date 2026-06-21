extends Camera2D

@export var move_speed: float = 500.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0

var drag_start: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var selection_start: Vector2 = Vector2.ZERO

@onready var selection_box = $SelectionBox
@onready var placement_ghost: ColorRect = $PlacementGhost

const BUILDING_SCENES = {
	"farmstead": "res://scenes/farm.tscn",
}

func _ready():
	selection_box.visible = false
	if placement_ghost:
		placement_ghost.visible = false
	GameManager.placement_mode_changed.connect(_on_placement_mode_changed)

func _process(_delta):
	var input = Vector2.ZERO
	input.x = Input.get_axis("ui_left", "ui_right")
	input.y = Input.get_axis("ui_up", "ui_down")
	position += input.normalized() * move_speed * _delta / zoom

	if GameManager.is_placing_building and placement_ghost and placement_ghost.visible:
		placement_ghost.global_position = get_global_mouse_position() - placement_ghost.size * 0.5

func _input(event):
	if GameManager.is_placing_building:
		_handle_placement_input(event)
		return

	if event is InputEventMouseButton:
		# Don't let world click/drag selection logic fire when the click
		# is actually over a visible UI panel (e.g. the recruit buttons).
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and _is_over_ui(event.position):
			return

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = (zoom + Vector2.ONE * zoom_speed).clamp(Vector2.ONE * min_zoom, Vector2.ONE * max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = (zoom - Vector2.ONE * zoom_speed).clamp(Vector2.ONE * min_zoom, Vector2.ONE * max_zoom)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				selection_start = get_global_mouse_position()
				is_dragging = true
				selection_box.visible = true
			else:
				is_dragging = false
				selection_box.visible = false
				_finish_selection()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click()

	if event is InputEventMouseMotion and is_dragging:
		_update_selection_box()

func _handle_placement_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not _is_over_ui(event.position):
			_confirm_placement()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			GameManager.cancel_building_placement()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		GameManager.cancel_building_placement()

func _confirm_placement():
	var building_type = GameManager.placement_building_type
	var builder = GameManager.placement_builder
	var scene_path = BUILDING_SCENES.get(building_type)
	var cost = _get_building_cost(building_type)

	if scene_path == null or cost == null:
		GameManager.cancel_building_placement()
		return

	if not GameManager.can_afford(cost):
		GameManager.cancel_building_placement()
		return

	if not is_instance_valid(builder):
		GameManager.cancel_building_placement()
		return

	GameManager.spend_resources(cost)

	var building = load(scene_path).instantiate()
	building.global_position = get_global_mouse_position()
	get_tree().current_scene.add_child(building)

	builder.assign_build(building)

	GameManager.cancel_building_placement()

func _get_building_cost(building_type: String):
	match building_type:
		"farmstead":
			return GameManager.FARM_COST
		_:
			return null

func _on_placement_mode_changed(active: bool, _building_type: String):
	if not placement_ghost:
		return
	placement_ghost.visible = active
	if active:
		is_dragging = false
		selection_box.visible = false

func _is_over_ui(screen_pos: Vector2) -> bool:
	var ui = get_tree().current_scene.get_node_or_null("UI")
	if ui == null:
		return false

	for panel_name in ["Resources", "UnitPanel", "BuildingPanel"]:
		var panel = ui.get_node_or_null(panel_name)
		if panel and panel.visible and panel.get_global_rect().has_point(screen_pos):
			return true

	return false

func _update_selection_box():
	var current_pos = get_global_mouse_position()
	var top_left = Vector2(min(selection_start.x, current_pos.x), min(selection_start.y, current_pos.y))
	var size = (current_pos - selection_start).abs()

	selection_box.global_position = top_left
	selection_box.size = size

func _finish_selection():
	var rect = Rect2(selection_box.global_position, selection_box.size)
	if rect.size.length() < 10:
		_handle_click_selection(selection_start)
		return

	var units = get_tree().get_nodes_in_group("units")
	var selected = []
	for unit in units:
		if rect.has_point(unit.global_position) and unit.team == 0:
			selected.append(unit)

	if selected.size() > 0:
		GameManager.clear_selection()
		for unit in selected:
			GameManager.selected_units.append(unit)
			unit.set_selected(true)
	else:
		GameManager.clear_selection()

func _handle_click_selection(click_pos: Vector2):
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = click_pos
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var results = space_state.intersect_point(query)

	for result in results:
		var collider = result.collider
		if collider.is_in_group("units") and collider.team == 0:
			GameManager.select_unit(collider)
			return
		if collider.is_in_group("village_centers") or collider is Building:
			GameManager.select_building(collider)
			return

	GameManager.clear_selection()

func _handle_right_click():
	var mouse_pos = get_global_mouse_position()
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var results = space_state.intersect_point(query)

	var target = null
	for result in results:
		var collider = result.collider
		if collider.is_in_group("resources") or collider.is_in_group("enemies") or collider.is_in_group("village_centers"):
			target = collider
			break

	for unit in GameManager.selected_units:
		if unit.is_in_group("workers"):
			if target and target.is_in_group("resources"):
				unit.assign_gather(target)
			elif target and target.is_in_group("village_centers"):
				unit.assign_return(target)
			else:
				unit.command_move(mouse_pos)
		elif unit.is_in_group("soldiers"):
			if target and target.is_in_group("enemies"):
				unit.assign_attack_target(target)
			else:
				unit.command_move(mouse_pos)
