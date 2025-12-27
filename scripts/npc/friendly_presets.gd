extends Node
class_name FriendlyPresets
## FriendlyPresets - Factory class for creating pre-configured friendly NPCs
## Use for quick spawning of common NPC types

## Create a shopkeeper - static, interactable
static func create_shopkeeper(shop_name: String, shop_id: String) -> FriendlyNPC:
	var npc := FriendlyNPC.new()
	npc.npc_name = shop_name
	npc.npc_id = "shopkeeper_" + shop_id
	npc.is_interactable = true
	npc.interaction_radius = 50.0
	npc.shop_id = shop_id
	npc.movement_pattern = FriendlyNPC.MovementPattern.STATIC

	Debug.log("NPC", "Created Shopkeeper: %s" % shop_name, ["shop:", shop_id])
	return npc


## Create a quest giver - static, interactable with dialogue
static func create_quest_giver(npc_name: String, npc_id: String, dialogue: String) -> FriendlyNPC:
	var npc := FriendlyNPC.new()
	npc.npc_name = npc_name
	npc.npc_id = npc_id
	npc.is_interactable = true
	npc.interaction_radius = 45.0
	npc.dialogue_id = dialogue
	npc.movement_pattern = FriendlyNPC.MovementPattern.STATIC

	Debug.log("NPC", "Created Quest Giver: %s" % npc_name, ["dialogue:", dialogue])
	return npc


## Create a villager - wanders around
static func create_villager(npc_name: String, npc_id: String = "") -> FriendlyNPC:
	var npc := FriendlyNPC.new()
	npc.npc_name = npc_name
	npc.npc_id = npc_id if not npc_id.is_empty() else "villager_" + str(randi())
	npc.is_interactable = true
	npc.interaction_radius = 40.0
	npc.dialogue_id = "villager_generic"
	npc.movement_pattern = FriendlyNPC.MovementPattern.WANDER
	npc.wander_radius = 80.0
	npc.wander_interval_min = 3.0
	npc.wander_interval_max = 8.0
	npc.move_speed = 40.0

	Debug.log("NPC", "Created Villager: %s" % npc_name)
	return npc


## Create a guard - patrols between points
static func create_guard(npc_name: String, patrol: Array[Vector2]) -> FriendlyNPC:
	var npc := FriendlyNPC.new()
	npc.npc_name = npc_name
	npc.npc_id = "guard_" + str(randi())
	npc.is_interactable = true
	npc.interaction_radius = 40.0
	npc.dialogue_id = "guard_generic"
	npc.movement_pattern = FriendlyNPC.MovementPattern.PATROL
	npc.patrol_points = patrol
	npc.patrol_wait_time = 2.0
	npc.patrol_loop = true
	npc.move_speed = 60.0

	Debug.log("NPC", "Created Guard: %s" % npc_name, ["patrol_points:", patrol.size()])
	return npc


## Create a blacksmith - static shop
static func create_blacksmith() -> FriendlyNPC:
	return create_shopkeeper("Blacksmith", "blacksmith")


## Create an alchemist - static shop
static func create_alchemist() -> FriendlyNPC:
	return create_shopkeeper("Alchemist", "alchemist")


## Create a merchant - static shop
static func create_merchant() -> FriendlyNPC:
	return create_shopkeeper("Merchant", "general_goods")


## Create an innkeeper - static with dialogue
static func create_innkeeper(inn_name: String = "Inn") -> FriendlyNPC:
	var npc := FriendlyNPC.new()
	npc.npc_name = "Innkeeper"
	npc.npc_id = "innkeeper_" + inn_name.to_lower().replace(" ", "_")
	npc.is_interactable = true
	npc.interaction_radius = 45.0
	npc.dialogue_id = "innkeeper"
	npc.shop_id = "inn_services"
	npc.movement_pattern = FriendlyNPC.MovementPattern.STATIC

	Debug.log("NPC", "Created Innkeeper", ["inn:", inn_name])
	return npc


## Factory method - create NPC by type name
static func create(type: String, name_override: String = "") -> FriendlyNPC:
	var npc_name := name_override if not name_override.is_empty() else type.capitalize()

	match type.to_lower():
		"shopkeeper":
			return create_shopkeeper(npc_name, "generic_shop")
		"blacksmith":
			return create_blacksmith()
		"alchemist":
			return create_alchemist()
		"merchant":
			return create_merchant()
		"innkeeper":
			return create_innkeeper()
		"villager":
			return create_villager(npc_name)
		"guard":
			return create_guard(npc_name, [Vector2(50, 0), Vector2(-50, 0)])
		"quest_giver":
			return create_quest_giver(npc_name, "quest_" + str(randi()), "quest_generic")
		_:
			Debug.warn("NPC", "Unknown NPC type: %s, creating villager" % type)
			return create_villager(npc_name)
