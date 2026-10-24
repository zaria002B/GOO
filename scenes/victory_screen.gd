
extends Control

@onready var restart_button: Button = \
	$CenterContainer/VBoxContainer/RestartButton

@onready var quit_button: Button = \
	$CenterContainer/VBoxContainer/QuitButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	restart_button.pressed.connect(restart_game)
	quit_button.pressed.connect(quit_game)


func restart_game() -> void:
	GameManager.reset_game()

	get_tree().change_scene_to_file(
        "res://scenes/level_1.tscn"
	)


func quit_game() -> void:
	get_tree().quit()
