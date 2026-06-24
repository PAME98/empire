extends Node

## Add this as a CHILD node of the "UI" CanvasLayer. On ready it:
##   * applies the shared HudTheme to every panel/label/button,
##   * hides the old top resource strip,
##   * builds a clean vertical resource bar down the left edge.
## Pure styling + a new resource readout — it doesn't touch game logic.

const RES := [
	{"key":"food",  "name":"Food",  "color":Color(0.55,0.80,0.35)},
	{"key":"wood",  "name":"Wood",  "color":Color(0.70,0.50,0.30)},
	{"key":"stone", "name":"Stone", "color":Color(0.70,0.72,0.76)},
	{"key":"gold",  "name":"Gold",  "color":Color(0.95,0.80,0.30)},
	{"key":"iron",  "name":"Iron",  "color":Color(0.62,0.66,0.74)},
	{"key":"water", "name":"Water", "color":Color(0.40,0.65,0.95)},
]

var _value_labels: Dictionary = {}
var _pop_label: Label = null


func _ready() -> void:
	var ui := get_parent()
	if ui == null:
		return
	var th := HudTheme.build()
	for c in ui.get_children():
		if c is Control:
			c.theme = th

	var topbar = ui.get_node_or_null("TopBar")
	if topbar:
		topbar.visible = false

	_build_resource_bar(ui, th)

	GameManager.resources_changed.connect(_on_resources_changed)
	_on_resources_changed(GameManager.food, GameManager.wood, GameManager.stone,
		GameManager.gold, GameManager.iron, GameManager.water,
		GameManager.population, GameManager.housing_capacity)


func _build_resource_bar(ui: Node, th: Theme) -> void:
	var panel := Panel.new()
	panel.name = "ResourceBar"
	panel.theme = th
	panel.anchor_left = 0.0; panel.anchor_right = 0.0
	panel.anchor_top = 0.0; panel.anchor_bottom = 0.0
	panel.offset_left = 12.0; panel.offset_top = 12.0
	panel.offset_right = 156.0; panel.offset_bottom = 268.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(panel)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 7)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)

	var title := Label.new()
	title.text = "RESOURCES"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	vb.add_child(title)

	for r in RES:
		vb.add_child(_res_row(r["name"], r["color"], r["key"]))

	var sep := HSeparator.new()
	vb.add_child(sep)

	var pop_row := _res_row("Pop", Color(0.80, 0.55, 0.85), "pop")
	vb.add_child(pop_row)
	_pop_label = _value_labels["pop"]


func _res_row(name: String, color: Color, key: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(dot)

	var nm := Label.new()
	nm.text = name
	nm.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	nm.add_theme_font_size_override("font_size", 13)
	nm.custom_minimum_size = Vector2(46, 0)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(nm)

	var val := Label.new()
	val.text = "0"
	val.add_theme_font_size_override("font_size", 15)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(val)

	_value_labels[key] = val
	return hb


func _on_resources_changed(food: int, wood: int, stone: int, gold: int, iron: int, water: int, population: int, max_population: int) -> void:
	var vals := {"food":food, "wood":wood, "stone":stone, "gold":gold, "iron":iron, "water":water}
	for k in vals:
		if _value_labels.has(k):
			_value_labels[k].text = str(vals[k])
	if _pop_label:
		_pop_label.text = "%d / %d" % [population, max_population]
		_pop_label.add_theme_color_override("font_color",
			Color(1.0, 0.55, 0.5) if population >= max_population else HudTheme.TEXT)
