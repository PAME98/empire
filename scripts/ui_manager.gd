extends CanvasLayer

# Game references
var game_manager: Node
var economy_system: EconomySystem
var merchant_manager: MerchantManager
var player_data: PlayerData

# UI elements
var money_label: Label
var wealth_label: Label
var items_label: Label
var inv_list_vbox: VBoxContainer

# ── Colour palette ──────────────────────────────────────────────
const C_PARCHMENT      := Color(0.910, 0.835, 0.639, 0.93)
const C_PARCHMENT_DARK := Color(0.820, 0.745, 0.549, 0.97)
const C_INK            := Color(0.172, 0.094, 0.063, 1.0)
const C_BRASS          := Color(0.788, 0.573, 0.165, 1.0)
const C_BRASS_DARK     := Color(0.580, 0.400, 0.090, 1.0)
const C_NAVY           := Color(0.102, 0.153, 0.267, 0.88)
const C_SEA            := Color(0.290, 0.486, 0.557, 1.0)
const C_RED_WAX        := Color(0.600, 0.137, 0.137, 1.0)

const FS_TITLE  := 15
const FS_BODY   := 12
const FS_SMALL  := 11

# ────────────────────────────────────────────────────────────────
func _ready():
	# FIX: get_tree().root.get_child(0) is unreliable — autoload
	# singletons are added as children of root BEFORE the main
	# scene, so child 0 may be an autoload (e.g. game_clock.gd)
	# instead of your actual game manager.
	#
	# get_tree().current_scene always points to the root node of
	# your currently loaded scene, which is what you actually want.
	game_manager = get_tree().current_scene
	if not game_manager:
		push_error("UIManager: game_manager not found")
		return

	await get_tree().process_frame

	economy_system   = game_manager.economy_system
	merchant_manager = game_manager.merchant_manager
	player_data      = game_manager.player_data

	if not player_data:
		push_error("UIManager: player_data is null")
		return

	create_ui()

# ═══════════════════════════════════════════════════════════════
#  THEME HELPERS
# ═══════════════════════════════════════════════════════════════

func _panel_theme(bg: Color, border: Color = C_BRASS_DARK, radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(8)
	return s

func _label_ink(lbl: Label, size: int = FS_BODY) -> void:
	lbl.add_theme_color_override("font_color", C_INK)
	lbl.add_theme_font_size_override("font_size", size)

func _section_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", C_BRASS_DARK)
	lbl.add_theme_font_size_override("font_size", FS_TITLE)
	return lbl

func _sep() -> HSeparator:
	var s := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = C_BRASS
	style.set_content_margin(SIDE_TOP, 2)
	style.set_content_margin(SIDE_BOTTOM, 2)
	s.add_theme_stylebox_override("separator", style)
	return s

# ═══════════════════════════════════════════════════════════════
#  CREATE UI  –  map overlay (no merchant list — use cities!)
# ═══════════════════════════════════════════════════════════════

func create_ui():
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_player_panel(root)
	_build_inventory_panel(root)
	_build_market_ticker(root)
	update_ui()

# ── TOP-LEFT: Player status ──────────────────────────────────────
func _build_player_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_theme(C_PARCHMENT, C_BRASS_DARK))
	panel.custom_minimum_size = Vector2(260, 0)
	panel.anchor_left   = 0.0
	panel.anchor_top    = 0.0
	panel.anchor_right  = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left   = 12
	panel.offset_top    = 12
	panel.offset_right  = 272
	panel.offset_bottom = 120
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := _section_header("⚓  Merchant Ledger")
	vbox.add_child(title)
	vbox.add_child(_sep())

	money_label  = Label.new(); _label_ink(money_label)
	wealth_label = Label.new(); _label_ink(wealth_label)
	items_label  = Label.new(); _label_ink(items_label, FS_SMALL)
	vbox.add_child(money_label)
	vbox.add_child(wealth_label)
	vbox.add_child(items_label)

	# Hint to player
	var hint := Label.new()
	hint.text = "Enter a city to trade."
	hint.add_theme_color_override("font_color", Color(C_BRASS_DARK, 0.75))
	hint.add_theme_font_size_override("font_size", FS_SMALL)
	vbox.add_child(hint)

# ── BOTTOM-RIGHT: Inventory ──────────────────────────────────────
func _build_inventory_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_theme(C_PARCHMENT_DARK, C_BRASS_DARK))
	panel.anchor_left   = 1.0
	panel.anchor_top    = 1.0
	panel.anchor_right  = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left   = -282
	panel.offset_top    = -280
	panel.offset_right  = -12
	panel.offset_bottom = -12
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var title := _section_header("🎒  Cargo Hold")
	vbox.add_child(title)
	vbox.add_child(_sep())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	inv_list_vbox = VBoxContainer.new()
	inv_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_list_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(inv_list_vbox)

# ── BOTTOM-LEFT: Market price ticker ─────────────────────────────
func _build_market_ticker(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_theme(C_NAVY, C_SEA))
	panel.anchor_left   = 0.0
	panel.anchor_top    = 1.0
	panel.anchor_right  = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left   = 12
	panel.offset_top    = -160
	panel.offset_right  = 272
	panel.offset_bottom = -12
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "📈  Market Prices"
	title.add_theme_color_override("font_color", C_PARCHMENT)
	title.add_theme_font_size_override("font_size", FS_TITLE)
	vbox.add_child(title)
	vbox.add_child(_sep())

	if economy_system:
		for item in economy_system.get_all_items():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			vbox.add_child(row)

			var name_lbl := Label.new()
			name_lbl.text = item.capitalize()
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.add_theme_color_override("font_color", Color(C_PARCHMENT, 0.8))
			name_lbl.add_theme_font_size_override("font_size", FS_SMALL)
			row.add_child(name_lbl)

			var trend := economy_system.get_trend_arrow(item)
			var price_lbl := Label.new()
			price_lbl.text = "%s %d 💰" % [trend, economy_system.get_price(item)]
			price_lbl.add_theme_color_override("font_color", C_BRASS)
			price_lbl.add_theme_font_size_override("font_size", FS_SMALL)
			row.add_child(price_lbl)

# ═══════════════════════════════════════════════════════════════
#  UPDATE  –  refresh live panels
# ═══════════════════════════════════════════════════════════════

func update_ui():
	var item_count := 0
	for item in player_data.inventory:
		item_count += player_data.inventory[item]

	money_label.text  = "💰  %d coins" % player_data.money
	wealth_label.text = "⚖   Wealth: %d" % player_data.get_total_wealth(economy_system)
	items_label.text  = "📦  %d items in hold" % item_count

	update_inventory_list()

func update_inventory_list():
	if not player_data:
		return
	for child in inv_list_vbox.get_children():
		child.queue_free()

	var items := player_data.get_inventory_items()
	if items.is_empty():
		var lbl := Label.new()
		lbl.text = "The hold is empty."
		_label_ink(lbl, FS_SMALL)
		inv_list_vbox.add_child(lbl)
		return

	for item in items:
		var amount := player_data.get_item_amount(item)
		var price  := economy_system.get_price(item)
		var value  := amount * price

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		inv_list_vbox.add_child(row)

		var lbl := Label.new()
		lbl.text = "%d×  %-12s" % [amount, item.capitalize()]
		_label_ink(lbl, FS_SMALL)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var val_lbl := Label.new()
		val_lbl.text = "%d 💰" % value
		val_lbl.add_theme_color_override("font_color", C_BRASS_DARK)
		val_lbl.add_theme_font_size_override("font_size", FS_SMALL)
		row.add_child(val_lbl)
