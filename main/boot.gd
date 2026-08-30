extends Node
## The base build's main scene is test/world.tscn; this redirects it to the menu
## (project.godot can't change through an update pack).
func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred("res://main/Menu.tscn")
