extends Resource
class_name CombatHUDConfig
## CombatHUDConfig - Configuration resource for combat HUD layout
##
## Structure:
##   CombatHUD
##   ├── AbilityWheel (positioned via ability_wheel_anchor_pct)
##   │   ├── AttackButton (center of wheel)
##   │   └── AbilitySlots[1-5] (arc around attack)
##   ├── UtilityBar (positioned via utility_bar_anchor_pct)
##   │   ├── DodgeButton (right side)
##   │   └── QuickSlotButton (left side, with gap)
##   └── InteractButton
##
## Positioning hierarchy:
##   1. Groups (AbilityWheel, UtilityBar) positioned relative to screen via anchor_pct
##   2. Buttons within groups positioned relative to each other
##
## Uses percentage-based positioning for multi-device support
## All anchor values are percentages (0.0 to 1.0) from bottom-right corner

#region AbilityWheel Group
@export_group("AbilityWheel: Group Position")
## Anchor point for AbilityWheel center, as percentage from bottom-right corner
@export var ability_wheel_anchor_pct: Vector2 = Vector2(0.12, 0.18)

@export_group("AbilityWheel: Attack Button")
@export var attack_radius: float = 30.0
@export var attack_color: Color = Color(0.98, 0.6, 0.6, 0.85)
@export var attack_pressed_color: Color = Color(1.0, 0.8, 0.8, 0.95)

@export_group("AbilityWheel: Ability Slots")
@export var ability_count: int = 5
@export var ability_radius: float = 12.0
@export var ability_color: Color = Color(0.55, 1.0, 0.98, 0.85)
@export var ability_pressed_color: Color = Color(0.75, 1.0, 1.0, 0.95)
@export var ability_no_mana_color: Color = Color(0.3, 0.3, 0.5, 0.7)
@export var ability_cooldown_color: Color = Color(0.2, 0.2, 0.2, 0.6)
## Distance from attack button center as percentage of screen height
@export var arc_distance_pct: float = 0.17
## Arc angles in degrees (0 = right, 90 = down, 180 = left, 270 = up)
@export var arc_start_angle: float = 155.0
@export var arc_end_angle: float = 295.0
#endregion

#region UtilityBar Group
@export_group("UtilityBar: Group Position")
## Anchor point for UtilityBar center, as percentage from bottom-right corner
@export var utility_bar_anchor_pct: Vector2 = Vector2(0.41, 0.12)
## Gap between Dodge and QuickSlot buttons (in base pixels, will be scaled)
@export var utility_bar_gap: float = 8.0

@export_group("UtilityBar: Dodge Button")
@export var dodge_radius: float = 16.0
@export var dodge_color: Color = Color(0.38, 0.27, 1.0, 0.85)
@export var dodge_pressed_color: Color = Color(0.55, 0.45, 1.0, 0.95)
@export var dodge_no_stamina_color: Color = Color(0.3, 0.3, 0.4, 0.7)

@export_group("UtilityBar: Quick Slot")
@export var quick_slot_radius: float = 16.0
@export var quick_slot_color: Color = Color(0.51, 1.0, 0.37, 0.85)
@export var quick_slot_pressed_color: Color = Color(0.7, 1.0, 0.6, 0.95)
@export var quick_slot_empty_color: Color = Color(0.3, 0.4, 0.3, 0.5)
#endregion

#region Interact Button
@export_group("Interact Button")
## Offset from bottom-right corner as percentage
@export var interact_offset_pct: Vector2 = Vector2(0.18, 0.45)
@export var interact_size: Vector2 = Vector2(32, 13)
#endregion

@export_group("Visual Feedback")
## Scale multiplier when button is pressed
@export var press_scale: float = 0.9
## Duration of press animation in seconds
@export var press_animation_duration: float = 0.08
## Border/outline width
@export var button_border_width: float = 0.5
@export var button_border_color: Color = Color(1.0, 1.0, 1.0, 0.4)

@export_group("Scaling")
## Reference screen height for scaling calculations (270p pixel art viewport)
@export var base_screen_height: float = 270.0
@export var min_scale: float = 1.0
@export var max_scale: float = 4.0
## User-adjustable scale multiplier (1.0 = default)
@export var user_scale: float = 1.0

@export_group("Layout Options (Stubs)")
## Left-handed mode mirrors the layout
@export var left_handed_mode: bool = false
## Layout preset name
@export var layout_preset: String = "default"


## Convert percentage offset to pixel position from bottom-right
func get_position_from_pct(offset_pct: Vector2, screen_size: Vector2) -> Vector2:
	return Vector2(
		screen_size.x - (offset_pct.x * screen_size.x),
		screen_size.y - (offset_pct.y * screen_size.y)
	)


## Get arc distance in pixels based on screen height
func get_arc_distance(screen_height: float) -> float:
	return arc_distance_pct * screen_height


## Calculate ability button positions around the attack button
func get_ability_positions(attack_center: Vector2, screen_height: float) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var arc_distance := get_arc_distance(screen_height)

	if ability_count <= 1:
		# Single ability goes at the middle of the arc
		var angle_rad := deg_to_rad((arc_start_angle + arc_end_angle) / 2.0)
		var offset := Vector2(cos(angle_rad), sin(angle_rad)) * arc_distance
		positions.append(attack_center + offset)
		return positions

	var angle_step := (arc_end_angle - arc_start_angle) / float(ability_count - 1)

	for i in ability_count:
		var angle_deg := arc_start_angle + (angle_step * float(i))
		var angle_rad := deg_to_rad(angle_deg)
		var offset := Vector2(cos(angle_rad), sin(angle_rad)) * arc_distance
		positions.append(attack_center + offset)

	return positions


## Get scale factor based on screen size
func get_screen_scale() -> float:
	var screen_height := DisplayServer.window_get_size().y
	var scale := float(screen_height) / base_screen_height
	scale = clampf(scale * user_scale, min_scale, max_scale)
	return scale


## Apply left-handed mode transformation to a position
func apply_handedness(pos: Vector2, screen_width: float) -> Vector2:
	if left_handed_mode:
		# Mirror horizontally
		return Vector2(screen_width - pos.x, pos.y)
	return pos


## Get AbilityWheel center position in screen coordinates
func get_ability_wheel_center(screen_size: Vector2) -> Vector2:
	var pos := get_position_from_pct(ability_wheel_anchor_pct, screen_size)
	return apply_handedness(pos, screen_size.x)


## Get UtilityBar center position in screen coordinates
func get_utility_bar_center(screen_size: Vector2) -> Vector2:
	var pos := get_position_from_pct(utility_bar_anchor_pct, screen_size)
	return apply_handedness(pos, screen_size.x)


## Get scaled gap for UtilityBar buttons
func get_utility_bar_gap(scale_factor: float) -> float:
	return utility_bar_gap * scale_factor
