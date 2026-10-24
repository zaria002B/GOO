
extends Node3D


func _ready() -> void:
	GameManager.start_timer()
	GameManager.time_up.connect(on_time_up)


func on_time_up() -> void:
	get_tree().call_deferred(
		"change_scene_to_file",
        "res://scenes/game_over.tscn"
	)
