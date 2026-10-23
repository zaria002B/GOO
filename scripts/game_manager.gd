
extends Node

signal card_collected(current: int, total: int)
signal all_cards_collected

var cards_collected: int = 0
var total_cards: int = 3


func collect_card() -> void:
	cards_collected += 1

	print("Access Card Collected: ", cards_collected, "/", total_cards)

	card_collected.emit(cards_collected, total_cards)

	if cards_collected >= total_cards:
		print("All access cards collected! Exit unlocked!")

		all_cards_collected.emit()


func reset_game() -> void:
	cards_collected = 0
