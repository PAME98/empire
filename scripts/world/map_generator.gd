extends Node
## Procedurally generates a map, then enters town-center placement mode.
##
## STARTUP SEQUENCE:
##   1. Clear all pre-placed buildings, units, and hand-placed trees from
##      main.tscn (VillageCenter, House, Citizens, Trees in Resources).
##   2. Generate rivers → mountains → forests (procedurally).
##   3. Bake navigation mesh.
##   4. Enter placement mode: PlacementGhost follows mouse, green = valid,
##      red = blocked. Left-click places VillageCenter + 5 citizens.
##
## RIVER APPROACH:
##   Catmull-Rom spline with a mild single-pass meander (one gentle lateral
##   offset per control point, alternating side). No secondary sine wave —
##   that caused the artificial snake look. The river just curves naturally
##   from edge to edge with 3-5 bends. Overlap is prevented by storing dense
##   spline samples and checking all of them during mountain/tree placement.

const VILLAGE_CENTER_SCENE := "res://scenes/buildings/village_center.tscn"
const CITIZEN_SCENE        := "res://scenes/units/citizen.tscn"
const TREE_SCENE           := "res://scenes/world/tree.tscn"
const MOUNTAIN_SCENE       := "res://scenes/world/mountain.tscn"

# ---------------------------------------------------------------------------
# Forests
# ---------------------------------------------------------------------------
const FOREST_CLUSTERS_PER_MPX := 12.0
const TREES_PER_CLUSTER_MIN   := 5
const TREES_PER_CLUSTER_MAX   := 14
const FOREST_SPREAD           := 90.0
const TREE_RADIUS             := 18.0

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------
const NAV_AGENT_RADIUS := 10.0
const MIN_OBSTACLE_GAP := NAV_AGENT_RADIUS * 2.0 + 8.0

# ---------------------------------------------------------------------------
# Mountains
# ---------------------------------------------------------------------------
const MOUNTAIN_RANGES_PER_MPX := 4.0
const MOUNTAINS_PER_RANGE_MIN := 6
const MOUNTAINS_PER_RANGE_MAX := 16
const MOUNTAIN_SPREAD         := 66.0
const MOUNTAIN_STONE_MIN      := 400
const MOUNTAIN_STONE_MAX      := 900
const IRON_MOUNTAIN_CHANCE    := 0.35
const MOUNTAIN_IRON_MIN       := 150
const MOUNTAIN_IRON_MAX       := 450
const MOUNTAIN_RADIUS         := 45.0

# ---------------------------------------------------------------------------
# Rivers
# ---------------------------------------------------------------------------
const RIVER_COUNT_MIN    := 1
const RIVER_COUNT_MAX    := 2   # reduced from 3 — rivers are wide, 2 is plenty

const RIVER_WIDTH_MIN    := 60.0
const RIVER_WIDTH_MAX    := 140.0
const RIVER_TAPER_RATIO  := 0.42  # ends taper to this fraction of peak width

## Number of interior bend points. 3-4 gives natural single-direction curves
## without the snake look. Each point alternates left/right of the main axis.
const RIVER_CONTROL_POINTS := 4

## Max lateral displacement per control point, as fraction of shorter map axis.
## 0.16 gives gentle bends. Raise only if you want more dramatic curves.
const RIVER_WANDER       := 0.16

## Spline samples for mesh + collision. 100 is smooth without being heavy.
const RIVER_SAMPLES      := 100

## Store every Nth sample in _river_points for obstacle rejection.
## Lower = more accurate rejection boundary.
const RIVER_REJECT_STEP  := 2

## Clearance kept between rivers and any other obstacle.
const RIVER_CLEAR_RADIUS := RIVER_WIDTH_MAX * 0.5 + MIN_OBSTACLE_GAP

## How far apart two rivers must be at their closest sample points.
## Prevents rivers merging visually or spawning right next to each other.
const RIVER_MIN_SEPARATION := RIVER_WIDTH_MAX + 80.0

const RIVER_Y := 0.3   # water surface height; raise slightly if it sinks into ground

# ---------------------------------------------------------------------------
# Ground
# ---------------------------------------------------------------------------
const GROUND_TILE_SCENE := "res://assets/kenney/nature/models/ground_grass.glb"
const GROUND_TILE_SCALE := 100.0

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------
## Radius cleared around the town center placement spot.
const SPAWN_SAFE_RADIUS := 200.0
## Citizens spawn in a ring at this radius from the town center.
const CITIZEN_SPAWN_RADIUS := 90.0
const CITIZEN_COUNT        := 5

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------
var _rng              := RandomNumberGenerator.new()
var _map_rect         : Rect2
var _center           : Vector2

## Dense river sample positions — used for accurate obstacle rejection.
var _river_samples_all : Array[Vector2] = []   # every sample from every river
var _river_points      : Array[Vector2] = []   # subsampled (every RIVER_REJECT_STEP)
var _mountain_points   : Array[Vector2] = []
var _tree_points       : Array[Vector2] = []

var _placement_valid  : bool = false
var _ghost            : MeshInstance3D = null


func _ready() -> void:
	_rng.randomize()
	var size: Vector2 = MapSettings.map_size
	_map_rect = Rect2(Vector2.ZERO, size)
	_center   = size * 0.5

	_clear_prebuilt_nodes()
	_resize_ground(size)
	_generate_rivers()
	_generate_mountain_ranges()
	_generate_forests()

	await _bake_navigation()
	_begin_placement()


# ---------------------------------------------------------------------------
# Clear pre-placed nodes from main.tscn
# ---------------------------------------------------------------------------
func _clear_prebuilt_nodes() -> void:
	var scene := get_tree().current_scene

	# Remove all children of Buildings (VillageCenter, House, …)
	var buildings := scene.get_node_or_null("Buildings")
	if buildings:
		for child in buildings.get_children():
			child.queue_free()

	# Remove all children of Units (pre-placed citizens)
	var units := scene.get_node_or_null("Units")
	if units:
		for child in units.get_children():
			child.queue_free()

	# Remove hand-placed trees/resources (MapGenerator will re-add them procedurally)
	var resources := scene.get_node_or_null("Resources")
	if resources:
		for child in resources.get_children():
			child.queue_free()


# ---------------------------------------------------------------------------
# Ground
# ---------------------------------------------------------------------------
func _resize_ground(size: Vector2) -> void:
	var scene  := get_tree().current_scene
	var ground := scene.get_node_or_null("Ground")
	if ground == null:
		push_warning("MapGenerator: no Ground node found.")
		return
	if ground is MeshInstance3D:
		ground.mesh    = null
		ground.visible = false

	var packed := load(GROUND_TILE_SCENE) as PackedScene
	if packed == null:
		push_warning("MapGenerator: could not load " + GROUND_TILE_SCENE)
		return

	var cols      := int(ceil(size.x / GROUND_TILE_SCALE))
	var rows      := int(ceil(size.y / GROUND_TILE_SCALE))
	var container := Node3D.new()
	container.name = "GroundTiles"

	for row in rows:
		for col in cols:
			var tile: Node3D = packed.instantiate()
			tile.scale    = Vector3.ONE * GROUND_TILE_SCALE
			tile.position = Vector3(
				col * GROUND_TILE_SCALE + GROUND_TILE_SCALE * 0.5,
				-0.1,
				row * GROUND_TILE_SCALE + GROUND_TILE_SCALE * 0.5
			)
			container.add_child(tile)

	scene.add_child.call_deferred(container)


# ---------------------------------------------------------------------------
# Rivers
# ---------------------------------------------------------------------------
func _generate_rivers() -> void:
	var resources := _get_or_create("Resources")
	var count     := _rng.randi_range(RIVER_COUNT_MIN, RIVER_COUNT_MAX)
	for _i in count:
		var base_width := _rng.randf_range(RIVER_WIDTH_MIN, RIVER_WIDTH_MAX)
		var ctrl       := _make_river_control_points()
		if ctrl.is_empty():
			continue
		_place_river(ctrl, base_width, resources)


## Builds control points for one river. Returns empty array if no valid
## pair of edges can be found far enough from existing rivers.
func _make_river_control_points() -> Array[Vector2]:
	# Try a few random edge pairs; reject if the midpoint is too close to
	# an existing river (rough early-rejection before full sample check).
	for _attempt in 8:
		var edge_a := _rng.randi() % 4
		var edge_b := (edge_a + 1 + _rng.randi() % 3) % 4
		var p_start := _point_on_edge(edge_a)
		var p_end   := _point_on_edge(edge_b)
		var midpt   := (p_start + p_end) * 0.5

		# Early-reject if midpoint lands on an existing river.
		if _overlaps_river_raw(midpt, RIVER_MIN_SEPARATION):
			continue

		# Build alternating-side control points for a natural single-curve path.
		var flow := (p_end - p_start).normalized()
		var perp := Vector2(-flow.y, flow.x)
		var max_d := minf(_map_rect.size.x, _map_rect.size.y) * RIVER_WANDER

		var pts: Array[Vector2] = [p_start]
		var sign := 1.0 if _rng.randf() > 0.5 else -1.0
		for i in RIVER_CONTROL_POINTS:
			var t    := (i + 1.0) / (RIVER_CONTROL_POINTS + 1.0)
			var base := p_start.lerp(p_end, t)
			# Scale displacement by a bell so ends stay near the edge entry points.
			var bell := sin(PI * t)
			var disp := _rng.randf_range(max_d * 0.5, max_d) * sign * bell
			sign = -sign
			pts.append(base + perp * disp)
		pts.append(p_end)
		return pts

	return []


func _point_on_edge(edge: int) -> Vector2:
	var s := _map_rect.size
	match edge:
		0: return Vector2(_rng.randf_range(s.x * 0.15, s.x * 0.85), 0.0)
		1: return Vector2(_rng.randf_range(s.x * 0.15, s.x * 0.85), s.y)
		2: return Vector2(0.0, _rng.randf_range(s.y * 0.15, s.y * 0.85))
		_: return Vector2(s.x,  _rng.randf_range(s.y * 0.15, s.y * 0.85))


func _catmull_rom(pts: Array[Vector2], t: float) -> Vector2:
	var n   := pts.size()
	var seg := clampi(int(t * (n - 1)), 0, n - 2)
	var lt  := t * (n - 1) - seg
	var p0  := pts[maxi(seg - 1, 0)]
	var p1  := pts[seg]
	var p2  := pts[mini(seg + 1, n - 1)]
	var p3  := pts[mini(seg + 2, n - 1)]
	var lt2 := lt * lt
	var lt3 := lt2 * lt
	return 0.5 * (
		2.0 * p1 +
		(-p0 + p2) * lt +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * lt2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * lt3
	)


func _river_width_at(t: float, base: float) -> float:
	return base * (RIVER_TAPER_RATIO + (1.0 - RIVER_TAPER_RATIO) * sin(PI * t))


func _place_river(ctrl: Array[Vector2], base_width: float, resources: Node3D) -> void:
	var container    := Node3D.new()
	container.name    = "River"
	var local_samples : Array[Vector2] = []

	# Sample the spline.
	for i in (RIVER_SAMPLES + 1):
		var t   := float(i) / RIVER_SAMPLES
		var pos := _catmull_rom(ctrl, t)
		pos.x    = clampf(pos.x, _map_rect.position.x, _map_rect.end.x)
		pos.y    = clampf(pos.y, _map_rect.position.y, _map_rect.end.y)
		local_samples.append(pos)
		_river_samples_all.append(pos)
		if i % RIVER_REJECT_STEP == 0:
			_river_points.append(pos)

	# Ribbon mesh.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in local_samples.size():
		var t    := float(i) / (local_samples.size() - 1)
		var pos  := local_samples[i]
		var half := _river_width_at(t, base_width) * 0.5

		var tangent: Vector2
		if i == 0:
			tangent = (local_samples[1] - local_samples[0]).normalized()
		elif i == local_samples.size() - 1:
			tangent = (local_samples[i] - local_samples[i - 1]).normalized()
		else:
			tangent = (local_samples[i + 1] - local_samples[i - 1]).normalized()
		var perp := Vector2(-tangent.y, tangent.x)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, t))
		st.add_vertex(Vector3(pos.x - perp.x * half, RIVER_Y, pos.y - perp.y * half))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, t))
		st.add_vertex(Vector3(pos.x + perp.x * half, RIVER_Y, pos.y + perp.y * half))

	var vc := local_samples.size() * 2
	for i in range(0, vc - 2, 2):
		st.add_index(i);     st.add_index(i + 1); st.add_index(i + 2)
		st.add_index(i + 1); st.add_index(i + 3); st.add_index(i + 2)

	var mi              := MeshInstance3D.new()
	mi.mesh              = st.commit()
	mi.material_override = _make_water_material()
	container.add_child(mi)

	# Collision chain.
	for i in range(1, local_samples.size()):
		var w := (_river_width_at(float(i-1)/local_samples.size(), base_width) +
				  _river_width_at(float(i)  /local_samples.size(), base_width)) * 0.5
		container.add_child(RiverSegment.build_segment(
			_to3(local_samples[i - 1]), _to3(local_samples[i]), w))

	resources.add_child(container)


func _make_water_material() -> ShaderMaterial:
	# Clean, readable water: two scrolling diagonal ripple layers blended
	# together, darker in the centre, foam at the banks. No normal hacks —
	# just pure colour so it reads well from the isometric camera distance.
	var code := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec4  deep_col    : source_color = vec4(0.07, 0.22, 0.50, 0.94);
uniform vec4  shallow_col : source_color = vec4(0.22, 0.54, 0.78, 0.86);
uniform vec4  foam_col    : source_color = vec4(0.86, 0.95, 1.00, 0.80);
uniform float speed       : hint_range(0.1, 2.0) = 0.45;
uniform float scale       : hint_range(0.5, 6.0) = 1.8;
uniform float foam_w      : hint_range(0.0, 0.35) = 0.13;

void fragment() {
	vec2  uv   = UV;
	float t    = TIME * speed;

	// Two diagonal ripple layers at different angles and speeds.
	float r1 = sin((uv.y * scale * 6.0 + uv.x * scale * 1.5) + t * 2.0) * 0.5 + 0.5;
	float r2 = sin((uv.y * scale * 4.2 - uv.x * scale * 2.8) - t * 1.3 + 2.0) * 0.5 + 0.5;
	float rip = r1 * 0.6 + r2 * 0.4;

	// Blend deep (centre) → shallow (bank) based on distance from uv.x = 0.5.
	float bank  = abs(uv.x - 0.5) * 2.0;
	vec4  water = mix(deep_col, shallow_col, pow(bank, 1.6));

	// Gentle highlight from ripples.
	water.rgb  += rip * 0.10 * (1.0 - bank);

	// Foam band — animated softly along the bank edge.
	float ft   = smoothstep(foam_w, 0.0, bank - (1.0 - foam_w * 2.0));
	ft        *= 0.6 + 0.4 * sin(uv.y * 6.0 * scale + t * 1.5);
	vec4  col  = mix(water, foam_col, clamp(ft, 0.0, 1.0));

	ALBEDO    = col.rgb;
	ALPHA     = col.a;
	ROUGHNESS = 0.10;
	METALLIC  = 0.0;
	SPECULAR  = 0.65;
}
"""
	var sh     := Shader.new()
	sh.code     = code
	var mat    := ShaderMaterial.new()
	mat.shader  = sh
	return mat


# ---------------------------------------------------------------------------
# Mountains
# ---------------------------------------------------------------------------
func _generate_mountain_ranges() -> void:
	var resources   := _get_or_create("Resources")
	var scene_pack  := load(MOUNTAIN_SCENE)
	if scene_pack == null:
		push_warning("MapGenerator: could not load " + MOUNTAIN_SCENE); return

	var area_mpx := (_map_rect.size.x * _map_rect.size.y) / 1_000_000.0
	var ranges   : int = max(int(round(area_mpx * MOUNTAIN_RANGES_PER_MPX)), 1)

	for _r in ranges:
		var centre := _random_map_point(0.0)
		var dir    := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		var perp   := dir.orthogonal()
		var count  := _rng.randi_range(MOUNTAINS_PER_RANGE_MIN, MOUNTAINS_PER_RANGE_MAX)

		for _n in count:
			var pos := centre \
				+ dir  * _rng.randf_range(-1.0, 1.0) * MOUNTAIN_SPREAD * 2.4 \
				+ perp * _rng.randf_range(-0.45, 0.45) * MOUNTAIN_SPREAD
			if not _map_rect.has_point(pos): continue
			if _overlaps_river(pos, MOUNTAIN_RADIUS):    continue
			if _overlaps_mountain(pos, MOUNTAIN_RADIUS): continue

			var m: Node3D = scene_pack.instantiate()
			resources.add_child(m)
			m.global_position = _to3(pos)
			m.stone_amount = _rng.randi_range(MOUNTAIN_STONE_MIN, MOUNTAIN_STONE_MAX)
			m.iron_amount  = _rng.randi_range(MOUNTAIN_IRON_MIN, MOUNTAIN_IRON_MAX) \
							 if _rng.randf() < IRON_MOUNTAIN_CHANCE else 0
			_mountain_points.append(pos)


# ---------------------------------------------------------------------------
# Forests
# ---------------------------------------------------------------------------
func _generate_forests() -> void:
	var resources  := _get_or_create("Resources")
	var scene_pack := load(TREE_SCENE)
	if scene_pack == null:
		push_warning("MapGenerator: could not load " + TREE_SCENE); return

	var area_mpx := (_map_rect.size.x * _map_rect.size.y) / 1_000_000.0
	var clusters : int = max(int(round(area_mpx * FOREST_CLUSTERS_PER_MPX)), 2)

	for _c in clusters:
		var centre := _random_map_point(0.0)
		var count  := _rng.randi_range(TREES_PER_CLUSTER_MIN, TREES_PER_CLUSTER_MAX)
		for _n in count:
			var pos := centre + Vector2(
				_rng.randf_range(-FOREST_SPREAD, FOREST_SPREAD),
				_rng.randf_range(-FOREST_SPREAD, FOREST_SPREAD)
			)
			if not _map_rect.has_point(pos): continue
			if _overlaps_river(pos, TREE_RADIUS):    continue
			if _overlaps_mountain(pos, TREE_RADIUS): continue
			if _overlaps_tree(pos, TREE_RADIUS):     continue

			var node: Node3D = scene_pack.instantiate()
			resources.add_child(node)
			node.global_position = _to3(pos)
			_tree_points.append(pos)


# ---------------------------------------------------------------------------
# Overlap helpers
# ---------------------------------------------------------------------------

## Raw check against all dense river samples (used for river-vs-river separation).
func _overlaps_river_raw(pos: Vector2, threshold: float) -> bool:
	for p in _river_samples_all:
		if pos.distance_to(p) < threshold:
			return true
	return false


## Check used by mountains and trees — against the subsampled rejection grid.
func _overlaps_river(pos: Vector2, clearance: float) -> bool:
	var threshold := RIVER_CLEAR_RADIUS + clearance
	for p in _river_points:
		if pos.distance_to(p) < threshold:
			return true
	return false


func _overlaps_mountain(pos: Vector2, clearance: float) -> bool:
	var threshold := MOUNTAIN_RADIUS + clearance + MIN_OBSTACLE_GAP
	for p in _mountain_points:
		if pos.distance_to(p) < threshold:
			return true
	return false


func _overlaps_tree(pos: Vector2, clearance: float) -> bool:
	var threshold := TREE_RADIUS + clearance + MIN_OBSTACLE_GAP
	for p in _tree_points:
		if pos.distance_to(p) < threshold:
			return true
	return false


## Used by placement validation — checks rivers, mountains, and trees.
func _placement_blocked(pos: Vector2) -> bool:
	return (
		_overlaps_river(pos, SPAWN_SAFE_RADIUS) or
		_overlaps_mountain(pos, SPAWN_SAFE_RADIUS) or
		_overlaps_tree(pos, SPAWN_SAFE_RADIUS)
	)


# ---------------------------------------------------------------------------
# Town center placement
# ---------------------------------------------------------------------------
func _begin_placement() -> void:
	# Reuse the PlacementGhost MeshInstance3D already in main.tscn.
	var scene := get_tree().current_scene
	_ghost = scene.get_node_or_null("PlacementGhost") as MeshInstance3D
	if _ghost == null:
		push_warning("MapGenerator: PlacementGhost node not found in scene.")
		return

	# Resize ghost to match VillageCenter footprint (84x55x84).
	var box      := BoxMesh.new()
	box.size      = Vector3(84, 55, 84)
	_ghost.mesh   = box
	_ghost.visible = true

	# Make a fresh valid/invalid material pair.
	var mat             := StandardMaterial3D.new()
	mat.albedo_color     = Color(0.2, 0.9, 0.2, 0.45)
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = mat

	set_process(true)
	set_process_input(true)


func _process(_delta: float) -> void:
	if _ghost == null or not _ghost.visible:
		return

	var wp := _mouse_to_ground()
	if wp == null:
		return

	var pos2 := Vector2(wp.x, wp.z)
	_placement_valid = not _placement_blocked(pos2)

	_ghost.position = Vector3(wp.x, 27.5, wp.z)  # 27.5 = half of VillageCenter height

	var mat := _ghost.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.2, 0.9, 0.2, 0.45) if _placement_valid \
					 else Color(0.9, 0.15, 0.15, 0.45)


func _input(event: InputEvent) -> void:
	if _ghost == null or not _ghost.visible:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and _placement_valid:
		_confirm_placement()


func _confirm_placement() -> void:
	var wp := _mouse_to_ground()
	if wp == null:
		return

	_ghost.visible = false
	set_process(false)
	set_process_input(false)

	var place_pos := Vector3(wp.x, 0.0, wp.z)

	# Spawn VillageCenter.
	var vc_pack := load(VILLAGE_CENTER_SCENE) as PackedScene
	if vc_pack:
		var vc : Node3D = vc_pack.instantiate()
		_get_or_create("Buildings").add_child(vc)
		vc.global_position = place_pos
	else:
		push_warning("MapGenerator: could not load " + VILLAGE_CENTER_SCENE)

	# Spawn 5 citizens in a ring around it.
	var cit_pack := load(CITIZEN_SCENE) as PackedScene
	if cit_pack:
		var units := _get_or_create("Units")
		for i in CITIZEN_COUNT:
			var angle  := (TAU / CITIZEN_COUNT) * i
			var offset := Vector3(cos(angle), 0.0, sin(angle)) * CITIZEN_SPAWN_RADIUS
			var cit    : Node3D = cit_pack.instantiate()
			units.add_child(cit)
			cit.global_position = place_pos + offset
	else:
		push_warning("MapGenerator: could not load " + CITIZEN_SCENE)

	rebake_navigation()


## Casts a ray from the mouse through Camera3D onto the Y=0 plane.
func _mouse_to_ground() -> Vector3:
	var scene  := get_tree().current_scene
	# Camera is a Node3D wrapper; the actual Camera3D is its child.
	var cam    := scene.get_node_or_null("Camera/Camera3D") as Camera3D
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO

	var mpos       := get_viewport().get_mouse_position()
	var ray_origin := cam.project_ray_origin(mpos)
	var ray_dir    := cam.project_ray_normal(mpos)
	if absf(ray_dir.y) < 0.0001:
		return Vector3.ZERO
	var t := -ray_origin.y / ray_dir.y
	return ray_origin + ray_dir * t


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------
var _rebake_pending : bool = false

func rebake_navigation() -> void:
	if _rebake_pending: return
	_rebake_pending = true
	_deferred_rebake()

func _deferred_rebake() -> void:
	await get_tree().process_frame
	_rebake_pending = false
	await _bake_navigation()

func _ensure_nav_floor() -> void:
	var scene := get_tree().current_scene
	if scene.get_node_or_null("NavFloor") != null: return
	var body           := StaticBody3D.new()
	body.name           = "NavFloor"
	body.collision_layer = 1
	body.collision_mask  = 0
	var shape  := BoxShape3D.new()
	shape.size  = Vector3(_map_rect.size.x + 200.0, 2.0, _map_rect.size.y + 200.0)
	var col    := CollisionShape3D.new()
	col.shape   = shape
	col.position = Vector3(_center.x, -1.0, _center.y)
	body.add_child(col)
	scene.add_child.call_deferred(body)

func _bake_navigation() -> void:
	var scene       := get_tree().current_scene
	var nav         := scene.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var created_new := false
	if nav == null:
		nav             = NavigationRegion3D.new()
		nav.name        = "NavigationRegion3D"
		created_new     = true
		scene.add_child.call_deferred(nav)
	nav.position = Vector3.ZERO
	_ensure_nav_floor()

	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius    = NAV_AGENT_RADIUS
	nm.agent_height    = 30.0
	nm.agent_max_climb = 4.0
	nm.cell_size       = 4.0
	nm.cell_height     = 4.0
	nm.filter_baking_aabb = AABB(
		Vector3(_map_rect.position.x, -50.0, _map_rect.position.y),
		Vector3(_map_rect.size.x, 200.0, _map_rect.size.y)
	)
	nav.navigation_mesh = nm

	await get_tree().process_frame
	await get_tree().process_frame
	if created_new and not nav.is_inside_tree():
		await get_tree().process_frame

	nav.bake_navigation_mesh(true)
	await nav.bake_finished


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _random_map_point(min_dist_from_center: float = 0.0) -> Vector2:
	for _attempt in 30:
		var p := Vector2(
			_rng.randf_range(_map_rect.position.x, _map_rect.end.x),
			_rng.randf_range(_map_rect.position.y, _map_rect.end.y)
		)
		if p.distance_to(_center) >= min_dist_from_center:
			return p
	return _center + Vector2(min_dist_from_center, min_dist_from_center)

func _to3(v: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(v.x, y, v.y)

func _get_or_create(node_name: String) -> Node3D:
	var scene := get_tree().current_scene
	var n     := scene.get_node_or_null(node_name)
	if n == null:
		n = Node3D.new(); n.name = node_name
		scene.add_child.call_deferred(n)
	return n
