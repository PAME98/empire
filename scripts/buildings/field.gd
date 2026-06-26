class_name Field
extends Building

## A farmable plot made of CELLS, Kingdoms-Reborn style. You drag a rectangle
## and the field becomes the set of cells inside it that AREN'T blocked by
## trees/rocks/water/buildings — so it conforms around obstacles instead of
## being refused outright. Each cell renders its own soil + crop; the whole
## field shares one work cycle:
##
##   EMPTY --[till]--> TILLED --[sow]--> SOWN --[groom]--> GROOMED
##         --(passive grow timer)-->  READY --[harvest]--> EMPTY (+ crop piles)
##
## Three steps (till/sow/groom) and the harvest are worked by a citizen
## standing at the field calling add_field_progress(); GROOMED->READY is a pure
## timer. Yield, worker slots and total labour scale with the number of cells,
## so a bigger field needs more hands and gives more crop.
##
## SELECTION: shows a green rectangle OUTLINE (not the crude unit-style disc).
## CROP: set_crop()/available_crops() let the UI switch what it grows while the
## plot is empty (Hud shows a crop picker when a built field is selected).
##
## NETWORKING: stage/stage_progress are host-authoritative and mirrored to
## clients via apply_network_state_extra() through the building-state sync, like
## Barracks/VillageCenter. Cell layout is fixed at spawn time and arrives with
## the spawn RPC, so it never needs ongoing syncing.

enum Stage { EMPTY, TILLED, SOWN, GROOMED, READY }

const WORK_GROUP := "fields_needing_work"
const GROW_VISUAL_INTERVAL := 0.5
## Crops the player can switch a field to (UI driven). Add more here + give
## them a colour in DroppedResource / a yield tweak if you want variety.
const CROPS := ["wheat", "vegetables"]

@export var crop_type: String = "wheat"
## Yield for a ~4-cell (one base tile) field; scales linearly with cell count.
@export var base_yield: int = 24
## Seconds of labour per worked stage for a 4-cell field; scales with cells.
@export var till_time: float = 14.0
@export var sow_time: float = 12.0
@export var groom_time: float = 16.0
@export var harvest_time: float = 18.0
## Passive grow seconds (no worker needed) between GROOMED and READY.
@export var grow_time: float = 40.0
@export var max_workers: int = 1

var stage: Stage = Stage.EMPTY
var stage_progress: float = 0.0
var workers: Array = []
var harvest_yield: int = 24

var _cells: Array = []          # local Vector3 cell centres (y = 0)
var _cell_size: float = 32.0
var _labour_factor: float = 1.0
var _soil_meshes: Array = []
var _crop_meshes: Array = []
var _outline: Node3D = null
var _grow_visual_timer: float = 0.0

@onready var _finished: Node3D = get_node_or_null("FinishedMesh")


func _ready() -> void:
	super._ready()
	add_to_group("fields")
	if _cells.is_empty():
		# Dropped without an explicit cell list (e.g. straight into a scene) —
		# seed a single cell so it still works.
		_cells = [Vector3.ZERO]
		_rebuild()
	_refresh_work_group()
	_refresh_visual()


func _process(delta: float) -> void:
	super._process(delta)
	if not GameManager.is_sim_authority():
		return
	if not is_constructed:
		return
	if stage == Stage.GROOMED:
		stage_progress += delta
		_grow_visual_timer += delta
		if _grow_visual_timer >= GROW_VISUAL_INTERVAL:
			_grow_visual_timer = 0.0
			_refresh_visual()
		if stage_progress >= grow_time:
			stage = Stage.READY
			stage_progress = 0.0
			_refresh_work_group()
			_refresh_visual()
			_push_state_sync()


# ---------------------------------------------------------------------------
# Cell layout (set at spawn by FieldPlacer / NetworkCommands)
# ---------------------------------------------------------------------------
## `world_centers` is the list of valid cell centres (Vector3, world space),
## `cell` the grid size. Builds per-cell visuals + a bounding collision and
## scales gameplay with the cell count.
func set_cells(world_centers: Array, cell: float) -> void:
	_cell_size = cell
	_cells.clear()
	for wc in world_centers:
		var w: Vector3 = wc if wc is Vector3 else Vector3(wc.x, 0.0, wc.y)
		_cells.append(w - global_position)
	var n: int = maxi(_cells.size(), 1)
	harvest_yield = maxi(1, int(round(base_yield * n / 4.0)))
	max_workers = clampi(int(round(n * 0.5)), 1, 8)
	_labour_factor = maxf(float(n), 1.0)
	_rebuild()
	_refresh_work_group()
	_refresh_visual()


func cell_count() -> int:
	return _cells.size()


func _rebuild() -> void:
	if _finished == null:
		_finished = get_node_or_null("FinishedMesh")
	for m in _soil_meshes:
		if is_instance_valid(m):
			m.queue_free()
	for m in _crop_meshes:
		if is_instance_valid(m):
			m.queue_free()
	_soil_meshes.clear()
	_crop_meshes.clear()
	if is_instance_valid(_outline):
		_outline.queue_free()
		_outline = null
	if _finished == null:
		return
	var cs := _cell_size
	for c in _cells:
		var soil := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(cs, 2.0, cs)
		soil.mesh = sb
		soil.position = Vector3(c.x, 1.0, c.z)
		_finished.add_child(soil)
		_soil_meshes.append(soil)

		var crop := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(cs * 0.82, 14.0, cs * 0.82)
		crop.mesh = cb
		crop.position = Vector3(c.x, 8.0, c.z)
		crop.visible = false
		_finished.add_child(crop)
		_crop_meshes.append(crop)
	_rebuild_collision()


func _rebuild_collision() -> void:
	# One bounding box over the cells so the field is clickable/selectable and
	# occupies its footprint. The conforming "holes" are visual-only; the
	# obstacles that carved them already block that ground.
	var col := get_node_or_null("CollisionShape3D")
	if col == null:
		return
	var b := _bounds()
	var sh := BoxShape3D.new()
	sh.size = Vector3((b[1].x - b[0].x) + _cell_size, 8.0, (b[1].z - b[0].z) + _cell_size)
	col.shape = sh
	col.position = Vector3((b[0].x + b[1].x) * 0.5, 4.0, (b[0].z + b[1].z) * 0.5)


## Returns [min, max] local-space corners over all cells (centres).
func _bounds() -> Array:
	var mn := Vector3(INF, 0, INF)
	var mx := Vector3(-INF, 0, -INF)
	for c in _cells:
		mn.x = minf(mn.x, c.x); mn.z = minf(mn.z, c.z)
		mx.x = maxf(mx.x, c.x); mx.z = maxf(mx.z, c.z)
	if mn.x == INF:
		mn = Vector3.ZERO; mx = Vector3.ZERO
	return [mn, mx]


# ---------------------------------------------------------------------------
# Work cycle
# ---------------------------------------------------------------------------
func current_stage_time() -> float:
	var base := 0.0
	match stage:
		Stage.EMPTY: base = till_time
		Stage.TILLED: base = sow_time
		Stage.SOWN: base = groom_time
		Stage.READY: base = harvest_time
	return base * _labour_factor


func needs_worker() -> bool:
	return stage != Stage.GROOMED


func assign_worker(worker) -> bool:
	workers = workers.filter(func(w): return is_instance_valid(w))
	if not needs_worker():
		return false
	if workers.size() >= max_workers:
		return false
	if worker in workers:
		return true
	workers.append(worker)
	return true


func remove_worker(worker) -> void:
	workers.erase(worker)


func worker_count() -> int:
	return workers.filter(func(w): return is_instance_valid(w)).size()


func add_field_progress(amount: float) -> void:
	if not GameManager.is_sim_authority():
		return
	if not is_constructed or not needs_worker():
		return
	var required := current_stage_time()
	if required <= 0.0:
		return
	stage_progress += amount
	if stage_progress < required:
		return
	stage_progress = 0.0
	match stage:
		Stage.EMPTY: stage = Stage.TILLED
		Stage.TILLED: stage = Stage.SOWN
		Stage.SOWN: stage = Stage.GROOMED
		Stage.READY:
			_harvest()
			stage = Stage.EMPTY
	_refresh_work_group()
	_refresh_visual()
	_push_state_sync()


func _harvest() -> void:
	var scene := get_tree().current_scene
	var resources := scene.get_node_or_null("Resources")
	var parent: Node = resources if resources else scene
	if not _dropped_resource_available():
		push_warning("Field: DroppedResource missing — crop not dropped.")
		return
	var piles := maxi(1, mini(3, _cells.size()))
	var per_pile := int(ceil(float(harvest_yield) / piles))
	var remaining := harvest_yield
	for _i in piles:
		if remaining <= 0:
			break
		var amt := mini(per_pile, remaining)
		remaining -= amt
		var cell: Vector3 = _cells.pick_random() if not _cells.is_empty() else Vector3.ZERO
		DroppedResource.spawn(crop_type, amt, global_position + cell, parent, _cell_size * 0.4)
	GameManager.notify("%s harvested." % crop_type.capitalize())


func _refresh_work_group() -> void:
	if needs_worker() and is_constructed:
		add_to_group(WORK_GROUP)
	else:
		remove_from_group(WORK_GROUP)
		for w in workers.duplicate():
			if is_instance_valid(w) and w.has_method("release_from_field"):
				w.release_from_field(self)
		workers.clear()


## THE WORK FIX: a placed field is a construction site first; once a citizen
## finishes building it we must (re)join the work group, or no field hand ever
## picks it up. Building.finish_building doesn't know about that, so override.
func finish_building() -> void:
	var was := is_constructed
	super.finish_building()
	if is_constructed and not was:
		_refresh_work_group()
		_refresh_visual()
		_push_state_sync()


func _push_state_sync() -> void:
	var net_id: int = get_meta("building_net_id", -1)
	if net_id != -1:
		NetworkCommands.server_sync_building_state(net_id)


# ---------------------------------------------------------------------------
# Crop selection
# ---------------------------------------------------------------------------
func available_crops() -> Array:
	return CROPS


func set_crop(type: String) -> void:
	if not (type in CROPS):
		return
	if type == crop_type:
		return
	crop_type = type
	# If the plot is already past sowing, restart the cycle so the new crop is
	# what actually grows (you don't harvest wheat from a field you just set to
	# vegetables). Tilled soil is kept.
	if stage in [Stage.SOWN, Stage.GROOMED, Stage.READY]:
		stage = Stage.TILLED
		stage_progress = 0.0
		_refresh_work_group()
		_push_state_sync()
	_refresh_visual()
	GameManager.notify("Field set to grow %s." % type.capitalize())


# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------
func _refresh_visual() -> void:
	var soil_colors := {
		Stage.EMPTY:   Color(0.45, 0.36, 0.22),
		Stage.TILLED:  Color(0.32, 0.24, 0.14),
		Stage.SOWN:    Color(0.30, 0.23, 0.14),
		Stage.GROOMED: Color(0.30, 0.23, 0.14),
		Stage.READY:   Color(0.30, 0.23, 0.14),
	}
	var soil_c: Color = soil_colors.get(stage, Color(0.4, 0.32, 0.2))
	for s in _soil_meshes:
		if is_instance_valid(s):
			var m := StandardMaterial3D.new()
			m.albedo_color = soil_c
			s.material_override = m
	var show_crop: bool = stage in [Stage.SOWN, Stage.GROOMED, Stage.READY]
	var ratio := 0.3
	match stage:
		Stage.GROOMED: ratio = clampf(0.3 + 0.7 * (stage_progress / maxf(grow_time, 0.01)), 0.3, 1.0)
		Stage.READY: ratio = 1.0
	var crop_c := _crop_color()
	for c in _crop_meshes:
		if is_instance_valid(c):
			c.visible = show_crop
			c.scale = Vector3(1.0, ratio, 1.0)
			var cm := StandardMaterial3D.new()
			cm.albedo_color = crop_c
			c.material_override = cm


func _crop_color() -> Color:
	if stage == Stage.READY:
		return Color(0.85, 0.7, 0.2) if crop_type == "wheat" else Color(0.85, 0.55, 0.2)
	return Color(0.55, 0.72, 0.2) if crop_type == "wheat" else Color(0.35, 0.6, 0.25)


func stage_label() -> String:
	match stage:
		Stage.EMPTY: return "Empty — needs tilling"
		Stage.TILLED: return "Tilled — needs sowing"
		Stage.SOWN: return "Sown — needs grooming"
		Stage.GROOMED: return "Growing…"
		Stage.READY: return "Ready to harvest"
	return "?"


# ---------------------------------------------------------------------------
# Selection — green outline, NOT the unit-style disc ring
# ---------------------------------------------------------------------------
func set_selected(value: bool) -> void:
	selected = value
	if value:
		_show_outline()
	elif is_instance_valid(_outline):
		_outline.visible = false


func _show_outline() -> void:
	if not is_instance_valid(_outline):
		_outline = _build_outline()
		add_child(_outline)
	_outline.visible = true


func _build_outline() -> Node3D:
	var root := Node3D.new()
	var b := _bounds()
	var half := _cell_size * 0.5
	var x0 :Variant = b[0].x - half
	var x1 :Variant = b[1].x + half
	var z0 :Variant = b[0].z - half
	var z1 :Variant = b[1].z + half
	var thick := 3.0
	var y := 1.6
	var col := Color(0.30, 1.0, 0.45, 0.9)
	root.add_child(_edge(Vector3((x0 + x1) * 0.5, y, z0), Vector3(x1 - x0 + thick, thick, thick), col))
	root.add_child(_edge(Vector3((x0 + x1) * 0.5, y, z1), Vector3(x1 - x0 + thick, thick, thick), col))
	root.add_child(_edge(Vector3(x0, y, (z0 + z1) * 0.5), Vector3(thick, thick, z1 - z0 + thick), col))
	root.add_child(_edge(Vector3(x1, y, (z0 + z1) * 0.5), Vector3(thick, thick, z1 - z0 + thick), col))
	return root


func _edge(pos: Vector3, size: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	mi.material_override = m
	return mi


# ---------------------------------------------------------------------------
func _dropped_resource_available() -> bool:
	return ResourceLoader.exists("res://scripts/world/dropped_resource.gd")


func destroy() -> void:
	for w in workers.duplicate():
		if is_instance_valid(w) and w.has_method("release_from_field"):
			w.release_from_field(self)
	workers.clear()
	super.destroy()


func apply_network_state_extra(p_stage: int, p_stage_progress: float) -> void:
	stage = p_stage as Stage
	stage_progress = p_stage_progress
	_refresh_work_group()
	_refresh_visual()
