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
const TREE_SCENE     := "res://scenes/tree.tscn"
const MOUNTAIN_SCENE := "res://scenes/mountain.tscn"
const IRON_SCENE     := "res://scenes/iron_ore.tscn"
const WATER_SCENE    := "res://scenes/water_source.tscn"

## Clear radius around the village spawn so the start area isn't cluttered.
const SPAWN_SAFE_RADIUS := 220.0

# ---------------------------------------------------------------------------
# Forests
# ---------------------------------------------------------------------------
const FOREST_CLUSTERS_PER_MPX := 12.0   # clusters per 1,000,000 px²
const TREES_PER_CLUSTER_MIN   := 5
const TREES_PER_CLUSTER_MAX   := 14
const FOREST_SPREAD           := 90.0

# ---------------------------------------------------------------------------
# Mountains (stone) — each is one ResourceNode the quarry can be built on
# ---------------------------------------------------------------------------
const MOUNTAIN_CLUSTERS_PER_MPX := 5.0
const MOUNTAINS_PER_CLUSTER_MIN := 2
const MOUNTAINS_PER_CLUSTER_MAX := 5
const MOUNTAIN_SPREAD           := 80.0

# ---------------------------------------------------------------------------
# Iron ore — sparser than stone
# ---------------------------------------------------------------------------
const IRON_CLUSTERS_PER_MPX := 3.0
const IRON_PER_CLUSTER_MIN  := 1
const IRON_PER_CLUSTER_MAX  := 3
const IRON_SPREAD           := 60.0

# ---------------------------------------------------------------------------
# Water (rivers = chains of water ResourceNodes + a decorative line)
# ---------------------------------------------------------------------------
const RIVER_COUNT_MIN   := 1
const RIVER_COUNT_MAX   := 3
const RIVER_NODE_SPACING := 70.0    # px between gatherable water nodes along a river
const RIVER_LINE_WIDTH  := 26.0
const RIVER_COLOR       := Color(0.18, 0.45, 0.72, 0.55)

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------
var _rng := RandomNumberGenerator.new()
var _map_rect: Rect2     # (0,0) .. (size)
var _center: Vector2


func _ready() -> void:
	_rng.randomize()

	var size: Vector2 = MapSettings.map_size
	_map_rect = Rect2(Vector2.ZERO, size)
	_center   = size * 0.5

	_resize_ground(size)
	_recenter_start(size)
	_generate_rivers()
	_generate_mountains()
	_generate_iron()
	_generate_forests()


# ---------------------------------------------------------------------------
# Ground
# ---------------------------------------------------------------------------
func _resize_ground(size: Vector2) -> void:
	var ground = get_tree().current_scene.get_node_or_null("Ground")
	if ground == null:
		push_warning("MapGenerator: no Ground node found — skipping resize.")
		return
	ground.position = Vector2.ZERO
	ground.size     = size


# ---------------------------------------------------------------------------
# Recentre the starting village/units/camera onto the map centre so the
# player never starts out of bounds regardless of map size.
# ---------------------------------------------------------------------------
func _recenter_start(size: Vector2) -> void:
	var scene := get_tree().current_scene

	# The original scene was authored around (640, 360) as the "start point".
	# Shift everything by the delta between that and the new map centre.
	var old_anchor := Vector2(640, 360)
	var delta := _center - old_anchor

	var buildings := scene.get_node_or_null("Buildings")
	if buildings:
		for b in buildings.get_children():
			b.position += delta

	var units := scene.get_node_or_null("Units")
	if units:
		for u in units.get_children():
			u.position += delta

	var cam := scene.get_node_or_null("Camera")
	if cam:
		cam.position = _center


# ---------------------------------------------------------------------------
# Rivers — a decorative Line2D plus gatherable water ResourceNodes along it
# ---------------------------------------------------------------------------
func _generate_rivers() -> void:
	var env := _get_or_create("Environment")
	var resources := _get_or_create("Resources")
	var water_scene := load(WATER_SCENE)
	var count := _rng.randi_range(RIVER_COUNT_MIN, RIVER_COUNT_MAX)

	for _i in count:
		var points := _river_path()

		# Decorative line under the nodes.
		var line := Line2D.new()
		line.width          = RIVER_LINE_WIDTH
		line.default_color  = RIVER_COLOR
		line.joint_mode     = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode   = Line2D.LINE_CAP_ROUND
		for p in points:
			line.add_point(p)
		env.add_child(line)

		# Gatherable water nodes spaced along the river.
		if water_scene == null:
			continue
		var dist_acc := 0.0
		for i in range(1, points.size()):
			var seg :Vector2 = points[i] - points[i - 1]
			var seg_len := seg.length()
			dist_acc += seg_len
			if dist_acc >= RIVER_NODE_SPACING:
				dist_acc = 0.0
				var pos: Vector2 = points[i]
				if pos.distance_to(_center) < SPAWN_SAFE_RADIUS:
					continue
				var water: Node2D = water_scene.instantiate()
				water.global_position = pos
				resources.add_child(water)


func _river_path() -> Array:
	var edge := _rng.randi() % 4
	var r := _map_rect
	var start: Vector2
	var end: Vector2
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
		var t := float(i) / segments
		var base := start.lerp(end, t)
		var jitter := Vector2(
			_rng.randf_range(-60.0, 60.0),
			_rng.randf_range(-60.0, 60.0)
		) * (1.0 - absf(t - 0.5) * 1.5)
		points.append(base + jitter)
	return points


# ---------------------------------------------------------------------------
# Mountains (stone deposits)
# ---------------------------------------------------------------------------
func _generate_mountains() -> void:
	_scatter_clusters(
		MOUNTAIN_SCENE, MOUNTAIN_CLUSTERS_PER_MPX,
		MOUNTAINS_PER_CLUSTER_MIN, MOUNTAINS_PER_CLUSTER_MAX,
		MOUNTAIN_SPREAD, SPAWN_SAFE_RADIUS * 1.3
	)


# ---------------------------------------------------------------------------
# Iron ore deposits
# ---------------------------------------------------------------------------
func _generate_iron() -> void:
	_scatter_clusters(
		IRON_SCENE, IRON_CLUSTERS_PER_MPX,
		IRON_PER_CLUSTER_MIN, IRON_PER_CLUSTER_MAX,
		IRON_SPREAD, SPAWN_SAFE_RADIUS * 1.5
	)


# ---------------------------------------------------------------------------
# Forests
# ---------------------------------------------------------------------------
func _generate_forests() -> void:
	_scatter_clusters(
		TREE_SCENE, FOREST_CLUSTERS_PER_MPX,
		TREES_PER_CLUSTER_MIN, TREES_PER_CLUSTER_MAX,
		FOREST_SPREAD, SPAWN_SAFE_RADIUS
	)


# ---------------------------------------------------------------------------
# Generic cluster scatter — used by forests, mountains and iron.
# ---------------------------------------------------------------------------
func _scatter_clusters(
	scene_path: String, clusters_per_mpx: float,
	per_cluster_min: int, per_cluster_max: int,
	spread: float, safe_radius: float
) -> void:
	var resources := _get_or_create("Resources")
	var scene := load(scene_path)
	if scene == null:
		push_warning("MapGenerator: could not load " + scene_path)
		return

	var area_mpx := (_map_rect.size.x * _map_rect.size.y) / 1_000_000.0
	var clusters := int(round(area_mpx * clusters_per_mpx))
	clusters = max(clusters, 2)

	for _c in clusters:
		var centre := _random_map_point(safe_radius)
		var count := _rng.randi_range(per_cluster_min, per_cluster_max)
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
			var node: Node2D = scene.instantiate()
			node.global_position = pos
			resources.add_child(node)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _random_map_point(min_dist_from_center: float = 0.0) -> Vector2:
	var attempts := 0
	while attempts < 30:
		var p := Vector2(
			_rng.randf_range(_map_rect.position.x, _map_rect.end.x),
			_rng.randf_range(_map_rect.position.y, _map_rect.end.y)
		)
		if p.distance_to(_center) >= min_dist_from_center:
			return p
		attempts += 1
	return _center + Vector2(min_dist_from_center, min_dist_from_center)


func _get_or_create(node_name: String) -> Node2D:
	var scene := get_tree().current_scene
	var n := scene.get_node_or_null(node_name)
	if n == null:
		n = Node2D.new()
		n.name = node_name
		scene.add_child(n)
	return n
