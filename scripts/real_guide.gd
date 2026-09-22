extends Node3D

## Editor-only comparison overlay for the measured Haapsalu geometry.
##
## Keep this node visible while aligning the authored street in the editor.
## It hides itself when a game run starts unless a developer deliberately
## enables the exported override.
@export var show_during_game := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = show_during_game

