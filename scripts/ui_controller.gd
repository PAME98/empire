extends CanvasLayer

## Wires GameManager signals to on-screen labels/panels and routes button
## presses back into GameManager / the selected building.

@onready var food_label: Label = $TopBar/Resources/FoodLabel
@onready var wood_label: Label = $TopBar/Resources/WoodLabel
@onready var stone_label: Label = $TopBar/Resources/StoneLabel
@onready var gold_label: Label = $TopBar/Resources/GoldLabel
@onready var pop_label: Label = $TopBar/Resources/PopLabel

@onready var time_label: Label = $TimePanel/TimeLabel
@onready var season_label: Label = $TimePanel/SeasonLabel
@onready var pop_breakdown_label: Label = $TimePanel/PopBreakdown

@onready var selection_panel: Panel = $SelectionPanel
@onready var selection_title: Label = $SelectionPanel/Title
@onready var selection_info: Label = $SelectionPanel/Info
@onready var selection_hint: Label = $SelectionPanel/Hint

@onready var build_menu: Panel = $BuildMenu
@onready var build_house_btn: Button = $BuildMenu/HouseButton
@onready var build_farm_btn: Button = $BuildMenu/FarmButton
@onready var build_lumber_btn: Button = $BuildMenu/LumberButton
@onready var build_quarry_btn: Button = $BuildMenu/QuarryButton
@onready var build_barracks_btn: Button = $BuildMenu/BarracksButton

@onready var village_actions: VBoxContainer = $SelectionPanel/VillageActions
@onready var recruit_citizen_btn: Button = $SelectionPanel/VillageActions/RecruitCitizenButton

@onready var barracks_actions: VBoxContainer = $SelectionPanel/BarracksActions
@onready var train_soldier_btn: Button = $SelectionPanel/BarracksActions/TrainSoldierButton
@onready var train_artillery_btn: Button = $SelectionPanel/BarracksActions/TrainArtilleryButton

@onready var notification_label: Label = $NotificationLabel

var _notification_timer: float = 0.0


func _ready() -> void:
	GameManager.resources_changed.connect(_on_resources_changed)
	GameManager.time_changed.connect(_on_time_changed)
	GameManager.selection_changed.connect(_on_selection_changed)
	GameManager.placement_mode_changed.connect(_on_placement_mode_changed)
	GameManager.attack_targeting_mode_changed.connect(_on_attack_targeting_mode_changed)
	GameManager.notification.connect(_on_notification)

	build_house_btn.pressed.connect(func(): _start_placement("house"))
	build_farm_btn.pressed.connect(func(): _start_placement("farm"))
	build_lumber_btn.pressed.connect(func(): _start_placement("lumber_camp"))
	build_quarry_btn.pressed.connect(func(): _start_placement("quarry"))
	build_barracks_btn.pressed.connect(func(): _start_placement("barracks"))

	recruit_citizen_btn.pressed.connect(_on_recruit_citizen_pressed)
	train_soldier_btn.pressed.connect(_on_train_soldier_pressed)
	train_artillery_btn.pressed.connect(_on_train_artillery_pressed)

	selection_panel.visible = false
	village_actions.visible = false
	barracks_actions.visible = false
	notification_label.visible = false

	GameManager.update_ui()


func _process(delta: float) -> void:
	if GameManager.selected_building != null and is_instance_valid(GameManager.selected_building):
		_refresh_selected_building_info()

	if GameManager.selected_resource_node != null:
		if is_instance_valid(GameManager.selected_resource_node):
			_show_resource_node_selection(GameManager.selected_resource_node)
		else:
			GameManager.clear_selection()

	if notification_label.visible:
		_notification_timer -= delta
		if _notification_timer <= 0.0:
			notification_label.visible = false


func _on_resources_changed(food: int, wood: int, stone: int, gold: int, population: int, max_population: int) -> void:
	food_label.text = "Food: %d" % food
	wood_label.text = "Wood: %d" % wood
	stone_label.text = "Stone: %d" % stone
	gold_label.text = "Gold: %d" % gold
	pop_label.text = "Pop: %d / %d" % [population, max_population]


func _on_time_changed(year: int, season: String, _progress: float) -> void:
	time_label.text = "Year %d" % year
	season_label.text = season
	pop_breakdown_label.text = "Children: %d   Adults: %d   Elders: %d   Soldiers: %d" % [
		GameManager.child_count, GameManager.adult_count, GameManager.elder_count, GameManager.all_soldiers.size()
	]


# ---------------------------------------------------------------------------
# Selection panel
# ---------------------------------------------------------------------------
func _on_selection_changed(units: Array, building, resource_node) -> void:
	village_actions.visible = false
	barracks_actions.visible = false

	if building != null:
		selection_panel.visible = true
		_show_building_selection(building)
		return

	if resource_node != null:
		selection_panel.visible = true
		_show_resource_node_selection(resource_node)
		return

	if units.is_empty():
		selection_panel.visible = false
		return

	selection_panel.visible = true
	if units.size() == 1:
		_show_single_unit(units[0])
	else:
		selection_title.text = "%d units selected" % units.size()
		selection_info.text = _group_summary(units)
		selection_hint.text = "Right-click ground to move, a resource to gather, or a build site to help build."


func _show_resource_node_selection(resource_node) -> void:
	var label = _resource_type_label(resource_node.resource_type)
	selection_title.text = label
	if resource_node.is_depleted():
		selection_info.text = "Depleted — nothing left to gather here."
	else:
		selection_info.text = "%d / %d %s remaining" % [resource_node.amount, resource_node.max_amount, resource_node.resource_type]
	selection_hint.text = "Select a citizen, then right-click this to start gathering it."


func _resource_type_label(resource_type: String) -> String:
	match resource_type:
		"wood": return "Tree"
		"stone": return "Stone Deposit"
		"food": return "Berry Bush"
	return "Resource"


func _show_single_unit(unit) -> void:
	if unit is Citizen:
		selection_title.text = "%s (Age %d)" % [unit.life_stage_label(), unit.age]
		selection_info.text = "Job: %s\nHealth: %d/%d\nCarrying: %d %s" % [
			unit.job_label(), unit.health, unit.max_health, unit.carried_amount, unit.carried_resource
		]
		selection_hint.text = "Right-click: move / gather resource / help build."
	elif unit is Soldier:
		selection_title.text = "Soldier"
		selection_info.text = "Health: %d/%d\nDamage: %d" % [unit.health, unit.max_health, unit.attack_damage]
		selection_hint.text = "Right-click an enemy to attack, or ground to move."
	elif unit is Artillery:
		selection_title.text = "Artillery"
		selection_info.text = "Health: %d/%d\nDamage: %d (splash radius %d)" % [
			unit.health, unit.max_health, unit.attack_damage, int(unit.splash_radius)
		]
		selection_hint.text = "Right-click an enemy to bombard it. Press T, then left-click ground for an area strike."
	else:
		selection_title.text = "Unit"
		selection_info.text = ""
		selection_hint.text = ""


func _group_summary(units: Array) -> String:
	var citizens = 0
	var soldiers = 0
	var artillery = 0
	for u in units:
		if u is Citizen:
			citizens += 1
		elif u is Artillery:
			artillery += 1
		elif u is Soldier:
			soldiers += 1
	var parts: Array[String] = []
	if citizens > 0:
		parts.append("%d citizens" % citizens)
	if soldiers > 0:
		parts.append("%d soldiers" % soldiers)
	if artillery > 0:
		parts.append("%d artillery" % artillery)
	return ", ".join(parts)


func _show_building_selection(building) -> void:
	if building is VillageCenter:
		selection_title.text = "Village Center"
		village_actions.visible = true
		_refresh_selected_building_info()
	elif building is Barracks:
		selection_title.text = "Barracks (%s)" % ("ready" if building.is_constructed else "under construction")
		barracks_actions.visible = building.is_constructed
		_refresh_selected_building_info()
	elif building is House:
		selection_title.text = "House"
		selection_info.text = "Adds %d housing." % building.capacity
		selection_hint.text = ""
	elif building is Farm:
		selection_title.text = "Farm"
		_refresh_selected_building_info()
	elif building is LumberCamp:
		selection_title.text = "Lumber Camp"
		_refresh_selected_building_info()
	elif building is Quarry:
		selection_title.text = "Quarry"
		_refresh_selected_building_info()
	else:
		selection_title.text = "Building"
		selection_info.text = ""
		selection_hint.text = ""


func _refresh_selected_building_info() -> void:
	var building = GameManager.selected_building
	if building == null:
		return

	if building is VillageCenter:
		if building.is_recruiting:
			var current = building.recruit_queue[0]
			var pct = int(clampf(building.recruit_elapsed / current["duration"] * 100.0, 0.0, 100.0))
			selection_info.text = "Training citizen: %d%%\nQueued: %d" % [pct, building.recruit_queue.size() - 1]
		else:
			selection_info.text = "Idle — recruit a new citizen."
		selection_hint.text = "Costs 40 food, needs free housing."

	elif building is Barracks:
		if not building.is_constructed:
			selection_info.text = "Construction: %d%%" % int(clampf(building.build_progress / building.build_time * 100.0, 0.0, 100.0))
		elif building.is_training:
			var current_id: String = building.train_queue[0]
			var duration = GameManager.BUILD_TIMES.get(current_id, 8.0)
			var pct = int(clampf(building.train_elapsed / duration * 100.0, 0.0, 100.0))
			selection_info.text = "Training %s: %d%%\nQueued: %d" % [current_id.capitalize(), pct, building.train_queue.size() - 1]
		else:
			selection_info.text = "Idle — train a soldier or artillery."
		var soldier_cost = GameManager.COSTS.get("soldier", {})
		var artillery_cost = GameManager.COSTS.get("artillery", {})
		selection_hint.text = ""

	elif building is ResourceBuilding:
		var status = "under construction" if not building.is_constructed else "%d/%d workers, stockpile %d" % [
			building.worker_count(), building.max_workers, int(building.stockpile)
		]
		selection_info.text = status
		selection_hint.text = "Right-click while a citizen is selected to assign them here."


func _on_recruit_citizen_pressed() -> void:
	if GameManager.selected_building is VillageCenter:
		GameManager.selected_building.queue_citizen()


func _on_train_soldier_pressed() -> void:
	if GameManager.selected_building is Barracks:
		GameManager.selected_building.queue_soldier()


func _on_train_artillery_pressed() -> void:
	if GameManager.selected_building is Barracks:
		GameManager.selected_building.queue_artillery()


# ---------------------------------------------------------------------------
# Artillery attack-position targeting
# ---------------------------------------------------------------------------
func _on_attack_targeting_mode_changed(active: bool, radius: float) -> void:
	if active:
		_on_notification("Attack-position mode: left-click an area to bombard it (blast radius %d). Right-click or Esc to cancel." % int(radius))


# ---------------------------------------------------------------------------
# Build menu
# ---------------------------------------------------------------------------
func _start_placement(building_id: String) -> void:
	if GameManager.is_targeting_attack_position:
		GameManager.cancel_attack_position_targeting()
	var builder = null
	if GameManager.selected_units.size() == 1 and GameManager.selected_units[0] is Citizen:
		builder = GameManager.selected_units[0]
	GameManager.start_building_placement(building_id, builder)


func _on_placement_mode_changed(active: bool, building_id: String) -> void:
	build_house_btn.disabled = active
	build_farm_btn.disabled = active
	build_lumber_btn.disabled = active
	build_quarry_btn.disabled = active
	build_barracks_btn.disabled = active
	if active:
		var cost = GameManager.COSTS.get(building_id, {})
		_on_notification("Placing %s — click to confirm, right-click/Esc to cancel. Cost: %s" % [building_id, _format_cost(cost)])


func _format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for key in cost:
		parts.append("%d %s" % [cost[key], key])
	return ", ".join(parts)


# ---------------------------------------------------------------------------
# Notifications
# ---------------------------------------------------------------------------
func _on_notification(text: String) -> void:
	notification_label.text = text
	notification_label.visible = true
	_notification_timer = 3.0
