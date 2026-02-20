extends Node2D
class_name GoldPickup
## GoldPickup - Auto-collecting gold coin dropped by enemies
## Spawns with scatter animation and auto-collects when player is near

## Gold value of this pickup
var gold_value: int = 1

## Visual
var _visual: ColorRect

## Pickup settings
const PICKUP_RADIUS: float = 30.0
const MAGNET_RADIUS: float = 50.0
const MAGNET_SPEED: float = 200.0
const COIN_SIZE: Vector2 = Vector2(8, 8)

## Scatter animation
var _scatter_velocity: Vector2 = Vector2.ZERO
var _scatter_friction: float = 3.0  # Lower = slower deceleration
var _is_scattering: bool = true
var _scatter_time: float = 0.0
const SCATTER_DURATION: float = 0.6  # Longer scatter time

## Bobbing
var _bob_time: float = 0.0
var _bob_offset: float = 0.0
const BOB_SPEED: float = 3.0
const BOB_AMOUNT: float = 2.0

## State
var _can_pickup: bool = false
var _is_being_magnetized: bool = false


func _ready() -> void:
	_setup_visual()
	_bob_offset = randf() * TAU  # Random phase for varied bobbing

	# Delay pickup ability until scatter is done
	get_tree().create_timer(SCATTER_DURATION).timeout.connect(_enable_pickup)

	add_to_group("gold_pickups")


func _setup_visual() -> void:
	_visual = ColorRect.new()
	_visual.size = COIN_SIZE
	_visual.position = -COIN_SIZE / 2
	_visual.color = Color(1.0, 0.85, 0.2)  # Gold yellow
	add_child(_visual)


func _enable_pickup() -> void:
	_can_pickup = true
	_is_scattering = false


func _physics_process(delta: float) -> void:
	# Scatter animation
	if _is_scattering:
		_scatter_time += delta
		position += _scatter_velocity * delta
		_scatter_velocity = _scatter_velocity.lerp(Vector2.ZERO, _scatter_friction * delta)

	# Bobbing animation (after scatter)
	if not _is_scattering and _visual:
		_bob_time += delta * BOB_SPEED
		_visual.position.y = (-COIN_SIZE.y / 2) + sin(_bob_time + _bob_offset) * BOB_AMOUNT

	# Check for player proximity
	if _can_pickup and Game.is_player_valid():
		var player_pos: Vector2 = Game.player.global_position
		var distance: float = global_position.distance_to(player_pos)

		# Magnet effect - pull toward player
		if distance < MAGNET_RADIUS:
			_is_being_magnetized = true
			var direction: Vector2 = (player_pos - global_position).normalized()
			var speed: float = MAGNET_SPEED * (1.0 - distance / MAGNET_RADIUS)  # Faster when closer
			position += direction * speed * delta

		# Pickup when very close
		if distance < PICKUP_RADIUS:
			_collect()


func _collect() -> void:
	Debug.info("GoldPickup", "Collecting coin", "Value: %d, Inventory gold before: %d" % [gold_value, Inventory.gold])
	Inventory.add_gold(gold_value)
	Debug.info("GoldPickup", "Coin collected", "Inventory gold after: %d" % Inventory.gold)

	# Notify LootManager that this drop was collected
	_notify_loot_manager_collected()

	# Small scale pop effect before destroying
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector2(1.5, 1.5), 0.05)
	tween.tween_property(_visual, "scale", Vector2.ZERO, 0.1)
	tween.tween_callback(queue_free)

	# Disable further processing
	_can_pickup = false
	set_physics_process(false)


## Notify LootManager when this gold is collected
func _notify_loot_manager_collected() -> void:
	var drop_id: String = get_meta("drop_id", "")
	if drop_id.is_empty():
		return

	var loot_mgr = get_node_or_null("/root/LootManager")
	if loot_mgr:
		loot_mgr.remove_drop(drop_id)
		Debug.log("GoldPickup", "Notified LootManager: drop %s collected" % drop_id)


## Set scatter direction and speed
func set_scatter(direction: Vector2, speed: float) -> void:
	_scatter_velocity = direction * speed


## Factory method to create gold at position with scatter
static func create_at(pos: Vector2, value: int, scatter_dir: Vector2 = Vector2.ZERO, scatter_speed: float = 0.0) -> GoldPickup:
	var pickup := GoldPickup.new()
	pickup.position = pos
	pickup.gold_value = value
	if scatter_dir != Vector2.ZERO:
		pickup.set_scatter(scatter_dir, scatter_speed)
	return pickup


## Spawn multiple coins with scatter effect
static func spawn_coins(parent: Node, pos: Vector2, total_gold: int, coin_count: int = 0) -> void:
	Debug.info("GoldPickup", "Spawning coins", "Total gold: %d" % total_gold)
	# Determine coin count based on gold amount if not specified
	if coin_count <= 0:
		coin_count = clampi(total_gold / 2, 3, 15)  # 3-15 coins

	var gold_per_coin: int = maxi(1, total_gold / coin_count)
	var remainder: int = total_gold - (gold_per_coin * coin_count)
	Debug.info("GoldPickup", "Coin distribution", "%d coins, %d gold each" % [coin_count, gold_per_coin])

	# Get LootManager for registration
	var loot_mgr = parent.get_node_or_null("/root/LootManager")

	for i in coin_count:
		# Random scatter direction
		var angle: float = randf() * TAU
		var scatter_dir := Vector2(cos(angle), sin(angle))
		var scatter_speed: float = randf_range(120.0, 220.0)  # Faster = fly further

		# First coin gets remainder
		var coin_value: int = gold_per_coin + (remainder if i == 0 else 0)

		var coin := GoldPickup.create_at(pos, coin_value, scatter_dir, scatter_speed)

		# Register with LootManager for chunk persistence
		if loot_mgr:
			var drop_id: String = loot_mgr.register_gold_drop(pos, coin_value)
			if not drop_id.is_empty():
				coin.set_meta("drop_id", drop_id)
				# Note: Node is set after adding to tree, so defer it
				coin.tree_entered.connect(func(): loot_mgr.set_drop_node(drop_id, coin), CONNECT_ONE_SHOT)

		parent.add_child(coin)
