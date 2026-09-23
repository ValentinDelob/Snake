class_name SnakeHud
extends CanvasLayer

## The interface: a slim top bar while playing, and a centred card for the
## menu, the pause and the game over screens.
##
## The whole tree is built in code. Panels, pills and keycaps are styled
## StyleBoxFlat rather than plain text, so the layout holds at any window
## size and there is a single place to change the look.

const PANEL_COLOR := Color(0.04, 0.06, 0.1, 0.72)
const CARD_COLOR := Color(0.04, 0.055, 0.09, 0.93)
const KEYCAP_COLOR := Color(0.13, 0.17, 0.24, 0.95)
const BORDER_COLOR := Color(0.35, 0.42, 0.52, 0.55)

var _top_bar: Control
var _score_value: Label
var _best_value: Label
var _mode_chip: Label
var _item_slot: ItemSlot
var _item_hint: Control
var _boost_label: Label

var _overlay: Control
var _card: PanelContainer
var _title: Label
var _subtitle: Label
var _chips: HBoxContainer
var _cta_holder: CenterContainer
var _cta_panel: PanelContainer
var _cta_key: Label
var _cta_action: Label
var _hints: VBoxContainer

var _shown_score := -1
var _breath := 0.0


func _ready() -> void:
	_build_top_bar()
	_build_overlay()


# --------------------------------------------------------------------------- #
# Playing: the top bar
# --------------------------------------------------------------------------- #
## A slow breath on the call to action, to pull the eye to it. Driven here
## rather than by a looping tween, which cannot outlive its panel.
func _process(delta: float) -> void:
	if not _overlay.visible:
		return
	_breath += delta
	_cta_panel.modulate.a = 0.78 + 0.22 * (0.5 + 0.5 * sin(_breath * 2.4))


func _build_top_bar() -> void:
	_top_bar = Control.new()
	_top_bar.name = "TopBar"
	_top_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_bar)

	# One row across the top: score on the left, camera in the middle, best
	# on the right. A container rather than fixed positions, so nothing can
	# fall off the edge whatever the window size.
	var top_margin := MarginContainer.new()
	top_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_margin.add_theme_constant_override("margin_left", 22)
	top_margin.add_theme_constant_override("margin_right", 22)
	top_margin.add_theme_constant_override("margin_top", 18)
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(top_margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	top_margin.add_child(row)

	# Score, top left
	var score_pill := _pill()
	score_pill.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(score_pill)

	var score_box := HBoxContainer.new()
	score_box.add_theme_constant_override("separation", 10)
	score_pill.add_child(score_box)

	var score_caption := _label("SCORE", 13, GameConfig.DIM_COLOR)
	score_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_box.add_child(score_caption)

	_score_value = _label("0", 30, GameConfig.TEXT_COLOR)
	score_box.add_child(_score_value)

	row.add_child(_spacer())

	# Camera chip, centred
	var mode_pill := _pill()
	mode_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mode_style: StyleBoxFlat = mode_pill.get_theme_stylebox("panel")
	mode_style.bg_color = Color(PANEL_COLOR.r, PANEL_COLOR.g, PANEL_COLOR.b, 0.45)
	row.add_child(mode_pill)

	_mode_chip = _label("3D follow", 13, GameConfig.DIM_COLOR)
	mode_pill.add_child(_mode_chip)

	row.add_child(_spacer())

	# Best, top right
	var best_pill := _pill()
	best_pill.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(best_pill)

	var best_box := HBoxContainer.new()
	best_box.add_theme_constant_override("separation", 8)
	best_pill.add_child(best_box)
	var best_caption := _label("BEST", 13, GameConfig.DIM_COLOR)
	best_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	best_box.add_child(best_caption)
	_best_value = _label("0", 18, GameConfig.ACCENT_COLOR)
	best_box.add_child(_best_value)

	# Item slot under the score
	var item_row := HBoxContainer.new()
	item_row.position = Vector2(22, 74)
	item_row.add_theme_constant_override("separation", 12)
	_top_bar.add_child(item_row)

	_item_slot = ItemSlot.new()
	_item_slot.custom_minimum_size = Vector2(54, 54)
	item_row.add_child(_item_slot)

	var item_column := VBoxContainer.new()
	item_column.add_theme_constant_override("separation", 2)
	item_column.alignment = BoxContainer.ALIGNMENT_CENTER
	item_row.add_child(item_column)

	_item_hint = _keycap_row(["SPACE"], "fire")
	item_column.add_child(_item_hint)

	_boost_label = _label("", 14, GameConfig.SPARK_COLOR)
	item_column.add_child(_boost_label)


func set_stats(score: int, best: int, mode_text: String) -> void:
	if score != _shown_score:
		_shown_score = score
		_score_value.text = str(score)
		_punch(_score_value)
	_best_value.text = str(best)
	_mode_chip.text = mode_text


## Item slot state: what is carried, and the countdown while it burns.
func set_item(carried: bool, boost_left: float, boost_total: float) -> void:
	var boosting := boost_left > 0.0
	_item_slot.set_state(carried, boosting, boost_left / maxf(boost_total, 0.001))
	_item_hint.visible = carried and not boosting
	if boosting:
		_boost_label.text = "BOOST  %.1fs" % boost_left
		_boost_label.add_theme_color_override("font_color", GameConfig.SPARK_COLOR)
	elif carried:
		_boost_label.text = ""
	else:
		_boost_label.text = "no item"
		_boost_label.add_theme_color_override("font_color", GameConfig.DIM_COLOR)


func set_bar_visible(value: bool) -> void:
	_top_bar.visible = value


# --------------------------------------------------------------------------- #
# Menu, pause and game over: the card
# --------------------------------------------------------------------------- #
func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.04, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(centre)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _card_style())
	centre.add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 46)
	margin.add_theme_constant_override("margin_right", 46)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 30)
	_card.add_child(margin)

	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 14)
	margin.add_child(card_box)

	_title = _label("SNAKE 3D", 52, GameConfig.SNAKE_HEAD_COLOR)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(_title)

	_subtitle = _label("", 17, GameConfig.TEXT_COLOR)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(_subtitle)

	_chips = HBoxContainer.new()
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.add_theme_constant_override("separation", 10)
	card_box.add_child(_chips)

	_cta_holder = CenterContainer.new()
	card_box.add_child(_cta_holder)
	_build_call_to_action()

	_hints = VBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	_hints.add_theme_constant_override("separation", 6)
	card_box.add_child(_hints)


func show_menu(best: int, games: int) -> void:
	_title.text = "SNAKE 3D"
	_title.add_theme_color_override("font_color", GameConfig.SNAKE_HEAD_COLOR)
	_subtitle.text = "hold LEFT or RIGHT to steer - the snake never stops"
	_set_chips([
		["BEST", str(best), GameConfig.ACCENT_COLOR],
		["GAMES", str(games), GameConfig.TEXT_COLOR],
	])
	_set_call_to_action("ENTER", "play")
	_set_hints([
		[["SPACE"], "fire the speed boost"],
		[["C", "V"], "camera  /  flat view"],
		[["P", "ESC"], "pause  /  quit"],
	])
	_present()


func show_pause() -> void:
	_title.text = "PAUSED"
	_title.add_theme_color_override("font_color", GameConfig.TEXT_COLOR)
	_subtitle.text = ""
	_set_chips([])
	_set_call_to_action("P", "resume")
	_set_hints([
		[["ESC"], "back to the menu"],
	])
	_present()


func show_game_over(cause: String, score: int, best: int, record: bool) -> void:
	_title.text = "GAME OVER"
	_title.add_theme_color_override("font_color", GameConfig.DANGER_COLOR)
	_subtitle.text = cause
	_set_chips([
		["SCORE", str(score), GameConfig.TEXT_COLOR],
		["NEW BEST" if record else "BEST", str(best), GameConfig.ACCENT_COLOR],
	])
	_set_call_to_action("R", "play again")
	_set_hints([
		[["M"], "menu"],
		[["ESC"], "quit"],
	])
	_present()


func hide_overlay() -> void:
	_overlay.visible = false


# --------------------------------------------------------------------------- #
# Building blocks
# --------------------------------------------------------------------------- #
func _present() -> void:
	_overlay.visible = true
	# A short rise instead of a hard cut.
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.97, 0.97)
	_card.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_card, "modulate:a", 1.0, 0.18)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _punch(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(1.25, 1.25)
	create_tween().tween_property(node, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The one action the player is meant to take, spelled out loudly.
##
## Built once and only re-labelled afterwards: rebuilding it per screen left
## a looping tween pointing at a freed panel, which Godot reports as an
## infinite loop and which took the game down with it.
func _build_call_to_action() -> void:
	_cta_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		GameConfig.SNAKE_BODY_COLOR.r, GameConfig.SNAKE_BODY_COLOR.g,
		GameConfig.SNAKE_BODY_COLOR.b, 0.18
	)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(12)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.border_color = Color(
		GameConfig.SNAKE_HEAD_COLOR.r, GameConfig.SNAKE_HEAD_COLOR.g,
		GameConfig.SNAKE_HEAD_COLOR.b, 0.6
	)
	style.set_border_width_all(1)
	_cta_panel.add_theme_stylebox_override("panel", style)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_cta_panel.add_child(box)

	var keycap := _keycap("ENTER")
	_cta_key = keycap.get_child(0) as Label
	box.add_child(keycap)

	_cta_action = _label("play", 20, GameConfig.SNAKE_HEAD_COLOR)
	_cta_action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_cta_action)

	_cta_holder.add_child(_cta_panel)


func _set_call_to_action(key: String, action: String) -> void:
	_cta_key.text = key
	_cta_action.text = action


func _set_chips(entries: Array) -> void:
	for child in _chips.get_children():
		child.queue_free()
	_chips.visible = not entries.is_empty()
	for entry: Array in entries:
		_chips.add_child(_chip(entry[0], entry[1], entry[2]))


func _set_hints(rows: Array) -> void:
	for child in _hints.get_children():
		child.queue_free()
	for row: Array in rows:
		_hints.add_child(_keycap_row(row[0], row[1]))


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _pill() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(18)
	style.set_content_margin_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _chip(caption: String, value: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.12)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.border_color = Color(color.r, color.g, color.b, 0.35)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var caption_label := _label(caption, 12, GameConfig.DIM_COLOR)
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(caption_label)
	box.add_child(_label(value, 18, color))
	return panel


## One line of the legend: a few keycaps and what they do.
func _keycap_row(keys: Array, action: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for key: String in keys:
		row.add_child(_keycap(key))
	var action_label := _label(action, 14, GameConfig.DIM_COLOR)
	action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(action_label)
	return row


func _keycap(text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = KEYCAP_COLOR
	style.set_corner_radius_all(6)
	style.set_content_margin_all(4)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 1)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(_label(text, 13, GameConfig.TEXT_COLOR))
	return panel


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_COLOR
	style.set_corner_radius_all(22)
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 18
	return style
