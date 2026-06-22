class_name AttackAreaIndicator
extends Node2D

## Reusable area-of-effect visual. Two jobs, one drawing routine:
##   - "targeting" mode: the orange ghost circle that follows the mouse while
##     the player is in attack-position mode (after pressing T), showing
##     exactly where and how big the blast will be before they commit.
##   - "aiming" mode: pinned at the locked impact point while a shell winds
##     up, shrinking and brightening as it gets closer to landing so the
##     player has a fair warning window to react.
## camera_controller.gd drives the first one; Artillery drives the second.

var radius: float = 60.0
var progress: float = 0.0  # 0..1, only used in "aiming" mode
var mode: String = "targeting"  # "targeting" | "aiming"


func _ready() -> void:
	z_index = 50
	top_level = true  # world-space visual, unaffected by parent transforms/zoom tricks


func set_radius(r: float) -> void:
	radius = r
	queue_redraw()


func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	queue_redraw()


func set_mode(m: String) -> void:
	mode = m
	queue_redraw()


func _draw() -> void:
	if mode == "targeting":
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.55, 0.1, 0.16))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.55, 0.1, 0.9), 2.5)
		draw_line(Vector2(-14, 0), Vector2(14, 0), Color(1.0, 0.55, 0.1, 0.9), 2.0)
		draw_line(Vector2(0, -14), Vector2(0, 14), Color(1.0, 0.55, 0.1, 0.9), 2.0)
	else:
		# Windup: a faint outer ring at full blast radius, plus a brighter
		# ring that shrinks inward and shifts toward red as the shot nears.
		var shrink = lerpf(radius, radius * 0.3, progress)
		var col = Color(1.0, 0.85 - 0.65 * progress, 0.1, 0.9)
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.2, 0.05, 0.10))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.2, 0.05, 0.5), 1.5)
		draw_arc(Vector2.ZERO, shrink, 0.0, TAU, 48, col, 3.0)
