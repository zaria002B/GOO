
extends Control

@export_file("*.tscn") var level_scene_path: String = \
    "res://scenes/level_1.tscn"

@onready var start_button: Button = \
	$CenterContainer/VBoxContainer/StartButton

@onready var quit_button: Button = \
	$CenterContainer/VBoxContainer/QuitButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	start_button.pressed.connect(start_game)
	quit_button.pressed.connect(quit_game)


func start_game() -> void:
	GameManager.reset_game()

	var error: Error = get_tree().change_scene_to_file(
		level_scene_path
	)

	if error != OK:
		push_error("Could not load level: " + level_scene_path)


func quit_game() -> void:
	get_tree().quit()
