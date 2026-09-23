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

var carried := false
var boost_ratio := 0.0        # 1 when the boost starts, 0 when it ends
var boosting := false

var _pulse := 0.0


func _process(delta: float) -> void:
	# Only the lit states animate; an empty slot is a static drawing.
	if carried or boosting:
		_pulse += delta
		queue_redraw()


func set_state(has_item: bool, is_boosting: bool, ratio: float) -> void:
	if carried == has_item and boosting == is_boosting and is_equal_approx(boost_ratio, ratio):
		return
	carried = has_item
	boosting = is_boosting
	boost_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 2.0
	var lit := carried or boosting
	var glow := 0.5 + 0.5 * sin(_pulse * 3.2)

	# Disc
	draw_circle(centre, radius, Color(0.04, 0.06, 0.1, 0.72))

	# Outline, brighter when something is in the slot
	var outline := GameConfig.DIM_COLOR
	outline.a = 0.45
	if lit:
		outline = GameConfig.BOOST_COLOR.lerp(GameConfig.SPARK_COLOR, glow)
	draw_arc(centre, radius, 0.0, TAU, 48, outline, 2.0, true)

	# Fuse ring while the boost burns
	if boosting and boost_ratio > 0.0:
		draw_arc(
			centre, radius - 4.0,
			-PI * 0.5, -PI * 0.5 + TAU * boost_ratio,
			48, GameConfig.SPARK_COLOR, 3.0, true
		)

	# The bolt itself
	var bolt_color := GameConfig.DIM_COLOR
	bolt_color.a = 0.35
	if lit:
		bolt_color = GameConfig.BOOST_COLOR.lerp(GameConfig.SPARK_COLOR, glow * 0.7)

	var scale_factor := radius * 0.62
	var points := PackedVector2Array()
	for point: Vector2 in BOLT_OUTLINE:
		points.append(centre + point * scale_factor)
	draw_colored_polygon(points, bolt_color)
