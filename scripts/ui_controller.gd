extends CanvasLayer

@onready var food_label = $Resources/FoodLabel
@onready var wood_label = $Resources/WoodLabel
@onready var pop_label = $Resources/PopLabel
@onready var unit_panel = $UnitPanel
@onready var building_panel = $BuildingPanel
@onready var queue_label = $BuildingPanel/QueueLabel
@onready var unit_name_label = $UnitPanel/UnitName
@onready var unit_hint_label = $UnitPanel/UnitHint
@onready var build_farmstead_button = $UnitPanel/BuildFarmsteadButton

func _ready():
	GameManager.resources_changed.connect(_on_resources_changed)
	GameManager.unit_selected.connect(_on_unit_selected)
	GameManager.building_selected.connect(_on_building_selected)
	GameManager.selection_cleared.connect(_on_selection_cleared)
	GameManager.placement_mode_changed.connect(_on_placement_mode_changed)
	unit_panel.visible = false
	building_panel.visible = false

func _process(_delta):
	if building_panel.visible:
		_update_queue_label()

func _update_queue_label():
	var building = GameManager.selected_building
	if building == null or not ("recruit_queue" in building):
		queue_label.text = ""
		return

	if building.recruit_queue.is_empty():
		queue_label.text = "Queue: empty"
	else:
		var current = building.recruit_queue[0]
		var pct = int(clamp(building.recruit_elapsed / current["duration"] * 100.0, 0, 100))
		var waiting = building.recruit_queue.size() - 1
		var text = "Recruiting %s: %d%%" % [current["type"], pct]
		if waiting > 0:
			text += " (+%d queued)" % waiting
		queue_label.text = text

func _on_resources_changed(food: int, wood: int, pop: int, max_pop: int):
	food_label.text = "Food: %d" % food
	wood_label.text = "Wood: %d" % wood
	pop_label.text = "Pop: %d/%d" % [pop, max_pop]

func _on_unit_selected(unit):
	unit_panel.visible = true
	building_panel.visible = false

	var is_worker = unit.is_in_group("workers")
	build_farmstead_button.visible = is_worker

	if is_worker:
		unit_name_label.text = "Worker Selected"
		unit_hint_label.text = "Right-click a tree to chop wood, or a farmstead to harvest food."
	else:
		unit_name_label.text = "Soldier Selected"
		unit_hint_label.text = "Right-click an enemy to attack, or open ground to move."

func _on_building_selected(_building):
	unit_panel.visible = false
	building_panel.visible = true

func _on_selection_cleared():
	unit_panel.visible = false
	building_panel.visible = false

func _on_spawn_worker_pressed():
	if GameManager.selected_building and GameManager.selected_building.is_in_group("village_centers"):
		GameManager.selected_building.spawn_worker()

func _on_spawn_soldier_pressed():
	if GameManager.selected_building and GameManager.selected_building.is_in_group("village_centers"):
		GameManager.selected_building.spawn_soldier()

func _on_build_farmstead_pressed():
	if GameManager.selected_units.is_empty():
		return

	var worker = GameManager.selected_units[0]
	if not worker.is_in_group("workers"):
		return

	if not GameManager.can_afford(GameManager.FARM_COST):
		unit_hint_label.text = "Not enough wood for a Farmstead (need 75)."
		return

	GameManager.start_building_placement("farmstead", worker)

func _on_placement_mode_changed(active: bool, _building_type: String):
	if active:
		unit_hint_label.text = "Click on the ground to place the Farmstead (right-click to cancel)."
