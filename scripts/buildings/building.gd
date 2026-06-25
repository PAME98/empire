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

const GLOBAL_BUILDING_SCALE := 1.75

@export var max_health: int = 400
@export var build_time: float = 6.0
@export var team: int = 0
@export var starts_built: bool = false
@export var building_scale: float = -1.0

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
	pass


func add_build_progress(amount: float) -> void:
	if is_constructed:
		return
	build_progress += amount
	if build_progress >= build_time:
		finish_building()
		# NETWORKING: finishing construction flips is_constructed on the
		# host's copy only. Clients hold their own separate instance of this
		# building and never otherwise learn it finished — push it now
		# instead of waiting for the next periodic building-state sync, so
		# the client's UI/visuals update immediately rather than lagging.
		if GameManager.is_sim_authority():
			var net_id: int = get_meta("building_net_id", -1)
			if net_id != -1:
				NetworkCommands.server_sync_building_state(net_id)


func finish_building() -> void:
	if is_constructed:
		return
	is_constructed = true
	remove_from_group("construction_sites")
	_refresh_construction_visual()


func _refresh_construction_visual() -> void:
	if finished_sprite:
		finished_sprite.visible = true
	if construction_sprite:
		construction_sprite.visible = false
	_apply_build_tint(finished_sprite, not is_constructed)


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


func is_selectable_by_player() -> bool:
	return team == _player_team()


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


## NETWORKING: called on CLIENTS ONLY by NetworkCommands._receive_building_state
## to mirror the host's authoritative construction/health values. Never call
## this on the host — its own values are already correct and authoritative.
func apply_network_state(p_is_constructed: bool, p_build_progress: float, p_health: int) -> void:
	build_progress = p_build_progress
	health = p_health
	if p_is_constructed and not is_constructed:
		finish_building()
	elif not p_is_constructed:
		is_constructed = false
		_refresh_construction_visual()
