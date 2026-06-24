extends Node

const ATLAS := "res://assets/kenney/textures/colormap.png"
const BASE         := "res://assets/kenney/models/"
const BASE_NATURE  := "res://assets/kenney/nature/models/"
const BASE_BUILDINGS := "res://assets/kenney/buildings/"

const SWAP_TABLE: Dictionary = {
	"res://scripts/world/resource_node.gd": {
		"target": "Mesh",
		"by_resource_type": {
			"wood": {
				"base": BASE_NATURE,
				"scale": 55.0,
				"apply_atlas": false,
				"models": [
					"tree_default.glb", "tree_oak.glb", "tree_tall.glb",
					"tree_fat.glb", "tree_simple.glb", "tree_detailed.glb",
					"tree_pineDefaultA.glb", "tree_pineDefaultB.glb",
					"tree_pineTallA.glb", "tree_pineTallB.glb",
				],
			},
			"water": {
				"models": [],  # river tiles handle the visual — skip swap
			},
		},
		"y_offset": 0.0,
	},
	"res://scripts/world/mountain.gd": {
		"target": "Mesh",
		"base": BASE,
		"scale": 80.0,
		"apply_atlas": true,
		"models": ["rock-large.glb","rock-wide.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/house.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": [
			"house_variant_a.glb",
			"house_variant_b.glb",
			"house_variant_c.glb",
			"house_variant_d.glb",
		],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/farm.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["farm.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/grain_farm.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["grain_farm.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/veg_garden.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["veg_garden.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/hunter.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["hunter.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/lumber_camp.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["lumber_camp.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/quarry.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["quarry.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/mine.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["mine.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/herbalist.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["herbalist.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/well.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["well.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/charcoal_kiln.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["charcoal_kiln.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/mill.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["mill.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/bakery.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["bakery.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/sawmill.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["sawmill.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/smelter.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["smelter.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/blacksmith.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["blacksmith.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/apothecary.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["apothecary.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/barracks.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["barracks.glb"],
		"y_offset": 0.0,
	},
	"res://scripts/buildings/village_center.gd": {
		"target": "FinishedMesh",
		"base": BASE_BUILDINGS,
		"scale": 90.0,
		"apply_atlas": false,
		"models": ["village_center.glb"],
		"y_offset": 0.0,
	},
}

var _atlas_mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_atlas_mat = _build_atlas_material()
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if not node.get_script():
		return
	var path = node.get_script().resource_path
	if not SWAP_TABLE.has(path):
		return
	node.ready.connect(_do_swap.bind(node, path), CONNECT_ONE_SHOT)


func _do_swap(node: Node, script_path: String) -> void:
	if not is_instance_valid(node):
		return
	var entry: Dictionary = SWAP_TABLE[script_path]
	var target_name: String = entry.get("target", "FinishedMesh")
	var models: Array
	var base: String
	var scale: float
	var apply_atlas: bool

	if entry.has("by_resource_type"):
		var rtype: String = node.get("resource_type") if node.get("resource_type") != null else ""
		var rentry: Dictionary = entry["by_resource_type"].get(rtype, {})
		if rentry.is_empty() or rentry.get("models", []).is_empty():
			# Hide the placeholder mesh for skipped types (e.g. water)
			var mesh_node := node.get_node_or_null(target_name)
			if mesh_node:
				mesh_node.visible = false
			return
		models      = rentry["models"]
		base        = rentry.get("base", BASE)
		scale       = rentry.get("scale", 18.0)
		apply_atlas = rentry.get("apply_atlas", true)
	else:
		models      = entry.get("models", [])
		if models.is_empty():
			return
		base        = entry.get("base", BASE)
		scale       = entry.get("scale", 18.0)
		apply_atlas = entry.get("apply_atlas", true)

	var filename: String = models[_rng.randi() % models.size()]
	_swap_mesh(node, base + filename, entry.get("y_offset", 0.0), target_name, scale, apply_atlas)


func _swap_mesh(node: Node, glb_path: String, y_offset: float, target_name: String, scale: float, apply_atlas: bool) -> void:
	var target := node.get_node_or_null(target_name) as MeshInstance3D
	if target == null:
		push_warning("MeshSwapper: no " + target_name + " on " + node.name)
		return
	var packed := load(glb_path) as PackedScene
	if packed == null:
		push_warning("MeshSwapper: could not load " + glb_path)
		return
	var model: Node3D = packed.instantiate()
	var source: MeshInstance3D = _find_first_mesh(model)
	if source == null:
		push_warning("MeshSwapper: no MeshInstance3D in " + glb_path)
		model.free()
		return
	target.mesh = source.mesh
	target.scale = Vector3.ONE * scale
	target.position.y = y_offset
	if apply_atlas:
		_apply_atlas(target)
	else:
		for i in target.get_surface_override_material_count():
			target.set_surface_override_material(i, null)
	model.free()


func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result = _find_first_mesh(child)
		if result:
			return result
	return null


func _apply_atlas(root: Node) -> void:
	if root is MeshInstance3D:
		for i in root.get_surface_override_material_count():
			root.set_surface_override_material(i, _atlas_mat)
	for child in root.get_children():
		_apply_atlas(child)


func _build_atlas_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex := load(ATLAS) as Texture2D
	if tex:
		mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.9
	mat.metallic  = 0.0
	return mat
