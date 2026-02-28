class_name AttackCompositionData
extends Resource
## The editor's native format for attack animation compositions.
## Stores per-direction sequences with timing, weapon, effects, echoes, and movement.
## A converter generates AbilityVisualData from this for runtime playback.

const DIRECTIONS: Array[String] = ["down", "up", "right"]

## Unique composition ID (matches the template ID, e.g., "melee_single")
@export var composition_id: String = ""

## Human-readable name for display in the editor
@export var display_name: String = ""

## Runtime template ID for ability visual lookup.
## If empty, composition_id is used as the runtime filename.
@export var runtime_template_id: String = ""

## Base animation name in SpriteFrames (e.g., "attack")
## Direction suffix (_down, _up, _right) added at runtime.
@export var animation_name: String = "attack"

## Whether the character is movement-locked during the entire sequence
@export var locks_movement: bool = true

## Per-direction sequence data — the core of the composition.
## Keys: "down", "up", "right" → DirectionSequence resources.
@export var direction_sequences: Dictionary = {}

# ── Legacy fields (kept for migration from old .tres files) ──────────
@export var frames: Array[CompositionFrame] = []
@export var movement_type: String = ""
@export var movement_distance: float = 20.0
@export var movement_start_frame: int = -1
@export var movement_end_frame: int = -1
@export var damage_frame: int = -1


## Get the DirectionSequence for a specific direction. Returns null if missing.
func get_sequence(direction: String) -> DirectionSequence:
	if direction_sequences.has(direction):
		return direction_sequences[direction] as DirectionSequence
	return null


## Ensure all 3 directions have sequences (creates empty ones if missing).
func ensure_all_directions() -> void:
	for dir_name in DIRECTIONS:
		if not direction_sequences.has(dir_name):
			direction_sequences[dir_name] = DirectionSequence.new()


## Migrate from legacy flat format (old .tres files).
## Copies the shared frames array into all 3 directions.
func migrate_from_legacy() -> void:
	if direction_sequences.is_empty() and not frames.is_empty():
		for dir_name in DIRECTIONS:
			var seq := DirectionSequence.new()
			seq.movement_type = movement_type
			seq.movement_distance = movement_distance
			seq.movement_start_frame = movement_start_frame
			seq.movement_end_frame = movement_end_frame
			seq.damage_frame = damage_frame
			for frame in frames:
				seq.frames.append(frame.duplicate())
			direction_sequences[dir_name] = seq
		# Clear legacy fields after migration
		frames.clear()


## Helper: total duration of a specific direction in seconds
func get_total_duration_sec(direction: String = "down") -> float:
	var seq := get_sequence(direction)
	if seq:
		return seq.get_total_duration_sec()
	return 0.0


## Helper: create a default composition with N frames at the given FPS
static func create_default(frame_count: int, fps: float = 15.0) -> AttackCompositionData:
	var data := AttackCompositionData.new()
	for dir_name in DIRECTIONS:
		data.direction_sequences[dir_name] = DirectionSequence.create_default(frame_count, fps)
	return data
