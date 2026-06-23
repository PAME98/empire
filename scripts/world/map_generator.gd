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
const FOREST_CLUSTERS_PER_MPX := 12.0   # clusters per 1,000,000 px²
const TREES_PER_CLUSTER_MIN   := 5
const TREES_PER_CLUSTER_MAX   := 14
const FOREST_SPREAD           := 90.0

# ---------------------------------------------------------------------------
# Mountains — solid terrain ranges. Every mountain tile holds stone; a fraction
# of them also hold iron. Quarries (stone) and mines (iron) are built on them.
# ---------------------------------------------------------------------------
const MOUNTAIN_RANGES_PER_MPX := 4.0    # mountain ranges per 1,000,000 px²
const MOUNTAINS_PER_RANGE_MIN := 6
const MOUNTAINS_PER_RANGE_MAX := 16
const MOUNTAIN_SPREAD         := 66.0   # tile spacing within a range (tight = connected ridge)
const MOUNTAIN_STONE_MIN      := 4000
const MOUNTAIN_STONE_MAX      := 9000
const IRON_MOUNTAIN_CHANCE    := 0.35   # chance a given mountain tile also bears iron
const MOUNTAIN_IRON_MIN       := 1500
const MOUNTAIN_IRON_MAX       := 4500

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
	if ground.mesh is PlaneMesh:
		ground.mesh.size = size
	# PlaneMesh is centred on its origin, so move the ground to the map centre.
	ground.position = Vector3(size.x * 0.5, 0.0, size.y * 0.5)


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
	var delta3 := Vector3(delta.x, 0.0, delta.y)

	var buildings := scene.get_node_or_null("Buildings")
	if buildings:
		for b in buildings.get_children():
			b.position += delta3

	var units := scene.get_node_or_null("Units")
	if units:
		for u in units.get_children():
			u.position += delta3

	# The hand-placed starting trees live under Resources and were authored
	# around the old anchor too. Procedural resources are added *after* this
	# runs (in absolute map coords), so at this point Resources only holds the
	# starter nodes — shift them so the player still spawns next to wood.
	var resources := scene.get_node_or_null("Resources")
	if resources:
		for r in resources.get_children():
			r.position += delta3

	var cam := scene.get_node_or_null("Camera")
	if cam:
		cam.position = Vector3(_center.x, 0.0, _center.y)


# ---------------------------------------------------------------------------
# Rivers — a decorative Line2D plus gatherable water ResourceNodes along it
# ---------------------------------------------------------------------------
func _generate_rivers() -> void:
	var resources := _get_or_create("Resources")
	var water_scene := load(WATER_SCENE)
	if water_scene == null:
		return
	var count := _rng.randi_range(RIVER_COUNT_MIN, RIVER_COUNT_MAX)

	for _i in count:
		var points := _river_path()
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
				var water: Node3D = water_scene.instantiate()
				resources.add_child(water)
				water.global_position = _to3(pos)


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
# Mountain ranges — elongated ridges of solid mountain tiles. Every tile holds
# stone; a fraction also hold iron (shown by a vein marker). Quarries and mines
# are built directly on these.
# ---------------------------------------------------------------------------
func _generate_mountain_ranges() -> void:
	var resources := _get_or_create("Resources")
	var scene := load(MOUNTAIN_SCENE)
	if scene == null:
		push_warning("MapGenerator: could not load " + MOUNTAIN_SCENE)
		return

	var area_mpx := (_map_rect.size.x * _map_rect.size.y) / 1_000_000.0
	var ranges :Variant = max(int(round(area_mpx * MOUNTAIN_RANGES_PER_MPX)), 1)
	var safe_radius := SPAWN_SAFE_RADIUS * 1.3

	for _r in ranges:
		var centre := _random_map_point(safe_radius)
		# Give each range a random orientation so it reads as a ridge line
		# rather than a circular blob.
		var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		var perp := dir.orthogonal()
		var count := _rng.randi_range(MOUNTAINS_PER_RANGE_MIN, MOUNTAINS_PER_RANGE_MAX)

		for _n in count:
			var along := _rng.randf_range(-1.0, 1.0)
			var across := _rng.randf_range(-0.45, 0.45)
			var pos: Vector2 = centre + dir * along * MOUNTAIN_SPREAD * 2.4 + perp * across * MOUNTAIN_SPREAD
			if not _map_rect.has_point(pos):
				continue
			if pos.distance_to(_center) < safe_radius:
				continue
			var m: Node3D = scene.instantiate()
			resources.add_child(m)
			m.global_position = _to3(pos)
			m.stone_amount = _rng.randi_range(MOUNTAIN_STONE_MIN, MOUNTAIN_STONE_MAX)
			if _rng.randf() < IRON_MOUNTAIN_CHANCE:
				m.iron_amount = _rng.randi_range(MOUNTAIN_IRON_MIN, MOUNTAIN_IRON_MAX)
			else:
				m.iron_amount = 0


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
			var node: Node3D = scene.instantiate()
			resources.add_child(node)
			node.global_position = _to3(pos)


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


func _to3(v: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(v.x, y, v.y)


func _get_or_create(node_name: String) -> Node3D:
	var scene := get_tree().current_scene
	var n := scene.get_node_or_null(node_name)
	if n == null:
		n = Node3D.new()
		n.name = node_name
		scene.add_child(n)
	return n
