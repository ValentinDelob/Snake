class_name SnakeHud
extends CanvasLayer

## What the player asked for on the menu. The HUD owns the pages and their
## back navigation; the game only hears about the decisions.
signal solo_requested()
signal host_requested()
signal join_requested(address: String)
signal quality_chosen(mode: int)
signal vsync_toggled()
signal fps_limit_cycled()
signal debug_toggled()
signal rivals_cycled()
signal effects_toggled()
signal quit_requested()

## The interface: a slim top bar while playing, and a centred card for the
## menu, the pause and the game over screens.
##
## The whole tree is built in code. Panels, pills and keycaps are styled
## StyleBoxFlat rather than plain text, so the layout holds at any window
## size and there is a single place to change the look.

## Frosted white glass over a sunny scene: bright panels, dark ink, and
## a soft navy shadow under everything so it floats above the arena.
const PANEL_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const CARD_COLOR := Color(1.0, 0.99, 0.97, 0.95)
const KEYCAP_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const BORDER_COLOR := Color(0.12, 0.15, 0.3, 0.14)
const BUTTON_COLOR := Color(0.95, 0.95, 1.0, 1.0)
const SHADOW_COLOR := Color(0.1, 0.12, 0.35, 0.2)
## How far down the item slot sits: the score pill ends around 74 px.
const ITEM_SLOT_TOP := 92
## The letters of the logo, one colour each, taken from the snakes.
const LOGO_TEXT := "SNAKE 3D"

## The menu is three pages deep: the main one, the multiplayer choice, and
## the address box behind "join".
enum MenuPage { MAIN, MULTIPLAYER, JOIN, GRAPHICS }

var _top_bar: Control
var _score_value: Label
var _best_value: Label
var _mode_chip: Label
var _item_slot: ItemSlot
var _item_hint: Control
var _boost_label: Label
var _players_box: VBoxContainer
var _players_pill: PanelContainer
var _spectator_label: Label

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

var _buttons: VBoxContainer
var _address_field: LineEdit
var _menu_page: MenuPage = MenuPage.MAIN
## The menu is walked by hand rather than leaning on the engine's focus
## neighbours: it behaves the same whether the window is focused or not,
## and it can be driven by the self-test.
var _menu_items: Array[Control] = []
var _menu_index := 0
var _menu_best := 0.0
var _menu_games := 0
var _menu_message := ""
var _saved_address := ""

var _debug_panel: PanelContainer
var _debug_fps: Label
var _shown_fps := -1

var _spit_hint: Control
var _clock: Label
var _shown_clock := -1
var _shown_best := -1
var _shown_score := -1
var _breath := 0.0
var _score_note: Label
var _score_note_time := 0.0
var _logo: HBoxContainer
var _theme: Theme


func _ready() -> void:
	_theme = _build_theme()
	_build_top_bar()
	_build_overlay()


# --------------------------------------------------------------------------- #
# Playing: the top bar
# --------------------------------------------------------------------------- #
## A slow breath on the call to action, to pull the eye to it. Driven here
## rather than by a looping tween, which cannot outlive its panel.
func _process(delta: float) -> void:
	if _score_note_time > 0.0:
		_score_note_time = maxf(0.0, _score_note_time - delta)
		_score_note.modulate.a = minf(1.0, _score_note_time / 0.4)
	if not _overlay.visible:
		return
	_breath += delta
	_cta_panel.modulate.a = 0.78 + 0.22 * (0.5 + 0.5 * sin(_breath * 2.4))
	# The logo bobs letter by letter, a slow wave running through it.
	if _logo.visible:
		for index in range(_logo.get_child_count()):
			var letter := _logo.get_child(index) as Label
			letter.position.y = sin(_breath * 3.0 - index * 0.55) * 5.0


func _build_top_bar() -> void:
	_top_bar = Control.new()
	_top_bar.theme = _theme
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

	var score_caption := _label("LENGTH", 13, GameConfig.DIM_COLOR)
	score_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_box.add_child(score_caption)

	_score_value = _label("0", 30, GameConfig.TEXT_COLOR)
	score_box.add_child(_score_value)

	# Points won or lost in one go deserve saying out loud, otherwise the
	# number simply jumps and the player never learns what the crate did.
	_score_note = _label("", 20, GameConfig.ACCENT_COLOR)
	_score_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_note.modulate.a = 0.0
	score_box.add_child(_score_note)

	row.add_child(_spacer())

	# Camera chip, centred
	var mode_pill := _pill()
	mode_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mode_style: StyleBoxFlat = mode_pill.get_theme_stylebox("panel")
	mode_style.bg_color = Color(PANEL_COLOR.r, PANEL_COLOR.g, PANEL_COLOR.b, 0.45)
	row.add_child(mode_pill)

	var mode_box := HBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 12)
	mode_pill.add_child(mode_box)

	# The clock, in the middle, where everyone will look for it.
	_clock = _label("5:00", 17, GameConfig.TEXT_COLOR)
	mode_box.add_child(_clock)

	_mode_chip = _label("3D follow", 13, GameConfig.DIM_COLOR)
	_mode_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_box.add_child(_mode_chip)

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

	# Item slot under the score, with a clear gap below the score pill and
	# its shadow: pressed right up against it, the two read as one block.
	var item_row := HBoxContainer.new()
	item_row.position = Vector2(22, ITEM_SLOT_TOP)
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

	_spit_hint = _keycap_row(["E"], "bring it up")
	_spit_hint.visible = false
	item_column.add_child(_spit_hint)

	_boost_label = _label("", 14, GameConfig.SPARK_COLOR)
	item_column.add_child(_boost_label)

	# Who else is in the round, and who is still alive
	_players_pill = _pill()
	_players_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_players_pill.offset_right = -22
	_players_pill.offset_top = 74
	_players_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_players_pill.visible = false
	_top_bar.add_child(_players_pill)
	_players_box = VBoxContainer.new()
	_players_box.alignment = BoxContainer.ALIGNMENT_END
	_players_box.add_theme_constant_override("separation", 2)
	_players_pill.add_child(_players_box)

	# The debug readout. One line for now; it is a column so the next thing
	# worth watching can simply be added under it.
	_debug_panel = _pill()
	_debug_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_debug_panel.offset_left = 22
	_debug_panel.offset_top = -74
	_debug_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_debug_panel.visible = false
	_top_bar.add_child(_debug_panel)

	var debug_column := VBoxContainer.new()
	debug_column.add_theme_constant_override("separation", 2)
	_debug_panel.add_child(debug_column)

	var debug_caption := _label("DEBUG", 11, GameConfig.DIM_COLOR)
	debug_column.add_child(debug_caption)
	_debug_fps = _label("FPS  --", 16, GameConfig.ACCENT_COLOR)
	debug_column.add_child(_debug_fps)

	_spectator_label = _label("", 16, GameConfig.FROST_COLOR)
	_spectator_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spectator_label.offset_top = -70
	_spectator_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_spectator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectator_label.visible = false
	_top_bar.add_child(_spectator_label)


## The two numbers that matter now: how long this snake is, and the longest
## one ever grown. Both are lengths, not tallies.
func set_stats(length: float, best: float, mode_text: String) -> void:
	var shown := int(round(length * 10.0))
	if shown != _shown_score:
		if shown > _shown_score:
			_punch(_score_value)
		_shown_score = shown
		_score_value.text = "%.1f" % length
	var best_shown := int(round(best * 10.0))
	if best_shown != _shown_best:
		_shown_best = best_shown
		_best_value.text = "%.1f" % best
	if mode_text != _mode_chip.text:
		_mode_chip.text = mode_text


## Whether the snake has enough inside it to bring any of it up.
func set_can_spit(can: bool) -> void:
	if _spit_hint.visible != can:
		_spit_hint.visible = can


## How long is left on the round clock.
func set_clock(seconds: float) -> void:
	var whole := int(ceil(maxf(0.0, seconds)))
	if whole == _shown_clock:
		return
	_shown_clock = whole
	_clock.text = "%d:%02d" % [whole / 60, whole % 60]
	# The last ten seconds tick loudly: every one of them gives the clock a kick.
	if whole <= 10 and whole > 0:
		_punch(_clock)
	_clock.add_theme_color_override(
		"font_color",
		GameConfig.DANGER_COLOR if whole <= 30 else GameConfig.TEXT_COLOR
	)


## Say out loud what dying cost, since it no longer ends anything.
func announce_loss(length: float) -> void:
	_score_note.text = "-%.1f" % length
	_score_note.add_theme_color_override("font_color", GameConfig.DANGER_COLOR)
	_score_note_time = 2.0
	_score_note.modulate.a = 1.0
	_punch(_score_note)


## Show or hide the debug readout, and keep it fed. The frame rate is the
## engine's own count, so it measures the whole frame rather than the part
## the game happens to time.
func set_debug(enabled: bool) -> void:
	if _debug_panel.visible != enabled:
		_debug_panel.visible = enabled
		_shown_fps = -1
	if not enabled:
		return
	var fps := Engine.get_frames_per_second()
	if fps != _shown_fps:
		_shown_fps = fps
		_debug_fps.text = "FPS  %d" % fps


## What the debug readout says, or nothing at all when it is switched off.
## The self-test reads this rather than guessing at the panel.
func debug_readout() -> String:
	return _debug_fps.text if _debug_panel.visible else ""


## Call out a jump in the score: "+3" beside it, in its own colour, fading
## away on its own.
func announce_score(points: float) -> void:
	if absf(points) < 0.05:
		return
	_score_note.text = "+%.1f" % points if points > 0.0 else "%.1f" % points
	_score_note.add_theme_color_override(
		"font_color",
		GameConfig.GOOD_COLOR if points > 0.0 else GameConfig.DANGER_COLOR
	)
	_score_note_time = 1.6
	_score_note.modulate.a = 1.0
	_punch(_score_note)


## Item slot state: what is carried, and the effect currently running.
## Kinds mirror SnakeWorld.Item: 0 none, 1 speed, 2 slow.
func set_item(carried: int, effect: int, time_left: float, total: float) -> void:
	_item_slot.set_state(carried, effect, time_left / maxf(total, 0.001))
	_item_hint.visible = carried != 0 and effect == 0

	if effect == 2:
		_boost_label.text = "SLOWED  %.1fs" % time_left
		_boost_label.add_theme_color_override("font_color", GameConfig.FROST_COLOR)
	elif effect == SnakeWorld.Item.SHEARS:
		_boost_label.text = "SHEARS  %.1fs" % time_left
		_boost_label.add_theme_color_override("font_color", GameConfig.SHEARS_COLOR.darkened(0.45))
	elif effect == 5:
		_boost_label.text = "GHOST  %.1fs" % time_left
		_boost_label.add_theme_color_override("font_color", GameConfig.PHASE_COLOR)
	elif effect == 1:
		_boost_label.text = "BOOST  %.1fs" % time_left
		_boost_label.add_theme_color_override("font_color", GameConfig.SPARK_COLOR)
	elif carried != 0:
		_boost_label.text = ""
	else:
		_boost_label.text = "no item"
		_boost_label.add_theme_color_override("font_color", GameConfig.DIM_COLOR)


## One line per player while a match is on; hidden when playing solo.
func set_players(rows: Array, local_id: int, spectating: bool) -> void:
	_players_box.visible = rows.size() > 1
	_players_pill.visible = _players_box.visible
	if _players_box.visible:
		while _players_box.get_child_count() < rows.size():
			_players_box.add_child(_label("", 15, GameConfig.TEXT_COLOR))
		while _players_box.get_child_count() > rows.size():
			var extra := _players_box.get_child(_players_box.get_child_count() - 1)
			_players_box.remove_child(extra)
			extra.queue_free()

		for index in range(rows.size()):
			var row: Dictionary = rows[index]
			var label: Label = _players_box.get_child(index)
			var palette: Array = GameConfig.palette_for(
				0 if row["id"] == local_id else maxi(1, index)
			)
			# Peer ids are huge random numbers: nobody needs to read those.
			var name_text: String = row.get("name", (
				"you" if row["id"] == local_id else "player %d" % (index + 1)
			))
			label.text = "%s  %.1f%s" % [
				name_text, row["length"], "" if row["alive"] else "  gone",
			]
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.add_theme_color_override(
				"font_color", palette[1] if row["alive"] else GameConfig.DIM_COLOR
			)

	_spectator_label.visible = spectating
	if spectating:
		_spectator_label.text = "you are out - fly around with the arrow keys"


func set_bar_visible(value: bool) -> void:
	_top_bar.visible = value


# --------------------------------------------------------------------------- #
# Menu, pause and game over: the card
# --------------------------------------------------------------------------- #
func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.theme = _theme
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# A light navy veil: enough to lift the white card off a bright scene,
	# not so much that the arena behind it goes dark.
	dim.color = Color(0.1, 0.12, 0.32, 0.3)
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

	_logo = HBoxContainer.new()
	_logo.alignment = BoxContainer.ALIGNMENT_CENTER
	_logo.add_theme_constant_override("separation", 2)
	for index in range(LOGO_TEXT.length()):
		var palette: Array = GameConfig.palette_for(index)
		var letter := _label(LOGO_TEXT[index], 64, palette[1])
		_outline(letter, 12)
		letter.custom_minimum_size = Vector2(24 if LOGO_TEXT[index] == " " else 0, 84)
		_logo.add_child(letter)
	card_box.add_child(_logo)

	_title = _label("SNAKE 3D", 56, GameConfig.GOOD_COLOR)
	_outline(_title, 10)
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

	_buttons = VBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 8)
	card_box.add_child(_buttons)

	_hints = VBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	_hints.add_theme_constant_override("separation", 6)
	card_box.add_child(_hints)


func show_menu(best: float, games: int, message: String = "") -> void:
	_menu_best = best
	_menu_games = games
	_menu_message = message
	_show_menu_page(MenuPage.MAIN)


## Step back through the menu pages. Returns false when there is nowhere
## left to go, which is the game's cue to quit.
func menu_back() -> bool:
	match _menu_page:
		MenuPage.JOIN:
			_show_menu_page(MenuPage.MULTIPLAYER)
			return true
		MenuPage.MULTIPLAYER, MenuPage.GRAPHICS:
			_show_menu_page(MenuPage.MAIN)
			return true
		_:
			return false


func _show_menu_page(page: MenuPage) -> void:
	_menu_page = page
	# The big coloured logo belongs to the front page; the pages behind it
	# are tall enough already.
	_use_logo(page == MenuPage.MAIN)
	_title.text = "SNAKE 3D"
	_title.add_theme_color_override("font_color", GameConfig.GOOD_COLOR)
	_cta_holder.visible = false
	_address_field = null

	match page:
		MenuPage.MAIN:
			_subtitle.text = (
				_menu_message if _menu_message != ""
				else "grab the bolt for speed - the crate is a gamble"
			)
			_subtitle.add_theme_color_override(
				"font_color",
				GameConfig.DANGER_COLOR if _menu_message != "" else GameConfig.TEXT_COLOR
			)
			_set_chips([
				["BEST", "%.1f" % _menu_best, GameConfig.ACCENT_COLOR],
				["GAMES", str(_menu_games), GameConfig.TEXT_COLOR],
			])
			_set_buttons([
				{"text": "PLAY SOLO", "primary": true, "action": solo_requested},
				# Right under solo, since it is what solo will be played against.
				{"text": "RIVALS  %s" % _rivals_label(), "action": func(): rivals_cycled.emit()},
				{"text": "MULTIPLAYER", "action": func(): _show_menu_page(MenuPage.MULTIPLAYER)},
				{"text": "GRAPHICS", "action": func(): _show_menu_page(MenuPage.GRAPHICS)},
				{"text": "QUIT", "action": quit_requested},
			])
			_set_hints([
				[["SPACE"], "fire the item you carry"],
				[["C", "V"], "camera  /  flat view"],
			])
		MenuPage.MULTIPLAYER:
			_menu_message = ""
			_subtitle.text = "play against somebody on another computer"
			_subtitle.add_theme_color_override("font_color", GameConfig.TEXT_COLOR)
			_set_chips([])
			_set_buttons([
				{"text": "HOST A GAME", "primary": true, "action": host_requested},
				{"text": "JOIN A GAME", "action": func(): _show_menu_page(MenuPage.JOIN)},
				{"text": "BACK", "action": func(): _show_menu_page(MenuPage.MAIN)},
			])
			_set_hints([
				[["ESC"], "back"],
			])
		MenuPage.GRAPHICS:
			_subtitle.text = "how the snake is cut, and how the frames are paced"
			_subtitle.add_theme_color_override("font_color", GameConfig.TEXT_COLOR)
			_set_chips([])
			var entries: Array = []
			for index in range(GameConfig.QUALITY_MODES.size()):
				var mode: Dictionary = GameConfig.QUALITY_MODES[index]
				var chosen: bool = index == int(GameConfig.quality)
				entries.append({
					"text": "%s%s  -  %s" % [
						"> " if chosen else "", mode["label"], mode["note"],
					],
					"primary": chosen,
					"action": func(): quality_chosen.emit(index),
				})
			# How the frames are paced belongs on the same page: it is the
			# other half of how smooth the game feels.
			entries.append({
				"text": "VSYNC  %s" % ("ON" if PlayerProfile.get_preference("vsync") else "OFF"),
				"action": func(): vsync_toggled.emit(),
			})
			entries.append({
				"text": "FPS LIMIT  %s" % GameConfig.fps_limit_label(
					int(PlayerProfile.get_preference("fps_limit"))
				),
				"action": func(): fps_limit_cycled.emit(),
			})
			# Sparks, pollen and trails: pure show, so they can be turned down
			# without losing anything the game says.
			entries.append({
				"text": "EFFECTS  %s" % ("FULL" if PlayerProfile.get_preference("effects") else "LIGHT"),
				"action": func(): effects_toggled.emit(),
			})
			entries.append({
				"text": "DEBUG  %s" % ("ON" if PlayerProfile.get_preference("debug") else "OFF"),
				"action": func(): debug_toggled.emit(),
			})
			entries.append({"text": "BACK", "action": func(): _show_menu_page(MenuPage.MAIN)})
			_set_buttons(entries)
			_set_hints([
				[["ESC"], "back"],
			])
		MenuPage.JOIN:
			_subtitle.text = "address of the computer hosting the game"
			_subtitle.add_theme_color_override("font_color", GameConfig.TEXT_COLOR)
			_set_chips([])
			_set_buttons([
				{"field": true},
				{"text": "CONNECT", "primary": true, "action": func(): _submit_address()},
				{"text": "BACK", "action": func(): _show_menu_page(MenuPage.MULTIPLAYER)},
			])
			_set_hints([
				[["ENTER"], "connect"],
				[["ESC"], "back"],
			])
	_present()


func _rivals_label() -> String:
	var count := int(PlayerProfile.get_preference("rivals"))
	return "NONE" if count <= 0 else str(count)


func _submit_address() -> void:
	var address := "127.0.0.1"
	if _address_field != null and _address_field.text.strip_edges() != "":
		address = _address_field.text.strip_edges()
	join_requested.emit(address)


## Fill the button column. An entry is either a button or the address box.
func _set_buttons(entries: Array) -> void:
	for child in _buttons.get_children():
		child.queue_free()
	_buttons.visible = not entries.is_empty()

	_menu_items = []
	for entry: Dictionary in entries:
		var control: Control
		if entry.get("field", false):
			control = _build_address_field()
		else:
			control = _build_button(entry["text"], entry.get("primary", false), entry["action"])
			# A long page gets slimmer buttons so it still fits a small window.
			if entries.size() > 6:
				control.custom_minimum_size.y = 40
		_buttons.add_child(control)
		_menu_items.append(control)

	# Select the first thing on the page, so the keyboard works without a
	# click and the self-test can drive the menu the way a player does.
	_menu_index = 0
	if not _menu_items.is_empty():
		_select_menu_item(0)


func _select_menu_item(index: int) -> void:
	if _menu_items.is_empty():
		return
	_menu_index = wrapi(index, 0, _menu_items.size())
	var item := _menu_items[_menu_index]
	item.call_deferred("grab_focus")


## The engine moves the focus too (clicks, its own arrow handling), so the
## real focus always wins over our index.
func _sync_menu_index() -> void:
	var owner := get_viewport().gui_get_focus_owner()
	var owned := _menu_items.find(owner)
	if owned >= 0:
		_menu_index = owned


## Move the selection. The game routes the arrow keys here.
func move_menu_focus(step: int) -> void:
	if _menu_items.is_empty():
		return
	_sync_menu_index()
	_select_menu_item(_menu_index + step)


## Press whatever is selected.
func activate_menu_item() -> bool:
	if _menu_items.is_empty():
		return false
	_sync_menu_index()
	var item := _menu_items[_menu_index]
	if item is LineEdit:
		_submit_address()
	elif item is Button:
		(item as Button).emit_signal("pressed")
	return true


func menu_open() -> bool:
	return not _menu_items.is_empty() and _overlay.visible


func _build_button(text: String, primary: bool, action) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 50)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 19)

	# The primary button is a solid green sweet with white letters; the rest
	# are white glass with dark ink. Whatever has the focus gets an orange
	# ring, so the keyboard always shows where it is.
	var ink: Color = Color.WHITE if primary else GameConfig.TEXT_COLOR
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, ink)
	button.add_theme_stylebox_override("normal", _button_style(primary, 0.0))
	button.add_theme_stylebox_override("hover", _button_style(primary, 0.08))
	button.add_theme_stylebox_override("pressed", _button_style(primary, -0.08))
	button.add_theme_stylebox_override("focus", _button_style(primary, 0.06, true))

	if action is Signal:
		button.pressed.connect(func(): action.emit())
	else:
		button.pressed.connect(action)
	return button


func _button_style(primary: bool, lift: float, focused: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if primary:
		style.bg_color = GameConfig.GOOD_COLOR.lightened(0.1 + lift)
	elif focused:
		style.bg_color = Color(1.0, 0.95, 0.88).lightened(lift)
	else:
		style.bg_color = BUTTON_COLOR.lightened(lift)
	style.set_corner_radius_all(25)
	style.set_content_margin_all(10)
	style.border_color = GameConfig.ACCENT_COLOR if focused else (
		GameConfig.GOOD_COLOR.darkened(0.2) if primary else BORDER_COLOR
	)
	style.set_border_width_all(3 if focused else 1)
	style.shadow_color = SHADOW_COLOR
	style.shadow_size = 8 if focused else 4
	style.shadow_offset = Vector2(0, 3)
	return style


func _build_address_field() -> LineEdit:
	_address_field = LineEdit.new()
	_address_field.custom_minimum_size = Vector2(300, 46)
	_address_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_address_field.placeholder_text = "192.168.1.20"
	_address_field.add_theme_font_size_override("font_size", 18)
	_address_field.add_theme_color_override("font_color", GameConfig.TEXT_COLOR)
	_address_field.add_theme_stylebox_override("normal", _button_style(false, 0.0))
	_address_field.add_theme_stylebox_override("focus", _button_style(false, 0.08, true))
	_address_field.text = _saved_address
	_address_field.caret_column = _saved_address.length()
	# The remembered address is a suggestion: selecting it means typing
	# replaces it instead of landing in the middle of it.
	_address_field.focus_entered.connect(func(): _address_field.select_all())
	_address_field.text_submitted.connect(func(_text): _submit_address())
	# A focused LineEdit swallows escape, which left the page with no way
	# back for anybody typing. Give it the same meaning as everywhere else.
	_address_field.gui_input.connect(func(event: InputEvent):
		var key := event as InputEventKey
		if key != null and key.pressed and key.keycode == KEY_ESCAPE:
			_address_field.accept_event()
			_show_menu_page(MenuPage.MULTIPLAYER)
	)
	return _address_field


## Redraw the menu where it stands, so a mode picked on the graphics page
## shows as the chosen one straight away.
func refresh_menu_page() -> void:
	if _menu_items.is_empty():
		return
	# The selection stays on the entry that was just pressed, so a setting
	# that cycles can be pressed again without walking back down to it.
	_sync_menu_index()
	var kept := _menu_index
	_show_menu_page(_menu_page)
	_select_menu_item(kept)


## Pre-fill the address box with whatever was used last. The menu remembers
## it even while the field does not exist, since the join page is built late.
func set_address(address: String) -> void:
	_saved_address = address
	if _address_field != null:
		_address_field.text = address


## The waiting room, before the host starts the round.
func show_lobby(is_host: bool, players: int, addresses: String, dialling: String = "") -> void:
	_use_logo(false)
	_title.text = "LOBBY"
	_title.add_theme_color_override("font_color", GameConfig.ACCENT_COLOR)
	if dialling != "":
		# Still knocking: say so rather than pretend the host is there.
		_subtitle.text = "connecting to  %s" % dialling
	elif is_host:
		_subtitle.text = "others join you at  %s" % addresses
	else:
		_subtitle.text = "waiting for the host to start"
	_subtitle.add_theme_color_override("font_color", GameConfig.TEXT_COLOR)
	if dialling != "":
		_set_chips([])
	else:
		_set_chips([
			["PLAYERS", str(players), GameConfig.GOOD_COLOR],
		])
	if dialling != "":
		_set_call_to_action("...", "connecting")
	elif is_host:
		_set_call_to_action("ENTER", "start the round")
	else:
		_set_call_to_action("...", "waiting")
	_set_hints([
		[["ESC"], "leave the session"],
	])
	_present()


## The end of a multiplayer round: one winner, everybody else watched.
## The clock ran out. Whoever grew the biggest snake takes the round.
func show_result(
	title: String, color: Color, subtitle: String, length: float, best: float, record: bool,
	again: String = "back to the lobby"
) -> void:
	_use_logo(false)
	_title.text = title
	_title.add_theme_color_override("font_color", color)
	_subtitle.text = subtitle
	_subtitle.add_theme_color_override("font_color", GameConfig.TEXT_COLOR)
	_set_chips([
		["YOUR LENGTH", "%.1f" % length, GameConfig.TEXT_COLOR],
		["NEW BEST" if record else "BEST", "%.1f" % best, GameConfig.ACCENT_COLOR],
	])
	var online := again == "back to the lobby"
	_set_call_to_action("ENTER" if online else "R", again)
	_set_hints([
		[["M"], "leave the session" if online else "menu"],
		[["ESC"], "quit"],
	])
	_present()


func show_pause() -> void:
	_use_logo(false)
	_title.text = "PAUSED"
	_title.add_theme_color_override("font_color", GameConfig.TEXT_COLOR)
	_subtitle.text = ""
	_set_chips([])
	_set_call_to_action("P", "resume")
	_set_hints([
		[["ESC"], "back to the menu"],
	])
	_present()


func show_game_over(cause: String, length: float, best: float, record: bool) -> void:
	_use_logo(false)
	_title.text = "TIME"
	_title.add_theme_color_override("font_color", GameConfig.ACCENT_COLOR)
	_subtitle.text = cause
	_set_chips([
		["LENGTH", "%.1f" % length, GameConfig.TEXT_COLOR],
		["NEW BEST" if record else "BEST", "%.1f" % best, GameConfig.ACCENT_COLOR],
	])
	_set_call_to_action("R", "play again")
	_set_hints([
		[["M"], "menu"],
		[["ESC"], "quit"],
	])
	_present()


func hide_overlay() -> void:
	_overlay.visible = false
	# A menu button that keeps the focus goes on answering the space bar
	# while the round is being played, which starts a fresh one under the
	# player's feet. Nothing on the overlay owns the keyboard once it is
	# out of the way.
	_menu_items.clear()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()


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
	style.bg_color = GameConfig.GOOD_COLOR.lightened(0.1)
	style.set_corner_radius_all(26)
	style.set_content_margin_all(12)
	style.content_margin_left = 24
	style.content_margin_right = 28
	style.border_color = GameConfig.GOOD_COLOR.darkened(0.2)
	style.set_border_width_all(1)
	style.shadow_color = SHADOW_COLOR
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	_cta_panel.add_theme_stylebox_override("panel", style)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_cta_panel.add_child(box)

	var keycap := _keycap("ENTER")
	_cta_key = keycap.get_child(0) as Label
	box.add_child(keycap)

	_cta_action = _label("play", 22, Color.WHITE)
	_cta_action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_cta_action)

	_cta_holder.add_child(_cta_panel)


func _set_call_to_action(key: String, action: String) -> void:
	_cta_holder.visible = true
	_cta_key.text = key
	_cta_action.text = action
	if _buttons != null:
		for child in _buttons.get_children():
			child.queue_free()
		_buttons.visible = false
		_address_field = null


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
	style.set_corner_radius_all(20)
	style.set_content_margin_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.border_color = Color(1.0, 1.0, 1.0, 0.95)
	style.set_border_width_all(1)
	style.shadow_color = SHADOW_COLOR
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _chip(caption: String, value: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.12)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.border_color = Color(color.r, color.g, color.b, 0.45)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var caption_label := _label(caption, 12, GameConfig.DIM_COLOR)
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(caption_label)
	box.add_child(_label(value, 20, color.darkened(0.15)))
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
	style.set_corner_radius_all(8)
	style.set_content_margin_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	# A deeper shadow underneath than around: it reads as a key you could press.
	style.border_width_bottom = 3
	style.shadow_color = SHADOW_COLOR
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(_label(text, 13, GameConfig.TEXT_COLOR))
	return panel


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_COLOR
	style.set_corner_radius_all(32)
	style.border_color = Color(1.0, 1.0, 1.0, 1.0)
	style.set_border_width_all(2)
	style.shadow_color = Color(0.1, 0.12, 0.35, 0.3)
	style.shadow_size = 30
	style.shadow_offset = Vector2(0, 10)
	return style


## A white outline and a soft drop shadow: what makes big lettering look
## like a sticker rather than print, and keeps it legible over anything.
func _outline(label: Label, size: int) -> void:
	label.add_theme_color_override("font_outline_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", size)
	label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.add_theme_constant_override("shadow_outline_size", size + 4)


## One rounded, heavy face for the whole interface. It is a system font, so
## nothing has to ship with the game; the engine falls back on its own if
## none of these is installed.
func _build_theme() -> Theme:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI Black", "Segoe UI", "Arial Rounded MT Bold", "Arial"])
	font.font_weight = 800
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	return theme


## The menu wears the coloured logo; every other card, a plain title.
func _use_logo(value: bool) -> void:
	_logo.visible = value
	_title.visible = not value
