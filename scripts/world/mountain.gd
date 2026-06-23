class_name Mountain
extends StaticBody3D

## A mountain is solid terrain that holds two independent mineral pools:
## STONE (every mountain has some) and IRON (only some mountains do). You don't
## gather a mountain by hand — instead you build a Quarry on it to extract its
## stone, and/or a Mine on it to extract its iron. Because the pools are
## separate, the same mountain can host both a quarry and a mine at once.
##
## A mountain advertises itself to deposit-backed buildings through groups:
##   "stone_sources" while it still has stone, "iron_sources" while it has iron.
## ResourceBuilding.bind_to_deposit() looks the mountain up by those groups and
## ResourceBuilding._process() drains the matching pool via harvest().

@export var stone_amount: int = 9000
@export var iron_amount: int = 4500  # 0 = an ordinary mountain with no iron

var max_stone: int
var max_iron: int

var selected: bool = false
var _selection_ring: MeshInstance3D = null

@onready var iron_vein: Node = get_node_or_null("IronVein")


func _ready() -> void:
	max_stone = stone_amount
	max_iron = iron_amount
	add_to_group("mountains")
	_refresh_groups()
	# The iron vein marker is only shown on iron-bearing mountains so the
	# player can tell at a glance where to put a mine.
	if iron_vein:
		iron_vein.visible = iron_amount > 0


## How much of a given resource ("stone" / "iron") this mountain still holds.
func remaining(resource: String) -> int:
	match resource:
		"stone": return stone_amount
		"iron": return iron_amount
	return 0


## Pull up to `requested` units of `resource` out of the mountain.
func harvest(resource: String, requested: int) -> int:
	var actual := 0
	match resource:
		"stone":
			actual = mini(requested, stone_amount)
			stone_amount -= actual
		"iron":
			actual = mini(requested, iron_amount)
			iron_amount -= actual
	_refresh_groups()
	_refresh_visual()
	return actual


## With no argument: true only when BOTH pools are empty. With a resource name:
## true when that specific pool is empty (what a quarry/mine checks).
func is_depleted(resource: String = "") -> bool:
	match resource:
		"stone": return stone_amount <= 0
		"iron": return iron_amount <= 0
	return stone_amount <= 0 and iron_amount <= 0


func _refresh_groups() -> void:
	_set_in_group("stone_sources", stone_amount > 0)
	_set_in_group("iron_sources", iron_amount > 0)


func _set_in_group(group_name: String, want: bool) -> void:
	if want and not is_in_group(group_name):
		add_to_group(group_name)
	elif not want and is_in_group(group_name):
		remove_from_group(group_name)


func _refresh_visual() -> void:
	if iron_vein:
		iron_vein.visible = iron_amount > 0


# ---------------------------------------------------------------------------
# Selection (left-click) — terrain isn't commandable, but selecting it shows
# how much stone/iron is left and reminds the player how to extract it.
# ---------------------------------------------------------------------------
func set_selected(value: bool) -> void:
	selected = value
	if value and _selection_ring == null:
		_selection_ring = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 48.0
		disc.bottom_radius = 48.0
		disc.height = 0.5
		_selection_ring.mesh = disc
		_selection_ring.position.y = 0.3
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0, 1, 0, 0.5)
		_selection_ring.material_override = mat
		add_child(_selection_ring)
	if _selection_ring:
		_selection_ring.visible = value
