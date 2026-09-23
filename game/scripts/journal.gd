extends Node

## Autoload "Journal": structured logging.
##
## Everything printed here is captured by the engine file logging enabled in
## project.godot, so an exported build without a console still leaves a full
## trace in user://logs/snake.log - the only way to diagnose a run afterwards.

enum Level { DEBUG, INFO, WARN, ERROR }

var min_level: Level = Level.INFO


func _ready() -> void:
	if OS.is_debug_build():
		min_level = Level.DEBUG


func banner(source: String = "startup") -> void:
	var version := Engine.get_version_info()
	info(source, "=".repeat(70))
	info(source, "Snake 3D starting")
	info(source, "godot    : %s" % version.string)
	info(source, "os       : %s %s" % [OS.get_name(), OS.get_version()])
	info(source, "renderer : %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	info(source, "user dir : %s" % OS.get_user_data_dir())
	info(source, "cmdline  : %s" % " ".join(OS.get_cmdline_args()))
	info(source, "user args: %s" % " ".join(OS.get_cmdline_user_args()))


func debug(source: String, message: String) -> void:
	_write(Level.DEBUG, source, message)


func info(source: String, message: String) -> void:
	_write(Level.INFO, source, message)


func warn(source: String, message: String) -> void:
	_write(Level.WARN, source, message)


func error(source: String, message: String) -> void:
	_write(Level.ERROR, source, message)
	push_error("%s: %s" % [source, message])


func _write(level: Level, source: String, message: String) -> void:
	if level < min_level:
		return
	print("%s | %-5s | %-10s | %s" % [
		Time.get_datetime_string_from_system(false, true),
		Level.keys()[level],
		source,
		message,
	])
