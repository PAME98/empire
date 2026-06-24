extends Node3D

## On a procedurally-generated map, the starting town center and citizens are
## spawned AND registered by MapGenerator the moment the player founds the town
## (see map_generator._confirm_placement). So there's nothing to register here
## on boot — doing so would double-count or register citizens that get cleared.
## We just make sure the HUD is initialised.
##
## (If you ever turn the map generator off and go back to a hand-placed town in
## main.tscn, restore the old loop that registered citizens from the "citizens"
## group here.)


func _ready() -> void:
	GameManager.update_ui()
