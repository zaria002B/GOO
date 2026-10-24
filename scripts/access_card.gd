
extends Node3D
@export_range(1, 3) var card_id: int = 1
@export var collection_radius: float = 1.0
@export var rotation_speed: float = 1.5
@export var float_height: float = 0.15
@export var float_speed: float = 2.0

var slime: SoftBody3D
var start_position: Vector3
var time_passed: float = 0.0
var collected: bool = false


func _ready() -> void:
	start_position = global_position

	slime = get_tree().get_first_node_in_group("player") as SoftBody3D


func _process(delta: float) -> void:
	if collected:
		return

	# Rotate the access card
	rotate_y(rotation_speed * delta)

	# Make it float up and down
	time_passed += delta

	global_position.y = start_position.y + \
		sin(time_passed * float_speed) * float_height

	# Check whether the slime is close enough
	if slime == null:
		return

	var slime_position: Vector3 = slime.get_centre_approx()

	if global_position.distance_to(slime_position) <= collection_radius:
		collect()


func collect() -> void:
	if collected:
		return

	collected = true

	GameManager.collect_card(card_id)

	queue_free()
