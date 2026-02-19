extends Control
class_name AbilitySlot
## AbilitySlot - A combat button that can be bound to an ability
## Handles cooldown tracking, mana checking, and visual feedback

signal ability_activated(slot_index: int, ability_id: String)
signal ability_hold_started(slot_index: int, ability_id: String)
signal ability_released(slot_index: int, ability_id: String, hold_duration: float)
signal ability_ready(slot_index: int)

enum SlotType { ABILITY, ATTACK, DODGE, QUICK_SLOT }

@export var slot_type: SlotType = SlotType.ABILITY
@export var slot_index: int = 0
@export var button_radius: float = 45.0

## Colors
@export_group("Colors")
@export var normal_color: Color = Color(0.55, 1.0, 0.98, 0.85)
@export var pressed_color: Color = Color(0.75, 1.0, 1.0, 0.95)
@export var no_resource_color: Color = Color(0.3, 0.4, 0.6, 0.7)  ## Blueish for not enough mana/stamina
@export var no_weapon_color: Color = Color(0.35, 0.35, 0.35, 0.6)  ## Grayed out for wrong/no weapon
@export var cooldown_color: Color = Color(0.2, 0.2, 0.2, 0.6)
@export var empty_color: Color = Color(0.3, 0.3, 0.3, 0.5)
@export var border_color: Color = Color(1.0, 1.0, 1.0, 0.4)
@export var border_width: float = 2.0

## Visual feedback
@export_group("Feedback")
@export var press_scale: float = 0.9
@export var press_duration: float = 0.08

## Ability binding
var bound_ability_id: String = ""
var ability_data: Dictionary = {}
var icon_text: String = ""
var icon_texture: Texture2D = null

## State
var is_pressed_state: bool = false
var is_on_cooldown: bool = false
var cooldown_remaining: float = 0.0
var cooldown_duration: float = 0.0
var has_enough_resource: bool = true
var has_valid_weapon: bool = true  ## False if skill requires a weapon type not equipped
var is_empty: bool = true
var touch_index: int = -1

## Hold tracking (for ranged skills)
var is_hold_skill: bool = false      ## True if this skill uses hold-to-release
var hold_start_time: float = 0.0     ## Time when hold started
var is_holding: bool = false         ## Currently holding

## Animation
var current_scale: float = 1.0
var _press_tween: Tween = null


func _ready() -> void:
	custom_minimum_size = Vector2(button_radius * 2, button_radius * 2)
	pivot_offset = size / 2.0
	_update_empty_state()


func _process(delta: float) -> void:
	# Update cooldown
	if is_on_cooldown:
		cooldown_remaining -= delta
		if cooldown_remaining <= 0.0:
			cooldown_remaining = 0.0
			is_on_cooldown = false
			ability_ready.emit(slot_index)
			Debug.log("Combat", "Ability ready", {"slot": slot_index, "ability": bound_ability_id})
		queue_redraw()

	# Check mana for abilities
	if slot_type == SlotType.ABILITY and not is_empty:
		_update_resource_check()


func _draw() -> void:
	var center := size / 2.0
	var radius := button_radius * current_scale
	var color := _get_current_color()

	# Draw button circle
	draw_circle(center, radius, color)

	# Draw border
	draw_arc(center, radius, 0, TAU, 32, border_color, border_width)

	# Draw cooldown overlay
	if is_on_cooldown and cooldown_duration > 0:
		var progress := cooldown_remaining / cooldown_duration
		# Draw from top (-PI/2) clockwise
		var sweep_angle := progress * TAU
		draw_arc(center, radius * 0.75, -PI/2, -PI/2 + sweep_angle, 24, cooldown_color, radius * 0.4)

		# Draw cooldown text
		var cd_text := "%.1f" % cooldown_remaining if cooldown_remaining < 10 else "%d" % int(cooldown_remaining)
		var font := ThemeDB.fallback_font
		var font_size := int(radius * 0.5)
		var text_size := font.get_string_size(cd_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := center - text_size / 2 + Vector2(0, text_size.y * 0.35)
		draw_string(font, text_pos, cd_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)
	else:
		# Draw icon/text
		_draw_icon(center, radius)

	# Draw mana cost indicator (small text at bottom)
	if slot_type == SlotType.ABILITY and not is_empty and ability_data.has("mana_cost"):
		var mana_cost: float = ability_data.get("mana_cost", 0)
		if mana_cost > 0:
			_draw_mana_cost(center, radius, mana_cost)


func _draw_icon(center: Vector2, radius: float) -> void:
	# Draw texture icon if available
	if icon_texture:
		var icon_size := radius * 1.4
		var icon_rect := Rect2(center - Vector2(icon_size, icon_size) / 2, Vector2(icon_size, icon_size))
		var modulate := Color.WHITE
		if not has_enough_resource:
			modulate = Color(0.7, 0.7, 0.7)
		if not has_valid_weapon:
			modulate = Color(0.5, 0.5, 0.5)
		draw_texture_rect(icon_texture, icon_rect, false, modulate)
		return

	# Fall back to text
	var display_text := icon_text if icon_text != "" else _get_default_icon()
	var font := ThemeDB.fallback_font
	var font_size := int(radius * 0.6)
	var text_size := font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := center - text_size / 2 + Vector2(0, text_size.y * 0.35)

	var text_color := Color.WHITE
	if not has_enough_resource:
		text_color = Color(0.7, 0.7, 0.7)

	draw_string(font, text_pos, display_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)


func _draw_mana_cost(center: Vector2, radius: float, cost: float) -> void:
	var cost_text := "%d" % int(cost)
	var font := ThemeDB.fallback_font
	var font_size := int(radius * 0.35)
	var text_size := font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2(center.x - text_size.x / 2, center.y + radius * 0.7)

	var cost_color := Color(0.4, 0.6, 1.0) if has_enough_resource else Color(1.0, 0.3, 0.3)
	draw_string(font, text_pos, cost_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, cost_color)


func _get_current_color() -> Color:
	if is_empty:
		return empty_color
	if is_on_cooldown:
		return cooldown_color
	if not has_valid_weapon:
		return no_weapon_color  # Gray for wrong/no weapon (highest priority)
	if not has_enough_resource:
		return no_resource_color  # Blueish for not enough mana/stamina
	if is_pressed_state:
		return pressed_color
	return normal_color


func _get_default_icon() -> String:
	match slot_type:
		SlotType.ATTACK:
			return "⚔"
		SlotType.DODGE:
			return "💨"
		SlotType.QUICK_SLOT:
			return "🧪"
		SlotType.ABILITY:
			return "✦"
	return "?"


func _update_resource_check() -> void:
	if is_empty or ability_data.is_empty():
		has_enough_resource = true
		return

	var mana_cost: float = ability_data.get("mana_cost", 0)
	var old_state := has_enough_resource
	has_enough_resource = PlayerStats.current_mana >= mana_cost

	if old_state != has_enough_resource:
		queue_redraw()


func _update_empty_state() -> void:
	match slot_type:
		SlotType.ATTACK, SlotType.DODGE:
			is_empty = false
		SlotType.ABILITY:
			is_empty = bound_ability_id == ""
		SlotType.QUICK_SLOT:
			is_empty = bound_ability_id == ""


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var local_pos := event.position - global_position
	var center := size / 2.0
	var distance := local_pos.distance_to(center)

	if event.pressed:
		if distance <= button_radius and _can_activate():
			touch_index = event.index
			_on_press()
	else:
		if event.index == touch_index:
			_on_release()


func _can_activate() -> bool:
	if is_empty and slot_type != SlotType.ATTACK:
		return false
	if is_on_cooldown:
		return false
	if not has_valid_weapon:
		return false
	if not has_enough_resource:
		return false
	return true


func _on_press() -> void:
	is_pressed_state = true
	_animate_press(true)
	queue_redraw()

	Debug.log("Combat", "Slot pressed", {"slot": slot_index, "type": SlotType.keys()[slot_type]})

	# Check if this is a hold skill (projectile type)
	# effect_type can be either a string or an enum value
	var effect_type = ability_data.get("effect_type", "")
	if effect_type is int:
		is_hold_skill = effect_type == TalentData.EffectType.PROJECTILE
	elif effect_type is String:
		is_hold_skill = effect_type.to_lower() == "projectile"
	else:
		is_hold_skill = false

	if is_hold_skill:
		# Start hold tracking
		hold_start_time = Time.get_ticks_msec() / 1000.0
		is_holding = true
		ability_hold_started.emit(slot_index, bound_ability_id)
		Debug.log("Combat", "Hold skill started", {"slot": slot_index})
	else:
		# Emit immediate activation signal for non-hold skills
		ability_activated.emit(slot_index, bound_ability_id)


func _on_release() -> void:
	# Calculate hold duration if this was a hold skill
	if is_holding and is_hold_skill:
		var current_time := Time.get_ticks_msec() / 1000.0
		var hold_duration := current_time - hold_start_time
		ability_released.emit(slot_index, bound_ability_id, hold_duration)
		Debug.log("Combat", "Hold skill released", {"slot": slot_index, "duration": hold_duration})

	is_pressed_state = false
	is_holding = false
	touch_index = -1
	_animate_press(false)
	queue_redraw()


func _animate_press(pressed: bool) -> void:
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()

	_press_tween = create_tween()
	_press_tween.set_ease(Tween.EASE_OUT)
	_press_tween.set_trans(Tween.TRANS_BACK if not pressed else Tween.TRANS_QUAD)

	var target_scale := press_scale if pressed else 1.0
	_press_tween.tween_property(self, "current_scale", target_scale, press_duration)
	_press_tween.tween_callback(queue_redraw)


## Public API

func bind_ability(ability_id: String, data: Dictionary = {}) -> void:
	bound_ability_id = ability_id
	ability_data = data

	# Try to load icon texture from icon_name
	icon_texture = null
	if data.has("icon_name"):
		icon_texture = TalentIconLoader.load_icon(data.icon_name)

	if data.has("icon"):
		icon_text = data.icon
	elif data.has("name"):
		# Use first letter as fallback
		icon_text = data.name.substr(0, 1).to_upper()
	else:
		icon_text = ""

	_update_empty_state()
	_update_resource_check()
	queue_redraw()

	Debug.log("Combat", "Ability bound", {"slot": slot_index, "ability": ability_id})


func clear_ability() -> void:
	bound_ability_id = ""
	ability_data = {}
	icon_text = ""
	icon_texture = null
	is_on_cooldown = false
	cooldown_remaining = 0.0
	_update_empty_state()
	queue_redraw()


func start_cooldown(duration: float) -> void:
	if duration <= 0:
		return

	cooldown_duration = duration
	cooldown_remaining = duration
	is_on_cooldown = true
	queue_redraw()

	Debug.log("Combat", "Cooldown started", {"slot": slot_index, "duration": duration})


func get_cooldown_progress() -> float:
	if cooldown_duration <= 0:
		return 0.0
	return cooldown_remaining / cooldown_duration


func set_icon(icon: String) -> void:
	icon_text = icon
	queue_redraw()


func set_colors(normal: Color, pressed: Color, no_resource: Color = Color.TRANSPARENT) -> void:
	normal_color = normal
	pressed_color = pressed
	if no_resource != Color.TRANSPARENT:
		no_resource_color = no_resource
	queue_redraw()


func set_radius(radius: float) -> void:
	button_radius = radius
	custom_minimum_size = Vector2(radius * 2, radius * 2)
	pivot_offset = custom_minimum_size / 2.0
	queue_redraw()


func get_hold_duration() -> float:
	## Get the current hold duration (while holding)
	if not is_holding:
		return 0.0
	var current_time := Time.get_ticks_msec() / 1000.0
	return current_time - hold_start_time


func is_currently_holding() -> bool:
	## Check if this slot is currently being held
	return is_holding


## Update weapon validity based on equipped weapon category
func update_weapon_validity(equipped_weapon_category: String) -> void:
	var old_state := has_valid_weapon

	# Get the required weapon category from ability data
	var required_cat: String = ability_data.get("required_weapon_category", "")

	if required_cat.is_empty():
		# No weapon requirement
		has_valid_weapon = true
	elif equipped_weapon_category.is_empty():
		# Weapon required but none equipped
		has_valid_weapon = false
	elif required_cat == equipped_weapon_category:
		# Exact match
		has_valid_weapon = true
	elif required_cat == "melee" and equipped_weapon_category.begins_with("melee"):
		# "melee" matches melee_1h and melee_2h
		has_valid_weapon = true
	else:
		has_valid_weapon = false

	if old_state != has_valid_weapon:
		queue_redraw()
