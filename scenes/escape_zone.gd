
extends Marker3D

@export var detection_radius: float = 2.0

@export_file("*.tscn") var victory_scene_path: String = \
    "res://scenes/victory_screen.tscn"

var slime: SoftBody3D
var game_finished: bool = false


func _ready() -> void:
	slime = get_tree().get_first_node_in_group("player") as SoftBody3D


func _physics_process(_delta: float) -> void:
	if game_finished:
		return

	# Don't allow victory until all cards are collected
	if not GameManager.has_all_cards():
		return

	if slime == null:
		return

	# Get slime's current position
	var slime_position: Vector3 = slime.get_centre_approx()

	# Check distance to escape zone
	var distance: float = \
		slime_position.distance_to(global_position)

	if distance <= detection_radius:
		complete_game()




func complete_game() -> void:
	if game_finished:
		return
	game_finished = true
	GameManager.stop_timer()
	print("EXPERIMENT S-01 HAS ESCAPED!")
	print("Loading victory scene: ", victory_scene_path)
	if not ResourceLoader.exists(victory_scene_path):
		push_error("Victory scene not found: " + victory_scene_path)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().call_deferred(
		"change_scene_to_file",
		victory_scene_path
	)
