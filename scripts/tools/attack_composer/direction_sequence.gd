class_name DirectionSequence
extends Resource
## Holds per-direction frame timeline and sequence-level properties.
## Each direction (down, up, right) gets its own DirectionSequence.

## Per-frame timeline data for this direction
@export var frames: Array[CompositionFrame] = []

## Movement type: "lunge", "dash", or "" (no movement)
@export var movement_type: String = ""

## Movement distance in pixels
@export var movement_distance: float = 20.0

## Frame index where movement starts (-1 = no movement)
@export var movement_start_frame: int = -1

## Frame index where movement ends (-1 = no movement)
@export var movement_end_frame: int = -1

## Frame index that triggers the damage event (-1 = no damage)
@export var damage_frame: int = -1


## Helper: total duration of all frames in milliseconds
func get_total_duration_ms() -> int:
	var total := 0
	for frame in frames:
		total += frame.duration_ms
	return total


## Helper: total duration in seconds
func get_total_duration_sec() -> float:
	return get_total_duration_ms() / 1000.0


## Factory: create a default sequence with N frames at the given FPS
static func create_default(frame_count: int, fps: float = 15.0) -> DirectionSequence:
	var seq := DirectionSequence.new()
	var ms_per_frame := int(1000.0 / fps)
	for i in frame_count:
		var frame := CompositionFrame.new()
		frame.duration_ms = ms_per_frame
		seq.frames.append(frame)
	return seq
