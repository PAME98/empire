extends Node
## Procedurally generates a map of the given size on _ready().
## Lives as a child of Main. Reads MapSettings.map_size (set by the main menu)
## and populates:
##   - Ground (ColorRect)         — resized to fill the map
##   - Resources (Node2D)         — trees, mountains (stone), iron ore, water
##   - Environment (Node2D)       — decorative river lines under the water nodes
## It also recentres the VillageCenter, starting House, citizens and Camera
## onto the middle of the generated map so the player always starts in-bounds.
##
## COORDINATE SYSTEM: the map spans (0,0) .. (size), matching the positive
## layout already used in main.tscn. The map centre is size * 0.5.

# ---------------------------------------------------------------------------
# Scenes
# ---------------------------------------------------------------------------
const TREE_SCENE     := "res://scenes/world/tree.tscn"
const MOUNTAIN_SCENE := "res://scenes/world/mountain.tscn"
const WATER_SCENE    := "res://scenes/world/water_source.tscn"

## Clear radius around the village spawn so the start area isn't cluttered.
const SPAWN_SAFE_RADIUS := 220.0

# ---------------------------------------------------------------------------
# Forests
# ---------------------------------------------------------------------------
const FOREST_CLUSTERS_PER_MPX := 12.0
const TREES_PER_CLUSTER_MIN   := 5
const TREES_PER_CLUSTER_MAX   := 14
const FOREST_SPREAD           := 90.0

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

# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------
const RIVER_COUNT_MIN    := 1
const RIVER_COUNT_MAX    := 3
const RIVER_NODE_SPACING := 70.0
const GROUND_RIVER_BASE  := "res://assets/kenney/nature/models/"
const RIVER_TILE_SCALE   := 80.0   # slightly smaller than ground so no gaps

# ---------------------------------------------------------------------------
# Ground
# ---------------------------------------------------------------------------
const GROUND_TILE_SCENE := "res://assets/kenney/nature/models/ground_grass.glb"
const GROUND_TILE_SCALE := 100.0

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------
var _rng := RandomNumberGenerator.new()
var _map_rect: Rect2
var _center: Vector2


func _ready() -> void:
	_rng.randomize()
	var size: Vector2 = MapSettings.map_size
	_map_rect = Rect2(Vector2.ZERO, size)
	_center   = size * 0.5
	_resize_ground(size)
	_recenter_start(size)
	_generate_rivers()
	_generate_mountain_ranges()
	_generate_forests()


# ---------------------------------------------------------------------------
# Ground
# ---------------------------------------------------------------------------
func _resize_ground(size: Vector2) -> void:
	var ground = get_tree().current_scene.get_node_or_null("Ground")
	if ground == null:
		push_warning("MapGenerator: no Ground node found — skipping resize.")
		return
	if ground is MeshInstance3D:
		ground.mesh = null
		ground.visible = false

	var packed := load(GROUND_TILE_SCENE) as PackedScene
	if packed == null:
		push_warning("MapGenerator: could not load ground tile " + GROUND_TILE_SCENE)
		return

	var cols := int(ceil(size.x / GROUND_TILE_SCALE))
	var rows := int(ceil(size.y / GROUND_TILE_SCALE))
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

	get_tree().current_scene.add_child.call_deferred(container)


# ---------------------------------------------------------------------------
# Recentre
# ---------------------------------------------------------------------------
func _recenter_start(size: Vector2) -> void:
	var scene      := get_tree().current_scene
	var old_anchor := Vector2(640, 360)
	var delta      := _center - old_anchor
	var delta3     := Vector3(delta.x, 0.0, delta.y)

	for group_name in ["Buildings", "Units", "Resources"]:
		var g := scene.get_node_or_null(group_name)
		if g:
			for child in g.get_children():
				child.position += delta3

	var cam := scene.get_node_or_null("Camera")
	if cam:
		cam.position = Vector3(_center.x, 0.0, _center.y)


# ---------------------------------------------------------------------------
# Rivers
# ---------------------------------------------------------------------------
func _river_path() -> Array:
	var edge  := _rng.randi() % 4
	var r     := _map_rect
	var start : Vector2
	var end   : Vector2
	match edge:
		0:
			start = Vector2(_rng.randf_range(r.position.x, r.end.x), r.position.y)
			end   = Vector2(_rng.randf_range(r.position.x, r.end.x), r.end.y)
		1:
			start = Vector2(_rng.randf_range(r.position.x, r.end.x), r.end.y)
			end   = Vector2(_rng.randf_range(r.position.x, r.end.x), r.position.y)
		2:
			start = Vector2(r.position.x, _rng.randf_range(r.position.y, r.end.y))
			end   = Vector2(r.end.x,      _rng.randf_range(r.position.y, r.end.y))
		3:
			start = Vector2(r.end.x,      _rng.randf_range(r.position.y, r.end.y))
			end   = Vector2(r.position.x, _rng.randf_range(r.position.y, r.end.y))

	var points: Array = []
	var segments := 18
	for i in segments + 1:
		var t    := float(i) / segments
		var base := start.lerp(end, t)
		var jitter := Vector2(
			_rng.randf_range(-60.0, 60.0),
			_rng.randf_range(-60.0, 60.0)
		) * (1.0 - absf(t - 0.5) * 1.5)
		points.append(base + jitter)
	return points


func _generate_rivers() -> void:
	var resources  := _get_or_create("Resources")
	var water_scene := load(WATER_SCENE)
	if water_scene == null:
		return
	var count := _rng.randi_range(RIVER_COUNT_MIN, RIVER_COUNT_MAX)
	for _i in count:
		var points := _river_path()
		_place_river_tiles(points)
		_place_river_gameplay_nodes(points, resources, water_scene)


func _place_river_gameplay_nodes(points: Array, resources: Node3D, water_scene: PackedScene) -> void:
	var dist_acc := 0.0
	for i in range(1, points.size()):
		var seg: Vector2 = points[i] - points[i - 1]
		dist_acc += seg.length()
		if dist_acc >= RIVER_NODE_SPACING:
			dist_acc = 0.0
			var pos: Vector2 = points[i]
			if pos.distance_to(_center) < SPAWN_SAFE_RADIUS:
				continue
			var water: Node3D = water_scene.instantiate()
			resources.add_child(water)
			water.global_position = _to3(pos)
			# Hide placeholder mesh — river tiles provide the visual
			var mesh_node := water.get_node_or_null("Mesh")
			if mesh_node:
				mesh_node.visible = false


func _place_river_tiles(points: Array) -> void:
	if points.size() < 2:
		return

	var straight := load(GROUND_RIVER_BASE + "ground_riverStraight.glb") as PackedScene
	if straight == null:
		push_warning("MapGenerator: could not load ground_riverStraight.glb")
		return

	# Build a water material once
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color     = Color(0.18, 0.45, 0.72, 0.75)
	water_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness        = 0.1
	water_mat.metallic         = 0.2
	water_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED

	var container := Node3D.new()
	container.name = "RiverTiles"

	var dist_acc := 0.0
	for i in range(1, points.size()):
		var seg: Vector2 = points[i] - points[i - 1]
		var seg_len := seg.length()
		if seg_len < 0.001:
			continue
		var seg_dir := seg.normalized()
		dist_acc += seg_len

		while dist_acc >= RIVER_TILE_SCALE:
			dist_acc -= RIVER_TILE_SCALE
			var t   := clampf(1.0 - (dist_acc / seg_len), 0.0, 1.0)
			var pos : Vector2 = points[i - 1].lerp(points[i], t)
			# Clamp to map instead of skipping — fixes edge gaps
			pos.x = clampf(pos.x, _map_rect.position.x, _map_rect.end.x)
			pos.y = clampf(pos.y, _map_rect.position.y, _map_rect.end.y)

			var rot_y := atan2(seg_dir.x, seg_dir.y)

			# Ground channel tile
			var tile: Node3D = straight.instantiate()
			tile.scale      = Vector3.ONE * RIVER_TILE_SCALE
			tile.position   = Vector3(pos.x, -0.05, pos.y)
			tile.rotation.y = rot_y
			container.add_child(tile)

			# Water surface — a thin plane sitting just above the channel floor
			# The channel in the GLB is roughly 40% of the tile width and centered
			var water_mesh              := MeshInstance3D.new()
			var plane                   := PlaneMesh.new()
			plane.size                  = Vector2(RIVER_TILE_SCALE * 0.38, RIVER_TILE_SCALE)
			water_mesh.mesh             = plane
			water_mesh.material_override = water_mat
			water_mesh.position         = Vector3(pos.x, 0.18, pos.y)
			water_mesh.rotation.y       = rot_y
			container.add_child(water_mesh)

	get_tree().current_scene.add_child.call_deferred(container)

# ---------------------------------------------------------------------------
# Mountains
# ---------------------------------------------------------------------------
func _generate_mountain_ranges() -> void:
	var resources   := _get_or_create("Resources")
	var scene       := load(MOUNTAIN_SCENE)
	if scene == null:
		push_warning("MapGenerator: could not load " + MOUNTAIN_SCENE)
		return

	var area_mpx  := (_map_rect.size.x * _map_rect.size.y) / 1_000_000.0
	var ranges    :Variant = max(int(round(area_mpx * MOUNTAIN_RANGES_PER_MPX)), 1)
	var safe_radius := SPAWN_SAFE_RADIUS * 1.3

	for _r in ranges:
		var centre := _random_map_point(safe_radius)
		var dir    := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		var perp   := dir.orthogonal()
		var count  := _rng.randi_range(MOUNTAINS_PER_RANGE_MIN, MOUNTAINS_PER_RANGE_MAX)

		for _n in count:
			var along  := _rng.randf_range(-1.0, 1.0)
			var across := _rng.randf_range(-0.45, 0.45)
			var pos: Vector2 = centre + dir * along * MOUNTAIN_SPREAD * 2.4 + perp * across * MOUNTAIN_SPREAD
			if not _map_rect.has_point(pos):
				continue
			if pos.distance_to(_center) < safe_radius:
				continue
			var m: Node3D = scene.instantiate()
			resources.add_child(m)
			m.global_position = _to3(pos)
			m.stone_amount    = _rng.randi_range(MOUNTAIN_STONE_MIN, MOUNTAIN_STONE_MAX)
			m.iron_amount     = _rng.randi_range(MOUNTAIN_IRON_MIN, MOUNTAIN_IRON_MAX) if _rng.randf() < IRON_MOUNTAIN_CHANCE else 0


# ---------------------------------------------------------------------------
# Forests
# ---------------------------------------------------------------------------
func _generate_forests() -> void:
	_scatter_clusters(
		TREE_SCENE, FOREST_CLUSTERS_PER_MPX,
		TREES_PER_CLUSTER_MIN, TREES_PER_CLUSTER_MAX,
		FOREST_SPREAD, SPAWN_SAFE_RADIUS
	)


func _scatter_clusters(
	scene_path: String, clusters_per_mpx: float,
	per_cluster_min: int, per_cluster_max: int,
	spread: float, safe_radius: float
) -> void:
	var resources := _get_or_create("Resources")
	var scene     := load(scene_path)
	if scene == null:
		push_warning("MapGenerator: could not load " + scene_path)
		return

	var area_mpx := (_map_rect.size.x * _map_rect.size.y) / 1_000_000.0
	var clusters :Variant = max(int(round(area_mpx * clusters_per_mpx)), 2)

	for _c in clusters:
		var centre := _random_map_point(safe_radius)
		var count  := _rng.randi_range(per_cluster_min, per_cluster_max)
		for _n in count:
			var offset := Vector2(
				_rng.randf_range(-spread, spread),
				_rng.randf_range(-spread, spread)
			)
			var pos := centre + offset
			if not _map_rect.has_point(pos):
				continue
			if pos.distance_to(_center) < safe_radius:
				continue
			var node: Node3D = scene.instantiate()
			resources.add_child(node)
			node.global_position = _to3(pos)


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
		n      = Node3D.new()
		n.name = node_name
		scene.add_child(n)
	return n
