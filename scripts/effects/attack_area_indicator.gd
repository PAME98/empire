class_name AttackAreaIndicator
extends Node3D

## Reusable area-of-effect ground marker. Two modes share one flat disc:
##   - "targeting": the orange ghost that follows the mouse while the player is
##     choosing where artillery will strike.
##   - "aiming": pinned at the locked impact point while a shell winds up,
##     shrinking and reddening as it nears landing for a fair warning window.
## Built in code so the scene is a bare Node3D + this script.

var radius: float = 60.0
var progress: float = 0.0      # 0..1, only used in "aiming" mode
var mode: String = "targeting" # "targeting" | "aiming"

var _disc: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	_disc = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.5
	_disc.mesh = cyl
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc.material_override = _mat
	add_child(_disc)
	_apply()


func set_radius(r: float) -> void:
	radius = r
	_apply()


func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	_apply()


func set_mode(m: String) -> void:
	mode = m
	_apply()


func _apply() -> void:
	if _disc == null:
		return
	if mode == "targeting":
		_disc.scale = Vector3(radius, 1.0, radius)
		_mat.albedo_color = Color(1.0, 0.55, 0.1, 0.28)
	else:
		var shrink := lerpf(radius, radius * 0.3, progress)
		_disc.scale = Vector3(shrink, 1.0, shrink)
		_mat.albedo_color = Color(1.0, 0.85 - 0.65 * progress, 0.1, 0.5)
