class_name SnakeHud
extends CanvasLayer

## Score bar and the centred overlay used by the menu, the pause and the
## game over screens.

@onready var _score: Label = $Score
@onready var _item: Label = $Item
@onready var _mode: Label = $Mode
@onready var _best: Label = $Best
@onready var _overlay: Control = $Overlay
@onready var _title: Label = $Overlay/Box/Title
@onready var _subtitle: Label = $Overlay/Box/Subtitle
@onready var _extra: Label = $Overlay/Box/Extra
@onready var _hint: Label = $Overlay/Box/Hint


func _ready() -> void:
	_score.add_theme_color_override("font_color", GameConfig.TEXT_COLOR)
	_best.add_theme_color_override("font_color", GameConfig.ACCENT_COLOR)
	_mode.add_theme_color_override("font_color", GameConfig.DIM_COLOR)
	_subtitle.add_theme_color_override("font_color", GameConfig.TEXT_COLOR)
	_extra.add_theme_color_override("font_color", GameConfig.ACCENT_COLOR)
	_hint.add_theme_color_override("font_color", GameConfig.DIM_COLOR)


## The special item slot, and the boost countdown once it is fired.
func set_item(text: String, color: Color) -> void:
	_item.text = text
	_item.add_theme_color_override("font_color", color)


func set_stats(score: int, best: int, mode_text: String) -> void:
	_score.text = "SCORE %d" % score
	_best.text = "BEST %d" % best
	_mode.text = mode_text


func set_bar_visible(value: bool) -> void:
	_score.visible = value
	_best.visible = value
	_mode.visible = value
	_item.visible = value


func show_overlay(title: String, color: Color, subtitle: String, extra: String, hint: String) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", color)
	_subtitle.text = subtitle
	_extra.text = extra
	_hint.text = hint
	_overlay.visible = true


func hide_overlay() -> void:
	_overlay.visible = false
