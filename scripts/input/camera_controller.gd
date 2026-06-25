extends Node3D
## camera_controller.gd — multiplayer-aware.
## FIX: replaced _send_command (broken Callable.bindv().rpc_id() pattern)
## with explicit per-command RPC calls. Godot 4 requires calling .rpc_id()
## directly on the method reference, not on a bound Callable.

@export var pan_speed:      float = 600.0
@export var rotate_speed:   float = 1.6
@export var zoom_step:      float = 0.08
@export var boom_min:       float = 350.0
@export var boom_max:       float = 2200.0
@export var pitch_degrees:  float = 55.0
@export var edge_pan_enabled: bool  = true
@export var edge_pan_margin:  float = 24.0

var _zoom:             float   = 0.35
var is_dragging:       bool    = false
var drag_start_screen: Vector2 = Vector2.ZERO
var _map_size:         Vector2 = Vector2.ZERO

@onready var cam: Camera3D = $Camera3D
var selection_box:      Control             = null
var placement_ghost:    Node3D              = null
var attack_area_ghost:  AttackAreaIndicator = null

const BUILDING_SCENES := {
	"house":         "res://scenes/buildings/house.tscn",
	"farm":          "res://scenes/buildings/farm.tscn",
	"grain_farm":    "res://scenes/buildings/grain_farm.tscn",
	"veg_garden":    "res://scenes/buildings/veg_garden.tscn",
	"hunter":        "res://scenes/buildings/hunter.tscn",
	"lumber_camp":   "res://scenes/buildings/lumber_camp.tscn",
	"quarry":        "res://scenes/buildings/quarry.tscn",
	"mine":          "res://scenes/buildings/mine.tscn",
	"herbalist":     "res://scenes/buildings/herbalist.tscn",
	"well":          "res://scenes/buildings/well.tscn",
	"charcoal_kiln": "res://scenes/buildings/charcoal_kiln.tscn",
	"mill":          "res://scenes/buildings/mill.tscn",
	"bakery":        "res://scenes/buildings/bakery.tscn",
	"sawmill":       "res://scenes/buildings/sawmill.tscn",
	"smelter":       "res://scenes/buildings/smelter.tscn",
	"blacksmith":    "res://scenes/buildings/blacksmith.tscn",
	"apothecary":    "res://scenes/buildings/apothecary.tscn",
	"barracks":      "res://scenes/buildings/barracks.tscn",
}

const DEPOSIT_BUILDINGS      := ["quarry", "mine"]
const GHOST_VALID_COLOR      := Color(0.2, 0.9, 0.2, 0.45)
const GHOST_INVALID_COLOR    := Color(0.9, 0.15, 0.15, 0.45)
const KIT_UNIT               := 14.0
const GRID_RADIUS_CELLS      := 12
const GRID_LINE_COLOR        := Color(0.95, 0.95, 1.0, 0.20)
const GRID_LINE_COLOR_HI     := Color(0.3, 0.95, 0.4, 0.6)

var _ghost_footprint: float   = 36.0
var _ghost_extents:   Vector2 = Vector2(24, 24)
var placement_grid:   MeshInstance3D = null


func grid_cell() -> float:
	return KIT_UNIT * Building.GLOBAL_BUILDING_SCALE


func _ready() -> void:
	var scene       := get_tree().current_scene
	selection_box    = scene.get_node_or_null("UI/SelectionBox")
	placement_ghost  = scene.get_node_or_null("PlacementGhost")
	attack_area_ghost = scene.get_node_or_null("AttackAreaGhost")
	if selection_box:     selection_box.visible    = false
	if placement_ghost:   placement_ghost.visible  = false
	if attack_area_ghost: attack_area_ghost.visible = false

	GameManager.placement_mode_changed.connect(_on_placement_mode_changed)
	GameManager.attack_targeting_mode_changed.connect(_on_attack_targeting_mode_changed)
	_build_placement_grid()
	_map_size = MapSettings.map_size
	_apply_zoom()


func _build_placement_grid() -> void:
	placement_grid        = MeshInstance3D.new()
	placement_grid.name   = "PlacementGrid"
	placement_grid.mesh   = ImmediateMesh.new()
	placement_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m                 := StandardMaterial3D.new()
	m.shading_mode         = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency         = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode            = BaseMaterial3D.CULL_DISABLED
	placement_grid.material_override = m
	placement_grid.visible = false
	get_tree().current_scene.add_child.call_deferred(placement_grid)


func _process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x    = Input.get_axis("ui_left", "ui_right")
	input_dir.y    = Input.get_axis("ui_up",   "ui_down")
	input_dir      += _edge_pan_dir()
	if input_dir != Vector2.ZERO:
		var move  := Vector3(input_dir.x, 0.0, input_dir.y).rotated(Vector3.UP, rotation.y)
		var speed := pan_speed * lerpf(0.5, 2.2, _zoom)
		position  += move.normalized() * speed * delta
		_clamp_to_bounds()

	if Input.is_action_pressed("ui_page_up")   or Input.is_key_pressed(KEY_Q):
		rotation.y += rotate_speed * delta
	if Input.is_action_pressed("ui_page_down") or Input.is_key_pressed(KEY_E):
		rotation.y -= rotate_speed * delta

	if GameManager.is_placing_building and placement_ghost and placement_ghost.visible:
		var raw := _ground_point(_mouse())
		var gp  := _snap_to_grid(raw, _ghost_extents)
		placement_ghost.global_position = gp
		var terrain_ok := GameManager.placement_building_id in DEPOSIT_BUILDINGS \
			or GameManager.can_place_building_at(gp, _ghost_footprint)
		var ok := terrain_ok and not _overlaps_existing_building(gp, _ghost_extents)
		_tint_ghost(placement_ghost, ok)
		_draw_grid(gp, ok)

	if GameManager.is_targeting_attack_position and attack_area_ghost and attack_area_ghost.visible:
		attack_area_ghost.global_position = _ground_point(_mouse())


func _edge_pan_dir() -> Vector2:
	if not edge_pan_enabled or is_dragging: return Vector2.ZERO
	var vp  := get_viewport().get_visible_rect().size
	var m   := _mouse()
	if m.x < 0 or m.y < 0 or m.x > vp.x or m.y > vp.y: return Vector2.ZERO
	var dir := Vector2.ZERO
	if m.x < edge_pan_margin:           dir.x = -1.0
	elif m.x > vp.x - edge_pan_margin:  dir.x =  1.0
	if m.y < edge_pan_margin:           dir.y = -1.0
	elif m.y > vp.y - edge_pan_margin:  dir.y =  1.0
	return dir


func _clamp_to_bounds() -> void:
	if _map_size == Vector2.ZERO: return
	position.x = clampf(position.x, 0.0, _map_size.x)
	position.z = clampf(position.z, 0.0, _map_size.y)
	position.y = 0.0


func _apply_zoom() -> void:
	var boom  := lerpf(boom_min, boom_max, _zoom)
	var pitch := deg_to_rad(pitch_degrees)
	cam.position = Vector3(0.0, boom * sin(pitch), boom * cos(pitch))
	cam.rotation = Vector3(-pitch, 0.0, 0.0)


func _mouse() -> Vector2:
	return get_viewport().get_mouse_position()


func _ground_point(screen_pos: Vector2) -> Vector3:
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	if absf(d.y) < 0.0001: return Vector3(position.x, 0.0, position.z)
	var t := -o.y / d.y
	if t < 0.0:             return Vector3(position.x, 0.0, position.z)
	return o + d * t


func _raycast(screen_pos: Vector2):
	var o      := cam.project_ray_origin(screen_pos)
	var d      := cam.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.create(o, o + d * 100000.0)
	params.collide_with_areas  = false
	params.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	return hit.get("collider") if hit else null


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		_toggle_attack_targeting(); return

	if GameManager.is_placing_building:
		_handle_placement_input(event); return

	if GameManager.is_targeting_attack_position:
		_handle_attack_targeting_input(event); return

	if event is InputEventMouseButton:
		if _is_over_ui(event.position): return
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom - zoom_step, 0.0, 1.0); _apply_zoom()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom + zoom_step, 0.0, 1.0); _apply_zoom()
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					drag_start_screen = event.position
					is_dragging       = true
					if selection_box:
						selection_box.visible  = true
						selection_box.position = drag_start_screen
						selection_box.size     = Vector2.ZERO
				else:
					is_dragging = false
					if selection_box: selection_box.visible = false
					_finish_left_drag(event.position)
			MOUSE_BUTTON_RIGHT:
				if event.pressed: _handle_right_click()

	elif event is InputEventMouseMotion and is_dragging:
		_update_selection_box(event.position)

	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		GameManager.clear_selection()


func _update_selection_box(current: Vector2) -> void:
	if selection_box == null: return
	var tl := Vector2(minf(drag_start_screen.x, current.x), minf(drag_start_screen.y, current.y))
	selection_box.position = tl
	selection_box.size     = (current - drag_start_screen).abs()


func _finish_left_drag(end_screen: Vector2) -> void:
	if drag_start_screen.distance_to(end_screen) < 8.0:
		_handle_single_click(end_screen); return
	var rect := Rect2(
		Vector2(minf(drag_start_screen.x, end_screen.x), minf(drag_start_screen.y, end_screen.y)),
		(end_screen - drag_start_screen).abs()
	)
	var found: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit) or not unit.is_selectable_by_player(): continue
		if cam.is_position_behind(unit.global_position): continue
		if rect.has_point(cam.unproject_position(unit.global_position)):
			found.append(unit)
	if found.is_empty(): GameManager.clear_selection()
	else:                GameManager.select_units(found)


func _handle_single_click(screen_pos: Vector2) -> void:
	var obj: Variant = _raycast(screen_pos)
	if obj == null:          GameManager.clear_selection(); return
	if obj is Unit and obj.is_selectable_by_player():
		GameManager.select_units([obj])
	elif obj is Building and obj.is_selectable_by_player():
		GameManager.select_building(obj)
	elif obj is Mountain or obj is ResourceNode:
		GameManager.select_resource_node(obj)
	else:
		GameManager.clear_selection()


# ---------------------------------------------------------------------------
# Right-click orders — explicit RPC calls per command type.
# FIX: the old _send_command used Callable(NC, method).bindv(args).rpc_id(1)
# which does NOT correctly serialize arguments in Godot 4. Each command now
# calls its RPC method directly.
# ---------------------------------------------------------------------------
func _handle_right_click() -> void:
	if GameManager.selected_units.is_empty(): return
	var screen := _mouse()
	var target: Variant = _raycast(screen)
	var ground  := _ground_point(screen)

	var my_team := _my_team()
	var owned   := GameManager.selected_units.filter(
		func(u): return is_instance_valid(u) and u.is_alive and u.team == my_team
	)
	var unit_ids: Array = owned.map(
		func(u): return u.get_meta("unit_id", -1)
	).filter(func(id): return id != -1)

	if unit_ids.is_empty():
		if not owned.is_empty():
			GameManager.notify("Selected units have no network id.")
		return

	if target != null and (target is Unit or target is Building) \
			and "team" in target and target.team != my_team \
			and (not ("is_alive" in target) or target.is_alive):
		# Attack
		_rpc_or_local("request_attack", [unit_ids, target.get_path()])

	elif target != null and not (target is Unit) \
			and (target.is_in_group("resources")
				or target.is_in_group("farms")
				or target.is_in_group("lumber_camps")
				or target.is_in_group("quarries")
				or target.is_in_group("mines")):
		# Gather
		_rpc_or_local("request_gather", [unit_ids, target.get_path()])

	elif target != null and not (target is Unit) \
			and target.is_in_group("construction_sites") \
			and "team" in target and target.team == my_team:
		# Build — send building_net_id (int), not NodePath
		var net_id: int = target.get_meta("building_net_id", -1)
		_rpc_or_local("request_build_on", [unit_ids, net_id])

	elif target != null and not (target is Unit) \
			and target.is_in_group("village_centers") \
			and "team" in target and target.team == my_team:
		# Return to work / deliver resources
		_rpc_or_local("request_return_to_work", [unit_ids])

	else:
		# Move
		_rpc_or_local("request_move", [unit_ids, ground])


# ---------------------------------------------------------------------------
# FIX: explicit dispatch — host calls directly, client uses typed RPC methods.
# ---------------------------------------------------------------------------
func _rpc_or_local(method: String, args: Array) -> void:
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		NetworkCommands.callv(method, args)
	else:
		match method:
			"request_move":
				NetworkCommands.request_move.rpc_id(1, args[0], args[1])
			"request_attack":
				NetworkCommands.request_attack.rpc_id(1, args[0], args[1])
			"request_attack_position":
				NetworkCommands.request_attack_position.rpc_id(1, args[0], args[1])
			"request_gather":
				NetworkCommands.request_gather.rpc_id(1, args[0], args[1])
			"request_build_on":
				NetworkCommands.request_build_on.rpc_id(1, args[0], args[1])
			"request_place_building":
				NetworkCommands.request_place_building.rpc_id(1, args[0], args[1])
			"request_attack_position":
				NetworkCommands.request_attack_position.rpc_id(1, args[0], args[1])
			"request_return_to_work":
				NetworkCommands.request_return_to_work.rpc_id(1, args[0])
			_:
				push_warning("_rpc_or_local: unhandled method " + method)


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
	var building_id := GameManager.placement_building_id
	var cost: Variant = GameManager.COSTS.get(building_id, {})
	if cost.is_empty():
		GameManager.cancel_building_placement(); return
	if not GameManager.can_afford(cost):
		GameManager.notify("Not enough resources.")
		GameManager.cancel_building_placement(); return

	var inst := load(BUILDING_SCENES.get(building_id, ""))
	if inst == null:
		GameManager.cancel_building_placement(); return
	var temp_node: Node = inst.instantiate()
	var s         := Building.GLOBAL_BUILDING_SCALE
	var my_ext    := _scene_extents(temp_node, s)
	temp_node.free()

	var pos := _snap_to_grid(_ground_point(_mouse()), my_ext)

	_rpc_or_local("request_place_building", [building_id, pos])
	GameManager.cancel_building_placement()


# ---------------------------------------------------------------------------
# Attack-position targeting
# ---------------------------------------------------------------------------
func _toggle_attack_targeting() -> void:
	if GameManager.is_placing_building: return
	if GameManager.is_targeting_attack_position:
		GameManager.cancel_attack_position_targeting(); return
	var radius   := 0.0
	var any_arty := false
	var my_team  := _my_team()
	for unit in GameManager.selected_units:
		if is_instance_valid(unit) and unit.is_alive and unit is Artillery and unit.team == my_team:
			any_arty = true
			radius   = maxf(radius, unit.splash_radius)
	if any_arty:
		GameManager.start_attack_position_targeting(radius)
	else:
		GameManager.notify("Select an artillery unit to give an attack-position order.")


func _handle_attack_targeting_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not _is_over_ui(event.position):
			_confirm_attack_position()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			GameManager.cancel_attack_position_targeting()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		GameManager.cancel_attack_position_targeting()


func _confirm_attack_position() -> void:
	var pos     := _ground_point(_mouse())
	var my_team := _my_team()
	var unit_ids: Array = GameManager.selected_units.filter(
		func(u): return is_instance_valid(u) and u.is_alive and u is Artillery and u.team == my_team
	).map(func(u): return u.get_meta("unit_id", -1)).filter(func(id): return id != -1)
	if unit_ids.is_empty(): return
	_rpc_or_local("request_attack_position", [unit_ids, pos])
	GameManager.cancel_attack_position_targeting()


func _on_attack_targeting_mode_changed(active: bool, radius: float) -> void:
	if attack_area_ghost:
		attack_area_ghost.visible = active
		if active:
			attack_area_ghost.set_mode("targeting")
			attack_area_ghost.set_radius(radius)
	if active:
		is_dragging = false
		if selection_box: selection_box.visible = false


func _on_placement_mode_changed(active: bool, building_id: String) -> void:
	if not placement_ghost: return
	_clear_ghost_model()
	if active:
		_build_ghost_model(building_id)
		is_dragging = false
		if selection_box: selection_box.visible = false
	placement_ghost.visible = active
	if placement_grid:
		placement_grid.visible = active
		if not active:
			(placement_grid.mesh as ImmediateMesh).clear_surfaces()


# ---------------------------------------------------------------------------
# Ghost helpers
# ---------------------------------------------------------------------------
func _clear_ghost_model() -> void:
	if placement_ghost is MeshInstance3D: placement_ghost.mesh = null
	for c in placement_ghost.get_children():
		if c.name == "GhostModel": c.queue_free()


func _build_ghost_model(building_id: String) -> void:
	_ghost_footprint = 36.0 * Building.GLOBAL_BUILDING_SCALE
	var path: Variant = BUILDING_SCENES.get(building_id)
	if path == null: _ghost_fallback_box(_ghost_footprint); return
	var packed := load(path) as PackedScene
	if packed == null: _ghost_fallback_box(_ghost_footprint); return
	var inst := packed.instantiate()
	var s    := Building.GLOBAL_BUILDING_SCALE
	if "building_scale" in inst and inst.building_scale > 0.0:
		s = inst.building_scale
	_ghost_footprint = _scene_footprint(inst, s)
	_ghost_extents   = _scene_extents(inst, s)
	var finished     = inst.get_node_or_null("FinishedMesh")
	if finished and _node_has_mesh(finished):
		var holder    := finished.duplicate()
		holder.name    = "GhostModel"
		holder.visible = true
		holder.scale   = Vector3.ONE * s
		placement_ghost.add_child(holder)
	else:
		_ghost_fallback_box(_ghost_footprint)
	inst.queue_free()


func _scene_footprint(inst: Node, s: float) -> float:
	var col  := inst.get_node_or_null("CollisionShape3D")
	var base := 36.0
	if col and col.shape:
		var sh: Variant = col.shape
		if sh is BoxShape3D:        base = maxf(sh.size.x, sh.size.z) * 0.5
		elif sh is CylinderShape3D: base = sh.radius
		elif sh is SphereShape3D:   base = sh.radius
	return base * s


func _scene_extents(inst: Node, s: float) -> Vector2:
	var col := inst.get_node_or_null("CollisionShape3D")
	var hx  := 24.0
	var hz  := 24.0
	if col and col.shape:
		var sh: Variant = col.shape
		if sh is BoxShape3D:        hx = sh.size.x * 0.5; hz = sh.size.z * 0.5
		elif sh is CylinderShape3D: hx = sh.radius;       hz = sh.radius
	return Vector2(hx, hz) * s


func _snap_to_grid(pos: Vector3, ext: Vector2) -> Vector3:
	var g  := grid_cell()
	var mx := roundf((pos.x - ext.x) / g) * g
	var mz := roundf((pos.z - ext.y) / g) * g
	return Vector3(mx + ext.x, pos.y, mz + ext.y)


func _draw_grid(center: Vector3, ok: bool) -> void:
	if placement_grid == null: return
	var im := placement_grid.mesh as ImmediateMesh
	im.clear_surfaces()
	var g  := grid_cell()
	var n  := GRID_RADIUS_CELLS
	var cx := roundf(center.x / g) * g
	var cz := roundf(center.z / g) * g
	var y  := 0.6
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-n, n + 1):
		im.surface_set_color(GRID_LINE_COLOR)
		im.surface_add_vertex(Vector3(cx + i * g, y, cz - n * g))
		im.surface_add_vertex(Vector3(cx + i * g, y, cz + n * g))
		im.surface_add_vertex(Vector3(cx - n * g, y, cz + i * g))
		im.surface_add_vertex(Vector3(cx + n * g, y, cz + i * g))
	var hi := GRID_LINE_COLOR_HI if ok else GHOST_INVALID_COLOR
	var x0 := center.x - _ghost_extents.x; var x1 := center.x + _ghost_extents.x
	var z0 := center.z - _ghost_extents.y; var z1 := center.z + _ghost_extents.y
	var y2 := 0.8
	for seg in [[Vector3(x0,y2,z0),Vector3(x1,y2,z0)],[Vector3(x1,y2,z0),Vector3(x1,y2,z1)],
				[Vector3(x1,y2,z1),Vector3(x0,y2,z1)],[Vector3(x0,y2,z1),Vector3(x0,y2,z0)]]:
		im.surface_set_color(hi)
		im.surface_add_vertex(seg[0]); im.surface_add_vertex(seg[1])
	im.surface_end()


func _node_has_mesh(root: Node) -> bool:
	if root is MeshInstance3D and root.mesh != null: return true
	for c in root.get_children():
		if _node_has_mesh(c): return true
	return false


func _ghost_fallback_box(footprint: float) -> void:
	var mi  := MeshInstance3D.new(); mi.name = "GhostModel"
	var box := BoxMesh.new()
	var h   := maxf(footprint * 1.2, 40.0)
	box.size = Vector3(footprint * 2.0, h, footprint * 2.0)
	mi.mesh  = box; mi.position.y = h * 0.5
	placement_ghost.add_child(mi)


func _overlaps_existing_building(world_pos: Vector3, ext: Vector2, exclude = null) -> bool:
	var eps := 1.0
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b == exclude: continue
		var be := Vector2(24, 24)
		if b.has_method("footprint_extents"): be = b.footprint_extents()
		if absf(world_pos.x - b.global_position.x) < ext.x + be.x - eps \
		and absf(world_pos.z - b.global_position.z) < ext.y + be.y - eps:
			return true
	return false


func _tint_ghost(root: Node, ok: bool) -> void:
	if root is GeometryInstance3D:
		var m          := StandardMaterial3D.new()
		m.albedo_color  = GHOST_VALID_COLOR if ok else GHOST_INVALID_COLOR
		m.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
		root.material_override = m
	for c in root.get_children(): _tint_ghost(c, ok)


func _is_over_ui(screen_pos: Vector2) -> bool:
	var ui := get_tree().current_scene.get_node_or_null("UI")
	if ui == null: return false
	return _ui_blocks(ui, screen_pos)


func _ui_blocks(node: Node, screen_pos: Vector2) -> bool:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if c.visible and c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
					and c.get_global_rect().has_point(screen_pos): return true
			if c.visible and _ui_blocks(c, screen_pos): return true
		elif _ui_blocks(child, screen_pos): return true
	return false


func _my_team() -> int:
	var nm := get_node_or_null("/root/NetworkManager")
	if nm == null:
		nm = get_node_or_null("/root/network_manager")
	if nm and nm.has_method("my_team"):
		return nm.my_team()
	return 0
