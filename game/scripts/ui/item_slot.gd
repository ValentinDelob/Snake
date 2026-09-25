class_name ItemSlot
extends Control

## The special item slot, drawn rather than written.
##
## Empty it is a faint outline; holding the bolt it lights up; while the
## boost burns, the ring around it empties like a fuse.

const BOLT_OUTLINE := [
	Vector2(0.16, -1.0), Vector2(-0.52, -0.06), Vector2(-0.12, -0.06),
	Vector2(-0.3, 1.0), Vector2(0.52, 0.02), Vector2(0.1, 0.02),
]

## What is in the slot and what is running, mirroring SnakeWorld.Item so
## the HUD does not have to translate: 0 nothing, 1 speed, 2 slow, 5 the
## ghost ring.
var carried := 0
var effect := 0
var effect_ratio := 0.0       # 1 when the effect starts, 0 when it ends

var _pulse := 0.0


func _process(delta: float) -> void:
	# Only the lit states animate; an empty, idle slot is a static drawing.
	if carried != 0 or effect != 0:
		_pulse += delta
		queue_redraw()


func set_state(carried_item: int, active_effect: int, ratio: float) -> void:
	if (
		carried == carried_item and effect == active_effect
		and is_equal_approx(effect_ratio, ratio)
	):
		return
	carried = carried_item
	effect = active_effect
	effect_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()


const GHOST := 5
const SHEARS := 6


func _effect_color() -> Color:
	if effect == 2:
		return GameConfig.FROST_COLOR
	if effect == SHEARS or carried == SHEARS:
		return GameConfig.SHEARS_COLOR
	if effect == GHOST or carried == GHOST:
		return GameConfig.PHASE_COLOR
	return GameConfig.BOOST_COLOR


func _draw() -> void:
	var centre := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 2.0
	var lit := carried != 0 or effect != 0
	var glow := 0.5 + 0.5 * sin(_pulse * 3.2)

	# Disc
	draw_circle(centre, radius, Color(0.04, 0.06, 0.1, 0.72))

	# Outline, brighter when something is in the slot or running
	var outline := GameConfig.DIM_COLOR
	outline.a = 0.45
	if lit:
		outline = _effect_color().lerp(GameConfig.SPARK_COLOR, glow)
	draw_arc(centre, radius, 0.0, TAU, 48, outline, 2.0, true)

	# Fuse ring while an effect runs, in the colour of that effect
	if effect != 0 and effect_ratio > 0.0:
		draw_arc(
			centre, radius - 4.0,
			-PI * 0.5, -PI * 0.5 + TAU * effect_ratio,
			48, _effect_color(), 3.0, true
		)

	# The bolt itself
	var item_color := GameConfig.DIM_COLOR
	item_color.a = 0.35
	var showing: int = carried if carried != 0 else effect

	# The ghost ring is drawn as a ring: nobody should have to remember
	# which colour of lightning bolt means what.
	if showing == GHOST:
		if carried != 0 or effect != 0:
			item_color = GameConfig.PHASE_COLOR.lerp(GameConfig.PHASE_PALE_COLOR, glow)
		draw_arc(centre, radius * 0.46, 0.0, TAU, 32, item_color, 3.0, true)
		return

	# The shears: two crossed blades and their two finger rings.
	if showing == SHEARS:
		if carried != 0 or effect != 0:
			item_color = GameConfig.SHEARS_COLOR.lerp(GameConfig.SHEARS_PALE_COLOR, glow)
		var reach := radius * 0.5
		for side: float in [-1.0, 1.0]:
			var tip := centre + Vector2(side * reach * 0.55, -reach)
			var grip := centre + Vector2(-side * reach * 0.45, reach * 0.35)
			draw_line(tip, grip, item_color, 3.5, true)
			draw_arc(grip + Vector2(-side * 2.0, 5.0), reach * 0.3, 0.0, TAU, 20, item_color, 2.5, true)
		return

	if carried != 0:
		item_color = GameConfig.BOOST_COLOR.lerp(GameConfig.SPARK_COLOR, glow * 0.7)

	var scale_factor := radius * 0.62
	var points := PackedVector2Array()
	for point: Vector2 in BOLT_OUTLINE:
		points.append(centre + point * scale_factor)
	draw_colored_polygon(points, item_color)
