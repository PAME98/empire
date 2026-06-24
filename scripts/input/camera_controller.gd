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

## Every placeable building's scene. MUST cover every id in build_menu.CATALOG
## and GameManager.COSTS, or _confirm_placement() silently cancels and nothing
## spawns (which is why most buildings appeared to "do nothing").
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

## Buildings that are meant to sit ON a mountain deposit, so they skip the
## "blocked by terrain" check (and the ghost stays green over mountains).
const DEPOSIT_BUILDINGS := ["quarry", "mine"]

const GHOST_VALID_COLOR   := Color(0.2, 0.9, 0.2, 0.45)
const GHOST_INVALID_COLOR := Color(0.9, 0.15, 0.15, 0.45)

## Build grid. One cell = one kit tile at the global building scale, so building
## footprints (whole numbers of tiles) line up exactly with cells and tile the
## raster edge-to-edge. The grid the player sees and snaps to.
const KIT_UNIT := 14.0
const GRID_RADIUS_CELLS := 12          # how many cells around the cursor to draw
const GRID_LINE_COLOR := Color(0.95, 0.95, 1.0, 0.20)
const GRID_LINE_COLOR_HI := Color(0.3, 0.95, 0.4, 0.6)

## Footprint of the building currently being placed (cached when the ghost is
## built, so the per-frame snap/overlap test is cheap).
var _ghost_footprint: float = 36.0
var _ghost_extents: Vector2 = Vector2(24, 24)
var placement_grid: MeshInstance3D = null


func grid_cell() -> float:
	return KIT_UNIT * Building.GLOBAL_BUILDING_SCALE


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

	_build_placement_grid()

	_map_size = MapSettings.map_size
	_apply_zoom()


## A flat grid overlay (little squares) shown on the ground while placing.
func _build_placement_grid() -> void:
	placement_grid = MeshInstance3D.new()
	placement_grid.name = "PlacementGrid"
	placement_grid.mesh = ImmediateMesh.new()
	placement_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	placement_grid.material_override = m
	placement_grid.visible = false
	get_tree().current_scene.add_child.call_deferred(placement_grid)


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
		var raw := _ground_point(_mouse())
		var gp := _snap_to_grid(raw, _ghost_extents)
		placement_ghost.global_position = gp
		var terrain_ok := GameManager.placement_building_id in DEPOSIT_BUILDINGS \
			or GameManager.can_place_building_at(gp, _ghost_footprint)
		# Footprints may touch (sit in adjacent cells) but not overlap.
		var ok := terrain_ok and not _overlaps_existing_building(gp, _ghost_extents)
		_tint_ghost(placement_ghost, ok)
		_draw_grid(gp, ok)

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

	# Instantiate first so we can measure the real footprint (its _ready applies
	# the size scale and registers it in the "buildings" group).
	var building = load(scene_path).instantiate()
	get_tree().current_scene.get_node("Buildings").add_child(building)

	var my_ext := Vector2(24, 24) * Building.GLOBAL_BUILDING_SCALE
	if building.has_method("footprint_extents"):
		my_ext = building.footprint_extents()
	# Snap to the same grid the ghost previews on.
	var placement_pos := _snap_to_grid(_ground_point(_mouse()), my_ext)
	building.global_position = placement_pos

	var my_r := 36.0 * Building.GLOBAL_BUILDING_SCALE
	if building.has_method("footprint_radius"):
		my_r = building.footprint_radius()

	# Quarry/mine are deliberately exempt from the TERRAIN check — they're
	# SUPPOSED to sit on a mountain deposit (bound below). They are NOT exempt
	# from the building-overlap check.
	var exempt_from_terrain_check :Variant = building_id in DEPOSIT_BUILDINGS
	if not exempt_from_terrain_check and not GameManager.can_place_building_at(placement_pos, my_r):
		GameManager.notify("Can't build there — blocked by terrain (river, mountain, or tree).")
		building.queue_free()
		GameManager.cancel_building_placement()
		return

	# Footprints may touch but not overlap.
	if _overlaps_existing_building(placement_pos, my_ext, building):
		GameManager.notify("Can't build there — another building is in the way.")
		building.queue_free()
		GameManager.cancel_building_placement()
		return

	GameManager.clear_trees_at(placement_pos, my_r)

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


# ---------------------------------------------------------------------------
# Placement ghost — now shows the actual building model at its real size
# ---------------------------------------------------------------------------
func _on_placement_mode_changed(active: bool, building_id: String) -> void:
	if not placement_ghost:
		return
	_clear_ghost_model()
	if active:
		_build_ghost_model(building_id)
		is_dragging = false
		if selection_box:
			selection_box.visible = false
	placement_ghost.visible = active
	if placement_grid:
		placement_grid.visible = active
		if not active:
			(placement_grid.mesh as ImmediateMesh).clear_surfaces()


## Remove any previously-built ghost model and hide the default box mesh.
func _clear_ghost_model() -> void:
	if placement_ghost is MeshInstance3D:
		placement_ghost.mesh = null
	for c in placement_ghost.get_children():
		if c.name == "GhostModel":
			c.queue_free()


## Instance the building's scene, lift out its FinishedMesh, and parent a copy
## under the ghost. Using the real model means the ghost is automatically the
## right shape and size. Falls back to a footprint-sized box if the scene has no
## FinishedMesh OR its FinishedMesh contains no actual mesh (e.g. a half-built
## scene), so every building always gets a visible ghost.
func _build_ghost_model(building_id: String) -> void:
	_ghost_footprint = 36.0 * Building.GLOBAL_BUILDING_SCALE
	var path = BUILDING_SCENES.get(building_id)
	if path == null:
		_ghost_fallback_box(_ghost_footprint)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_ghost_fallback_box(_ghost_footprint)
		return
	var inst := packed.instantiate()

	# Work out the size this building will actually be (its scene _ready hasn't
	# run, so read the scene's collision shape and the scale we will apply).
	var s : float = Building.GLOBAL_BUILDING_SCALE
	if "building_scale" in inst and inst.building_scale > 0.0:
		s = inst.building_scale
	_ghost_footprint = _scene_footprint(inst, s)
	_ghost_extents = _scene_extents(inst, s)

	var finished = inst.get_node_or_null("FinishedMesh")
	if finished and _node_has_mesh(finished):
		var holder := finished.duplicate()
		holder.name = "GhostModel"
		holder.visible = true
		holder.scale = Vector3.ONE * s   # FinishedMesh is scale 1 in every scene
		placement_ghost.add_child(holder)
	else:
		_ghost_fallback_box(_ghost_footprint)
	inst.queue_free()


## Footprint radius for a freshly-instanced (not-yet-in-tree) building scene.
func _scene_footprint(inst: Node, s: float) -> float:
	var col = inst.get_node_or_null("CollisionShape3D")
	var base := 36.0
	if col and col.shape:
		var sh = col.shape
		if sh is BoxShape3D:
			base = maxf(sh.size.x, sh.size.z) * 0.5
		elif sh is CylinderShape3D:
			base = sh.radius
		elif sh is SphereShape3D:
			base = sh.radius
	return base * s


## Footprint half-extents (x, z) for a freshly-instanced building scene.
func _scene_extents(inst: Node, s: float) -> Vector2:
	var col = inst.get_node_or_null("CollisionShape3D")
	var hx := 24.0
	var hz := 24.0
	if col and col.shape:
		var sh = col.shape
		if sh is BoxShape3D:
			hx = sh.size.x * 0.5
			hz = sh.size.z * 0.5
		elif sh is CylinderShape3D:
			hx = sh.radius
			hz = sh.radius
	return Vector2(hx, hz) * s


# ---------------------------------------------------------------------------
# Grid snapping + overlay
# ---------------------------------------------------------------------------
## Snap a world position so the building's footprint aligns to grid cells: the
## min corner lands on a grid line, so footprints that are whole numbers of
## cells tile the raster edge-to-edge.
func _snap_to_grid(pos: Vector3, ext: Vector2) -> Vector3:
	var g := grid_cell()
	var min_x := pos.x - ext.x
	var min_z := pos.z - ext.y
	min_x = roundf(min_x / g) * g
	min_z = roundf(min_z / g) * g
	return Vector3(min_x + ext.x, pos.y, min_z + ext.y)


## Rebuild the little-squares overlay around the snapped position. Cheap enough
## to redo each frame (a few hundred short line segments).
func _draw_grid(center: Vector3, ok: bool) -> void:
	if placement_grid == null:
		return
	var im := placement_grid.mesh as ImmediateMesh
	im.clear_surfaces()
	var g := grid_cell()
	var n := GRID_RADIUS_CELLS
	# Anchor lines to the same lattice the snap uses (multiples of g).
	var cx := roundf(center.x / g) * g
	var cz := roundf(center.z / g) * g
	var y := 0.6
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-n, n + 1):
		var x := cx + i * g
		im.surface_set_color(GRID_LINE_COLOR)
		im.surface_add_vertex(Vector3(x, y, cz - n * g))
		im.surface_add_vertex(Vector3(x, y, cz + n * g))
		var z := cz + i * g
		im.surface_add_vertex(Vector3(cx - n * g, y, z))
		im.surface_add_vertex(Vector3(cx + n * g, y, z))
	# Highlight the footprint the building would occupy.
	var hi := GRID_LINE_COLOR_HI if ok else GHOST_INVALID_COLOR
	var x0 := center.x - _ghost_extents.x
	var x1 := center.x + _ghost_extents.x
	var z0 := center.z - _ghost_extents.y
	var z1 := center.z + _ghost_extents.y
	var y2 := 0.8
	for seg in [[Vector3(x0,y2,z0),Vector3(x1,y2,z0)], [Vector3(x1,y2,z0),Vector3(x1,y2,z1)],
				[Vector3(x1,y2,z1),Vector3(x0,y2,z1)], [Vector3(x0,y2,z1),Vector3(x0,y2,z0)]]:
		im.surface_set_color(hi)
		im.surface_add_vertex(seg[0])
		im.surface_add_vertex(seg[1])
	im.surface_end()


func _node_has_mesh(root: Node) -> bool:
	if root is MeshInstance3D and root.mesh != null:
		return true
	for c in root.get_children():
		if _node_has_mesh(c):
			return true
	return false


## A grounded translucent box sized to the footprint, used when a scene has no
## usable model to preview.
func _ghost_fallback_box(footprint: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "GhostModel"
	var box := BoxMesh.new()
	var h := maxf(footprint * 1.2, 40.0)
	box.size = Vector3(footprint * 2.0, h, footprint * 2.0)
	mi.mesh = box
	mi.position.y = h * 0.5
	placement_ghost.add_child(mi)


## True if the candidate footprint would OVERLAP an existing building. Footprints
## that only touch (share an edge in adjacent cells) are allowed, so the grid
## tiles cleanly without buildings "blocking" their neighbours.
func _overlaps_existing_building(world_pos: Vector3, ext: Vector2, exclude :Variant = null) -> bool:
	var eps := 1.0   # shrink so exact edge-touching is not counted as overlap
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b == exclude:
			continue
		var be := Vector2(24, 24)
		if b.has_method("footprint_extents"):
			be = b.footprint_extents()
		var dx := absf(world_pos.x - b.global_position.x)
		var dz := absf(world_pos.z - b.global_position.z)
		if dx < ext.x + be.x - eps and dz < ext.y + be.y - eps:
			return true
	return false


## Apply the valid/invalid tint to every mesh under the ghost (box or model).
func _tint_ghost(root: Node, ok: bool) -> void:
	if root is GeometryInstance3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = GHOST_VALID_COLOR if ok else GHOST_INVALID_COLOR
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		root.material_override = m
	for c in root.get_children():
		_tint_ghost(c, ok)


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
	return _ui_blocks(ui, screen_pos)


## Recursively true if any visible Control under `node` that isn't click-through
## contains the point. Future-proof: new panels/buttons are picked up
## automatically without editing a hardcoded list.
func _ui_blocks(node: Node, screen_pos: Vector2) -> bool:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if c.visible and c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
					and c.get_global_rect().has_point(screen_pos):
				return true
			if c.visible and _ui_blocks(c, screen_pos):
				return true
		elif _ui_blocks(child, screen_pos):
			return true
	return false
