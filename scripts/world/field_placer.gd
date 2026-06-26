extends Node
## FieldPlacer — drag-to-draw, obstacle-conforming field plots (Kingdoms Reborn
## style). Add as an Autoload named "FieldPlacer" (like Hud). No scene edits.
##
## FLOW: the Build menu's "Field" button calls GameManager.start_field_draw().
##   * left-press anchors a corner,
##   * dragging rubber-bands a rectangle snapped to GameManager.FIELD_CELL,
##     clamped to FIELD_MIN/MAX_TILES per side. We test every cell in the rect
##     against can_place_building_at and show a green tile per valid cell / red
##     per blocked cell, so you SEE the field bend around trees/rocks/water.
##   * left-release sends the valid cells to the host (request_place_field),
##   * right-click or Esc cancels.
##
## Pure local UI — the host re-validates and spawns the field, so it's
## desync-safe.

var _active := false
var _dragging := false
var _start := Vector3.ZERO
var _ghost_root: Node3D = null
var _last_valid_cells: Array = []     # world-space Vector3 cell centres
var _last_centroid := Vector3.ZERO
var _last_rect := Vector4(INF, INF, INF, INF)  # nx, nz, dirx, dirz cache


func _ready() -> void:
	set_process(false)
	set_process_unhandled_input(false)
	call_deferred("_connect")


func _connect() -> void:
	if typeof(GameManager) == TYPE_NIL:
		return
	if GameManager.has_signal("field_draw_mode_changed") \
			and not GameManager.field_draw_mode_changed.is_connected(_on_mode):
		GameManager.field_draw_mode_changed.connect(_on_mode)


func _on_mode(active: bool) -> void:
	_active = active
	set_process(active)
	set_process_unhandled_input(active)
	if active:
		_ensure_root()
	else:
		_dragging = false
		_last_valid_cells.clear()
		_clear_root()


# ---------------------------------------------------------------------------
# Ghost tiles
# ---------------------------------------------------------------------------
func _ensure_root() -> void:
	_clear_root()
	var scene := get_tree().current_scene
	if scene == null:
		return
	_ghost_root = Node3D.new()
	scene.add_child(_ghost_root)


func _clear_root() -> void:
	if is_instance_valid(_ghost_root):
		_ghost_root.queue_free()
	_ghost_root = null


func _clear_tiles() -> void:
	if not is_instance_valid(_ghost_root):
		return
	for c in _ghost_root.get_children():
		c.queue_free()


func _add_tile(center: Vector3, cell: float, valid: bool) -> void:
	if not is_instance_valid(_ghost_root):
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(cell * 0.92, 4.0, cell * 0.92)
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.35, 0.9, 0.4, 0.45) if valid else Color(0.95, 0.3, 0.3, 0.35)
	mi.material_override = m
	# Parent FIRST, then position — global_position is invalid before the node
	# is inside the tree. _ghost_root sits at the scene origin, so local
	# position equals world here.
	_ghost_root.add_child(mi)
	mi.position = Vector3(center.x, 3.0, center.z)


# ---------------------------------------------------------------------------
# Input + drag
# ---------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if _active and _dragging:
		_update_rect(_mouse_to_ground())


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start = _snap(_mouse_to_ground())
				_dragging = true
				_last_rect = Vector4(INF, INF, INF, INF)
				_update_rect(_start)
				get_viewport().set_input_as_handled()
			elif _dragging:
				_dragging = false
				_commit()
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			GameManager.cancel_field_draw()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			GameManager.cancel_field_draw()
			get_viewport().set_input_as_handled()


func _update_rect(curr: Vector3) -> void:
	var cell: float = GameManager.FIELD_CELL
	var max_t: int = GameManager.FIELD_MAX_TILES
	var b := _snap(curr)
	var nx := clampi(int(round(absf(b.x - _start.x) / cell)) + 1, 1, max_t)
	var nz := clampi(int(round(absf(b.z - _start.z) / cell)) + 1, 1, max_t)
	var dirx := 1.0 if b.x >= _start.x else -1.0
	var dirz := 1.0 if b.z >= _start.z else -1.0

	# Only rebuild ghost tiles + re-run validity when the rectangle actually
	# changed cell extents (not every frame the mouse jitters within a cell).
	var rect := Vector4(nx, nz, dirx, dirz)
	if rect == _last_rect:
		return
	_last_rect = rect

	_clear_tiles()
	_last_valid_cells.clear()
	var sum := Vector3.ZERO
	for ix in nx:
		for iz in nz:
			var wc := Vector3(_start.x + dirx * ix_to_off(ix, cell),
							  0.0,
							  _start.z + dirz * ix_to_off(iz, cell))
			var ok := GameManager.can_place_building_at(wc, cell * 0.45)
			_add_tile(wc, cell, ok)
			if ok:
				_last_valid_cells.append(wc)
				sum += wc
	if _last_valid_cells.size() > 0:
		_last_centroid = sum / float(_last_valid_cells.size())


func ix_to_off(i: int, cell: float) -> float:
	# i is 1-based tile index; offset from the start corner.
	return float(i - 1) * cell


func _commit() -> void:
	_clear_tiles()
	if _last_valid_cells.is_empty():
		GameManager.notify("No clear ground for a field there.")
		GameManager.cancel_field_draw()
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		NetworkCommands.request_place_field.rpc_id(1, _last_centroid, _last_valid_cells, GameManager.FIELD_CELL)
	else:
		NetworkCommands.request_place_field(_last_centroid, _last_valid_cells, GameManager.FIELD_CELL)
	GameManager.cancel_field_draw()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _snap(p: Vector3) -> Vector3:
	var c: float = GameManager.FIELD_CELL
	return Vector3(round(p.x / c) * c, 0.0, round(p.z / c) * c)


func _camera() -> Camera3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var c := scene.get_node_or_null("Camera/Camera3D") as Camera3D
	if c == null:
		c = get_viewport().get_camera_3d()
	return c


func _mouse_to_ground() -> Vector3:
	var cam := _camera()
	if cam == null:
		return Vector3.ZERO
	var mpos := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mpos)
	var d := cam.project_ray_normal(mpos)
	if absf(d.y) < 0.0001:
		return Vector3.ZERO
	var t := -o.y / d.y
	return o + d * t
