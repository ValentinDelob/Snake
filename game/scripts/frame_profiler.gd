class_name FrameProfiler
extends RefCounted

## Where a frame goes, and how bad the worst ones are.
##
## Averages hide stutter: a run can sit at 60 fps and still feel broken
## because one frame in fifty takes 40 ms. So this keeps every frame time
## and reports the tail - the 1% and 0.1% worst - alongside what each part
## of the frame cost. Only built when the game is started with --profile.

const SECTIONS := ["sim", "camera", "board", "hud"]

const SETTLE_SECONDS := 1.0
const SPIKE_MS := 33.0

var _frames := PackedFloat32Array()      # milliseconds, settled play frames
var _opening := PackedFloat32Array()     # the first second of each round
var _totals := {}                        # section -> summed milliseconds
var _worst := {}                         # section -> worst single frame
var _frame_sections := {}                # section -> this frame's cost
var _counted := 0
## Everything the engine does around our own code: input, rendering, the
## wait for the display. Measured as the gap between one frame's last mark
## and the next frame's first.
var _outside := 0.0
var _last_end := 0


func _init() -> void:
	for name: String in SECTIONS:
		_totals[name] = 0.0
		_worst[name] = 0.0
		_frame_sections[name] = 0.0


## Close one section and open the next. Returns the new clock reading, so a
## frame is one chain of marks with a single clock read between each.
## Opens a frame and measures the gap since the previous one closed.
func begin_frame() -> int:
	var now := Time.get_ticks_usec()
	_outside = (now - _last_end) / 1000.0 if _last_end > 0 else 0.0
	return now


func mark(section: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	_frame_sections[section] = (now - since) / 1000.0
	return now


## Frames spent outside a round say nothing about how the game plays, so
## only the playing ones are kept - and the first second of a round is kept
## apart, because building an arena is a one off cost that would otherwise
## masquerade as stutter in the middle of a game.
func end_frame(delta: float, playing: bool, play_time: float) -> void:
	if not playing:
		return
	if play_time < SETTLE_SECONDS:
		_opening.append(delta * 1000.0)
		return
	_last_end = Time.get_ticks_usec()
	_counted += 1
	_frames.append(delta * 1000.0)
	# A spike is worth a line of its own: the shape of a stutter is in when
	# it happens and what the frame was doing, not in the average.
	if delta * 1000.0 > SPIKE_MS:
		Journal.warn("profile", "spike %.1f ms at t=%.1fs  outside=%.1f sim=%.2f camera=%.2f board=%.2f hud=%.2f" % [
			delta * 1000.0, play_time, _outside,
			_frame_sections["sim"], _frame_sections["camera"],
			_frame_sections["board"], _frame_sections["hud"],
		])
	for name: String in SECTIONS:
		var cost: float = _frame_sections[name]
		_totals[name] = float(_totals[name]) + cost
		_worst[name] = maxf(float(_worst[name]), cost)


func report() -> void:
	if _counted < 30:
		Journal.warn("profile", "Not enough frames to report on (%d)" % _counted)
		return

	var sorted := _frames.duplicate()
	sorted.sort()
	var average := 0.0
	for value: float in sorted:
		average += value
	average /= sorted.size()

	Journal.info("profile", "-".repeat(70))
	Journal.info("profile", "frames played   : %d" % _counted)
	Journal.info("profile", "average         : %.2f ms  (%.1f fps)" % [average, 1000.0 / average])
	Journal.info("profile", "median          : %.2f ms" % _percentile(sorted, 0.50))
	Journal.info("profile", "95th percentile : %.2f ms" % _percentile(sorted, 0.95))
	Journal.info("profile", "99th percentile : %.2f ms  (the 1%% low)" % _percentile(sorted, 0.99))
	Journal.info("profile", "99.9th          : %.2f ms" % _percentile(sorted, 0.999))
	Journal.info("profile", "worst frame     : %.2f ms" % sorted[sorted.size() - 1])
	Journal.info("profile", "over 20 ms      : %d frames (%.2f%%)" % [
		_over(sorted, 20.0), 100.0 * _over(sorted, 20.0) / _counted
	])
	Journal.info("profile", "over 33 ms      : %d frames (%.2f%%)" % [
		_over(sorted, 33.0), 100.0 * _over(sorted, 33.0) / _counted
	])
	for name: String in SECTIONS:
		Journal.info("profile", "%-16s: %.3f ms average, %.2f ms worst" % [
			name, float(_totals[name]) / _counted, float(_worst[name]),
		])

	if not _opening.is_empty():
		var opening := _opening.duplicate()
		opening.sort()
		Journal.info("profile", "round openings  : %d frames, worst %.2f ms, %d over 33 ms" % [
			opening.size(), opening[opening.size() - 1], _over(opening, 33.0),
		])
	Journal.info("profile", "-".repeat(70))


func _percentile(sorted: PackedFloat32Array, share: float) -> float:
	var index := int(share * (sorted.size() - 1))
	return sorted[clampi(index, 0, sorted.size() - 1)]


func _over(sorted: PackedFloat32Array, limit: float) -> int:
	var count := 0
	for index in range(sorted.size() - 1, -1, -1):
		if sorted[index] <= limit:
			break
		count += 1
	return count
