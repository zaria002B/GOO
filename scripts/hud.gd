
extends CanvasLayer

@onready var card_label: Label = $Control/CardLabel


func _ready() -> void:
	GameManager.card_collected.connect(update_cards)

	update_cards(
		GameManager.cards_collected,
		GameManager.total_cards
	)


func update_cards(current: int, total: int) -> void:
	card_label.text = "ACCESS CARDS: %d / %d" % [current, total]
