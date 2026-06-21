class_name House
extends Building

@export var capacity: int = 5

var _registered: bool = false


func _ready() -> void:
	super._ready()
	add_to_group("houses")


func finish_building() -> void:
	var was_constructed = is_constructed
	super.finish_building()
	if is_constructed and not was_constructed and not _registered:
		_registered = true
		GameManager.change_housing(capacity)


func destroy() -> void:
	if _registered:
		GameManager.change_housing(-capacity)
		_registered = false
	super.destroy()
