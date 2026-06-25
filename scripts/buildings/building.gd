class_name Building
extends StaticBody3D

## Shared base for all structures: village center, houses, resource buildings,
## barracks. Handles construction progress, health, and selection — concrete
## buildings add production/training behaviour on top.
##
## 3D port: instead of swapping an (often empty) ConstructionMesh in for the
## FinishedMesh, the real model is ALWAYS shown and simply tinted translucent
## while the building is still going up. This guarantees a placed building is
## never invisible, even if its scene only defines a FinishedMesh and leaves
## ConstructionMesh empty.

signal destroyed(building)

## ---------------------------------------------------------------------------
## GLOBAL SIZE. Every building's root is scaled by this on spawn, so models,
## collision and selection ring all grow together and stay grounded (model
## bases sit at local y=0, so scaling about the origin keeps them on the floor).
## Change this ONE number to make every building bigger or smaller.
## Per-scene exceptions: set `building_scale` in the inspector ( > 0 overrides ).
## ---------------------------------------------------------------------------
const GLOBAL_BUILDING_SCALE := 1.75

@export var max_health: int = 400
@export var build_time: float = 6.0
@export var team: int = 0
## When true the building is already finished on spawn (used for the
## hand-placed starting buildings).
@export var starts_built: bool = false
## Per-building size override. -1 = use GLOBAL_BUILDING_SCALE.
@export var building_scale: float = -1.0

## Tint applied over the model while it is still under construction.
const BUILD_TINT := Color(0.5, 0.8, 1.0, 0.5)

var health: int
var build_progress: float = 0.0
var is_constructed: bool = false
var selected: bool = false

@onready var construction_sprite: Node = get_node_or_null("ConstructionMesh")
@onready var finished_sprite: Node = get_node_or_null("FinishedMesh")
@onready var selection_ring: Node = get_node_or_null("SelectionRing")


func _ready() -> void:
	health = max_health
	add_to_group("buildings")

	# Apply the global (or per-building) size multiplier to the whole root.
	var s := building_scale if building_scale > 0.0 else GLOBAL_BUILDING_SCALE
	scale = Vector3.ONE * s

	if starts_built:
		build_progress = build_time
	if not is_constructed and not starts_built:
		add_to_group("construction_sites")
	_refresh_construction_visual()
	if selection_ring:
		selection_ring.visible = false
	if not is_constructed and build_progress >= build_time:
		finish_building()


func _process(_delta: float) -> void:
	# Kept so subclasses can safely call super._process(delta).
	pass


func add_build_progress(amount: float) -> void:
	if is_constructed:
		return
	build_progress += amount
	if build_progress >= build_time:
		finish_building()


func finish_building() -> void:
	if is_constructed:
		return
	is_constructed = true
	remove_from_group("construction_sites")
	_refresh_construction_visual()


func _refresh_construction_visual() -> void:
	# Always show the real model. The old behaviour hid FinishedMesh and showed
	# ConstructionMesh, but every building scene leaves ConstructionMesh empty,
	# so freshly-placed buildings were invisible until a citizen finished them.
	if finished_sprite:
		finished_sprite.visible = true
	# Keep any legacy ConstructionMesh hidden — the tint conveys "building".
	if construction_sprite:
		construction_sprite.visible = false
	_apply_build_tint(finished_sprite, not is_constructed)


## Recursively overlays (un-constructed) or clears (finished) the build tint on
## every GeometryInstance3D under the model root. material_overlay is used so we
## never disturb the model's own materials.
func _apply_build_tint(root: Node, building: bool) -> void:
	if root == null:
		return
	if root is GeometryInstance3D:
		if building:
			var m := StandardMaterial3D.new()
			m.albedo_color = BUILD_TINT
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			root.material_overlay = m
		else:
			root.material_overlay = null
	for c in root.get_children():
		_apply_build_tint(c, building)


## Approximate world-space footprint radius: half the larger XZ extent of the
## CollisionShape3D, multiplied by the applied (uniform) building scale. Used to
## keep buildings from overlapping each other.
func footprint_radius() -> float:
	var col := get_node_or_null("CollisionShape3D")
	var base := 36.0
	if col and col.shape:
		var sh = col.shape
		if sh is BoxShape3D:
			base = maxf(sh.size.x, sh.size.z) * 0.5
		elif sh is CylinderShape3D:
			base = sh.radius
		elif sh is SphereShape3D:
			base = sh.radius
	return base * scale.x


## World-space half-extents (x, z) of the footprint, from the CollisionShape3D
## box, multiplied by the applied scale. Used for grid-snapped, touch-allowed
## overlap tests (so buildings can sit in adjacent cells without "blocking").
func footprint_extents() -> Vector2:
	var col := get_node_or_null("CollisionShape3D")
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
		elif sh is SphereShape3D:
			hx = sh.radius
			hz = sh.radius
	return Vector2(hx, hz) * scale.x


func set_selected(value: bool) -> void:
	selected = value
	if selection_ring:
		selection_ring.visible = value


## True if the LOCAL player owns this building and may select/command it.
## Without this, every peer could select any building (the host, as team 0,
## could select and command the client's buildings). Mirrors Unit's gate.
func is_selectable_by_player() -> bool:
	return team == _player_team()


## This peer's team — 0 in single-player, else the assigned multiplayer team.
func _player_team() -> int:
	var nm := get_node_or_null("/root/NetworkManager")
	if nm == null:
		nm = get_node_or_null("/root/network_manager")
	if nm and nm.has_method("my_team"):
		return nm.my_team()
	return 0

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		destroy()


func destroy() -> void:
	destroyed.emit(self)
	queue_free()
