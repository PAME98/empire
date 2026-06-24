extends Panel
class_name BuildMenu

## Openable, centered, semi-transparent build menu. Hidden by default; opened by
## a "Build" launcher button (added to the UI automatically) or the B key, and
## closed with the launcher, the X, Escape, the dimmed backdrop, or by picking a
## building. Replaces the old always-on bottom bar.
##
## Adding a building = one CATALOG row (+ its scene path in
## camera_controller.BUILDING_SCENES and cost in GameManager.COSTS).

var CATALOG := [
	{"id": "house",         "label": "House",            "cat": "Housing",       "color": Color(0.80, 0.72, 0.55)},
	{"id": "farm",          "label": "Forager's Hut",    "cat": "Food",          "color": Color(0.85, 0.78, 0.25)},
	{"id": "grain_farm",    "label": "Grain Farm",       "cat": "Food",          "color": Color(0.85, 0.75, 0.30)},
	{"id": "veg_garden",    "label": "Vegetable Garden", "cat": "Food",          "color": Color(0.35, 0.65, 0.30)},
	{"id": "hunter",        "label": "Hunter's Hut",     "cat": "Food",          "color": Color(0.55, 0.40, 0.30)},
	{"id": "lumber_camp",   "label": "Lumber Camp",      "cat": "Raw Materials", "color": Color(0.45, 0.55, 0.30)},
	{"id": "quarry",        "label": "Quarry",           "cat": "Raw Materials", "color": Color(0.60, 0.60, 0.62)},
	{"id": "mine",          "label": "Mine",             "cat": "Raw Materials", "color": Color(0.35, 0.35, 0.40)},
	{"id": "herbalist",     "label": "Herbalist's Hut",  "cat": "Raw Materials", "color": Color(0.30, 0.60, 0.50)},
	{"id": "well",          "label": "Well",             "cat": "Raw Materials", "color": Color(0.45, 0.55, 0.65)},
	{"id": "charcoal_kiln", "label": "Charcoal Kiln",    "cat": "Workshops",     "color": Color(0.25, 0.25, 0.28)},
	{"id": "mill",          "label": "Mill",             "cat": "Workshops",     "color": Color(0.80, 0.70, 0.55)},
	{"id": "bakery",        "label": "Bakery",           "cat": "Workshops",     "color": Color(0.78, 0.45, 0.28)},
	{"id": "sawmill",       "label": "Sawmill",          "cat": "Workshops",     "color": Color(0.65, 0.50, 0.35)},
	{"id": "smelter",       "label": "Smelter",          "cat": "Workshops",     "color": Color(0.55, 0.30, 0.25)},
	{"id": "blacksmith",    "label": "Blacksmith",       "cat": "Workshops",     "color": Color(0.40, 0.42, 0.48)},
	{"id": "apothecary",    "label": "Apothecary",       "cat": "Workshops",     "color": Color(0.55, 0.45, 0.65)},
	{"id": "barracks",      "label": "Barracks",         "cat": "Military",      "color": Color(0.65, 0.30, 0.30)},
]

const CATEGORY_ORDER := ["Housing", "Food", "Raw Materials", "Workshops", "Military"]
const GRID_COLUMNS := 2

var _buttons: Dictionary = {}
var _demolish_btn: Button = null
var _launcher: Button = null
var _backdrop: ColorRect = null


func _ready() -> void:
	theme = HudTheme.build()
	# Centered popup.
	anchor_left = 0.5; anchor_right = 0.5; anchor_top = 0.5; anchor_bottom = 0.5
	offset_left = -270.0; offset_right = 270.0; offset_top = -290.0; offset_bottom = 290.0
	z_index = 2
	visible = false

	_build_backdrop()
	_build_ui()
	_build_launcher()

	GameManager.resources_changed.connect(func(_a,_b,_c,_d,_e,_f,_g,_h): _refresh())
	GameManager.placement_mode_changed.connect(func(_active,_id): _refresh())
	if GameManager.has_signal("demolish_mode_changed"):
		GameManager.demolish_mode_changed.connect(_on_demolish_mode_changed)
	_refresh()


# ---- open / close ----------------------------------------------------------
func open() -> void:
	visible = true
	if _backdrop: _backdrop.visible = true
	if _launcher: _launcher.text = "Build  ✕"
	_refresh()

func close() -> void:
	visible = false
	if _backdrop: _backdrop.visible = false
	if _launcher: _launcher.text = "Build  (B)"

func toggle() -> void:
	if visible: close()
	else: open()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			close()
			get_viewport().set_input_as_handled()


func _build_backdrop() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "BuildBackdrop"
	_backdrop.color = Color(0, 0, 0, 0.40)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.z_index = 1
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close())
	get_parent().add_child.call_deferred(_backdrop)


func _build_launcher() -> void:
	_launcher = Button.new()
	_launcher.name = "BuildToggle"
	_launcher.theme = HudTheme.build()
	_launcher.text = "Build  (B)"
	_launcher.anchor_left = 0.0; _launcher.anchor_right = 0.0
	_launcher.anchor_top = 1.0; _launcher.anchor_bottom = 1.0
	_launcher.offset_left = 12.0; _launcher.offset_right = 134.0
	_launcher.offset_top = -46.0; _launcher.offset_bottom = -12.0
	_launcher.pressed.connect(toggle)
	get_parent().add_child.call_deferred(_launcher)


# ---- menu contents ---------------------------------------------------------
func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Build"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(34, 0)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for cat in _ordered_categories():
		var hdr := Label.new()
		hdr.text = cat.to_upper()
		hdr.add_theme_font_size_override("font_size", 12)
		hdr.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
		list.add_child(hdr)

		var grid := GridContainer.new()
		grid.columns = GRID_COLUMNS
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		list.add_child(grid)

		for entry in CATALOG:
			if entry["cat"] == cat:
				grid.add_child(_make_card(entry))

	_demolish_btn = Button.new()
	_demolish_btn.text = "Demolish"
	_demolish_btn.toggle_mode = true
	_demolish_btn.modulate = Color(1.0, 0.78, 0.78)
	_demolish_btn.pressed.connect(_on_demolish_pressed)
	root.add_child(_demolish_btn)


func _make_card(entry: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 44)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_text = true
	card.tooltip_text = "%s\n%s" % [entry["label"], _cost_text(entry["id"])]

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 8)
	card.add_child(pad)

	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)
	pad.add_child(hb)

	var sw := ColorRect.new()
	sw.color = entry["color"]
	sw.custom_minimum_size = Vector2(18, 18)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sw)

	var lbl := Label.new()
	lbl.text = entry["label"]
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 13)
	hb.add_child(lbl)

	var id: String = entry["id"]
	card.pressed.connect(func(): _start_placement(id))
	_buttons[id] = card
	return card


func _ordered_categories() -> Array:
	var seen := {}
	for e in CATALOG:
		seen[e["cat"]] = true
	var ordered: Array = []
	for c in CATEGORY_ORDER:
		if seen.has(c):
			ordered.append(c)
			seen.erase(c)
	var rest := seen.keys()
	rest.sort()
	ordered.append_array(rest)
	return ordered


func _cost_text(id: String) -> String:
	var cost: Dictionary = GameManager.COSTS.get(id, {})
	if cost.is_empty():
		return "(no cost defined)"
	var parts: Array[String] = []
	for k in cost:
		parts.append("%d %s" % [cost[k], k])
	return "Cost: " + ", ".join(parts)


func _refresh() -> void:
	var busy: bool = GameManager.is_placing_building or _demolish_active()
	for id in _buttons:
		var btn: Button = _buttons[id]
		var cost: Dictionary = GameManager.COSTS.get(id, {})
		var affordable: bool = GameManager.can_afford(cost) if not cost.is_empty() else false
		btn.disabled = busy or not affordable


func _demolish_active() -> bool:
	return "is_demolish_mode" in GameManager and GameManager.is_demolish_mode


func _start_placement(building_id: String) -> void:
	if GameManager.is_placing_building:
		return
	if GameManager.is_targeting_attack_position:
		GameManager.cancel_attack_position_targeting()
	if _demolish_active():
		GameManager.cancel_demolish_mode()
	var builder = null
	if GameManager.selected_units.size() == 1 and GameManager.selected_units[0] is Citizen:
		builder = GameManager.selected_units[0]
	GameManager.start_building_placement(building_id, builder)
	close()


func _on_demolish_pressed() -> void:
	if _demolish_active():
		GameManager.cancel_demolish_mode()
	else:
		GameManager.start_demolish_mode()


func _on_demolish_mode_changed(active: bool) -> void:
	_demolish_btn.button_pressed = active
	_demolish_btn.text = "Demolishing… (Esc / right-click to stop)" if active else "Demolish"
	_refresh()
