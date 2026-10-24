
extends CanvasLayer

@onready var card_label: Label = $Control/CardLabel
@onready var objective_label: Label = $Control/ObjectiveLabel
@onready var timer_label: Label = $Control/TimerLabel


func _ready() -> void:
	# Connect card collection
	GameManager.card_collected.connect(update_hud)
	update_hud(0)

	# Connect countdown timer
	GameManager.time_changed.connect(update_timer)
	update_timer(ceili(GameManager.time_remaining))


func update_hud(_card_id: int) -> void:
	var count: int = GameManager.collected_cards.size()

	card_label.text = "ACCESS CARDS: %d / 3" % count

	if not GameManager.has_card(1):
		objective_label.text = \
            "HINT: One laboratory lamp glows an unusual red. Look above it."

	elif not GameManager.has_card(2):
		objective_label.text = \
            "HINT: Knowledge is stacked high. Search above the books."

	elif not GameManager.has_card(3):
		objective_label.text = \
            "HINT: Look up! The final secret hides near the ceiling lights."

	else:
		objective_label.text = \
            "OBJECTIVE: All cards acquired! Reach the final exit!"


func update_timer(seconds_left: int) -> void:
	var minutes: int = int(seconds_left / 60)
	var seconds: int = seconds_left % 60

	timer_label.text = "TIME: %02d:%02d" % [minutes, seconds]

	if seconds_left <= 30:
		timer_label.add_theme_color_override(
			"font_color", Color.RED
		)
	else:
		timer_label.add_theme_color_override(
			"font_color", Color.WHITE
		)
