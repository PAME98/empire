extends Node

## ONE-FILE HUD. Add this as an Autoload (Project > Project Settings > Globals >
## Autoload), name it "Hud". It needs NOTHING else — no scene edits, no other
## scripts. When the game's "UI" CanvasLayer appears it:
##   * applies a dark, semi-transparent, rounded theme to every panel/label/button
##   * hides the old top resource strip and the old bottom build bar
##   * adds a clean resource bar down the LEFT edge
##   * adds an openable, centered, semi-transparent BUILD menu (button + B key)
##
## If you previously added hud_skin.gd / hud_theme.gd or edited build_menu.gd,
## you can ignore/remove them — this supersedes all of it.

# ---- palette ----
const BG       := Color(0.09, 0.10, 0.14, 0.88)
const BG_SOFT  := Color(0.15, 0.17, 0.22, 0.85)
const BORDER   := Color(1, 1, 1, 0.10)
const ACCENT   := Color(0.36, 0.62, 1.00)
const TEXT     := Color(0.90, 0.93, 1.00)
const TEXT_DIM := Color(0.62, 0.68, 0.80)
const TEXT_OFF := Color(0.45, 0.49, 0.58)

const RES := [
	{"key":"food",  "name":"Food",  "color":Color(0.55,0.80,0.35)},
	{"key":"wood",  "name":"Wood",  "color":Color(0.70,0.50,0.30)},
	{"key":"stone", "name":"Stone", "color":Color(0.70,0.72,0.76)},
	{"key":"gold",  "name":"Gold",  "color":Color(0.95,0.80,0.30)},
	{"key":"iron",  "name":"Iron",  "color":Color(0.62,0.66,0.74)},
	{"key":"water", "name":"Water", "color":Color(0.40,0.65,0.95)},
]

const CATALOG := [
	{"id":"house","label":"House","cat":"Housing","color":Color(0.80,0.72,0.55)},
	{"id":"farm","label":"Forager's Hut","cat":"Food","color":Color(0.85,0.78,0.25)},
	{"id":"grain_farm","label":"Grain Farm","cat":"Food","color":Color(0.85,0.75,0.30)},
	{"id":"veg_garden","label":"Vegetable Garden","cat":"Food","color":Color(0.35,0.65,0.30)},
	{"id":"hunter","label":"Hunter's Hut","cat":"Food","color":Color(0.55,0.40,0.30)},
	{"id":"lumber_camp","label":"Lumber Camp","cat":"Raw Materials","color":Color(0.45,0.55,0.30)},
	{"id":"quarry","label":"Quarry","cat":"Raw Materials","color":Color(0.60,0.60,0.62)},
	{"id":"mine","label":"Mine","cat":"Raw Materials","color":Color(0.35,0.35,0.40)},
	{"id":"herbalist","label":"Herbalist's Hut","cat":"Raw Materials","color":Color(0.30,0.60,0.50)},
	{"id":"well","label":"Well","cat":"Raw Materials","color":Color(0.45,0.55,0.65)},
	{"id":"charcoal_kiln","label":"Charcoal Kiln","cat":"Workshops","color":Color(0.25,0.25,0.28)},
	{"id":"mill","label":"Mill","cat":"Workshops","color":Color(0.80,0.70,0.55)},
	{"id":"bakery","label":"Bakery","cat":"Workshops","color":Color(0.78,0.45,0.28)},
	{"id":"sawmill","label":"Sawmill","cat":"Workshops","color":Color(0.65,0.50,0.35)},
	{"id":"smelter","label":"Smelter","cat":"Workshops","color":Color(0.55,0.30,0.25)},
	{"id":"blacksmith","label":"Blacksmith","cat":"Workshops","color":Color(0.40,0.42,0.48)},
	{"id":"apothecary","label":"Apothecary","cat":"Workshops","color":Color(0.55,0.45,0.65)},
	{"id":"barracks","label":"Barracks","cat":"Military","color":Color(0.65,0.30,0.30)},
]
const CATEGORY_ORDER := ["Housing","Food","Raw Materials","Workshops","Military"]

var _theme: Theme
var _ui: CanvasLayer = null
var _value_labels := {}
var _pop_label: Label = null
var _menu: Panel = null
var _backdrop: ColorRect = null
var _launcher: Button = null
var _cards := {}
var _demolish_btn: Button = null
var _gm_connected := false


func _ready() -> void:
	# NOTE: deliberately does NOT touch GameManager here. Autoloads run _ready in
	# list order, so if Hud is above GameManager, accessing it now would crash
	# and the whole HUD would silently never run. We wait until a scene UI shows
	# up (by then every autoload exists).
	print("[Hud] ready — waiting for UI CanvasLayer")
	_theme = _make_theme()
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_try_existing")


func _connect_game_manager() -> void:
	if _gm_connected:
		return
	if typeof(GameManager) == TYPE_NIL:
		return
	if GameManager.has_signal("resources_changed") and not GameManager.resources_changed.is_connected(_on_resources_changed):
		GameManager.resources_changed.connect(_on_resources_changed)
	if GameManager.has_signal("placement_mode_changed") and not GameManager.placement_mode_changed.is_connected(_on_placement_changed):
		GameManager.placement_mode_changed.connect(_on_placement_changed)
	_gm_connected = true


func _on_placement_changed(_a, _b) -> void:
	_refresh_cards()


func _try_existing() -> void:
	var s := get_tree().current_scene
	if s:
		var ui := s.get_node_or_null("UI")
		if ui is CanvasLayer:
			_install(ui)


func _on_node_added(n: Node) -> void:
	if n is CanvasLayer and n.name == "UI":
		if n.is_node_ready():
			_install(n)
		else:
			n.ready.connect(_install.bind(n), CONNECT_ONE_SHOT)


func _install(ui: CanvasLayer) -> void:
	if ui == _ui and is_instance_valid(_menu):
		return
	print("[Hud] installing on UI: ", ui.get_path())
	_ui = ui
	# theme existing panels
	for c in ui.get_children():
		if c is Control:
			c.theme = _theme
	# hide the old top resource strip and old bottom build bar
	for nm in ["TopBar", "BuildMenu"]:
		var old = ui.get_node_or_null(nm)
		if old:
			old.visible = false
	# build our stuff (deferred so it runs after any old menu's deferred adds)
	call_deferred("_build_all")


func _build_all() -> void:
	if not is_instance_valid(_ui):
		return
	_connect_game_manager()
	# clear anything we (or an old build_menu) made, so re-installs don't stack
	for nm in ["ResourceBar", "HudMenu", "HudBackdrop", "HudBuildToggle", "BuildToggle", "BuildBackdrop"]:
		var old = _ui.get_node_or_null(nm)
		if old:
			old.queue_free()
	_build_resource_bar()
	_build_menu()
	_refresh_resources()
	_refresh_cards()
	print("[Hud] installed — resource bar + build menu added")


# ===========================================================================
# Resource bar (left)
# ===========================================================================
func _build_resource_bar() -> void:
	var panel := Panel.new()
	panel.name = "ResourceBar"
	panel.theme = _theme
	panel.anchor_left = 0; panel.anchor_right = 0; panel.anchor_top = 0; panel.anchor_bottom = 0
	panel.offset_left = 12; panel.offset_top = 12; panel.offset_right = 160; panel.offset_bottom = 272
	_ui.add_child(panel)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 7)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)

	var title := Label.new()
	title.text = "RESOURCES"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", TEXT_DIM)
	vb.add_child(title)

	for r in RES:
		vb.add_child(_res_row(r["name"], r["color"], r["key"]))
	vb.add_child(HSeparator.new())
	vb.add_child(_res_row("Pop", Color(0.80,0.55,0.85), "pop"))
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
	nm.add_theme_color_override("font_color", TEXT_DIM)
	nm.add_theme_font_size_override("font_size", 13)
	nm.custom_minimum_size = Vector2(48, 0)
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


func _refresh_resources() -> void:
	_on_resources_changed(GameManager.food, GameManager.wood, GameManager.stone,
		GameManager.gold, GameManager.iron, GameManager.water,
		GameManager.population, GameManager.housing_capacity)


func _on_resources_changed(food:int, wood:int, stone:int, gold:int, iron:int, water:int, population:int, max_population:int) -> void:
	var vals := {"food":food,"wood":wood,"stone":stone,"gold":gold,"iron":iron,"water":water}
	for k in vals:
		if _value_labels.has(k) and is_instance_valid(_value_labels[k]):
			_value_labels[k].text = str(vals[k])
	if is_instance_valid(_pop_label):
		_pop_label.text = "%d / %d" % [population, max_population]
		_pop_label.add_theme_color_override("font_color",
			Color(1.0,0.55,0.5) if population >= max_population else TEXT)


# ===========================================================================
# Build menu (centered popup + launcher + backdrop)
# ===========================================================================
func _build_menu() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "HudBackdrop"
	_backdrop.color = Color(0, 0, 0, 0.40)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_menu())
	_ui.add_child(_backdrop)

	_menu = Panel.new()
	_menu.name = "HudMenu"
	_menu.theme = _theme
	_menu.anchor_left = 0.5; _menu.anchor_right = 0.5; _menu.anchor_top = 0.5; _menu.anchor_bottom = 0.5
	_menu.offset_left = -270; _menu.offset_right = 270; _menu.offset_top = -290; _menu.offset_bottom = 290
	_menu.visible = false
	_ui.add_child(_menu)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side, 6)
	_menu.add_child(margin)

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
	var x := Button.new()
	x.text = "✕"; x.custom_minimum_size = Vector2(34,0)
	x.pressed.connect(_close_menu)
	header.add_child(x)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for cat in CATEGORY_ORDER:
		var hdr := Label.new()
		hdr.text = cat.to_upper()
		hdr.add_theme_font_size_override("font_size", 12)
		hdr.add_theme_color_override("font_color", TEXT_DIM)
		list.add_child(hdr)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		list.add_child(grid)
		for e in CATALOG:
			if e["cat"] == cat:
				grid.add_child(_make_card(e))

	_demolish_btn = Button.new()
	_demolish_btn.text = "Demolish"
	_demolish_btn.toggle_mode = true
	_demolish_btn.modulate = Color(1.0,0.78,0.78)
	_demolish_btn.pressed.connect(_on_demolish_pressed)
	root.add_child(_demolish_btn)

	_launcher = Button.new()
	_launcher.name = "HudBuildToggle"
	_launcher.theme = _theme
	_launcher.text = "Build  (B)"
	_launcher.anchor_top = 1; _launcher.anchor_bottom = 1
	_launcher.offset_left = 12; _launcher.offset_right = 134
	_launcher.offset_top = -46; _launcher.offset_bottom = -12
	_launcher.pressed.connect(_toggle_menu)
	_ui.add_child(_launcher)


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
	_cards[id] = card
	return card


func _cost_text(id: String) -> String:
	var cost: Dictionary = GameManager.COSTS.get(id, {})
	if cost.is_empty():
		return "(no cost defined)"
	var parts: Array[String] = []
	for k in cost:
		parts.append("%d %s" % [cost[k], k])
	return "Cost: " + ", ".join(parts)


func _refresh_cards() -> void:
	var busy: bool = GameManager.is_placing_building or _demolish_active()
	for id in _cards:
		if not is_instance_valid(_cards[id]):
			continue
		var cost: Dictionary = GameManager.COSTS.get(id, {})
		var ok: bool = GameManager.can_afford(cost) if not cost.is_empty() else false
		_cards[id].disabled = busy or not ok


func _toggle_menu() -> void:
	if is_instance_valid(_menu):
		if _menu.visible: _close_menu()
		else: _open_menu()

func _open_menu() -> void:
	_menu.visible = true
	if _backdrop: _backdrop.visible = true
	if _launcher: _launcher.text = "Build  ✕"
	_refresh_cards()

func _close_menu() -> void:
	if is_instance_valid(_menu): _menu.visible = false
	if is_instance_valid(_backdrop): _backdrop.visible = false
	if is_instance_valid(_launcher): _launcher.text = "Build  (B)"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B and is_instance_valid(_menu):
			_toggle_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_instance_valid(_menu) and _menu.visible:
			_close_menu()
			get_viewport().set_input_as_handled()


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
	_close_menu()


func _demolish_active() -> bool:
	return "is_demolish_mode" in GameManager and GameManager.is_demolish_mode

func _on_demolish_pressed() -> void:
	if _demolish_active():
		if GameManager.has_method("cancel_demolish_mode"): GameManager.cancel_demolish_mode()
	else:
		if GameManager.has_method("start_demolish_mode"): GameManager.start_demolish_mode()


# ===========================================================================
# Theme
# ===========================================================================
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_stylebox("panel", "Panel", _panel(BG, 12))
	t.set_stylebox("panel", "PanelContainer", _panel(BG, 12))
	t.set_stylebox("normal",   "Button", _btn(BG_SOFT))
	t.set_stylebox("hover",    "Button", _btn(Color(0.22,0.26,0.34,0.92)))
	t.set_stylebox("pressed",  "Button", _btn(Color(0.30,0.50,0.85,0.95)))
	t.set_stylebox("disabled", "Button", _btn(Color(0.12,0.13,0.17,0.55)))
	t.set_stylebox("focus",    "Button", StyleBoxEmpty.new())
	t.set_color("font_color",          "Button", TEXT)
	t.set_color("font_hover_color",    "Button", Color(1,1,1))
	t.set_color("font_pressed_color",  "Button", Color(1,1,1))
	t.set_color("font_disabled_color", "Button", TEXT_OFF)
	t.set_color("font_color", "Label", TEXT)
	return t

func _panel(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = BORDER
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0,0,0,0.35)
	sb.shadow_size = 6
	return sb

func _btn(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(1,1,1,0.06)
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	return sb
