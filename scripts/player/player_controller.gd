extends CharacterBody2D
class_name PlayerController
## PlayerController - Main player character controller
## Handles movement, facing direction, and coordinates with animator

## Signals
signal facing_changed(facing: Facing)
signal attack_started
signal attack_ended
signal dodge_started
signal dodge_ended
signal cast_started(skill_id: String, duration: float)
signal cast_progress(progress: float)  ## 0.0 to 1.0
signal cast_completed(skill_id: String)
signal cast_interrupted(skill_id: String, reason: String)
signal stance_activated(talent_id: String)
signal stance_deactivated(talent_id: String)

## Facing directions (4-cardinal for animations)
enum Facing { DOWN = 0, UP = 1, LEFT = 2, RIGHT = 3 }

## Movement settings
@export_group("Movement")
@export var move_speed: float = 150.0  ## Base run speed (pixels/sec)
@export var walk_speed_ratio: float = 0.4  ## Walk speed as fraction of run speed
@export var joystick_run_threshold: float = 0.7  ## Joystick displacement above this = run
@export var acceleration: float = 800.0
@export var friction: float = 1000.0

## Combat settings
@export_group("Combat")
@export var attack_lunge_force: float = 80.0
@export var attack_lunge_duration: float = 0.1
@export var dodge_speed: float = 300.0
@export var dodge_duration: float = 0.3
@export var dodge_stamina_cost: float = 25.0

## State
var input_direction: Vector2 = Vector2.ZERO  ## Normalized movement direction
var current_facing: Facing = Facing.DOWN
var is_attacking: bool = false
var is_dodging: bool = false
var is_locked: bool = false  ## Prevents input during certain actions
var is_casting: bool = false  ## Currently channeling a cast
var is_stance_active: bool = false  ## Currently in toggle stance (Phalanx Stance)
var is_running: bool = false  ## True when joystick pushed past run threshold
var _joystick_magnitude: float = 0.0  ## Raw joystick displacement (0.0 to 1.0)

## Components
@onready var hitbox_pivot: Node2D = $HitboxPivot
@onready var animator: PlayerAnimator = $Sprite

## Visual layers (weapon, effects, overlay)
var character_visuals: Node2D = null

## Ability visual sequencer
var ability_visual_player: AbilityVisualPlayer = null

## Level up effect
var _level_up_effect: LevelUpEffect

## Status effect manager
var _status_effect_manager: StatusEffectManager
var status_effect_manager: StatusEffectManager:
	get: return _status_effect_manager

## Internal
var _lunge_velocity: Vector2 = Vector2.ZERO
var _lunge_timer: float = 0.0
var _dodge_timer: float = 0.0
var _dodge_direction: Vector2 = Vector2.ZERO

## Casting state
var _current_cast_skill: String = ""
var _cast_timer: float = 0.0
var _cast_duration: float = 0.0
var _cast_can_move: bool = false
var _cast_interrupt_on_damage: bool = true

## Stance state (Phalanx Stance toggle)
var _stance_talent: TalentData = null
var _stance_stamina_drain: float = 5.0  ## Stamina drained per second while in stance


func _ready() -> void:
	Debug.print_saveload("[SAVELOAD] PlayerController._ready() | Frame: %d" % Engine.get_process_frames())
	Debug.print_saveload("[SAVELOAD] Player: Game.current_state BEFORE setting player: %s" % (Game.GameState.keys()[Game.current_state] if Game else "null"))
	Debug.info("Player", "PlayerController ready")
	Game.player = self
	Debug.print_saveload("[SAVELOAD] Player: Set Game.player = self, Game.current_state AFTER: %s" % (Game.GameState.keys()[Game.current_state] if Game else "null"))
	_load_settings_from_database()
	_update_facing(Facing.DOWN)
	_setup_level_up_effect()
	_setup_status_effect_manager()
	PlayerStats.connect_bonus_signals()
	_setup_animator()
	_setup_character_visuals()
	_setup_ability_visual_player()
	Debug.print_saveload("[SAVELOAD] PlayerController._ready() COMPLETE")


func _load_settings_from_database() -> void:
	## Load player settings from gameplay_settings.json (if available)
	## These override the @export defaults when database values exist
	## Note: For durations, 0 in database means "use code default" (not "disable")
	var db := Engine.get_singleton("DatabaseLoader")
	if not db:
		return
	move_speed = db.get_setting("base_move_speed", move_speed)
	walk_speed_ratio = db.get_setting("walk_speed_ratio", walk_speed_ratio)
	joystick_run_threshold = db.get_setting("joystick_run_threshold", joystick_run_threshold)
	dodge_speed = db.get_setting("base_dodge_speed", dodge_speed)
	dodge_stamina_cost = db.get_setting("base_dodge_stamina_cost", dodge_stamina_cost)
	attack_lunge_force = db.get_setting("base_lunge_force", attack_lunge_force)

	# Duration values: only override if database has non-zero value (0 = use code default)
	var db_dodge_duration: float = db.get_setting("base_dodge_duration", 0.0)
	if db_dodge_duration > 0:
		dodge_duration = db_dodge_duration

	var db_lunge_duration: float = db.get_setting("base_lunge_duration", 0.0)
	if db_lunge_duration > 0:
		attack_lunge_duration = db_lunge_duration

	Debug.log("Player", "Loaded settings from database", {
		"move_speed": move_speed,
		"walk_speed_ratio": walk_speed_ratio,
		"joystick_run_threshold": joystick_run_threshold,
		"dodge_speed": dodge_speed,
		"attack_lunge_force": attack_lunge_force,
		"dodge_duration": dodge_duration,
		"attack_lunge_duration": attack_lunge_duration
	})


func _on_attack_hit_frame() -> void:
	## Called when attack animation reaches impact frame
	## Enable hitbox for a brief moment
	if hitbox_pivot and hitbox_pivot.has_node("AttackHitbox/HitboxShape"):
		var hitbox_shape = hitbox_pivot.get_node("AttackHitbox/HitboxShape") as CollisionShape2D
		if hitbox_shape:
			hitbox_shape.disabled = false
			# Re-disable after brief moment
			get_tree().create_timer(0.1).timeout.connect(func():
				if hitbox_shape:
					hitbox_shape.disabled = true
			)


func _setup_level_up_effect() -> void:
	## Create and add level up effect
	_level_up_effect = LevelUpEffect.new()
	_level_up_effect.name = "LevelUpEffect"
	add_child(_level_up_effect)

	## Connect to level up signal
	PlayerStats.leveled_up.connect(_on_leveled_up)


func _setup_status_effect_manager() -> void:
	## Create and add status effect manager
	_status_effect_manager = StatusEffectManager.new()
	_status_effect_manager.name = "StatusEffectManager"
	add_child(_status_effect_manager)


func _setup_animator() -> void:
	## Connect animator signals for attack completion
	if animator:
		animator.attack_animation_finished.connect(_on_attack_animation_finished)
		Debug.log("Player", "Animator connected")


func _setup_character_visuals() -> void:
	var cv_script := load("res://scripts/combat/character_visuals.gd")
	character_visuals = cv_script.new()
	character_visuals.name = "CharacterVisuals"
	add_child(character_visuals)
	if animator:
		# Match sprite offset so weapon/effect layers align with the body
		character_visuals.position = animator.position
		character_visuals.initialize(animator)  # PlayerAnimator IS the AnimatedSprite2D

	# Load weapon visual for currently equipped weapon
	_update_weapon_visual()
	# Update weapon visual when equipment changes
	Inventory.equipment_changed.connect(_on_equipment_changed_weapon_visual)


func _setup_ability_visual_player() -> void:
	ability_visual_player = AbilityVisualPlayer.new()
	ability_visual_player.name = "AbilityVisualPlayer"
	add_child(ability_visual_player)

	# Initialize with the sprite
	if animator:
		ability_visual_player.initialize(animator)

	# Connect movement signal — the visual player requests movement,
	# PlayerController executes it
	ability_visual_player.movement_requested.connect(_on_visual_movement_requested)

	# Connect sequence lifecycle
	ability_visual_player.sequence_started.connect(_on_visual_sequence_started)
	ability_visual_player.sequence_finished.connect(_on_visual_sequence_finished)

	# Connect body animation signal to CharacterVisuals
	if character_visuals:
		character_visuals.connect_to_visual_player(ability_visual_player)


func _on_equipment_changed_weapon_visual(slot) -> void:
	## Update weapon visual when any equipment slot changes
	if slot == ItemData.EquipSlot.MAIN_HAND:
		_update_weapon_visual()


func _update_weapon_visual() -> void:
	## Load weapon sprite set: tries disk textures by sprite_id, falls back to procedural
	if not character_visuals:
		return
	var sprite_id := Inventory.get_equipped_weapon_sprite_id()
	var category := Inventory.get_equipped_weapon_category()
	var texture_set := WeaponTextureLoader.load_weapon_textures(sprite_id, category)
	character_visuals.set_weapon_texture_set(texture_set)


func _on_visual_movement_requested(direction: String, distance: float, duration: float) -> void:
	## Execute movement requested by the visual sequencer
	var move_dir: Vector2

	match direction:
		"toward_target":
			move_dir = _facing_to_vector(current_facing)
		"away_from_target":
			move_dir = -_facing_to_vector(current_facing)
		"facing":
			move_dir = _facing_to_vector(current_facing)
		_:
			move_dir = _facing_to_vector(current_facing)

	# Use the existing lunge system
	_lunge_velocity = move_dir * (distance / max(duration, 0.01))
	_lunge_timer = duration

	Debug.log("Combat", "Visual movement", {"dir": direction, "dist": distance, "dur": duration})


func _on_visual_sequence_started(template_id: String) -> void:
	is_attacking = true
	is_locked = true  # Lock movement during ability animation
	attack_started.emit()
	Debug.log("Combat", "Visual sequence started: %s" % template_id)


func _on_visual_sequence_finished(template_id: String) -> void:
	is_attacking = false
	is_locked = false
	attack_ended.emit()
	# Safety: ensure weapon is hidden when not in a sequence
	if character_visuals:
		character_visuals.set_weapon_visible(false)
	Debug.log("Combat", "Visual sequence finished: %s" % template_id)


func play_ability_visual(template_id: String, overrides: Dictionary = {}, target_pos: Vector2 = Vector2.ZERO) -> void:
	## Called by CombatHUD to trigger an ability's visual sequence
	if ability_visual_player.is_playing:
		Debug.warn("Combat", "Tried to play visual while one is active")
		return

	# Snap facing first so we know the direction for template selection
	if input_direction != Vector2.ZERO:
		_snap_facing_to_cardinal(input_direction)

	var direction := _facing_to_direction_string(current_facing)
	var template: AbilityVisualData = AbilityVisualTemplates.get_template(template_id, direction)
	if not template:
		Debug.warn("Combat", "Unknown visual template: %s" % template_id)
		# Fallback to legacy attack
		request_attack()
		return

	# Sync facing direction so animations resolve to the correct variant
	ability_visual_player.facing_direction = direction

	ability_visual_player.play(template, target_pos, overrides)


func _on_attack_animation_finished() -> void:
	## Called by animator when attack animation completes
	end_attack()


func _physics_process(delta: float) -> void:
	if not Game.can_player_move:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		move_and_slide()
		_update_animator()
		return

	_process_timers(delta)
	_process_movement(delta)
	move_and_slide()
	_update_animator()

	Debug.trace("Movement", "Velocity", velocity)


func _process_timers(delta: float) -> void:
	# Lunge timer
	if _lunge_timer > 0:
		_lunge_timer -= delta
		if _lunge_timer <= 0:
			_lunge_velocity = Vector2.ZERO

	# Dodge timer
	if _dodge_timer > 0:
		_dodge_timer -= delta
		if _dodge_timer <= 0:
			is_dodging = false
			is_locked = false
			dodge_ended.emit()
			Debug.log("Player", "Dodge ended")

	# Cast timer
	if is_casting:
		_cast_timer += delta
		var progress := clampf(_cast_timer / _cast_duration, 0.0, 1.0)
		cast_progress.emit(progress)

		# Check for movement interrupt (if not allowed to move while casting)
		if not _cast_can_move and input_direction != Vector2.ZERO:
			interrupt_cast("moved")
		elif _cast_timer >= _cast_duration:
			_complete_cast()

	# Drain stamina while in toggle stance
	if is_stance_active:
		var drain := _stance_stamina_drain * delta
		if PlayerStats.current_stamina <= drain:
			# Not enough stamina — auto-deactivate
			PlayerStats.current_stamina = 0.0
			deactivate_stance()
		else:
			PlayerStats.current_stamina -= drain


func _process_movement(delta: float) -> void:
	if is_locked:
		# During dodge, use dodge velocity
		if is_dodging:
			velocity = _dodge_direction * dodge_speed
		elif _lunge_timer > 0:
			# Visual sequencer movement (lunge during ability animations)
			velocity = _lunge_velocity
		else:
			# Locked with no active dodge/lunge — stop all movement
			velocity = Vector2.ZERO
		return

	var target_velocity := Vector2.ZERO

	# During lunge, use lunge velocity directly (like dodge)
	if _lunge_timer > 0:
		velocity = _lunge_velocity
		return

	if input_direction != Vector2.ZERO:
		# Calculate effective move speed with movement_speed stat bonus
		var base_speed := move_speed * (1.0 + PlayerStats.movement_speed / 100.0)
		# Apply walk/run multiplier (discrete, not analog)
		var effective_speed: float
		if is_running:
			effective_speed = base_speed
		else:
			effective_speed = base_speed * walk_speed_ratio
		# Apply acceleration toward target speed (direction is always normalized)
		target_velocity = input_direction * effective_speed
		velocity = velocity.move_toward(target_velocity, acceleration * delta)

		# Update facing based on input
		_update_facing_from_input(input_direction)
	else:
		# Apply friction when no input
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


## Input handling (called by InputManager or UI)
func set_input_direction(direction: Vector2) -> void:
	var raw := direction.limit_length(1.0)
	_joystick_magnitude = raw.length()

	# Separate direction from magnitude — direction is always unit-length
	if _joystick_magnitude > 0.01:
		input_direction = raw.normalized()
	else:
		input_direction = Vector2.ZERO
		_joystick_magnitude = 0.0

	# Determine walk vs run from joystick displacement
	is_running = _joystick_magnitude >= joystick_run_threshold


func request_attack() -> void:
	if not Game.can_player_attack or is_attacking or is_dodging:
		return

	is_attacking = true
	attack_started.emit()

	# Snap facing to nearest cardinal direction
	if input_direction != Vector2.ZERO:
		_snap_facing_to_cardinal(input_direction)

	# Apply lunge
	var lunge_dir := _facing_to_vector(current_facing)
	_lunge_velocity = lunge_dir * attack_lunge_force
	_lunge_timer = attack_lunge_duration

	Debug.log("Combat", "Attack started", ["facing:", Facing.keys()[current_facing]])


func request_dodge() -> void:
	if is_stance_active:
		return
	if is_dodging or is_attacking:
		return

	# Check if player has enough stamina
	if not PlayerStats.use_stamina(dodge_stamina_cost):
		Debug.log("Combat", "Dodge failed", "Not enough stamina")
		return

	is_dodging = true
	is_locked = true
	_dodge_timer = dodge_duration

	# Dodge in input direction, or facing direction if no input
	if input_direction != Vector2.ZERO:
		_dodge_direction = input_direction.normalized()
	else:
		_dodge_direction = _facing_to_vector(current_facing)

	dodge_started.emit()
	Debug.log("Combat", "Dodge started", ["direction:", _dodge_direction])


func end_attack() -> void:
	## Called by animator when attack animation finishes
	is_attacking = false
	attack_ended.emit()
	Debug.log("Combat", "Attack ended")


## Skill mechanics (called by CombatHUD when using skills)
func apply_skill_lunge(force: float, duration: float = 0.0) -> void:
	## Apply lunge in facing direction from skill
	## duration: Custom lunge duration from database (0 = use default attack_lunge_duration)
	var lunge_dir := _facing_to_vector(current_facing)
	_lunge_velocity = lunge_dir * force
	_lunge_timer = duration if duration > 0 else attack_lunge_duration
	Debug.log("Combat", "Skill lunge applied", {"force": force, "duration": _lunge_timer, "direction": lunge_dir})


func apply_recovery_lockout(duration: float) -> void:
	## Lock player input for recovery time after skill
	is_locked = true
	# Create a timer to unlock after duration
	get_tree().create_timer(duration).timeout.connect(_end_recovery_lockout)
	Debug.log("Combat", "Recovery lockout", {"duration": duration})


func _end_recovery_lockout() -> void:
	## Called when recovery timer expires
	if not is_dodging:  # Don't unlock if in middle of dodge
		is_locked = false
	Debug.log("Combat", "Recovery ended")


#===============================================================================
# TOGGLE STANCE (Phalanx Stance)
#===============================================================================

func activate_stance(talent: TalentData) -> void:
	## Enter toggle stance mode
	if is_stance_active:
		return
	is_stance_active = true
	_stance_talent = talent
	stance_activated.emit(talent.id)
	Debug.log("Combat", "Stance activated: %s" % talent.talent_name)


func deactivate_stance() -> void:
	## Exit toggle stance mode
	if not is_stance_active:
		return
	is_stance_active = false
	var talent_id := _stance_talent.id if _stance_talent else ""
	_stance_talent = null

	# Cancel the visual sequence so weapon hides and idle resumes
	if ability_visual_player and ability_visual_player.is_playing:
		ability_visual_player.cancel()

	stance_deactivated.emit(talent_id)
	Debug.log("Combat", "Stance deactivated")


## Facing logic
func _update_animator() -> void:
	## Animator handles its own state via signals and velocity polling.
	## Nothing to do here — kept for interface compatibility.
	pass


func _update_facing_from_input(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return

	var new_facing := current_facing

	# 8-way input → 4-way animation
	# Prioritize horizontal when diagonal (per design doc)
	if abs(direction.x) >= abs(direction.y) * 0.5:  # Horizontal priority
		if direction.x > 0:
			new_facing = Facing.RIGHT
		else:
			new_facing = Facing.LEFT
	else:
		if direction.y > 0:
			new_facing = Facing.DOWN
		else:
			new_facing = Facing.UP

	if new_facing != current_facing:
		_update_facing(new_facing)


func _snap_facing_to_cardinal(direction: Vector2) -> void:
	## Snap to nearest cardinal direction (for attacks)
	var new_facing: Facing

	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			new_facing = Facing.RIGHT
		else:
			new_facing = Facing.LEFT
	else:
		if direction.y > 0:
			new_facing = Facing.DOWN
		else:
			new_facing = Facing.UP

	if new_facing != current_facing:
		_update_facing(new_facing)


func _update_facing(new_facing: Facing) -> void:
	current_facing = new_facing
	facing_changed.emit(current_facing)

	# Update hitbox pivot rotation
	if hitbox_pivot:
		hitbox_pivot.rotation = _facing_to_rotation(current_facing)

	# Sync visuals direction
	var dir_name := _facing_to_direction_string(new_facing)
	var flipped := (new_facing == Facing.LEFT)
	if character_visuals:
		character_visuals.set_direction(dir_name, flipped)
	if ability_visual_player:
		ability_visual_player.facing_direction = dir_name

	Debug.trace("Player", "Facing changed", Facing.keys()[current_facing])


func _facing_to_direction_string(facing: Facing) -> String:
	## Convert Facing enum to direction string for animation resolution.
	## Left uses "right" sprites with flip_h.
	match facing:
		Facing.DOWN: return "down"
		Facing.UP: return "up"
		Facing.LEFT: return "right"
		Facing.RIGHT: return "right"
	return "down"


func _facing_to_vector(facing: Facing) -> Vector2:
	match facing:
		Facing.DOWN: return Vector2.DOWN
		Facing.UP: return Vector2.UP
		Facing.LEFT: return Vector2.LEFT
		Facing.RIGHT: return Vector2.RIGHT
	return Vector2.DOWN


func _facing_to_rotation(facing: Facing) -> float:
	match facing:
		Facing.DOWN: return 0.0
		Facing.UP: return PI
		Facing.LEFT: return PI / 2.0
		Facing.RIGHT: return -PI / 2.0
	return 0.0


## Level up callback
func _on_leveled_up(new_level: int) -> void:
	if _level_up_effect:
		_level_up_effect.play(new_level)


#===============================================================================
# DAMAGE AND STATUS EFFECTS
#===============================================================================

func take_damage(amount: float, _source: Node2D = null) -> void:
	## Called by enemy abilities when hitting player
	var attacker_pos := _source.global_position if _source and is_instance_valid(_source) else Vector2.INF
	var damage_applied := PlayerStats.damage(amount, "physical", false, attacker_pos)

	if not damage_applied:
		return  # Damage was parried - don't interrupt or log

	Debug.log("Combat", "Player took damage", amount)

	# Interrupt casting if flagged
	if is_casting and _cast_interrupt_on_damage:
		interrupt_cast("damage")


func apply_dot(effect_type: String, duration: float, damage_per_tick: float) -> void:
	## Apply a damage-over-time effect to the player
	if _status_effect_manager:
		_status_effect_manager.apply_dot(effect_type, duration, damage_per_tick)


func apply_stun(duration: float) -> void:
	## Apply stun effect (lock player input)
	is_locked = true
	Debug.log("Combat", "Player stunned", duration)
	# Create a timer to unlock after duration
	get_tree().create_timer(duration).timeout.connect(func(): is_locked = false)


func apply_slow(duration: float, percent: float) -> void:
	## Apply slow effect (reduce movement speed)
	var original_speed := move_speed
	move_speed *= (1.0 - percent)
	Debug.log("Combat", "Player slowed", {"duration": duration, "percent": percent * 100})
	get_tree().create_timer(duration).timeout.connect(func(): move_speed = original_speed)


#===============================================================================
# CASTING SYSTEM
#===============================================================================

func start_cast(skill_id: String, duration: float, can_move: bool = false, interrupt_on_damage: bool = true) -> bool:
	## Start casting a skill. Returns false if already casting or in invalid state.
	if is_casting or is_attacking or is_dodging:
		Debug.log("Combat", "Cast rejected", {"skill": skill_id, "reason": "busy"})
		return false

	if duration <= 0:
		Debug.log("Combat", "Cast rejected", {"skill": skill_id, "reason": "invalid duration"})
		return false

	is_casting = true
	_current_cast_skill = skill_id
	_cast_timer = 0.0
	_cast_duration = duration
	_cast_can_move = can_move
	_cast_interrupt_on_damage = interrupt_on_damage

	# Lock movement if can't move while casting
	if not can_move:
		is_locked = true

	cast_started.emit(skill_id, duration)
	Debug.log("Combat", "Cast started", {"skill": skill_id, "duration": duration, "can_move": can_move})
	return true


func interrupt_cast(reason: String = "interrupted") -> void:
	## Interrupt the current cast (from damage, movement, etc.)
	if not is_casting:
		return

	var skill_id := _current_cast_skill
	_end_cast_state()

	cast_interrupted.emit(skill_id, reason)
	Debug.log("Combat", "Cast interrupted", {"skill": skill_id, "reason": reason})


func cancel_cast() -> void:
	## Player-initiated cast cancellation
	interrupt_cast("cancelled")


func _complete_cast() -> void:
	## Called when cast timer reaches duration
	var skill_id := _current_cast_skill
	_end_cast_state()

	# Notify quest system for USE_ABILITY objectives
	if QuestManager:
		QuestManager.on_ability_used(skill_id)

	cast_completed.emit(skill_id)
	Debug.log("Combat", "Cast completed", {"skill": skill_id})


func _end_cast_state() -> void:
	## Clean up casting state
	is_casting = false
	_current_cast_skill = ""
	_cast_timer = 0.0
	_cast_duration = 0.0

	# Unlock if we locked for casting
	if not is_dodging:
		is_locked = false


func get_cast_progress() -> float:
	## Returns current cast progress (0.0 to 1.0)
	if not is_casting or _cast_duration <= 0:
		return 0.0
	return clampf(_cast_timer / _cast_duration, 0.0, 1.0)


func get_current_cast_skill() -> String:
	## Returns the skill ID currently being cast
	return _current_cast_skill


## Debug
func print_state() -> void:
	Debug.snapshot("Player", "PlayerController State", {
		"position": global_position,
		"velocity": velocity,
		"input_direction": input_direction,
		"joystick_magnitude": _joystick_magnitude,
		"is_running": is_running,
		"facing": Facing.keys()[current_facing],
		"is_attacking": is_attacking,
		"is_dodging": is_dodging,
		"is_locked": is_locked,
		"is_casting": is_casting,
		"cast_skill": _current_cast_skill,
		"cast_progress": get_cast_progress(),
	})


func debug_test_ends_when_buff() -> void:
	## Test the ends_when system - applies a buff that ends when player heals to full
	## Call from console or debug button
	if _status_effect_manager:
		# Deal some damage first so player isn't at full health
		PlayerStats.damage(20.0, "debug", false)
		Debug.info("Debug", "Dealt 20 damage to player")

		# Apply test buff that ends when healed to full
		_status_effect_manager.apply_buff("test_frenzy", 60.0, true, "player_full_health")
		Debug.info("Debug", "Applied test_frenzy buff (ends when player heals to full)")
		Debug.info("Debug", "Heal to full health to see buff disappear!")


