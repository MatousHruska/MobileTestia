class_name AttackCompositionData
extends Resource
## The editor's native format for attack animation compositions.
## Stores a per-frame timeline with timing, weapon, effects, echoes, and movement.
## A converter generates AbilityVisualData from this for runtime playback.

## Unique composition ID (matches the template ID, e.g., "melee_single")
@export var composition_id: String = ""

## Human-readable name for display in the editor
@export var display_name: String = ""

## Base animation name in SpriteFrames (e.g., "attack")
## Direction suffix (_down, _up, _right) added at runtime.
@export var animation_name: String = "attack"

## Whether the character is movement-locked during the entire sequence
@export var locks_movement: bool = true

## Per-frame timeline data — the core of the composition
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


## Helper: total duration of all frames in seconds
func get_total_duration_sec() -> float:
	var total_ms := 0
	for frame in frames:
		total_ms += frame.duration_ms
	return total_ms / 1000.0


## Helper: create a default composition with N frames at the given FPS
static func create_default(frame_count: int, fps: float = 15.0) -> AttackCompositionData:
	var data := AttackCompositionData.new()
	var ms_per_frame := int(1000.0 / fps)
	for i in frame_count:
		var frame := CompositionFrame.new()
		frame.duration_ms = ms_per_frame
		data.frames.append(frame)
	return data
