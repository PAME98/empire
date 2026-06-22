class_name ExplosionEffect
extends Node2D

## Self-contained, self-cleaning impact visual: an expanding ring + flash
## that fades out over a fraction of a second. Spawned at the exact impact
## point so the player gets unambiguous feedback about which area was just
## hit, independent from (and outliving) the unit that fired the shot.

var _radius: float = 60.0
var _t: float = 0.0
var _duration: float = 0.45


func _ready() -> void:
	z_index = 60
	top_level = true
	set_process(false)


func detonate(radius: float) -> void:
	_radius = radius
	_t = 0.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t >= _duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var p = clampf(_t / _duration, 0.0, 1.0)
	var r = lerpf(_radius * 0.15, _radius, ease(p, 0.3))
	var alpha = 1.0 - p
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.55, 0.1, 0.35 * alpha))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1.0, 0.85, 0.3, alpha), 4.0)
	draw_circle(Vector2.ZERO, r * 0.3, Color(1.0, 0.95, 0.7, alpha))
