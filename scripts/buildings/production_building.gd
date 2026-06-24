class_name ProductionBuilding
extends ResourceBuilding

## A workshop: the REFINEMENT half of the economy that sits between the raw-
## resource gatherers (Farm/Lumber Camp/Quarry/Mine) and the population that
## consumes finished goods. A Mill turns grain into flour, a Bakery turns
## flour + water into bread, a Smelter turns iron ore + coal into ingots.
##
## It deliberately reuses ResourceBuilding's machinery so the rest of the game
## doesn't have to learn a new building shape:
##   * WORKER SLOTS — inherited unchanged. Citizens auto-find and staff a
##     workshop exactly like they do a farm (see citizen.gd's autofind list).
##   * STOCKPILE + harvest() — inherited unchanged. The finished good piles up
##     in `stockpile`; the assigned worker harvests it and carries it to the
##     village center, the same delivery path gatherers already use.
##
## The ONLY thing that differs from a gatherer is HOW the stockpile fills: a
## gatherer produces freely (or drains a deposit); a workshop instead pays
## `inputs` out of the global stockpile for every unit it makes. That's the
## one method overridden below.
##
## LOGISTICS NOTE (v1): inputs are pulled straight from GameManager's global
## pool rather than being physically hauled in by a second citizen. The worker
## is assumed to fetch them off-screen. This keeps the first iteration playable;
## a later pass can add real input-hauling without touching this class's public
## surface.

## Goods consumed from the global stockpile per unit produced.
## e.g. {"flour": 1, "water": 1} for a Bakery. Keys may be legacy resources
## (food/wood/stone/gold/iron/water) or any new good in GameManager.stock.
@export var inputs: Dictionary = {}

var _progress: float = 0.0
var _starved_notice_sent: bool = false


func _ready() -> void:
	# Subclasses set resource_group/yield_resource/inputs BEFORE calling
	# super._ready(), so by the time ResourceBuilding._ready() runs (inside
	# this super call) the resource_group group is added correctly.
	super._ready()
	add_to_group("workshops")


func _process(delta: float) -> void:
	# NB: intentionally does NOT call super (ResourceBuilding._process) —
	# workshops neither produce freely nor drain a deposit. We re-implement
	# the produce-into-stockpile step with an input cost.
	if not is_constructed:
		return

	var active := 0
	for w in workers:
		if is_instance_valid(w):
			active += 1
	if active == 0:
		return

	if stockpile >= max_stockpile:
		return

	# Accumulate fractional progress; pay inputs and bank one finished unit
	# each time we cross a whole-unit threshold.
	_progress += base_production_rate * active * delta
	while _progress >= 1.0 and stockpile < max_stockpile:
		if not GameManager.has_inputs(inputs):
			# Out of at least one ingredient — hold progress at <1 unit so we
			# resume instantly once a hauler tops the global pool back up.
			_progress = minf(_progress, 0.999)
			if not _starved_notice_sent:
				_starved_notice_sent = true
				GameManager.notify("%s idle — missing inputs." % _display_name())
			return
		GameManager.consume_inputs(inputs)
		stockpile = minf(stockpile + 1.0, max_stockpile)
		_progress -= 1.0
		_starved_notice_sent = false


func _display_name() -> String:
	if resource_group != "":
		return resource_group.capitalize()
	return name
