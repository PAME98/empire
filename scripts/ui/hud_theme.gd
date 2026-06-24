extends RefCounted
class_name HudTheme

## A single dark, semi-transparent, rounded UI theme shared by every HUD element
## so the whole interface looks consistent instead of default-grey. Call
## HudTheme.build() from anywhere; the theme is cached and built once.

static var _cached: Theme

# palette
const BG        := Color(0.09, 0.10, 0.14, 0.86)   # panel background (semi-transparent)
const BG_SOFT   := Color(0.14, 0.16, 0.21, 0.80)
const BORDER    := Color(1, 1, 1, 0.10)
const ACCENT    := Color(0.36, 0.62, 1.00)
const TEXT      := Color(0.90, 0.93, 1.00)
const TEXT_DIM  := Color(0.62, 0.68, 0.80)
const TEXT_OFF  := Color(0.45, 0.49, 0.58)


static func build() -> Theme:
	if _cached:
		return _cached
	var t := Theme.new()
	t.default_font_size = 14

	t.set_stylebox("panel", "Panel", _panel(BG, 12))
	t.set_stylebox("panel", "PanelContainer", _panel(BG, 12))

	# Buttons
	t.set_stylebox("normal",   "Button", _btn(BG_SOFT))
	t.set_stylebox("hover",    "Button", _btn(Color(0.22, 0.26, 0.34, 0.92)))
	t.set_stylebox("pressed",  "Button", _btn(Color(0.30, 0.50, 0.85, 0.95)))
	t.set_stylebox("disabled", "Button", _btn(Color(0.12, 0.13, 0.17, 0.55)))
	t.set_stylebox("focus",    "Button", StyleBoxEmpty.new())
	t.set_color("font_color",          "Button", TEXT)
	t.set_color("font_hover_color",    "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color",  "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", TEXT_OFF)
	t.set_constant("h_separation", "Button", 6)

	# Labels
	t.set_color("font_color", "Label", TEXT)

	# Scroll/containers a touch tighter
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 8)

	# Progress bars (build/health if any use the theme)
	var pbg := _panel(Color(0, 0, 0, 0.4), 6); pbg.set_border_width_all(0)
	var pfg := _panel(ACCENT, 6); pfg.set_border_width_all(0)
	t.set_stylebox("background", "ProgressBar", pbg)
	t.set_stylebox("fill", "ProgressBar", pfg)

	_cached = t
	return t


static func _panel(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = BORDER
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	return sb


static func _btn(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
