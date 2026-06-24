extends Panel
class_name BuildMenu

## Single-source-of-truth build menu. Every placeable building is one row in
## CATALOG; the menu builds itself into per-category grids, each card showing a
## colour swatch that matches the building's in-world mesh, the name, and its
## cost as a tooltip. Cards grey out when unaffordable or while you're busy
## placing/demolishing. A Demolish toggle at the bottom enters removal mode.
##
## Adding a building later = one CATALOG row (+ its scene path in
## camera_controller.BUILDING_SCENES and cost in GameManager.COSTS).
##
## Builds its own scroll/grid at runtime, so the scene is just a Panel — no
## fragile @onready node paths to keep in sync.

# id, label, category, swatch colour (match each building's FinishedMesh albedo;
# tweak freely — this only drives the swatch).
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

var _buttons: Dictionary = {}   # id -> Button (the build cards)
var _demolish_btn: Button = null


func _ready() -> void:
	custom_minimum_size = Vector2(280, 380)
	_build_ui()

	GameManager.resources_changed.connect(func(_a, _b, _c, _d, _e, _f, _g, _h): _refresh())
	GameManager.placement_mode_changed.connect(func(_active, _id): _refresh())
	# These two require the GameManager demolish patch (see the .md). If you
	# haven't added them yet, comment this line out to load the menu.
	GameManager.demolish_mode_changed.connect(_on_demolish_mode_changed)
	_refresh()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Build"
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	for cat in _ordered_categories():
		var header := Label.new()
		header.text = cat
		header.add_theme_font_size_override("font_size", 13)
		header.modulate = Color(0.72, 0.78, 0.9)
		list.add_child(header)

		var grid := GridContainer.new()
		grid.columns = GRID_COLUMNS
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		list.add_child(grid)

		for entry in CATALOG:
			if entry["cat"] == cat:
				grid.add_child(_make_card(entry))

	# Demolish toggle, pinned under the scroll area.
	_demolish_btn = Button.new()
	_demolish_btn.text = "Demolish"
	_demolish_btn.toggle_mode = true
	_demolish_btn.modulate = Color(1.0, 0.7, 0.7)
	_demolish_btn.pressed.connect(_on_demolish_pressed)
	root.add_child(_demolish_btn)


func _make_card(entry: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 34)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_text = true
	card.tooltip_text = "%s\n%s" % [entry["label"], _cost_text(entry["id"])]

	# A swatch + label laid over the button. mouse_filter IGNORE so the click
	# still lands on the button underneath.
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 6)
	card.add_child(pad)

	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 8)
	pad.add_child(hb)

	var sw := ColorRect.new()
	sw.color = entry["color"]
	sw.custom_minimum_size = Vector2(14, 14)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sw)

	var lbl := Label.new()
	lbl.text = entry["label"]
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 12)
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


func _on_demolish_pressed() -> void:
	if _demolish_active():
		GameManager.cancel_demolish_mode()
	else:
		GameManager.start_demolish_mode()


func _on_demolish_mode_changed(active: bool) -> void:
	_demolish_btn.button_pressed = active
	_demolish_btn.text = "Demolishing… (Esc / right-click to stop)" if active else "Demolish"
	_refresh()
