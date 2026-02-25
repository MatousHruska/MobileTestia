class_name AbilityVisualPlayer
extends Node
## AbilityVisualPlayer - Orchestrates playback of AbilityVisualData sequences.
##
## Attached as a child of any character (player or enemy). Reads an
## AbilityVisualData, steps through its phases using timers and animation
## signals, and emits signals at key moments (damage frame, projectile spawn,
## etc.). The character's existing combat code listens to these signals
## instead of managing timing itself.

#===============================================================================
# SIGNALS
#===============================================================================

## Emitted when the full sequence starts
signal sequence_started(template_id: String)

## Emitted when the full sequence finishes (all phases done)
signal sequence_finished(template_id: String)

## Emitted on DAMAGE_EVENT phase - the combat system listens to this
signal damage_event()

## Emitted on SPAWN_PROJECTILE phase - combat system spawns projectile
signal spawn_projectile_event(context: Dictionary)

## Emitted on EFFECT phase - VFX system spawns effect
signal effect_event(effect_id: String)

## Emitted on WEAPON_VISIBILITY phase
signal weapon_visibility_changed(visible: bool)

## Emitted when any body animation phase starts (for the sprite system)
signal play_body_animation(anim_name: String)

## Emitted on MOVEMENT phase (for the character controller to execute)
signal movement_requested(direction: String, distance: float, duration: float)

## Emitted when a frame with echo data is reached (for speed echo rendering)
signal echo_requested(frame_index: int, echo_config: Dictionary)

#===============================================================================
# STATE
#===============================================================================

## Whether a sequence is currently playing
var is_playing: bool = false

## Current sequence being played
var _current_data: AbilityVisualData = null

## Current phase index (the latest phase that was started)
var _current_phase_index: int = -1

## Reference to the character's AnimatedSprite2D (set via initialize())
var _sprite: AnimatedSprite2D = null

## Target position for "toward_target" / "away_from_target" movement
var _target_position: Vector2 = Vector2.ZERO

## Character's facing direction string ("down", "up", "right")
## Updated by the character before or during play()
var facing_direction: String = "down"

## Hold system - for phases that pause until externally released (e.g., aim)
var _phase_held: bool = false

#===============================================================================
# CONCURRENCY TRACKING
#===============================================================================
## When a phase has concurrent=true, both it and the next phase execute at the
## same time. We track two "slots" — primary and concurrent. The sequence
## advances past the concurrent block only when BOTH slots have resolved.

## Primary slot timer (the phase that had concurrent=true)
var _primary_timer: float = 0.0
var _primary_waiting_for_anim: bool = false
var _primary_resolved: bool = true

## Concurrent slot timer (the next phase that runs alongside primary)
var _concurrent_timer: float = 0.0
var _concurrent_waiting_for_anim: bool = false
var _concurrent_resolved: bool = true

## Whether we're in a concurrent block (two phases running simultaneously)
var _in_concurrent_block: bool = false

## The phase index of the concurrent partner (to know where to advance after)
var _concurrent_end_index: int = -1

## Per-frame timing state (for data-driven compositions from Attack Composer)
var _frame_timing_active: bool = false
var _frame_timing_array: Array = []  # Array of duration_ms ints
var _frame_timing_index: int = 0
var _frame_timing_timer: float = 0.0
var _frame_timing_start_index: int = 0
var _frame_timing_phase: AbilityVisualPhase = null


#===============================================================================
# INITIALIZATION
#===============================================================================

## Call once to wire up the sprite reference
func initialize(sprite: AnimatedSprite2D) -> void:
	_sprite = sprite
	if _sprite and not _sprite.animation_finished.is_connected(_on_animation_finished):
		_sprite.animation_finished.connect(_on_animation_finished)


#===============================================================================
# PLAYBACK CONTROL
#===============================================================================

## Start playing a visual sequence. Optionally provide a target position
## for directional movement phases, and an overrides dictionary to patch
## phase durations/distances.
##
## Override keys:
##   "windup_duration" - replaces duration of phases with override_key "windup"
##   "lunge_distance"  - replaces move_distance of phases with override_key "lunge"
##   "lunge_duration"  - replaces duration of phases with override_key "lunge"
##   "recovery_duration" - replaces duration of phases with override_key "recovery"
##   "cast_duration"   - replaces duration of phases with override_key "cast"
##   "charge_duration" - replaces duration of phases with override_key "charge"
##   "dash_duration"   - replaces duration of phases with override_key "dash"
##   "dash_distance"   - replaces move_distance of phases with override_key "dash"
func play(data: AbilityVisualData, target_pos: Vector2 = Vector2.ZERO, overrides: Dictionary = {}) -> void:
	if is_playing:
		cancel()

	_current_data = _apply_overrides(data, overrides)
	_target_position = target_pos
	_current_phase_index = -1
	_phase_held = false
	_reset_timers()
	is_playing = true
	sequence_started.emit(data.template_id)
	_advance_to_next_phase()


## Stop/cancel the current sequence immediately
func cancel() -> void:
	if not is_playing:
		return
	var template_id := _current_data.template_id if _current_data else ""
	_reset_timers()
	_frame_timing_active = false
	_frame_timing_phase = null
	if _sprite:
		_sprite.speed_scale = 1.0
	is_playing = false
	_current_data = null
	_current_phase_index = -1
	_phase_held = false
	_in_concurrent_block = false
	sequence_finished.emit(template_id)


## Hold the current phase until release_held_phase() is called.
## Used for charge/aim abilities where the player holds a button.
func hold_current_phase() -> void:
	_phase_held = true


## Release a held phase, allowing the sequence to advance.
func release_held_phase() -> void:
	if not _phase_held:
		return
	_phase_held = false
	# If timers are already done, advance immediately
	if _in_concurrent_block:
		if _primary_resolved and _concurrent_resolved:
			_advance_past_concurrent_block()
	else:
		if _primary_timer <= 0.0 and not _primary_waiting_for_anim:
			_advance_to_next_phase()


#===============================================================================
# PROCESS
#===============================================================================

func _process(delta: float) -> void:
	if not is_playing:
		return

	if _phase_held:
		return

	# Tick per-frame timing if active
	if _frame_timing_active:
		_tick_frame_timing(delta)

	if _in_concurrent_block:
		_tick_concurrent_block(delta)
	else:
		_tick_single_phase(delta)


func _tick_frame_timing(delta: float) -> void:
	_frame_timing_timer -= delta
	if _frame_timing_timer <= 0.0:
		_frame_timing_index += 1
		if _frame_timing_index >= _frame_timing_array.size():
			# All frames played — stop frame timing, let phase timer resolve
			_frame_timing_active = false
			_frame_timing_phase = null
			if _sprite:
				_sprite.speed_scale = 1.0
		else:
			_frame_timing_timer += _frame_timing_array[_frame_timing_index] / 1000.0
			if _sprite:
				_sprite.frame = _frame_timing_start_index + _frame_timing_index
			_check_echo_for_current_frame()


func _check_echo_for_current_frame() -> void:
	if _frame_timing_phase == null:
		return
	var echo_data: Array = _frame_timing_phase.context_data.get("echo_data", [])
	var current_frame := _frame_timing_start_index + _frame_timing_index
	for echo_config in echo_data:
		if echo_config.get("frame_index", -1) == current_frame:
			echo_requested.emit(current_frame, echo_config)


func _tick_single_phase(delta: float) -> void:
	if _primary_timer > 0.0:
		_primary_timer -= delta
		if _primary_timer <= 0.0:
			_primary_timer = 0.0
			_advance_to_next_phase()


func _tick_concurrent_block(delta: float) -> void:
	if not _primary_resolved and _primary_timer > 0.0:
		_primary_timer -= delta
		if _primary_timer <= 0.0:
			_primary_timer = 0.0
			_primary_resolved = true

	if not _concurrent_resolved and _concurrent_timer > 0.0:
		_concurrent_timer -= delta
		if _concurrent_timer <= 0.0:
			_concurrent_timer = 0.0
			_concurrent_resolved = true

	if _primary_resolved and _concurrent_resolved:
		_advance_past_concurrent_block()


#===============================================================================
# PHASE ADVANCEMENT
#===============================================================================

func _advance_to_next_phase() -> void:
	_current_phase_index += 1

	if not _current_data or _current_phase_index >= _current_data.phases.size():
		_finish_sequence()
		return

	var phase: AbilityVisualPhase = _current_data.phases[_current_phase_index]

	# Check for concurrent block: this phase + the next one run simultaneously
	if phase.concurrent and _current_phase_index + 1 < _current_data.phases.size():
		var next_phase: AbilityVisualPhase = _current_data.phases[_current_phase_index + 1]
		_start_concurrent_block(phase, next_phase)
	else:
		_execute_phase_single(phase)


func _start_concurrent_block(primary_phase: AbilityVisualPhase, concurrent_phase: AbilityVisualPhase) -> void:
	_in_concurrent_block = true
	_concurrent_end_index = _current_phase_index + 1
	_primary_resolved = false
	_concurrent_resolved = false
	_primary_timer = 0.0
	_concurrent_timer = 0.0
	_primary_waiting_for_anim = false
	_concurrent_waiting_for_anim = false

	# Execute primary phase (the one with concurrent=true)
	_execute_phase_in_slot(primary_phase, true)

	# Execute concurrent phase (the next one)
	_execute_phase_in_slot(concurrent_phase, false)


func _execute_phase_in_slot(phase: AbilityVisualPhase, is_primary: bool) -> void:
	## Execute a phase into either the primary or concurrent slot.
	match phase.type:
		AbilityVisualPhase.PhaseType.BODY_ANIM:
			var resolved_name := _resolve_animation_name(phase.anim_name, facing_direction)
			play_body_animation.emit(resolved_name)
			if phase.duration > 0.0:
				if is_primary:
					_primary_timer = phase.duration
				else:
					_concurrent_timer = phase.duration
			elif _is_looping_animation(resolved_name):
				# Looping animations never emit animation_finished — resolve immediately
				if is_primary:
					_primary_resolved = true
				else:
					_concurrent_resolved = true
			else:
				# Wait for animation to finish
				if is_primary:
					_primary_waiting_for_anim = true
				else:
					_concurrent_waiting_for_anim = true

		AbilityVisualPhase.PhaseType.MOVEMENT:
			movement_requested.emit(phase.move_direction, phase.move_distance, phase.duration)
			if phase.duration > 0.0:
				if is_primary:
					_primary_timer = phase.duration
				else:
					_concurrent_timer = phase.duration
			else:
				# Instant movement
				if is_primary:
					_primary_resolved = true
				else:
					_concurrent_resolved = true

		AbilityVisualPhase.PhaseType.DAMAGE_EVENT:
			damage_event.emit()
			if is_primary:
				_primary_resolved = true
			else:
				_concurrent_resolved = true

		AbilityVisualPhase.PhaseType.SPAWN_PROJECTILE:
			spawn_projectile_event.emit(phase.context_data)
			if is_primary:
				_primary_resolved = true
			else:
				_concurrent_resolved = true

		AbilityVisualPhase.PhaseType.WEAPON_VISIBILITY:
			weapon_visibility_changed.emit(phase.weapon_visible)
			if is_primary:
				_primary_resolved = true
			else:
				_concurrent_resolved = true

		AbilityVisualPhase.PhaseType.EFFECT:
			effect_event.emit(phase.effect_id)
			if phase.duration > 0.0:
				if is_primary:
					_primary_timer = phase.duration
				else:
					_concurrent_timer = phase.duration
			else:
				if is_primary:
					_primary_resolved = true
				else:
					_concurrent_resolved = true

		AbilityVisualPhase.PhaseType.WAIT:
			if phase.duration > 0.0:
				if is_primary:
					_primary_timer = phase.duration
				else:
					_concurrent_timer = phase.duration
			else:
				if is_primary:
					_primary_resolved = true
				else:
					_concurrent_resolved = true


func _advance_past_concurrent_block() -> void:
	_in_concurrent_block = false
	# Jump past the concurrent partner
	_current_phase_index = _concurrent_end_index
	_advance_to_next_phase()


#===============================================================================
# SINGLE-PHASE EXECUTION (non-concurrent path)
#===============================================================================

func _execute_phase_single(phase: AbilityVisualPhase) -> void:
	match phase.type:
		AbilityVisualPhase.PhaseType.BODY_ANIM:
			var resolved_name := _resolve_animation_name(phase.anim_name, facing_direction)
			play_body_animation.emit(resolved_name)
			if phase.context_data.has("frame_timings"):
				# Data-driven per-frame timing from Attack Composer
				_frame_timing_active = true
				_frame_timing_array = phase.context_data["frame_timings"]
				_frame_timing_index = 0
				_frame_timing_start_index = phase.context_data.get("frame_start_index", 0)
				_frame_timing_phase = phase
				_frame_timing_timer = _frame_timing_array[0] / 1000.0
				_primary_timer = phase.duration
				_primary_waiting_for_anim = false
				# Pause the sprite's auto-playback and set initial frame
				if _sprite:
					_sprite.speed_scale = 0.0
					_sprite.frame = _frame_timing_start_index
				# Check for echo on first frame
				_check_echo_for_current_frame()
			elif phase.duration > 0.0:
				_primary_timer = phase.duration
				_primary_waiting_for_anim = false
			elif _is_looping_animation(resolved_name):
				# Looping animations never emit animation_finished — advance immediately
				_advance_to_next_phase()
			else:
				# duration=0 on BODY_ANIM means "wait for animation to finish"
				_primary_waiting_for_anim = true

		AbilityVisualPhase.PhaseType.MOVEMENT:
			movement_requested.emit(phase.move_direction, phase.move_distance, phase.duration)
			if phase.duration > 0.0:
				_primary_timer = phase.duration
			else:
				_advance_to_next_phase()

		AbilityVisualPhase.PhaseType.DAMAGE_EVENT:
			damage_event.emit()
			_advance_to_next_phase()

		AbilityVisualPhase.PhaseType.SPAWN_PROJECTILE:
			spawn_projectile_event.emit(phase.context_data)
			_advance_to_next_phase()

		AbilityVisualPhase.PhaseType.WEAPON_VISIBILITY:
			weapon_visibility_changed.emit(phase.weapon_visible)
			_advance_to_next_phase()

		AbilityVisualPhase.PhaseType.EFFECT:
			effect_event.emit(phase.effect_id)
			if phase.duration > 0.0:
				_primary_timer = phase.duration
			else:
				_advance_to_next_phase()

		AbilityVisualPhase.PhaseType.WAIT:
			if phase.duration > 0.0:
				_primary_timer = phase.duration
			else:
				_advance_to_next_phase()


#===============================================================================
# ANIMATION FINISHED CALLBACK
#===============================================================================

func _on_animation_finished() -> void:
	if not is_playing:
		return

	if _in_concurrent_block:
		# Resolve whichever slot was waiting for anim
		if _primary_waiting_for_anim:
			_primary_waiting_for_anim = false
			_primary_resolved = true
		if _concurrent_waiting_for_anim:
			_concurrent_waiting_for_anim = false
			_concurrent_resolved = true
		# Check if both are done
		if _primary_resolved and _concurrent_resolved and not _phase_held:
			_advance_past_concurrent_block()
	else:
		if _primary_waiting_for_anim:
			_primary_waiting_for_anim = false
			if not _phase_held:
				_advance_to_next_phase()


#===============================================================================
# SEQUENCE FINISH
#===============================================================================

func _finish_sequence() -> void:
	var template_id := _current_data.template_id if _current_data else ""
	_frame_timing_active = false
	_frame_timing_phase = null
	if _sprite:
		_sprite.speed_scale = 1.0
	is_playing = false
	_current_data = null
	_current_phase_index = -1
	_phase_held = false
	_in_concurrent_block = false
	_reset_timers()
	sequence_finished.emit(template_id)


#===============================================================================
# ANIMATION NAME FALLBACK
#===============================================================================

## Resolve an animation name with fallback chain.
## Delegates to AnimationUtils for the canonical implementation.
func _resolve_animation_name(base_name: String, direction: String) -> String:
	var frames: SpriteFrames = _sprite.sprite_frames if _sprite else null
	return AnimationUtils.resolve_animation_name(frames, base_name, direction)


#===============================================================================
# OVERRIDE APPLICATION
#===============================================================================

## Deep-copy the AbilityVisualData and patch phases based on overrides dictionary.
## This avoids mutating the shared template resource.
func _apply_overrides(data: AbilityVisualData, overrides: Dictionary) -> AbilityVisualData:
	if overrides.is_empty():
		return data

	var patched := AbilityVisualData.new()
	patched.template_id = data.template_id
	patched.display_name = data.display_name
	patched.locks_movement = data.locks_movement

	for original_phase in data.phases:
		var phase := _duplicate_phase(original_phase)

		if phase.override_key.is_empty():
			patched.phases.append(phase)
			continue

		# Apply duration overrides
		var dur_key := "%s_duration" % phase.override_key
		if overrides.has(dur_key):
			phase.duration = float(overrides[dur_key])

		# Apply distance overrides (for MOVEMENT phases)
		var dist_key := "%s_distance" % phase.override_key
		if overrides.has(dist_key):
			phase.move_distance = float(overrides[dist_key])

		patched.phases.append(phase)

	# Handle hit_effect_id override: replace effect_id on EFFECT phases with override_key "hit"
	var hit_effect_id: String = overrides.get("hit_effect_id", "")
	if not hit_effect_id.is_empty():
		for phase in patched.phases:
			if phase.type == AbilityVisualPhase.PhaseType.EFFECT and phase.override_key == "hit":
				phase.effect_id = hit_effect_id

	# Handle show_weapon override: flip the first WEAPON_VISIBILITY(false) to true,
	# and insert a WEAPON_VISIBILITY(false) before the final idle phase so the
	# weapon hides after the spell finishes.
	if overrides.get("show_weapon", false):
		var flipped := false
		for i in patched.phases.size():
			var phase: AbilityVisualPhase = patched.phases[i]
			if phase.type == AbilityVisualPhase.PhaseType.WEAPON_VISIBILITY and not phase.weapon_visible:
				phase.weapon_visible = true
				flipped = true
				break
		# Insert a hide-weapon phase before the final idle phase
		if flipped and patched.phases.size() >= 2:
			var last_phase: AbilityVisualPhase = patched.phases[patched.phases.size() - 1]
			if last_phase.type == AbilityVisualPhase.PhaseType.BODY_ANIM and last_phase.anim_name == "idle":
				var hide_phase := AbilityVisualPhase.create_weapon_visibility(false)
				patched.phases.insert(patched.phases.size() - 1, hide_phase)

	return patched


func _duplicate_phase(original: AbilityVisualPhase) -> AbilityVisualPhase:
	var phase := AbilityVisualPhase.new()
	phase.type = original.type
	phase.duration = original.duration
	phase.anim_name = original.anim_name
	phase.move_direction = original.move_direction
	phase.move_distance = original.move_distance
	phase.weapon_visible = original.weapon_visible
	phase.effect_id = original.effect_id
	phase.concurrent = original.concurrent
	phase.override_key = original.override_key
	phase.context_data = original.context_data.duplicate()
	return phase


#===============================================================================
# HELPERS
#===============================================================================

func _is_looping_animation(anim_name: String) -> bool:
	## Check if the given animation is set to loop in the sprite's SpriteFrames.
	## Looping animations never emit animation_finished, so the sequencer must
	## not wait for them — it should advance immediately instead.
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(anim_name):
		return _sprite.sprite_frames.get_animation_loop(anim_name)
	return false


func _reset_timers() -> void:
	_primary_timer = 0.0
	_primary_waiting_for_anim = false
	_primary_resolved = true
	_concurrent_timer = 0.0
	_concurrent_waiting_for_anim = false
	_concurrent_resolved = true
