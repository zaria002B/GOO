
extends Control

@onready var retry_button: Button = \
	$CenterContainer/VBoxContainer/RetryButton

@onready var menu_button: Button = \
	$CenterContainer/VBoxContainer/MenuButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	retry_button.pressed.connect(retry_game)
	menu_button.pressed.connect(return_to_menu)


func retry_game() -> void:
	GameManager.reset_game()

	get_tree().change_scene_to_file(
        "res://scenes/level_1.tscn"
	)


func return_to_menu() -> void:
	GameManager.reset_game()

	get_tree().change_scene_to_file(
        "res://scenes/main_menu.tscn"
	)
