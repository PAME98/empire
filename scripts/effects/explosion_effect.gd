class_name ExplosionEffect
extends Node3D

## Self-contained, self-cleaning impact visual: an expanding dome + flash that
## fades over a fraction of a second. Spawned at the exact impact point. Builds
## its own mesh so the scene is just a bare Node3D + this script.

var _radius: float = 60.0
var _t: float = 0.0
var _duration: float = 0.45

var _flash: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	_flash = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	_flash.mesh = sphere
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(1.0, 0.6, 0.15, 0.65)
	_flash.material_override = _mat
	add_child(_flash)
	set_process(false)


func detonate(radius: float) -> void:
	_radius = radius
	_t = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _duration:
		queue_free()
		return
	var p := clampf(_t / _duration, 0.0, 1.0)
	var r := lerpf(_radius * 0.15, _radius, ease(p, 0.3))
	# Flattened dome so it reads as a ground blast rather than a full sphere.
	_flash.scale = Vector3(r, r * 0.5, r)
	_mat.albedo_color.a = (1.0 - p) * 0.7
