extends HBoxContainer
class_name StatusEffectDisplay
## StatusEffectDisplay - Container for status effect icons in the HUD
##
## Displays active status effects (DoTs, buffs, debuffs) as icons with timers
## Icons appear from the left and are removed when effects expire

## Active effect icons - keyed by effect_type
var _effect_icons: Dictionary = {}

## Spacing between icons
const ICON_SPACING := 4


func _ready() -> void:
	add_theme_constant_override("separation", ICON_SPACING)
	_connect_to_player()


func _connect_to_player() -> void:
	# Wait for player to be available
	if Game and Game.is_player_valid():
		_on_player_ready()
	elif Game:
		Game.player_spawned.connect(_on_player_spawned)


func _on_player_spawned(_player: Node2D) -> void:
	# Small delay to ensure StatusEffectManager is ready
	await get_tree().process_frame
	_on_player_ready()


func _on_player_ready() -> void:
	var player := Game.player as PlayerController
	if not player:
		return

	# Find the StatusEffectManager
	var manager := player.get_node_or_null("StatusEffectManager") as StatusEffectManager
	if manager:
		manager.effect_applied.connect(_on_effect_applied)
		manager.effect_removed.connect(_on_effect_removed)
		manager.effect_tick.connect(_on_effect_tick)
		Debug.log("UI", "StatusEffectDisplay connected to StatusEffectManager")


func _on_effect_applied(effect_type: String, duration: float) -> void:
	if effect_type in _effect_icons:
		# Refresh existing icon
		var icon: StatusEffectIcon = _effect_icons[effect_type]
		if is_instance_valid(icon):
			icon.refresh_duration(duration)
	else:
		# Create new icon
		_add_effect_icon(effect_type, duration, true)


func _on_effect_removed(effect_type: String) -> void:
	if effect_type in _effect_icons:
		var icon: StatusEffectIcon = _effect_icons[effect_type]
		if is_instance_valid(icon):
			icon.queue_free()
		_effect_icons.erase(effect_type)


func _on_effect_tick(_effect_type: String, _damage: float) -> void:
	# Could add visual feedback on tick (flash, etc.)
	pass


func _add_effect_icon(effect_type: String, duration: float, is_debuff: bool) -> void:
	var icon := StatusEffectIcon.new()
	icon.setup(effect_type, duration, is_debuff)
	add_child(icon)
	_effect_icons[effect_type] = icon

	# Connect to track when icon is freed
	icon.tree_exiting.connect(_on_icon_removed.bind(effect_type))


func _on_icon_removed(effect_type: String) -> void:
	_effect_icons.erase(effect_type)


## Public method to add a buff (for future use)
func add_buff(buff_type: String, duration: float) -> void:
	if buff_type in _effect_icons:
		var icon: StatusEffectIcon = _effect_icons[buff_type]
		if is_instance_valid(icon):
			icon.refresh_duration(duration)
	else:
		_add_effect_icon(buff_type, duration, false)


## Clear all displayed effects
func clear_all() -> void:
	for effect_type in _effect_icons.keys():
		var icon: StatusEffectIcon = _effect_icons[effect_type]
		if is_instance_valid(icon):
			icon.queue_free()
	_effect_icons.clear()
