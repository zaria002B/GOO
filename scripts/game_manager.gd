
extends Node

signal card_collected(card_id: int)
signal all_cards_collected

var collected_cards: Array[int] = []

const TOTAL_CARDS: int = 3


func collect_card(card_id: int) -> void:

	if card_id < 1 or card_id > TOTAL_CARDS:
		push_warning("Invalid card ID: %d" % card_id)
		return

	if card_id in collected_cards:
		print("Card ", card_id, " already collected!")
		return

	collected_cards.append(card_id)

	print("Card collected: ", card_id)
	print("Total cards: ", collected_cards.size(), "/3")
	print("Collected IDs: ", collected_cards)

	card_collected.emit(card_id)

	if has_all_cards():
		print("ALL CARDS COLLECTED!")
		all_cards_collected.emit()


func has_card(card_id: int) -> bool:
	return card_id in collected_cards


func has_all_cards() -> bool:
	return collected_cards.size() >= TOTAL_CARDS


func reset_game() -> void:
	collected_cards.clear()
	
	
signal time_up
signal time_changed(seconds_left: int)

const TIME_LIMIT: float = 300.0 # 5 minutes

var time_remaining: float = TIME_LIMIT
var timer_running: bool = false


func _process(delta: float) -> void:
	if not timer_running:
		return
	time_remaining = maxf(time_remaining - delta, 0.0)
	time_changed.emit(ceili(time_remaining))
	if time_remaining <= 0.0:
		timer_running = false
		time_up.emit()


func start_timer() -> void:
	time_remaining = TIME_LIMIT
	timer_running = true
	time_changed.emit(ceili(time_remaining))


func stop_timer() -> void:
	timer_running = false
