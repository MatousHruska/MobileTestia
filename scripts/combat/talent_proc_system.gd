extends Node
## TalentProcSystem - Processes passive talent procs based on combat events
##
## Listens to combat signals (enemy killed, player dodged, player hit enemy, etc.)
## and triggers passive talent effects when conditions are met.
##
## Proc fields on TalentData:
##   proc_trigger: "on_kill", "on_dodge", "on_hit", "on_crit", "on_take_damage", "on_parry", "always"
##   proc_condition: "stamina_above_50", "target_full_hp", "target_marked", etc.
##   proc_effect: "apply_status:id", "restore_stamina:amt", "buff:stat:val:dur", etc.
##   proc_chance: 0 = always, else % chance
##   proc_cooldown: internal cooldown in seconds (0 = none)

## Signal emitted when a proc fires (for UI feedback, combat log)
signal proc_triggered(talent_id: String, effect: String)

## Signal emitted when a parry successfully negates damage
signal parry_succeeded(attacker: Node2D)

## Signal emitted with per-hit damage breakdown data (for debug overlay)
signal damage_breakdown_available(info: Dictionary)

## Internal cooldown tracking (talent_id -> time_remaining)
var _cooldowns: Dictionary = {}

## Tracking for "same_target_consecutive" condition
var _last_hit_target: Node2D = null
var _consecutive_hits: int = 0

## Tracking for temporary damage bonuses from procs
var _next_attack_bonus_percent: float = 0.0
var _next_attack_bonus_timer: float = 0.0

## Closing the Gap - continuous distance-based damage bonus
var _closing_gap_bonus: float = 0.0
var _closing_gap_cap: float = 0.0
var _closing_gap_nearest_name: String = ""
const CLOSING_GAP_REFERENCE_DISTANCE: float = 120.0  # pixels to reach max
const CLOSING_GAP_DECAY_TIME: float = 2.5  # seconds to fully decay
const CLOSING_GAP_TALENT_ID: String = "tal_noble_closing_gap"
const CLOSING_GAP_BONUS_PER_POINT: float = 7.0

## Conditional crit bonus (from "always" procs like Exposed Throat)
## This is checked by DamageCalculator before rolling crit
var bonus_crit_chance: float = 0.0

## Conditional armor % bonus (from "always" procs like Iron Posture)
## This is checked by DamageCalculator when calculating armor reduction
var bonus_armor_percent: float = 0.0

## Parry system state
var _parry_active: bool = false
var _parry_window_timer: float = 0.0
var _parry_talent: TalentData = null  ## The Cold Parry talent data (for counter damage)
var _parry_frontal_arc: float = 180.0  ## Frontal arc in degrees for parry

## Ultimate ability state (Father's Last Lesson)
var _ultimate_active: bool = false
var _ultimate_timer: float = 0.0
var _ultimate_crit_bonus: float = 1000.0  ## Added to bonus_crit_chance during ultimate
var _ultimate_no_stamina_cost: bool = false
var _ultimate_slow_tick: float = 0.0  ## Timer for periodic AOE slow
const ULTIMATE_SLOW_INTERVAL: float = 1.0  ## Apply slow every 1s
const ULTIMATE_SLOW_RADIUS: float = 200.0  ## Radius for enemy slow


func _ready() -> void:
	add_to_group("saveable")
	Debug.info("Procs", "TalentProcSystem initialized")

	# Connect to signals after databases are loaded
	if not DatabaseLoader.talent_trees.is_empty():
		_connect_signals()
	else:
		DatabaseLoader.databases_loaded.connect(_on_databases_loaded)


func _on_databases_loaded() -> void:
	_connect_signals()


func _connect_signals() -> void:
	# Enemy killed - NPCManager fires this when any enemy is unregistered (dies)
	if NPCManager:
		NPCManager.enemy_unregistered.connect(_on_enemy_killed)

	# Player took damage
	PlayerStats.damaged.connect(_on_player_damaged)

	# Player dodge - connect to player controller when available
	_try_connect_player_signals()

	# Recalculate always-procs when talents change (needed while game is paused in menus)
	if TalentManager:
		TalentManager.talent_learned.connect(_on_talent_changed)

	Debug.info("Procs", "Combat signals connected")


func _on_talent_changed(_talent_id: String, _new_points: int) -> void:
	_update_always_procs()


func _try_connect_player_signals() -> void:
	## Try to connect to player-specific signals (may not be ready yet)
	if Game.player:
		_connect_player(Game.player)


func _connect_player(player: Node2D) -> void:
	if player.has_signal("dodge_started"):
		if not player.dodge_started.is_connected(_on_player_dodged):
			player.dodge_started.connect(_on_player_dodged)
	Debug.info("Procs", "Connected to player signals")


func _process(delta: float) -> void:
	# Tick cooldowns
	var to_remove: Array[String] = []
	for talent_id in _cooldowns:
		_cooldowns[talent_id] -= delta
		if _cooldowns[talent_id] <= 0:
			to_remove.append(talent_id)
	for talent_id in to_remove:
		_cooldowns.erase(talent_id)

	# Tick next-attack bonus timer
	if _next_attack_bonus_timer > 0:
		_next_attack_bonus_timer -= delta
		if _next_attack_bonus_timer <= 0:
			_next_attack_bonus_percent = 0.0

	# Tick parry window timer (the visual sequencer handles its own timing,
	# but this is the authoritative parry state for damage interception)
	if _parry_active and _parry_window_timer > 0:
		_parry_window_timer -= delta
		if _parry_window_timer <= 0:
			_end_parry_window()

	# Tick ultimate timer
	if _ultimate_active:
		_ultimate_timer -= delta
		if _ultimate_timer <= 0:
			deactivate_ultimate()
		else:
			# Apply AOE slow to nearby enemies periodically
			_ultimate_slow_tick -= delta
			if _ultimate_slow_tick <= 0:
				_ultimate_slow_tick = ULTIMATE_SLOW_INTERVAL
				_apply_ultimate_slow()

	# Recalculate "always" procs (conditional crit, conditional armor, etc.)
	_update_always_procs()

	# Accumulate/decay Closing the Gap bonus based on movement toward enemies
	_update_closing_gap(delta)


#===============================================================================
# EVENT HANDLERS
#===============================================================================

func _on_enemy_killed(enemy: Node2D) -> void:
	## Fires all on_kill procs
	_process_procs("on_kill", enemy)


func _on_player_dodged() -> void:
	## Fires all on_dodge procs
	# Find nearest enemy for status application
	var nearest := _get_nearest_enemy()
	_process_procs("on_dodge", nearest)


func _on_player_damaged(amount: float, _damage_type: String, _is_crit: bool) -> void:
	## Fires all on_take_damage procs
	_process_procs("on_take_damage", null)


## Called by CombatHUD when player hits an enemy with a skill
func on_player_hit_enemy(enemy: Node2D, damage_result: Dictionary, talent: TalentData) -> void:
	# Track consecutive hits for Relentless
	if enemy == _last_hit_target:
		_consecutive_hits += 1
	else:
		_last_hit_target = enemy
		_consecutive_hits = 1

	_process_procs("on_hit", enemy)

	# Check for crit procs
	if damage_result.get("is_critical", false):
		_process_procs("on_crit", enemy)


## Called by Cold Parry system on successful parry
func on_parry_success(attacker: Node2D) -> void:
	_process_procs("on_parry", attacker)


#===============================================================================
# PROC PROCESSING
#===============================================================================

func _process_procs(trigger: String, target: Node2D) -> void:
	## Find all invested passive talents with matching proc_trigger and execute them
	for talent_id in TalentManager.invested_talents:
		var points: int = TalentManager.invested_talents[talent_id]
		if points <= 0:
			continue

		# Closing the Gap is handled continuously in _update_closing_gap()
		if talent_id == CLOSING_GAP_TALENT_ID:
			continue

		var talent := TalentManager.get_talent(talent_id)
		if not talent or not talent.is_passive() or not talent.has_proc():
			continue

		# Check if this talent's trigger matches
		# Support comma-separated triggers (e.g., "on_kill,on_crit")
		var triggers := talent.proc_trigger.split(",")
		var matches := false
		for t in triggers:
			if t.strip_edges() == trigger:
				matches = true
				break
		if not matches:
			continue

		# Check cooldown
		if _cooldowns.has(talent_id):
			continue

		# Check proc chance
		if talent.proc_chance > 0 and randf() * 100.0 > talent.proc_chance:
			continue

		# Check condition
		if not _check_condition(talent.proc_condition, target):
			continue

		# Execute the effect (scaled by points invested)
		_execute_effect(talent.proc_effect, points, target, talent_id)

		# Apply cooldown
		if talent.proc_cooldown > 0:
			_cooldowns[talent_id] = talent.proc_cooldown

		proc_triggered.emit(talent_id, talent.proc_effect)


func _check_condition(condition: String, target: Node2D) -> bool:
	## Check if a proc condition is met
	if condition.is_empty():
		return true

	# Support OR conditions (comma-separated)
	var conditions := condition.split(",")
	for cond in conditions:
		cond = cond.strip_edges()
		if _check_single_condition(cond, target):
			return true

	return false


func _check_single_condition(condition: String, target: Node2D) -> bool:
	match condition:
		"stamina_above_50":
			return PlayerStats.current_stamina > (PlayerStats.max_stamina * 0.5)
		"target_full_hp":
			if target and is_instance_valid(target) and "current_health" in target and "max_health" in target:
				return target.current_health >= target.max_health
			return false
		"target_marked":
			if target and is_instance_valid(target) and "status_effects" in target and target.status_effects:
				return target.status_effects.has_effect("status_marked")
			return false
		"target_hp_below_30":
			if target and is_instance_valid(target) and "current_health" in target and "max_health" in target:
				return target.current_health < (target.max_health * 0.3)
			return false
		"moved_toward_target":
			# Simplified: always true during combat (player is moving toward enemies)
			# Full implementation would track velocity direction vs enemy position
			return true
		"same_target_consecutive":
			return _consecutive_hits > 1
		"max_range_hit":
			# Simplified: 20% chance to represent "tip of weapon" hits
			# Full implementation would compare hit distance to weapon range
			return randf() < 0.2
		_:
			Debug.warn("Procs", "Unknown condition: %s" % condition)
			return true


func _execute_effect(effect_str: String, points: int, target: Node2D, talent_id: String) -> void:
	## Parse and execute a proc effect string
	## Effects can be semicolon-separated for multiple effects
	var effects := effect_str.split(";")
	for effect in effects:
		effect = effect.strip_edges()
		_execute_single_effect(effect, points, target, talent_id)


func _execute_single_effect(effect: String, points: int, target: Node2D, talent_id: String) -> void:
	var parts := effect.split(":")

	if parts.is_empty():
		return

	var effect_type := parts[0].strip_edges()

	match effect_type:
		"apply_status":
			# apply_status:status_id - Apply to target enemy
			if parts.size() >= 2 and target and is_instance_valid(target):
				var status_id := parts[1].strip_edges()
				if "status_effects" in target and target.status_effects:
					target.status_effects.apply_status_effect(status_id)
					Debug.log("Procs", "%s -> apply %s to %s" % [talent_id, status_id, target.name])

		"apply_status_self":
			# apply_status_self:status_id - Apply to player
			if parts.size() >= 2 and Game.player and Game.player.has_node("StatusEffectManager"):
				var status_id := parts[1].strip_edges()
				Game.player.status_effect_manager.apply_status_effect(status_id)
				Debug.log("Procs", "%s -> self-apply %s" % [talent_id, status_id])

		"apply_status_aoe":
			# apply_status_aoe:status_id:radius - Apply to all enemies in radius
			if parts.size() >= 3 and Game.player:
				var status_id := parts[1].strip_edges()
				var radius := float(parts[2].strip_edges())
				var enemies := NPCManager.get_enemies_in_radius(Game.player.global_position, radius)
				for enemy in enemies:
					if enemy != target and is_instance_valid(enemy) and "status_effects" in enemy and enemy.status_effects:
						enemy.status_effects.apply_status_effect(status_id)
						# Stagger AOE: interrupt enemy abilities (no knockback for AOE)
						if status_id == "status_stagger" and enemy.has_method("interrupt_ability"):
							enemy.interrupt_ability()
				Debug.log("Procs", "%s -> AOE %s (radius %s)" % [talent_id, status_id, radius])

		"restore_stamina":
			# restore_stamina:amount - Restore stamina (scaled by points)
			if parts.size() >= 2:
				var amount := float(parts[1].strip_edges()) * points
				PlayerStats.current_stamina = minf(PlayerStats.current_stamina + amount, PlayerStats.max_stamina)
				Debug.log("Procs", "%s -> restore %s stamina" % [talent_id, amount])

		"restore_health_pct_missing":
			# restore_health_pct_missing:pct - Heal % of missing HP (scaled by points)
			if parts.size() >= 2:
				var pct := float(parts[1].strip_edges()) * points / 100.0
				var missing := PlayerStats.max_life - PlayerStats.current_life
				var heal := missing * pct
				if heal > 0:
					PlayerStats.heal(heal)
					Debug.log("Procs", "%s -> heal %s (%.0f%% missing)" % [talent_id, heal, pct * 100])

		"buff":
			# buff:stat:value:duration - Temporary stat buff (value scaled by points)
			if parts.size() >= 4:
				var stat := parts[1].strip_edges()
				var value := float(parts[2].strip_edges()) * points
				var duration := float(parts[3].strip_edges())
				_apply_temporary_buff(stat, value, duration, talent_id)

		"damage_bonus_next":
			# damage_bonus_next:pct:duration - Next attack deals bonus % damage (scaled by points)
			if parts.size() >= 3:
				var pct := float(parts[1].strip_edges()) * points
				var duration := float(parts[2].strip_edges())
				_next_attack_bonus_percent += pct
				if duration > 0:
					_next_attack_bonus_timer = duration
				else:
					# Instant - apply to very next hit only, short window
					_next_attack_bonus_timer = 5.0
				Debug.log("Procs", "%s -> next attack +%s%% for %ss" % [talent_id, pct, duration])

		"conditional_crit":
			# conditional_crit:pct - Handled in _update_always_procs, not here
			pass

		"parry_upgrade":
			# parry_upgrade:key:value,key:value - Modifies Cold Parry behavior
			# Handled by the parry system directly checking if this talent is learned
			pass

		_:
			Debug.warn("Procs", "Unknown effect type: %s in %s" % [effect_type, talent_id])


#===============================================================================
# ALWAYS-ACTIVE PROCS (recalculated each frame)
#===============================================================================

func _update_always_procs() -> void:
	## Recalculate bonuses from "always" trigger talents
	var new_crit_bonus: float = 0.0
	var new_armor_pct: float = 0.0

	for talent_id in TalentManager.invested_talents:
		var points: int = TalentManager.invested_talents[talent_id]
		if points <= 0:
			continue

		var talent := TalentManager.get_talent(talent_id)
		if not talent or not talent.is_passive() or not talent.has_proc():
			continue
		if talent.proc_trigger != "always":
			continue

		# "always" procs check condition against current target or state
		var effects := talent.proc_effect.split(";")
		for effect in effects:
			effect = effect.strip_edges()
			var parts := effect.split(":")
			match parts[0]:
				"conditional_crit":
					var nearest := _get_nearest_enemy()
					if _check_condition(talent.proc_condition, nearest):
						new_crit_bonus += float(parts[1]) * points
				"conditional_armor_pct":
					if _check_condition(talent.proc_condition, null):
						new_armor_pct += float(parts[1]) * points

	bonus_crit_chance = new_crit_bonus

	# Trigger stat recalculation when conditional armor % changes
	if new_armor_pct != bonus_armor_percent:
		bonus_armor_percent = new_armor_pct
		PlayerStats.recalculate_stats()



#===============================================================================
# CLOSING THE GAP - CONTINUOUS DISTANCE-BASED BONUS
#===============================================================================

func _update_closing_gap(delta: float) -> void:
	## Accumulate damage bonus while player moves toward nearest enemy, decay otherwise
	var points := TalentManager.get_invested_points(CLOSING_GAP_TALENT_ID)
	if points <= 0:
		_closing_gap_bonus = 0.0
		_closing_gap_cap = 0.0
		_closing_gap_nearest_name = ""
		return

	_closing_gap_cap = CLOSING_GAP_BONUS_PER_POINT * points

	if not Game.player:
		return

	var nearest := _get_nearest_enemy()
	if nearest and is_instance_valid(nearest):
		_closing_gap_nearest_name = nearest.name
		var direction_to_enemy := (nearest.global_position - Game.player.global_position).normalized()
		var approach_speed: float = Game.player.velocity.dot(direction_to_enemy)

		if approach_speed > 0:
			# Moving toward enemy — accumulate bonus proportional to approach speed
			_closing_gap_bonus += approach_speed * delta * (_closing_gap_cap / CLOSING_GAP_REFERENCE_DISTANCE)
		else:
			# Stationary or moving away — gradual decay
			_closing_gap_bonus -= (_closing_gap_cap / CLOSING_GAP_DECAY_TIME) * delta
	else:
		_closing_gap_nearest_name = ""
		# No enemy nearby — decay
		_closing_gap_bonus -= (_closing_gap_cap / CLOSING_GAP_DECAY_TIME) * delta

	_closing_gap_bonus = clampf(_closing_gap_bonus, 0.0, _closing_gap_cap)


#===============================================================================
# BUFF APPLICATION
#===============================================================================

func _apply_temporary_buff(stat: String, value: float, duration: float, talent_id: String) -> void:
	## Apply a temporary stat buff via the player's status effect system
	## For simplicity, we use a custom buff that modifies PlayerStats directly
	if Game.player and Game.player.has_node("StatusEffectManager"):
		var buff_id := "proc_%s_%s" % [talent_id, stat]
		Game.player.status_effect_manager.apply_buff(buff_id, duration, true)
		Debug.log("Procs", "%s -> buff %s +%s for %ss" % [talent_id, stat, value, duration])


#===============================================================================
# DAMAGE BONUS QUERY (called by CombatHUD before applying damage)
#===============================================================================

## Get and consume the next-attack damage bonus percentage
## Combines proc bonuses (First Blood, etc.) with Closing the Gap bonus
func consume_next_attack_bonus() -> float:
	var bonus := _next_attack_bonus_percent + _closing_gap_bonus
	_next_attack_bonus_percent = 0.0
	_next_attack_bonus_timer = 0.0
	_closing_gap_bonus = 0.0
	return bonus


## Get bonus crit chance from passive talents (does NOT consume)
func get_bonus_crit_chance() -> float:
	return bonus_crit_chance


## Get bonus armor percent from passive talents (does NOT consume)
func get_bonus_armor_percent() -> float:
	return bonus_armor_percent



## Report damage breakdown for debug overlay
func report_damage_breakdown(info: Dictionary) -> void:
	damage_breakdown_available.emit(info)


#===============================================================================
# UTILITY
#===============================================================================

func _get_nearest_enemy() -> Node2D:
	if not Game.player:
		return null
	var enemies := NPCManager.get_enemies_in_radius(Game.player.global_position, 150.0)
	if enemies.is_empty():
		return null
	var nearest: Node2D = null
	var nearest_dist := INF
	for enemy in enemies:
		var dist := Game.player.global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest


#===============================================================================
# CONSECUTIVE HIT TRACKING
#===============================================================================

## Reset consecutive hits (called when player misses, switches targets, or takes damage)
func reset_consecutive_hits() -> void:
	_consecutive_hits = 0
	_last_hit_target = null


#===============================================================================
# PARRY SYSTEM
#===============================================================================

## Start the parry window. Called by CombatHUD when Cold Parry is activated.
## Duration should already include Deflective Spin bonus (calculated by CombatHUD).
func start_parry_window(duration: float, talent: TalentData) -> void:
	_parry_active = true
	_parry_window_timer = duration
	_parry_talent = talent
	_parry_frontal_arc = talent.hit_arc if talent.hit_arc > 0 else 180.0

	Debug.log("Procs", "Parry window started (%.1fs)" % _parry_window_timer)


## Check if parry is currently active
func is_parry_active() -> bool:
	return _parry_active


## Try to parry incoming damage. Returns true if damage was negated.
## Called by PlayerStats.damage() before applying damage.
## attacker_pos: world position of the attacker (for frontal arc check)
func try_parry(attacker_pos: Vector2) -> bool:
	if not _parry_active:
		return false

	# Check frontal arc - attacker must be in front of player
	if Game.player and _parry_frontal_arc < 360.0:
		var player_pos: Vector2 = Game.player.global_position
		var to_attacker := (attacker_pos - player_pos).normalized()
		var facing_vec := _get_player_facing_vector()
		var angle := rad_to_deg(facing_vec.angle_to(to_attacker))
		if abs(angle) > _parry_frontal_arc / 2.0:
			return false  # Attack came from behind

	# Parry succeeds - negate damage
	_parry_active = false
	_parry_window_timer = 0.0

	# Find the attacker node for counter-attack and procs
	var attacker := _find_attacker_at_position(attacker_pos)

	Debug.log("Procs", "PARRY SUCCESS! Counter-attacking")

	# Fire on_parry procs (Master's Riposte, etc.)
	on_parry_success(attacker)

	# Signal CombatHUD to execute counter-attack
	parry_succeeded.emit(attacker)

	return true


## End parry window (expired without being triggered)
func _end_parry_window() -> void:
	_parry_active = false
	_parry_window_timer = 0.0
	_parry_talent = null
	Debug.log("Procs", "Parry window expired")


## Cancel parry window (e.g., player interrupted)
func cancel_parry_window() -> void:
	if _parry_active:
		_end_parry_window()


## Get the Cold Parry talent data (for counter-attack damage calculation)
func get_parry_talent() -> TalentData:
	return _parry_talent


## Check if Deflective Spin allows projectile reflection
func can_reflect_projectiles() -> bool:
	return _parry_active and TalentManager.get_invested_points("tal_noble_deflective_spin") > 0


func _get_player_facing_vector() -> Vector2:
	if not Game.player:
		return Vector2.DOWN
	match Game.player.current_facing:
		PlayerController.Facing.DOWN: return Vector2.DOWN
		PlayerController.Facing.UP: return Vector2.UP
		PlayerController.Facing.LEFT: return Vector2.LEFT
		PlayerController.Facing.RIGHT: return Vector2.RIGHT
		_: return Vector2.DOWN


func _find_attacker_at_position(pos: Vector2) -> Node2D:
	## Find the nearest enemy to the given position (the attacker)
	var enemies := NPCManager.get_enemies_in_radius(pos, 60.0)
	if not enemies.is_empty():
		return enemies[0]
	# Fallback: find nearest enemy to player
	return _get_nearest_enemy()


#===============================================================================
# ULTIMATE ABILITY (Father's Last Lesson)
#===============================================================================

## Activate ultimate buff for the given duration
func activate_ultimate(duration: float) -> void:
	_ultimate_active = true
	_ultimate_timer = duration
	_ultimate_no_stamina_cost = true
	_ultimate_slow_tick = 0.0
	bonus_crit_chance += _ultimate_crit_bonus
	Debug.log("Procs", "ULTIMATE ACTIVATED! (%.1fs) Guaranteed crits, no stamina cost" % duration)


## Check if ultimate is currently active
func is_ultimate_active() -> bool:
	return _ultimate_active


## Check if stamina costs should be waived (during ultimate)
func should_waive_stamina_cost() -> bool:
	return _ultimate_no_stamina_cost


## Deactivate ultimate (called on expiry or forced cancel)
func deactivate_ultimate() -> void:
	if not _ultimate_active:
		return
	_ultimate_active = false
	_ultimate_timer = 0.0
	_ultimate_no_stamina_cost = false
	bonus_crit_chance -= _ultimate_crit_bonus
	if bonus_crit_chance < 0:
		bonus_crit_chance = 0.0
	Debug.log("Procs", "Ultimate expired")


func _apply_ultimate_slow() -> void:
	## Apply slow debuff to all enemies within radius during ultimate
	if not Game.player:
		return
	var enemies := NPCManager.get_enemies_in_radius(Game.player.global_position, ULTIMATE_SLOW_RADIUS)
	for enemy in enemies:
		if is_instance_valid(enemy) and "status_effects" in enemy and enemy.status_effects:
			enemy.status_effects.apply_status_effect("status_slow")


#===============================================================================
# PERSISTENCE
#===============================================================================

func get_save_key() -> String:
	return "talent_proc_system"


func get_save_priority() -> int:
	return 25  # After TalentManager


func get_save_data() -> Dictionary:
	return {}  # No persistent state needed - procs are ephemeral


func load_save_data(_data: Dictionary) -> void:
	_cooldowns.clear()
	_consecutive_hits = 0
	_last_hit_target = null
	_next_attack_bonus_percent = 0.0
	_next_attack_bonus_timer = 0.0
	_closing_gap_bonus = 0.0
	_closing_gap_cap = 0.0
	_closing_gap_nearest_name = ""
	bonus_armor_percent = 0.0
	_parry_active = false
	_parry_window_timer = 0.0
	_parry_talent = null
	_ultimate_active = false
	_ultimate_timer = 0.0
	_ultimate_no_stamina_cost = false
	_ultimate_slow_tick = 0.0
