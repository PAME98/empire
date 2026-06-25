extends Node
## Procedurally generates a map, then enters town-center placement mode.
##
## STARTUP SEQUENCE:
##   1. Clear pre-placed buildings/units/trees from main.tscn.
##   2. Build the land mask (continents vs ocean) into a texture.
##   3. Generate terrain (clipped ground plane + ocean plane + ocean collision)
##      -> rivers -> mountains -> forests, all constrained to land.
##   4. Bake navigation mesh.
##   5. Enter placement mode.
##
## CONTINENT / OCEAN APPROACH:
##   A FastNoiseLite "land value" field, pushed down near the borders by a
##   radial edge falloff, decides land vs ocean (land where value > SEA_LEVEL).
##   That field is baked into a mask TEXTURE. The ground is a single shaded
##   plane whose fragments are discarded below sea level, so the coastline
##   follows the bilinear-interpolated contour — smooth, rounded edges at pixel
##   resolution rather than the stair-stepped edge of a tile grid. A sand band
##   hugs the waterline to read the coast clearly. The ocean is a plane beneath
##   the ground plane that shows through wherever land is discarded. Gameplay
##   (mountains/rivers/forests/placement) uses the same CPU land field, and a
##   coarse cell grid of tall collision boxes carves the sea out of the navmesh.
##
## FEATURE REGIONS:
##   Two low-frequency noises gate WHERE mountains and rivers appear, so the map
##   has mountain regions and flat regions, river regions and dry regions.
##
## RIVER APPROACH:
##   A river starts at an inland high point and flows DOWNHILL along the
##   negative gradient of the land field until it reaches the coast and spills a
##   little into the water. Width grows from source to sea.

const VILLAGE_CENTER_SCENE := "res://scenes/buildings/village_center.tscn"
const CITIZEN_SCENE        := "res://scenes/units/citizen.tscn"
const TREE_SCENE           := "res://scenes/world/tree.tscn"
const MOUNTAIN_SCENE       := "res://scenes/world/mountain.tscn"

# ---------------------------------------------------------------------------
# Continents / ocean
# ---------------------------------------------------------------------------
## Noise frequency in world units. SMALLER => larger, fewer continents.
const CONTINENT_NOISE_FREQ   := 0.00035
const CONTINENT_OCTAVES      := 4
## Land where land_value > SEA_LEVEL. Raise => more ocean / smaller land.
const SEA_LEVEL              := 0.46
## Radial edge falloff: where ocean starts to win, and how hard it pushes the
## borders under water. Keeps a clean coast ring around the playable area.
const EDGE_FALLOFF_START     := 0.55
const EDGE_FALLOFF_STRENGTH  := 1.15
## Ground fragments below SEA_LEVEL - COAST_FEATHER are discarded (ocean shows);
## the sand beach band spans SEA_LEVEL .. SEA_LEVEL + BEACH_BAND. River mouths
## use these so they reach past the sand and actually touch the water.
const COAST_FEATHER := 0.010
const BEACH_BAND    := 0.030

## Heights. Ground plane sits at GROUND_Y; ocean surface a touch below so it
## shows through the discarded coast and never floods flat land.
const GROUND_Y               := 0.0
const OCEAN_Y                := -0.5
## Ocean collision box height. Must exceed agent_max_climb so the baker
## excludes ocean from the walkable mesh.
const OCEAN_COLLIDER_HEIGHT  := 60.0
## Cell size for ocean collision boxes (gameplay coastline). Independent of the
## visual coast, which is smooth. Smaller => tighter shoreline collision.
const OCEAN_COLLISION_CELL   := 64.0

## Land mask texture resolution. LOWER target res = smoother/rounder coasts
## (bilinear interpolation does the rounding). Capped so huge maps stay cheap.
const LAND_MASK_TEXEL        := 26.0
const LAND_MASK_MAX_DIM      := 720

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
const MOUNTAIN_RANGES_PER_MPX := 2.0
const MOUNTAINS_PER_RANGE_MIN := 4
const MOUNTAINS_PER_RANGE_MAX := 9
const MOUNTAIN_SPREAD         := 140.0
const MOUNTAIN_STONE_MIN      := 400
const MOUNTAIN_STONE_MAX      := 900
const IRON_MOUNTAIN_CHANCE    := 0.35
const MOUNTAIN_IRON_MIN       := 150
const MOUNTAIN_IRON_MAX       := 450
## Overlap radius. Larger now that mountains have wider footprints.
const MOUNTAIN_RADIUS         := 95.0
## Per-instance scaling. mountain.tscn is ~72 x 60 x 56. Low Y, wide XZ:
## broad massifs that cover area rather than tall spires.
const MOUNTAIN_SCALE_Y_MIN    := 1.0
const MOUNTAIN_SCALE_Y_MAX    := 1.7
const MOUNTAIN_SCALE_XZ_MIN   := 2.2
const MOUNTAIN_SCALE_XZ_MAX   := 3.4
## Mountain regions: higher threshold => rarer, fewer mountainous areas.
const MOUNTAIN_REGION_FREQ      := 0.0009
const MOUNTAIN_REGION_THRESHOLD := 0.60

# ---------------------------------------------------------------------------
# Rivers
# ---------------------------------------------------------------------------
const RIVER_COUNT_MIN    := 1
const RIVER_COUNT_MAX    := 4
const RIVER_WIDTH_MIN    := 45.0
const RIVER_WIDTH_MAX    := 95.0
const RIVER_SOURCE_WIDTH_RATIO := 0.42
const RIVER_SOURCE_MIN_VALUE := SEA_LEVEL + 0.14
const RIVER_REGION_FREQ      := 0.0007
const RIVER_REGION_THRESHOLD := 0.50
const RIVER_MARCH_STEP       := 70.0
const RIVER_MARCH_MAX_STEPS  := 240
const RIVER_DECIMATE_STEP    := 4
const RIVER_SAMPLES      := 120
const RIVER_REJECT_STEP  := 2
const RIVER_CLEAR_RADIUS := RIVER_WIDTH_MAX * 0.5 + MIN_OBSTACLE_GAP
const RIVER_MIN_SEPARATION := RIVER_WIDTH_MAX + 80.0
const RIVER_Y := 0.05
## River mouths end here — just seaward of the ground discard edge so they
## overlap the ocean instead of stopping in the beach sand.
const RIVER_MOUTH_OVERSHOOT := 0.03
const RIVER_MOUTH_LEVEL     := SEA_LEVEL - COAST_FEATHER - RIVER_MOUTH_OVERSHOOT
## Steps used to confirm a river's mouth reaches open ocean (not an inland lake).
const OCEAN_CHECK_STEPS := 90

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------
const SPAWN_SAFE_RADIUS := 200.0
const CITIZEN_SPAWN_RADIUS := 90.0
const CITIZEN_COUNT        := 5

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------
var _rng                   := RandomNumberGenerator.new()
var _continent_noise       := FastNoiseLite.new()
var _mountain_region_noise := FastNoiseLite.new()
var _river_region_noise    := FastNoiseLite.new()
var _land_mask_tex         : ImageTexture
var _map_rect              : Rect2
var _center                : Vector2

var _river_samples_all : Array[Vector2] = []
var _river_points      : Array[Vector2] = []
var _river_sources     : Array[Vector2] = []
var _mountain_points   : Array[Vector2] = []
var _tree_points       : Array[Vector2] = []

var _placement_valid  : bool = false
var _ghost            : MeshInstance3D = null


func _ready() -> void:
	# Seed from the SHARED map seed so every peer generates the identical world.
	# randomize() would reseed from the system clock per-machine, which is what
	# made host and client get different maps. MapSettings.rng_seed is set on all
	# peers by NetworkManager.start_game() before this scene loads; in
	# single-player it defaults to 0 (a fixed map) unless the main menu set it.
	_rng.seed = MapSettings.rng_seed
	var size: Vector2 = MapSettings.map_size
	_map_rect = Rect2(Vector2.ZERO, size)
	_center   = size * 0.5

	_configure_noises()

	_clear_prebuilt_nodes()
	_generate_terrain(size)
	_generate_rivers()
	_generate_mountain_ranges()
	_generate_forests()

	await _bake_navigation()
	# Town founding is owned by start_placement.tscn (its own ghost + click).
	# Calling _begin_placement() here as well drove a SECOND ghost on the shared
	# PlacementGhost node; after you placed the village centre that ghost kept
	# following the cursor and turned red over the now-occupied spot. Disabled
	# while start_placement.tscn is in the scene. If you ever remove that node
	# and go back to map-gen founding, just uncomment the line below.
	#_begin_placement()


func _configure_noises() -> void:
	_continent_noise.seed = _rng.randi()
	_continent_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent_noise.frequency = CONTINENT_NOISE_FREQ
	_continent_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_continent_noise.fractal_octaves = CONTINENT_OCTAVES

	_mountain_region_noise.seed = _rng.randi()
	_mountain_region_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mountain_region_noise.frequency = MOUNTAIN_REGION_FREQ

	_river_region_noise.seed = _rng.randi()
	_river_region_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_river_region_noise.frequency = RIVER_REGION_FREQ


# ---------------------------------------------------------------------------
# Land mask + feature regions
# ---------------------------------------------------------------------------
func _land_value(pos: Vector2) -> float:
	var n := _continent_noise.get_noise_2d(pos.x, pos.y) * 0.5 + 0.5
	return n - _edge_falloff(pos)


func _edge_falloff(pos: Vector2) -> float:
	var nx := absf(pos.x / _map_rect.size.x * 2.0 - 1.0)
	var ny := absf(pos.y / _map_rect.size.y * 2.0 - 1.0)
	var d  := maxf(nx, ny)
	return smoothstep(EDGE_FALLOFF_START, 1.0, d) * EDGE_FALLOFF_STRENGTH


func _is_land(pos: Vector2) -> bool:
	return _land_value(pos) > SEA_LEVEL


func _mountain_region(pos: Vector2) -> float:
	return _mountain_region_noise.get_noise_2d(pos.x, pos.y) * 0.5 + 0.5


func _river_region(pos: Vector2) -> float:
	return _river_region_noise.get_noise_2d(pos.x, pos.y) * 0.5 + 0.5


func _land_gradient(pos: Vector2) -> Vector2:
	var e := 24.0
	var dx := _land_value(pos + Vector2(e, 0.0)) - _land_value(pos - Vector2(e, 0.0))
	var dy := _land_value(pos + Vector2(0.0, e)) - _land_value(pos - Vector2(0.0, e))
	return Vector2(dx, dy)


func _random_land_point(min_value: float = SEA_LEVEL, tries: int = 60) -> Variant:
	for _i in tries:
		var p := Vector2(
			_rng.randf_range(_map_rect.position.x, _map_rect.end.x),
			_rng.randf_range(_map_rect.position.y, _map_rect.end.y)
		)
		if _land_value(p) > min_value:
			return p
	return null


# ---------------------------------------------------------------------------
# Clear pre-placed nodes from main.tscn
# ---------------------------------------------------------------------------
func _clear_prebuilt_nodes() -> void:
	var scene := get_tree().current_scene
	for group_name in ["Buildings", "Units", "Resources"]:
		var n := scene.get_node_or_null(group_name)
		if n:
			for child in n.get_children():
				child.queue_free()


# ---------------------------------------------------------------------------
# Terrain: clipped ground plane + ocean plane + ocean collision
# ---------------------------------------------------------------------------
func _generate_terrain(size: Vector2) -> void:
	var scene  := get_tree().current_scene
	var ground := scene.get_node_or_null("Ground")
	if ground is MeshInstance3D:
		ground.mesh    = null
		ground.visible = false

	_land_mask_tex = _build_land_mask_texture(size)
	_build_ground_plane(size)
	_build_ocean_plane(size)
	_build_ocean_collision(size)


## Bake the continuous land field into an RF texture. Bilinear sampling of this
## in the ground shader is what makes the coastline a smooth curve.
func _build_land_mask_texture(size: Vector2) -> ImageTexture:
	var w := clampi(int(round(size.x / LAND_MASK_TEXEL)), 64, LAND_MASK_MAX_DIM)
	var h := clampi(int(round(size.y / LAND_MASK_TEXEL)), 64, LAND_MASK_MAX_DIM)
	var img := Image.create(w, h, false, Image.FORMAT_RF)
	for y in h:
		var wy := (y + 0.5) / float(h) * size.y
		for x in w:
			var wx := (x + 0.5) / float(w) * size.x
			img.set_pixel(x, y, Color(_land_value(Vector2(wx, wy)), 0.0, 0.0))
	return ImageTexture.create_from_image(img)


func _build_ground_plane(size: Vector2) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var mi := MeshInstance3D.new()
	mi.name = "GroundPlane"
	mi.mesh = plane
	mi.position = Vector3(_center.x, GROUND_Y, _center.y)
	mi.material_override = _make_ground_material()
	get_tree().current_scene.add_child.call_deferred(mi)


func _build_ocean_plane(size: Vector2) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var mi := MeshInstance3D.new()
	mi.name = "OceanSurface"
	mi.mesh = plane
	mi.position = Vector3(_center.x, OCEAN_Y, _center.y)
	mi.material_override = _make_ocean_material()
	get_tree().current_scene.add_child.call_deferred(mi)


func _make_ground_material() -> ShaderMaterial:
	# Single shaded ground plane. Fragments below sea level are discarded so the
	# coast follows the bilinear mask contour (rounded). A sand band hugs the
	# waterline; two value-noise octaves break up the grass colour.
	var code := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

uniform sampler2D land_mask : filter_linear, repeat_disable;
uniform vec2  world_size;
uniform float sea_level     = 0.46;
uniform float coast_feather = 0.010;
uniform float beach_band    = 0.030;
uniform vec3  grass_low  : source_color = vec3(0.28, 0.45, 0.17);
uniform vec3  grass_high : source_color = vec3(0.44, 0.60, 0.27);
uniform vec3  sand_col   : source_color = vec3(0.78, 0.71, 0.47);

varying vec3 v_world;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 muv = v_world.xz / world_size;
	float lv = texture(land_mask, muv).r;
	if (lv < sea_level - coast_feather) {
		discard;
	}
	float n  = vnoise(v_world.xz * 0.030);
	float n2 = vnoise(v_world.xz * 0.008);
	vec3 grass = mix(grass_low, grass_high, n * 0.6 + n2 * 0.4);

	float beach = 1.0 - smoothstep(sea_level, sea_level + beach_band, lv);
	ALBEDO    = mix(grass, sand_col, beach);
	ROUGHNESS = 1.0;
	SPECULAR  = 0.0;
}
"""
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("land_mask", _land_mask_tex)
	mat.set_shader_parameter("world_size", _map_rect.size)
	mat.set_shader_parameter("sea_level", SEA_LEVEL)
	mat.set_shader_parameter("coast_feather", COAST_FEATHER)
	mat.set_shader_parameter("beach_band", BEACH_BAND)
	return mat


func _make_ocean_material() -> ShaderMaterial:
	var code := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec4  deep_col    : source_color = vec4(0.03, 0.12, 0.30, 1.0);
uniform vec4  shallow_col : source_color = vec4(0.08, 0.30, 0.55, 1.0);
uniform vec4  sky_col     : source_color = vec4(0.58, 0.74, 0.88, 1.0);
uniform float speed       : hint_range(0.02, 1.0) = 0.16;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * speed;
	vec2  p = v_world.xz * 0.01;

	float r1 = sin(p.x * 1.6 + t * 1.3);
	float r2 = sin(p.y * 1.3 - t * 1.1 + 1.0);
	float r3 = sin((p.x + p.y) * 0.9 + t * 0.7);
	float ripple = (r1 + r2 + r3) / 3.0;
	float tone   = ripple * 0.5 + 0.5;

	vec3 base = mix(deep_col.rgb, shallow_col.rgb, tone * 0.55);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	base = mix(base, sky_col.rgb, fres * 0.55);
	float glint = smoothstep(0.82, 1.0, ripple);

	ALBEDO    = base;
	EMISSION  = sky_col.rgb * glint * 0.20;
	ROUGHNESS = 0.06;
	METALLIC  = 0.0;
	SPECULAR  = 0.80;
}
"""
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat


func _build_ocean_collision(size: Vector2) -> void:
	var cell := OCEAN_COLLISION_CELL
	var cols := int(ceil(size.x / cell))
	var rows := int(ceil(size.y / cell))

	var ocean_set := {}
	for row in rows:
		for col in cols:
			var c := Vector2(col * cell + cell * 0.5, row * cell + cell * 0.5)
			if not _is_land(c):
				ocean_set[Vector2i(col, row)] = true
	if ocean_set.is_empty():
		return

	var body := StaticBody3D.new()
	body.name = "OceanBody"
	body.collision_layer = 1
	body.collision_mask  = 0
	body.add_to_group("obstacles")
	body.add_to_group("ocean")

	for row in rows:
		var run_start := -1
		for col in range(cols + 1):
			var is_ocean := col < cols and ocean_set.has(Vector2i(col, row))
			if is_ocean and run_start == -1:
				run_start = col
			elif not is_ocean and run_start != -1:
				_add_ocean_box(body, run_start, col - 1, row, cell)
				run_start = -1

	get_tree().current_scene.add_child.call_deferred(body)


func _add_ocean_box(body: StaticBody3D, col_start: int, col_end: int, row: int, cell: float) -> void:
	var span  := (col_end - col_start + 1)
	var width := span * cell
	var cx    := (col_start * cell) + width * 0.5
	var cz    := (row * cell) + cell * 0.5

	var shape := BoxShape3D.new()
	shape.size = Vector3(width, OCEAN_COLLIDER_HEIGHT, cell)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(cx, OCEAN_COLLIDER_HEIGHT * 0.5 - 1.0, cz)
	body.add_child(col)


# ---------------------------------------------------------------------------
# Rivers — inland source -> coast, gated by river region
# ---------------------------------------------------------------------------
func _generate_rivers() -> void:
	var resources := _get_or_create("Resources")
	var count     := _rng.randi_range(RIVER_COUNT_MIN, RIVER_COUNT_MAX)
	for _i in count:
		var base_width := _rng.randf_range(RIVER_WIDTH_MIN, RIVER_WIDTH_MAX)
		var ctrl       := _make_river_to_sea()
		if ctrl.is_empty():
			continue
		_place_river(ctrl, base_width, resources)


func _make_river_to_sea() -> Array[Vector2]:
	for _attempt in 32:
		var src_v = _random_land_point(RIVER_SOURCE_MIN_VALUE)
		if src_v == null:
			continue
		var src: Vector2 = src_v

		if _river_region(src) < RIVER_REGION_THRESHOLD:
			continue

		var too_close := false
		for s in _river_sources:
			if src.distance_to(s) < RIVER_MIN_SEPARATION:
				too_close = true
				break
		if too_close:
			continue

		var path := _march_to_sea(src)
		if path.size() < 3:
			continue
		path = _smooth_path(path, 3)
		var ctrl := _decimate(path, RIVER_DECIMATE_STEP)
		if ctrl.size() < 3:
			continue
		if _polyline_self_intersects(ctrl):
			continue
		_river_sources.append(src)
		return ctrl
	return []


## True if downhill water from `pos` runs off the map edge (open ocean) rather
## than dead-ending in an enclosed inland basin (a lake).
func _is_open_ocean(pos: Vector2) -> bool:
	var p := pos
	for _k in OCEAN_CHECK_STEPS:
		if p.x <= _map_rect.position.x or p.x >= _map_rect.end.x \
				or p.y <= _map_rect.position.y or p.y >= _map_rect.end.y:
			return true
		if _land_value(p) > SEA_LEVEL:
			return false
		var g := -_land_gradient(p)
		if g.length() < 0.000001:
			return false
		p += g.normalized() * (RIVER_MARCH_STEP * 1.5)
	return false


## Point on segment a->b where land_value crosses `level`. Used to end the
## river just past the shore (at RIVER_MOUTH_LEVEL) so it touches the water.
func _crossing_at(a: Vector2, b: Vector2, level: float) -> Vector2:
	var va := _land_value(a)
	var vb := _land_value(b)
	var denom := va - vb
	if absf(denom) < 0.000001:
		return b
	var f := clampf((va - level) / denom, 0.0, 1.0)
	return a.lerp(b, f)


func _march_to_sea(start: Vector2) -> Array[Vector2]:
	var pts: Array[Vector2] = [start]
	var pos := start
	var prev_dir := Vector2.ZERO

	for _step in RIVER_MARCH_MAX_STEPS:
		var down := -_land_gradient(pos)
		if down.length() < 0.00001:
			down = prev_dir if prev_dir != Vector2.ZERO \
				else Vector2.RIGHT.rotated(_rng.randf() * TAU)
		down = down.normalized()

		if prev_dir != Vector2.ZERO:
			down = (down * 0.78 + prev_dir * 0.22).normalized()
		down = down.rotated(_rng.randf_range(-0.14, 0.14))
		prev_dir = down

		var next := pos + down * RIVER_MARCH_STEP
		var on_border := next.x <= _map_rect.position.x or next.x >= _map_rect.end.x \
				or next.y <= _map_rect.position.y or next.y >= _map_rect.end.y
		next.x = clampf(next.x, _map_rect.position.x, _map_rect.end.x)
		next.y = clampf(next.y, _map_rect.position.y, _map_rect.end.y)

		# Reached water past the beach: confirm open ocean, then end the river
		# right at the mouth level (just into the water, overlapping the ocean).
		if _land_value(next) <= RIVER_MOUTH_LEVEL:
			if not _is_open_ocean(next):
				return []   # leads to an inland lake — reject
			pts.append(_crossing_at(pos, next, RIVER_MOUTH_LEVEL))
			return pts

		pts.append(next)
		pos = next

		# Ran to the border while still on land — no clean ocean mouth.
		if on_border:
			return []

	return []


func _decimate(pts: Array[Vector2], step: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in pts.size():
		if i % step == 0:
			out.append(pts[i])
	if out.is_empty() or out[out.size() - 1] != pts[pts.size() - 1]:
		out.append(pts[pts.size() - 1])
	return out


## Laplacian smoothing — averages each interior point with its neighbours to
## relax kinks out of the marched path while keeping the endpoints pinned.
func _smooth_path(pts: Array[Vector2], iterations: int) -> Array[Vector2]:
	var p := pts
	for _it in iterations:
		if p.size() < 3:
			return p
		var out: Array[Vector2] = [p[0]]
		for i in range(1, p.size() - 1):
			out.append(p[i - 1] * 0.25 + p[i] * 0.5 + p[i + 1] * 0.25)
		out.append(p[p.size() - 1])
		p = out
	return p


func _ccw(a: Vector2, b: Vector2, c: Vector2) -> bool:
	return (c.y - a.y) * (b.x - a.x) > (b.y - a.y) * (c.x - a.x)


func _seg_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	return _ccw(a, c, d) != _ccw(b, c, d) and _ccw(a, b, c) != _ccw(a, b, d)


## True if the open polyline crosses itself (ignores adjacent segments).
func _polyline_self_intersects(pts: Array[Vector2]) -> bool:
	var n := pts.size()
	for i in range(n - 1):
		for j in range(i + 2, n - 1):
			if _seg_intersect(pts[i], pts[i + 1], pts[j], pts[j + 1]):
				return true
	return false


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
	return base * lerpf(RIVER_SOURCE_WIDTH_RATIO, 1.0, smoothstep(0.0, 1.0, t))


func _place_river(ctrl: Array[Vector2], base_width: float, resources: Node3D) -> void:
	var container    := Node3D.new()
	container.name    = "River"
	var samples : Array[Vector2] = []

	for i in (RIVER_SAMPLES + 1):
		var t   := float(i) / RIVER_SAMPLES
		var pos := _catmull_rom(ctrl, t)
		pos.x    = clampf(pos.x, _map_rect.position.x, _map_rect.end.x)
		pos.y    = clampf(pos.y, _map_rect.position.y, _map_rect.end.y)
		samples.append(pos)
		_river_samples_all.append(pos)
		if i % RIVER_REJECT_STEP == 0:
			_river_points.append(pos)

	# Single soft-edged water ribbon (edges fade into the terrain in-shader).
	container.add_child(_build_river_ribbon(
		samples, base_width, _make_water_material()))

	# Collision chain (water width).
	for i in range(1, samples.size()):
		var w := (_river_width_at(float(i - 1) / samples.size(), base_width) +
				  _river_width_at(float(i)     / samples.size(), base_width)) * 0.5
		container.add_child(RiverSegment.build_segment(
			_to3(samples[i - 1]), _to3(samples[i]), w))

	resources.add_child(container)


## Builds one ribbon mesh that follows `samples`. UV.x spans the width (0..1),
## UV.y runs along the length so the water shader can flow along it. Surface
## height ramps down to sea level wherever the river is over water (the mouth).
func _build_river_ribbon(samples: Array[Vector2], base_width: float,
		mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := samples.size()

	for i in n:
		var t    := float(i) / (n - 1)
		var pos  := samples[i]
		var half := _river_width_at(t, base_width) * 0.5
		var py   := _river_surface_y(pos)

		var tangent: Vector2
		if i == 0:
			tangent = (samples[1] - samples[0]).normalized()
		elif i == n - 1:
			tangent = (samples[i] - samples[i - 1]).normalized()
		else:
			tangent = (samples[i + 1] - samples[i - 1]).normalized()
		var perp := Vector2(-tangent.y, tangent.x)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, t))
		st.add_vertex(Vector3(pos.x - perp.x * half, py, pos.y - perp.y * half))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, t))
		st.add_vertex(Vector3(pos.x + perp.x * half, py, pos.y + perp.y * half))

	var vc := n * 2
	for i in range(0, vc - 2, 2):
		st.add_index(i);     st.add_index(i + 1); st.add_index(i + 2)
		st.add_index(i + 1); st.add_index(i + 3); st.add_index(i + 2)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


## River surface height: RIVER_Y over land, ramping down to ~ocean level as the
## river crosses into the sea so the mouth meets the water instead of floating.
func _river_surface_y(pos: Vector2) -> float:
	var lv := _land_value(pos)
	if lv >= SEA_LEVEL:
		return RIVER_Y
	# Ease from land height at the shore down to the ocean surface at the mouth.
	var span := maxf(SEA_LEVEL - RIVER_MOUTH_LEVEL, 0.0001)
	var k := clampf((SEA_LEVEL - lv) / span, 0.0, 1.0)
	return lerpf(RIVER_Y, OCEAN_Y, k)


func _make_water_material() -> ShaderMaterial:
	# Flat, matte, stylised river — low specular and low cross-section contrast so
	# it reads as water lying on the ground, not a glossy 3D tube. Subtle ripples,
	# a thin foam line at the banks, soft edges and ends that fade into terrain/sea.
	var code := """
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_lambert;

uniform vec4  water_col : source_color = vec4(0.16, 0.42, 0.66, 0.86);
uniform vec4  deep_col  : source_color = vec4(0.11, 0.33, 0.56, 0.88);
uniform vec4  foam_col  : source_color = vec4(0.88, 0.95, 1.00, 0.90);
uniform float speed     : hint_range(0.1, 2.0) = 0.45;

void fragment() {
	float t    = TIME * speed;
	float bank = abs(UV.x - 0.5) * 2.0;          // 0 centre .. 1 edge

	// Gentle, low-contrast ripple so the surface stays flat-looking.
	float rip  = sin(UV.y * 16.0 - t * 2.0) * 0.5 + 0.5;
	float rip2 = sin(UV.y * 8.0 + UV.x * 5.0 - t * 1.2) * 0.5 + 0.5;
	float shade = (rip * 0.5 + rip2 * 0.5) - 0.5;

	// Very mild centre->bank shift (no strong gradient => no cylindrical look).
	vec3 col = mix(deep_col.rgb, water_col.rgb, bank * 0.35);
	col += shade * 0.04;

	// Thin foam line hugging the banks.
	float foam = smoothstep(0.74, 0.90, bank) * (1.0 - smoothstep(0.93, 1.0, bank));
	foam *= 0.6 + 0.4 * sin(UV.y * 20.0 - t * 2.2);
	col = mix(col, foam_col.rgb, clamp(foam, 0.0, 1.0) * 0.8);

	// Soft banks + faded ends.
	float edge_fade = 1.0 - smoothstep(0.90, 1.0, bank);
	float end_fade  = smoothstep(0.0, 0.05, UV.y) * (1.0 - smoothstep(0.90, 1.0, UV.y));
	float a = mix(deep_col.a, water_col.a, bank);

	ALBEDO    = col;
	ALPHA     = a * edge_fade * end_fade;
	ROUGHNESS = 0.65;
	METALLIC  = 0.0;
	SPECULAR  = 0.12;
}
"""
	var sh     := Shader.new()
	sh.code     = code
	var mat    := ShaderMaterial.new()
	mat.shader  = sh
	return mat


# ---------------------------------------------------------------------------
# Mountains — gated by mountain region, scaled much taller
# ---------------------------------------------------------------------------
func _generate_mountain_ranges() -> void:
	var resources   := _get_or_create("Resources")
	var scene_pack  := load(MOUNTAIN_SCENE)
	if scene_pack == null:
		push_warning("MapGenerator: could not load " + MOUNTAIN_SCENE); return

	var area_mpx := (_map_rect.size.x * _map_rect.size.y) / 1_000_000.0
	var ranges   : int = max(int(round(area_mpx * MOUNTAIN_RANGES_PER_MPX)), 1)

	for _r in ranges:
		var centre_v = _random_land_point(SEA_LEVEL + 0.05)
		if centre_v == null:
			continue
		var centre: Vector2 = centre_v

		if _mountain_region(centre) < MOUNTAIN_REGION_THRESHOLD:
			continue

		var dir    := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		var perp   := dir.orthogonal()
		var count  := _rng.randi_range(MOUNTAINS_PER_RANGE_MIN, MOUNTAINS_PER_RANGE_MAX)

		for _n in count:
			var pos := centre \
				+ dir  * _rng.randf_range(-1.0, 1.0) * MOUNTAIN_SPREAD * 2.4 \
				+ perp * _rng.randf_range(-0.45, 0.45) * MOUNTAIN_SPREAD
			if not _map_rect.has_point(pos): continue
			if not _is_land(pos):                        continue
			if _overlaps_river(pos, MOUNTAIN_RADIUS):    continue
			if _overlaps_mountain(pos, MOUNTAIN_RADIUS): continue

			var m: Node3D = scene_pack.instantiate()
			resources.add_child(m)
			var sxz := _rng.randf_range(MOUNTAIN_SCALE_XZ_MIN, MOUNTAIN_SCALE_XZ_MAX)
			var sy  := _rng.randf_range(MOUNTAIN_SCALE_Y_MIN, MOUNTAIN_SCALE_Y_MAX)
			m.scale = Vector3(sxz, sy, sxz)
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
		var centre_v = _random_land_point(SEA_LEVEL + 0.02)
		if centre_v == null:
			continue
		var centre: Vector2 = centre_v
		var count  := _rng.randi_range(TREES_PER_CLUSTER_MIN, TREES_PER_CLUSTER_MAX)
		for _n in count:
			var pos := centre + Vector2(
				_rng.randf_range(-FOREST_SPREAD, FOREST_SPREAD),
				_rng.randf_range(-FOREST_SPREAD, FOREST_SPREAD)
			)
			if not _map_rect.has_point(pos): continue
			if not _is_land(pos):                    continue
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
func _overlaps_river_raw(pos: Vector2, threshold: float) -> bool:
	for p in _river_samples_all:
		if pos.distance_to(p) < threshold:
			return true
	return false


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


func _placement_blocked(pos: Vector2) -> bool:
	if not _is_land(pos):
		return true
	return (
		_overlaps_river(pos, SPAWN_SAFE_RADIUS) or
		_overlaps_mountain(pos, SPAWN_SAFE_RADIUS) or
		_overlaps_tree(pos, SPAWN_SAFE_RADIUS)
	)


# ---------------------------------------------------------------------------
# Town center placement
# ---------------------------------------------------------------------------
func _begin_placement() -> void:
	var scene := get_tree().current_scene
	_ghost = scene.get_node_or_null("PlacementGhost") as MeshInstance3D
	if _ghost == null:
		push_warning("MapGenerator: PlacementGhost node not found in scene.")
		return

	var box      := BoxMesh.new()
	box.size      = Vector3(84, 55, 84)
	_ghost.mesh   = box
	_ghost.visible = true

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
	_ghost.position = Vector3(wp.x, 27.5, wp.z)
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

	var vc_pack := load(VILLAGE_CENTER_SCENE) as PackedScene
	if vc_pack:
		var vc : Node3D = vc_pack.instantiate()
		_get_or_create("Buildings").add_child(vc)
		vc.global_position = place_pos
	else:
		push_warning("MapGenerator: could not load " + VILLAGE_CENTER_SCENE)

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


func _mouse_to_ground() -> Vector3:
	var scene  := get_tree().current_scene
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
func _to3(v: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(v.x, y, v.y)

func _get_or_create(node_name: String) -> Node3D:
	var scene := get_tree().current_scene
	var n     := scene.get_node_or_null(node_name)
	if n == null:
		n = Node3D.new(); n.name = node_name
		scene.add_child.call_deferred(n)
	return n

# Exposes the proven land/ocean test so placement code can block the coast.
func is_land_at(p: Vector2) -> bool:
	return _is_land(p)
