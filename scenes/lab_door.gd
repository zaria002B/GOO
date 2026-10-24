
extends Node

signal card_collected(card_id: int)
signal all_cards_collected

var collected_cards: Array[int] = []
const TOTAL_CARDS := 3


func collect_card(card_id: int) -> void:
	if card_id in collected_cards:
		return

	collected_cards.append(card_id)

	print("Card collected: ", card_id)

	card_collected.emit(card_id)

	if collected_cards.size() == TOTAL_CARDS:
		all_cards_collected.emit()


func has_card(card_id: int) -> bool:
	return card_id in collected_cards


func has_all_cards() -> bool:
	return collected_cards.size() >= TOTAL_CARDS


func reset_game() -> void:
	collected_cards.clear()
