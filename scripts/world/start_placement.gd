extends Node3D
class_name StartPlacement

## Founds your town at game start, Kingdoms-Reborn style: a green ghost follows
## the cursor, left-click drops the Village Center, and 5 citizens spawn on it
## (registered with GameManager so population/births/eating work immediately).
##
## Placement rules for the Town Center: blocked by water, rivers and mountains;
## ALLOWED on trees, which vanish when you build. Set `allow_anywhere` if you'd
## rather be able to drop it literally anywhere (including water/mountains).
##
## Self-contained — just add this node to your main scene. If your map_generator
## still calls `_begin_placement()` in its _ready(), delete that one line.
##
## NETWORKING: founding the town spawns a Village Center and several citizens.
## In a networked game this must happen exactly once, decided by ONE player's
## click, validated/executed by the host, and mirrored to everyone else —
## never independently on every peer who happens to click their own ghost.
## Concretely: the ghost/click UI stays local to every peer (it's just visual
## feedback for "click here to found your town"), but the actual spawn now
## goes through NetworkCommands instead of instantiating scenes directly:
##   - In single-player (no multiplayer peer at all) nothing changes — this
##     peer IS the authority, so it founds the town directly, same as before.
##   - In a networked game, a non-host peer's click sends a request to the
##     host (request_found_town) instead of spawning anything locally; the
##     host validates the spot and does the real spawn, then every peer
##     (including clients) gets the Village Center + citizens via the normal
##     building-spawn and unit-spawn replication paths.
##   - The host's own click founds the town directly (it doesn't need to ask
##     itself permission), exactly like single-player.

@export var village_center_scene: String = "res://scenes/buildings/village_center.tscn"
@export var citizen_scene: String = "res://scenes/units/citizen.tscn"
@export var citizen_count: int = 5
@export var citizen_spawn_radius: float = 90.0
@export var footprint_radius: float = 44.0
@export var ghost_size: Vector3 = Vector3(84, 55, 84)
@export var allow_anywhere: bool = false
@export var ready_sentinel_node: String = "NavFloor"
@export var fallback_arm_delay: float = 3.0

var _ghost: MeshInstance3D = null
var _armed := false
var _done := false
var _valid := false
var _elapsed := 0.0
var _map_size := Vector2.ZERO


func _ready() -> void:
	_map_size = MapSettings.map_size
	if "is_initial_placement" in GameManager:
		GameManager.is_initial_placement = true
	set_process(true)
	set_process_input(true)


func _process(delta: float) -> void:
	if _done:
		return

	if not _armed:
		_elapsed += delta
		var scene := get_tree().current_scene
		var sentinel_ok := ready_sentinel_node == "" or scene.get_node_or_null(ready_sentinel_node) != null
		if _camera() != null and (sentinel_ok or _elapsed >= fallback_arm_delay):
			_arm()
		return

	var wp := _mouse_to_ground()
	_valid = _is_spot_valid(wp)
	_ghost.global_position = Vector3(wp.x, ghost_size.y * 0.5, wp.z)
	var mat := _ghost.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.2, 0.9, 0.2, 0.45) if _valid else Color(0.9, 0.15, 0.15, 0.45)


func _input(event: InputEvent) -> void:
	if not _armed or _done:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _valid:
		_found_town()
		get_viewport().set_input_as_handled()


func _arm() -> void:
	_armed = true
	_ghost = MeshInstance3D.new()
	_ghost.name = "VillageCenterGhost"
	var box := BoxMesh.new()
	box.size = ghost_size
	_ghost.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.2, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = mat
	get_tree().current_scene.add_child(_ghost)
	if GameManager.has_method("notify"):
		GameManager.notify("Found your town — left-click a green spot to place your Village Center.")


## True if THIS peer is allowed to spawn the town directly: single-player, or
## the host in a networked game. A non-host client must ask instead (see
## _found_town below).
func _can_found_directly() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _found_town() -> void:
	_done = true
	if is_instance_valid(_ghost):
		_ghost.queue_free()

	var wp := _mouse_to_ground()
	var place_pos := Vector3(wp.x, 0.0, wp.z)

	if not _can_found_directly():
		# We're a client: don't spawn anything ourselves. Ask the host to do
		# it; the host validates the spot and the resulting Village Center +
		# citizens arrive for us through the normal building/unit spawn
		# replication, same as any other networked spawn.
		#
		# NetworkManager is an autoload, referenced directly like everywhere
		# else in the project. We only reach this branch when
		# _can_found_directly() is false, which itself requires
		# multiplayer.has_multiplayer_peer() to be true — so NetworkManager
		# is guaranteed to be relevant and loaded here.
		var my_team := NetworkManager.my_team()
		NetworkCommands.request_found_town.rpc_id(1, place_pos, my_team)
		set_process(false)
		set_process_input(false)
		if GameManager.has_method("notify"):
			GameManager.notify("Founding town…")
		return

	# Found directly (single-player or host). Use OUR real team rather than a
	# hardcoded 0 — in single-player my_team() degrades to 0, and on the host
	# it's the host's assigned team — so this stays correct either way.
	_execute_found_town(place_pos, _local_team())


## This peer's own team. Falls back to 0 in single-player (no NetworkManager
## peer / before the registry is populated), matching the rest of the project.
func _local_team() -> int:
	var nm := get_node_or_null("/root/NetworkManager")
	if nm == null:
		nm = get_node_or_null("/root/network_manager")
	if nm and nm.has_method("my_team"):
		return nm.my_team()
	return 0


## The actual spawn logic. Only ever runs where _can_found_directly() was
## true at the call site: directly from _found_town() in single-player/host,
## or from NetworkCommands.request_found_town on the host when a client asks.
func _execute_found_town(place_pos: Vector3, team: int) -> void:
	# Any trees under the town vanish — this mutates the shared scene tree,
	# so it must only happen on the authoritative peer too.
	GameManager.clear_trees_at(place_pos, footprint_radius)

	var vc_pack := load(village_center_scene) as PackedScene
	if vc_pack:
		var vc := NetworkCommands.server_spawn_building(village_center_scene, place_pos, team)
		if vc == null:
			push_warning("StartPlacement: server_spawn_building returned null for " + village_center_scene)
	else:
		push_warning("StartPlacement: could not load " + village_center_scene)

	for i in citizen_count:
		var angle := (TAU / citizen_count) * i
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * citizen_spawn_radius
		var cit = NetworkCommands.server_spawn_unit(citizen_scene, place_pos + offset, team)
		if cit == null:
			continue
		if cit.has_method("setup_as_adult"):
			cit.setup_as_adult()
		if GameManager.has_method("register_population"):
			GameManager.register_population(cit)

	if "is_initial_placement" in GameManager:
		GameManager.is_initial_placement = false
	if GameManager.has_method("notify"):
		GameManager.notify("Town founded. You're free to build — open the build menu.")

	var map_gen = get_tree().current_scene.get_node_or_null("MapGenerator")
	if map_gen and map_gen.has_method("rebake_navigation"):
		map_gen.rebake_navigation()

	set_process(false)
	set_process_input(false)


# --- validity: blocked by water/rivers/mountains/buildings; trees are fine ---
func _is_spot_valid(wp: Vector3) -> bool:
	var pos2 := Vector2(wp.x, wp.z)
	if not _in_bounds(pos2):
		return false
	if allow_anywhere:
		return true

	# Coast/ocean via the generator's land field, if available.
	var map_gen = get_tree().current_scene.get_node_or_null("MapGenerator")
	if map_gen and map_gen.has_method("is_land_at"):
		if not map_gen.is_land_at(pos2):
			return false

	var space_state = get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = footprint_radius
	shape.height = 40.0
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, wp)
	query.collision_mask = 1
	for hit in space_state.intersect_shape(query, 16):
		var c = hit.get("collider")
		if c and (c.is_in_group("mountains") or c.is_in_group("rivers") \
				or c.is_in_group("water_sources") or c.is_in_group("buildings")):
			return false
	return true


func _camera() -> Camera3D:
	var scene := get_tree().current_scene
	var c := scene.get_node_or_null("Camera/Camera3D") as Camera3D
	if c == null:
		c = get_viewport().get_camera_3d()
	return c


func _mouse_to_ground() -> Vector3:
	var cam := _camera()
	if cam == null:
		return Vector3.ZERO
	var mpos := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mpos)
	var d := cam.project_ray_normal(mpos)
	if absf(d.y) < 0.0001:
		return Vector3.ZERO
	var t := -o.y / d.y
	return o + d * t


func _in_bounds(p: Vector2) -> bool:
	if _map_size == Vector2.ZERO:
		return true
	return p.x >= 0.0 and p.y >= 0.0 and p.x <= _map_size.x and p.y <= _map_size.y


func _parent(node_name: String) -> Node:
	var scene := get_tree().current_scene
	var n := scene.get_node_or_null(node_name)
	if n == null:
		n = Node3D.new()
		n.name = node_name
		scene.add_child(n)
	return n
