extends Node
## DebugManager - Extensive debugging and logging system for Heroes of Tesia
## Feed console output back to AI for analysis and troubleshooting
##
## Usage:
##   Debug.log("Player", "Spawned at position", player.position)
##   Debug.warn("Combat", "Damage overflow", damage_value)
##   Debug.err("Save", "Failed to write file", error_code)
##   Debug.trace("Movement", "Velocity update")  # Shows stack trace
##   Debug.perf_start("loading")  # Start performance timer
##   Debug.perf_end("loading")    # End and print elapsed time
##   Debug.dump(player_stats)     # Pretty print dictionary/object

class_name DebugManager

## Log levels
enum LogLevel { TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, NONE = 5 }

## Configuration
var enabled: bool = true
var log_level: LogLevel = LogLevel.DEBUG
var show_timestamps: bool = true
var show_frame_count: bool = true
var show_stack_trace_on_error: bool = true
var max_history: int = 500

## Category filtering - empty means all categories enabled
var enabled_categories: Array[String] = []
var disabled_categories: Array[String] = []

## Performance timers
var _perf_timers: Dictionary = {}

## Log history for dumping
var _log_history: Array[Dictionary] = []

## Category colors for console (ANSI-like markers for readability)
var _category_markers: Dictionary = {
	"Player": "[PLR]",
	"Movement": "[MOV]",
	"Combat": "[CMB]",
	"Input": "[INP]",
	"Camera": "[CAM]",
	"UI": "[UI_]",
	"Save": "[SAV]",
	"Load": "[LOD]",
	"Audio": "[AUD]",
	"Animation": "[ANI]",
	"Physics": "[PHY]",
	"Network": "[NET]",
	"Quest": "[QST]",
	"Inventory": "[INV]",
	"System": "[SYS]",
	"Debug": "[DBG]",
}

## Level prefixes
var _level_prefixes: Dictionary = {
	LogLevel.TRACE: "TRACE",
	LogLevel.DEBUG: "DEBUG",
	LogLevel.INFO: " INFO",
	LogLevel.WARN: " WARN",
	LogLevel.ERROR: "ERROR",
}


func _ready() -> void:
	_log_internal(LogLevel.INFO, "System", "DebugManager initialized", [])
	_log_internal(LogLevel.INFO, "System", "Log level set to", [LogLevel.keys()[log_level]])


## Core logging functions
func trace(category: String, message: String, data: Variant = null) -> void:
	_log_internal(LogLevel.TRACE, category, message, _wrap_data(data), true)

func log(category: String, message: String, data: Variant = null) -> void:
	_log_internal(LogLevel.DEBUG, category, message, _wrap_data(data))

func info(category: String, message: String, data: Variant = null) -> void:
	_log_internal(LogLevel.INFO, category, message, _wrap_data(data))

func warn(category: String, message: String, data: Variant = null) -> void:
	_log_internal(LogLevel.WARN, category, message, _wrap_data(data))

func err(category: String, message: String, data: Variant = null) -> void:
	_log_internal(LogLevel.ERROR, category, message, _wrap_data(data), show_stack_trace_on_error)


## Pretty print any data structure
func dump(data: Variant, label: String = "DUMP") -> void:
	if not enabled:
		return
	var formatted := _format_value(data, 0)
	var output := "\n┌─── %s ───\n%s\n└───────────" % [label, formatted]
	print(output)
	_store_history(LogLevel.DEBUG, "Debug", label, [formatted])


## Performance timing
func perf_start(timer_name: String) -> void:
	_perf_timers[timer_name] = Time.get_ticks_usec()
	_log_internal(LogLevel.DEBUG, "Perf", "Timer started", [timer_name])

func perf_end(timer_name: String) -> float:
	if not _perf_timers.has(timer_name):
		_log_internal(LogLevel.WARN, "Perf", "Timer not found", [timer_name])
		return -1.0
	var elapsed_usec: int = Time.get_ticks_usec() - _perf_timers[timer_name]
	var elapsed_ms: float = elapsed_usec / 1000.0
	_perf_timers.erase(timer_name)
	_log_internal(LogLevel.INFO, "Perf", "Timer '%s' completed" % timer_name, ["%.3f ms" % elapsed_ms])
	return elapsed_ms

func perf_mark(timer_name: String, label: String = "") -> void:
	## Log intermediate time without stopping timer
	if not _perf_timers.has(timer_name):
		_log_internal(LogLevel.WARN, "Perf", "Timer not found for mark", [timer_name])
		return
	var elapsed_usec: int = Time.get_ticks_usec() - _perf_timers[timer_name]
	var elapsed_ms: float = elapsed_usec / 1000.0
	var mark_label := label if label else "mark"
	_log_internal(LogLevel.DEBUG, "Perf", "Timer '%s' [%s]" % [timer_name, mark_label], ["%.3f ms" % elapsed_ms])


## State snapshots - useful for debugging complex states
func snapshot(category: String, label: String, data: Dictionary) -> void:
	if not enabled or not _should_log(LogLevel.DEBUG, category):
		return
	var header := _build_header(LogLevel.DEBUG, category)
	var output := "%s SNAPSHOT: %s\n" % [header, label]
	output += "┌" + "─".repeat(40) + "\n"
	for key in data:
		var value_str := _format_value(data[key], 1)
		output += "│ %s: %s\n" % [str(key), value_str]
	output += "└" + "─".repeat(40)
	print(output)
	_store_history(LogLevel.DEBUG, category, "SNAPSHOT: " + label, [data])


## Assert with logging
func assert_true(condition: bool, category: String, message: String) -> bool:
	if not condition:
		_log_internal(LogLevel.ERROR, category, "ASSERTION FAILED: " + message, [], true)
	return condition

func assert_not_null(value: Variant, category: String, name: String) -> bool:
	if value == null:
		_log_internal(LogLevel.ERROR, category, "ASSERTION FAILED: %s is null" % name, [], true)
		return false
	return true


## Dump log history (for crash reports or periodic saves)
func get_history_dump() -> String:
	var output := "=== DEBUG LOG HISTORY ===\n"
	output += "Entries: %d\n" % _log_history.size()
	output += "=" .repeat(50) + "\n\n"
	for entry in _log_history:
		output += "[%s] %s | %s | %s" % [
			entry.get("timestamp", "?"),
			entry.get("level", "?"),
			entry.get("category", "?"),
			entry.get("message", "?")
		]
		if entry.has("data") and entry.data.size() > 0:
			output += " | Data: %s" % str(entry.data)
		output += "\n"
	output += "\n=== END LOG HISTORY ==="
	return output

func print_history() -> void:
	print(get_history_dump())

func clear_history() -> void:
	_log_history.clear()
	info("Debug", "Log history cleared")


## Export for AI analysis - formatted for easy copy-paste
func export_for_ai(last_n: int = 50) -> String:
	var output := "```\n"
	output += "=== HEROES OF TESIA DEBUG EXPORT ===\n"
	output += "Timestamp: %s\n" % Time.get_datetime_string_from_system()
	output += "Frame: %d\n" % Engine.get_process_frames()
	output += "FPS: %.1f\n" % Engine.get_frames_per_second()
	output += "=" .repeat(40) + "\n\n"

	var start_idx: int = maxi(0, _log_history.size() - last_n)
	for i in range(start_idx, _log_history.size()):
		var entry: Dictionary = _log_history[i]
		output += "%s [%s] %s: %s" % [
			entry.get("timestamp", ""),
			entry.get("level", ""),
			entry.get("category", ""),
			entry.get("message", "")
		]
		if entry.has("data") and entry.data.size() > 0:
			for d in entry.data:
				output += " | %s" % str(d)
		output += "\n"

	output += "\n=== END EXPORT ===\n```"
	return output

func print_export(last_n: int = 50) -> void:
	print(export_for_ai(last_n))


## Category management
func enable_category(category: String) -> void:
	if category in disabled_categories:
		disabled_categories.erase(category)
	if category not in enabled_categories:
		enabled_categories.append(category)

func disable_category(category: String) -> void:
	if category in enabled_categories:
		enabled_categories.erase(category)
	if category not in disabled_categories:
		disabled_categories.append(category)

func enable_all_categories() -> void:
	enabled_categories.clear()
	disabled_categories.clear()

func set_level(level: LogLevel) -> void:
	log_level = level
	info("Debug", "Log level changed to", LogLevel.keys()[level])


## Internal implementation
func _log_internal(level: LogLevel, category: String, message: String, data: Array, include_trace: bool = false) -> void:
	if not enabled:
		return
	if not _should_log(level, category):
		return

	var header := _build_header(level, category)
	var output := "%s %s" % [header, message]

	# Append data
	if data.size() > 0:
		var data_strs: Array[String] = []
		for d in data:
			data_strs.append(_format_value_inline(d))
		output += " | " + " | ".join(data_strs)

	# Print main message
	if level == LogLevel.ERROR:
		push_error(output)
	elif level == LogLevel.WARN:
		push_warning(output)
	else:
		print(output)

	# Stack trace
	if include_trace:
		var stack := get_stack()
		if stack.size() > 2:  # Skip internal debug calls
			print("    Stack trace:")
			for i in range(2, min(stack.size(), 8)):
				var frame: Dictionary = stack[i]
				print("      → %s:%d in %s()" % [frame.source, frame.line, frame.function])

	# Store in history
	_store_history(level, category, message, data)


func _should_log(level: LogLevel, category: String) -> bool:
	if level < log_level:
		return false
	if enabled_categories.size() > 0 and category not in enabled_categories:
		return false
	if category in disabled_categories:
		return false
	return true


func _build_header(level: LogLevel, category: String) -> String:
	var parts: Array[String] = []

	if show_timestamps:
		var time := Time.get_time_dict_from_system()
		parts.append("[%02d:%02d:%02d]" % [time.hour, time.minute, time.second])

	if show_frame_count:
		parts.append("F%d" % Engine.get_process_frames())

	parts.append(_level_prefixes.get(level, "?????"))
	parts.append(_category_markers.get(category, "[%s]" % category.left(3).to_upper()))

	return " ".join(parts)


func _store_history(level: LogLevel, category: String, message: String, data: Array) -> void:
	var time := Time.get_time_dict_from_system()
	var entry := {
		"timestamp": "%02d:%02d:%02d" % [time.hour, time.minute, time.second],
		"frame": Engine.get_process_frames(),
		"level": _level_prefixes.get(level, "?").strip_edges(),
		"category": category,
		"message": message,
		"data": data.duplicate()
	}
	_log_history.append(entry)
	if _log_history.size() > max_history:
		_log_history.pop_front()


func _wrap_data(data: Variant) -> Array:
	if data == null:
		return []
	if data is Array:
		return data
	return [data]


func _format_value_inline(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Vector2:
		return "(%.2f, %.2f)" % [value.x, value.y]
	if value is Vector3:
		return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]
	if value is float:
		return "%.3f" % value
	if value is Dictionary:
		return "{%d keys}" % value.size()
	if value is Array:
		return "[%d items]" % value.size()
	return str(value)


func _format_value(value: Variant, indent: int) -> String:
	var indent_str := "│ ".repeat(indent)

	if value == null:
		return "null"

	if value is Dictionary:
		if value.is_empty():
			return "{}"
		var lines: Array[String] = ["{"]
		for key in value:
			var val_str := _format_value(value[key], indent + 1)
			lines.append("%s  %s: %s" % [indent_str, str(key), val_str])
		lines.append("%s}" % indent_str)
		return "\n".join(lines)

	if value is Array:
		if value.is_empty():
			return "[]"
		var lines: Array[String] = ["["]
		for i in range(value.size()):
			var val_str := _format_value(value[i], indent + 1)
			lines.append("%s  [%d] %s" % [indent_str, i, val_str])
		lines.append("%s]" % indent_str)
		return "\n".join(lines)

	if value is Vector2:
		return "Vector2(%.3f, %.3f)" % [value.x, value.y]

	if value is Vector3:
		return "Vector3(%.3f, %.3f, %.3f)" % [value.x, value.y, value.z]

	if value is float:
		return "%.4f" % value

	if value is Object:
		if value.has_method("get_class"):
			return "<%s>" % value.get_class()
		return "<Object>"

	return str(value)
