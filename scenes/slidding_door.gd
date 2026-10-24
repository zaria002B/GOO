
extends Node3D

@export_range(1, 3) var required_card_id: int = 1
@export var require_all_cards: bool = false

@export var slide_distance: float = 20.0
@export var slide_duration: float = 4.5

@onready var sliding_panel: AnimatableBody3D = $SlidingPanel
@onready var status_label: Label3D = $StatusLabel

var opened: bool = false


func _ready() -> void:
	GameManager.card_collected.connect(check_unlock)

	if require_all_cards:
		if GameManager.has_all_cards():
			open_door()
	elif GameManager.has_card(required_card_id):
		open_door()


func check_unlock(_card_id: int) -> void:
	if opened:
		return

	if require_all_cards:
		if GameManager.has_all_cards():
			open_door()
	elif GameManager.has_card(required_card_id):
		open_door()


func open_door() -> void:
	if opened:
		return

	opened = true
	status_label.text = "ACCESS GRANTED"

	var tween := create_tween()

	tween.tween_property(
		sliding_panel,
		"position",
		sliding_panel.position + Vector3.RIGHT * slide_distance,
		slide_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	print("Door opened!")
