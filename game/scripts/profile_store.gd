extends Node

## Autoload "PlayerProfile": the best score and the display preferences.
##
## A missing or corrupted file must never prevent the game from starting, so
## every failure degrades to the defaults.

const PATH := "user://savegame.json"

const DEFAULTS := {
	"high_score": 0,
	"best_length": 0.0,
	"games_played": 0,
	"view": "3d",
	"camera": "follow",
	"address": "127.0.0.1",
	"quality": "smooth",
	"vsync": true,
	"fps_limit": 0,
	"debug": false,
}

var data: Dictionary = DEFAULTS.duplicate()

## The self-test writes to its own file so it never inflates the player stats.
var path := PATH


func _ready() -> void:
	load_profile()


func use_path(new_path: String) -> void:
	path = new_path
	data = DEFAULTS.duplicate()
	Journal.info("profile", "Using profile file %s" % path)
	load_profile()


func load_profile() -> void:
	if not FileAccess.file_exists(path):
		Journal.info("profile", "No profile yet, starting fresh (%s)" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		Journal.warn("profile", "Cannot read %s (error %d)" % [path, FileAccess.get_open_error()])
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		Journal.warn("profile", "Unreadable profile %s, falling back to defaults" % path)
		return

	for key: String in DEFAULTS:
		if not parsed.has(key):
			continue
		var value: Variant = parsed[key]
		# JSON gives every number back as a float, so an int field must accept
		# both rather than silently keep its default.
		match typeof(DEFAULTS[key]):
			TYPE_INT:
				if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
					data[key] = int(value)
			TYPE_STRING:
				if typeof(value) == TYPE_STRING:
					data[key] = str(value)
			_:
				data[key] = value
	Journal.info("profile", "Profile loaded: high_score=%d games=%d view=%s camera=%s" % [
		high_score(), games_played(), data["view"], data["camera"],
	])


func save() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		Journal.warn("profile", "Cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()


func high_score() -> int:
	return int(data["high_score"])


func games_played() -> int:
	return int(data["games_played"])


func get_preference(key: String) -> Variant:
	return data.get(key, DEFAULTS.get(key))


func set_preference(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		Journal.warn("profile", "Unknown preference %s" % key)
		return
	if data[key] == value:
		return
	data[key] = value
	Journal.info("profile", "Preference %s = %s" % [key, value])
	save()


## Register a finished game. Returns true on a new record.
## The longest snake ever grown, which is what the game is played for.
func best_length() -> float:
	return float(data["best_length"])


## Remember a length if it beats the record. Returns true when it does.
func record_length(length: float) -> bool:
	if length <= best_length() + 0.01:
		return false
	Journal.info("profile", "New best length: %.1f (was %.1f)" % [length, best_length()])
	data["best_length"] = length
	save()
	return true


## One more round played, whatever came of it.
func finish_round() -> void:
	data["games_played"] = games_played() + 1
	save()
