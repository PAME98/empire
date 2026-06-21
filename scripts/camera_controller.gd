extends Camera2D

## The whole RTS input layer lives here: WASD/arrow pan, wheel zoom,
## left-click/drag box-select (works uniformly across citizens AND
## soldiers), right-click context commands (move / gather / attack / build
## depending on what's under the cursor and what's selected), and
## ghost-following building placement.

@export var move_speed: float = 560.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.4
@export var max_zoom: float = 2.5

var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO

@onready var selection_box: ColorRect = $SelectionBox
@onready var placement_ghost: ColorRect = $PlacementGhost

const BUILDING_SCENES := {
	"house": "res://scenes/house.tscn",
	"farm": "res://scenes/farm.tscn",
	"lumber_camp": "res://scenes/lumber_camp.tscn",
	"quarry": "res://scenes/quarry.tscn",
	"barracks": "res://scenes/barracks.tscn",
}


func _ready() -> void:
	selection_box.visible = false
	placement_ghost.visible = false
	GameManager.placement_mode_changed.connect(_on_placement_mode_changed)


func _process(delta: float) -> void:
	var input_dir = Vector2.ZERO
	input_dir.x = Input.get_axis("ui_left", "ui_right")
	input_dir.y = Input.get_axis("ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		position += input_dir.normalized() * move_speed * delta / zoom.x

	if GameManager.is_placing_building and placement_ghost.visible:
		placement_ghost.global_position = get_global_mouse_position() - placement_ghost.size * 0.5


func _input(event: InputEvent) -> void:
	if GameManager.is_placing_building:
		_handle_placement_input(event)
		return

	if event is InputEventMouseButton:
		if _is_over_ui(event.position):
			return

		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_by(zoom_speed)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_by(-zoom_speed)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					drag_start = get_global_mouse_position()
					is_dragging = true
					selection_box.visible = true
				else:
					is_dragging = false
					selection_box.visible = false
					_finish_left_drag()
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_handle_right_click()

	elif event is InputEventMouseMotion and is_dragging:
		_update_selection_box()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		GameManager.clear_selection()


func _zoom_by(amount: float) -> void:
	zoom = (zoom + Vector2.ONE * amount).clamp(Vector2.ONE * min_zoom, Vector2.ONE * max_zoom)


# ---------------------------------------------------------------------------
# Selection (left click / drag)
# ---------------------------------------------------------------------------
func _update_selection_box() -> void:
	var current = get_global_mouse_position()
	var top_left = Vector2(minf(drag_start.x, current.x), minf(drag_start.y, current.y))
	selection_box.global_position = top_left
	selection_box.size = (current - drag_start).abs()


func _finish_left_drag() -> void:
	var rect = Rect2(selection_box.global_position, selection_box.size)
	if rect.size.length() < 8.0:
		_handle_single_click(drag_start)
		return

	var found: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(unit) and rect.has_point(unit.global_position) and unit.is_selectable_by_player():
			found.append(unit)

	if found.is_empty():
		GameManager.clear_selection()
	else:
		GameManager.select_units(found)


# ---------------------------------------------------------------------------
# Single click selection — checks units first (smaller radius, in front),
# then resource nodes (trees etc, for the remaining-amount tooltip), then
# buildings. Iterating nodes directly instead of using a physics point query
# avoids physics-query timing edge cases entirely, which matters a lot at
# this project's scale (a few dozen units/buildings at most) and is far
# easier to reason about / debug than a physics-space query fired from
# _input().
# ---------------------------------------------------------------------------
const UNIT_CLICK_RADIUS: float = 16.0
const BUILDING_CLICK_PADDING: float = 6.0  # extra margin around a building's collision box


func _handle_single_click(click_pos: Vector2) -> void:
	var unit = _find_clickable_unit(click_pos)
	if unit:
		GameManager.select_units([unit])
		return

	var resource = _nearest_in_radius(click_pos, "resources", RESOURCE_CLICK_RADIUS)
	if resource:
		GameManager.select_resource_node(resource)
		return

	var building = _find_clickable_building(click_pos)
	if building:
		GameManager.select_building(building)
		return

	GameManager.clear_selection()


func _find_clickable_unit(world_pos: Vector2):
	var best = null
	var best_dist = UNIT_CLICK_RADIUS
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit) or not unit.is_selectable_by_player():
			continue
		var d = world_pos.distance_to(unit.global_position)
		if d <= best_dist:
			best_dist = d
			best = unit
	return best


func _find_clickable_building(world_pos: Vector2):
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building):
			continue
		if _is_point_in_building(world_pos, building):
			return building
	return null


func _is_point_in_building(world_pos: Vector2, building: Node) -> bool:
	var local_pos = world_pos - building.global_position
	var half_size = _building_half_size(building)
	return absf(local_pos.x) <= half_size.x + BUILDING_CLICK_PADDING and absf(local_pos.y) <= half_size.y + BUILDING_CLICK_PADDING


func _building_half_size(building: Node) -> Vector2:
	# Every building scene's CollisionShape2D uses a RectangleShape2D — read
	# its size directly so click tolerance always matches the actual sprite,
	# without needing a physics query.
	var shape_node = building.get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape is RectangleShape2D:
		return shape_node.shape.size * 0.5
	return Vector2(32, 32)  # sane fallback if a building is missing the node


# ---------------------------------------------------------------------------
# Right-click context commands — also resolved by direct node lookup so the
# same target (tree / resource building / construction site / enemy) is
# always found regardless of physics-frame timing.
# ---------------------------------------------------------------------------
const RESOURCE_CLICK_RADIUS: float = 26.0
const ENEMY_CLICK_RADIUS: float = 20.0


func _handle_right_click() -> void:
	if GameManager.selected_units.is_empty():
		return

	var mouse_pos = get_global_mouse_position()
	var target = _find_right_click_target(mouse_pos)

	for unit in GameManager.selected_units:
		if not is_instance_valid(unit) or not unit.is_alive:
			continue
		_issue_order(unit, target, mouse_pos)


func _find_right_click_target(world_pos: Vector2):
	# Priority: enemy > depletable resource node > construction site >
	# finished resource building > any other building. This mirrors what a
	# player expects right-clicking near overlapping things to do.
	var enemy = _nearest_in_radius(world_pos, "enemies", ENEMY_CLICK_RADIUS)
	if enemy:
		return enemy

	var resource = _nearest_in_radius(world_pos, "resources", RESOURCE_CLICK_RADIUS)
	if resource:
		return resource

	var building = _find_clickable_building(world_pos)
	if building:
		return building

	return null


func _nearest_in_radius(world_pos: Vector2, group_name: String, radius: float):
	var best = null
	var best_dist = radius
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node):
			continue
		var d = world_pos.distance_to(node.global_position)
		if d <= best_dist:
			best_dist = d
			best = node
	return best


func _issue_order(unit, target, mouse_pos: Vector2) -> void:
	if target == null:
		unit.command_move(mouse_pos)
		return

	if target.is_in_group("enemies"):
		unit.command_attack(target)
	elif target.is_in_group("resources"):
		unit.command_gather(target)
	elif target.is_in_group("construction_sites"):
		unit.command_build(target)
	elif target.is_in_group("farms") or target.is_in_group("lumber_camps") or target.is_in_group("quarries"):
		# Right-clicking a finished resource building also assigns the worker there.
		unit.command_gather(target)
	else:
		unit.command_move(mouse_pos)


# ---------------------------------------------------------------------------
# Building placement (ghost follows mouse until confirmed)
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

	GameManager.spend(cost)
	var building = load(scene_path).instantiate()
	building.global_position = get_global_mouse_position()
	get_tree().current_scene.get_node("Buildings").add_child(building)

	var builder = GameManager.placement_builder
	if is_instance_valid(builder) and builder.has_method("command_build"):
		builder.command_build(building)
	elif not GameManager.selected_units.is_empty():
		# No specific builder was chosen — send every currently selected
		# citizen to help construct it, same as a real RTS queue order.
		for unit in GameManager.selected_units:
			if is_instance_valid(unit) and unit.has_method("command_build"):
				unit.command_build(building)

	GameManager.cancel_building_placement()


func _on_placement_mode_changed(active: bool, _building_id: String) -> void:
	placement_ghost.visible = active
	if active:
		is_dragging = false
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
