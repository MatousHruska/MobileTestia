extends FriendlyNPC
class_name DatabaseNPC
## DatabaseNPC - FriendlyNPC that loads all data from DatabaseLoader
## Set only the database_id to configure the entire NPC

## Database configuration
@export var database_id: String = ""  ## ID to look up in DatabaseLoader.npcs

## Loaded data
var _npc_data: Dictionary = {}


func _ready() -> void:
	if database_id.is_empty():
		Debug.warn("NPC", "DatabaseNPC has no database_id set!")
		push_error("DatabaseNPC requires database_id")
		return

	# Load data from database BEFORE calling super._ready()
	_load_from_database()

	# Now call parent _ready() which will use the loaded values
	super._ready()


## Load NPC data from database
func _load_from_database() -> void:
	_npc_data = DatabaseLoader.get_npc(database_id)

	if _npc_data.is_empty():
		Debug.warn("NPC", "NPC not found in database: %s" % database_id)
		push_error("NPC '%s' not found in database" % database_id)
		return

	# Apply data to this NPC
	npc_name = _npc_data.get("name", "Unknown NPC")
	npc_id = database_id

	# Set type-specific properties
	var npc_type: String = _npc_data.get("type", "generic")
	match npc_type:
		"quest_giver":
			dialogue_id = "quest"  ## Could load from database too
		"trader":
			shop_id = _npc_data.get("shop_inventory_id", "")
			if shop_id.is_empty():
				Debug.warn("NPC", "Trader NPC '%s' has no shop_inventory_id" % npc_name)
		"trainer":
			dialogue_id = "trainer"
		"innkeeper":
			dialogue_id = "innkeeper"
		"blacksmith":
			shop_id = _npc_data.get("shop_inventory_id", "")
			dialogue_id = "blacksmith"
		"generic":
			dialogue_id = _npc_data.get("dialogue_greeting", "")

	# Interaction settings from database
	is_interactable = _npc_data.get("is_interactable", true)
	interaction_radius = 50.0  ## Could be in database too

	# Min level requirement
	var min_level: int = _npc_data.get("min_level", 1)
	if PlayerStats.level < min_level:
		is_interactable = false
		Debug.log("NPC", "%s requires level %d (player is %d)" % [npc_name, min_level, PlayerStats.level])

	Debug.info("NPC", "Loaded NPC from database", {
		"id": database_id,
		"name": npc_name,
		"type": npc_type,
		"shop_id": shop_id,
		"dialogue_id": dialogue_id
	})


## Override interaction to use database greeting
func interact() -> void:
	if not can_interact():
		return

	# Log interaction started
	print("Interaction started with %s" % npc_name)
	Debug.info("NPC", "Interaction started", {"npc": npc_name, "id": database_id})

	# Show greeting from database
	var greeting: String = _npc_data.get("dialogue_greeting", "")
	if not greeting.is_empty():
		Debug.log("NPC", "%s says: %s" % [npc_name, greeting])
		# TODO: Show greeting in UI

	# Call parent interaction
	super.interact()


## Get NPC data for quest/shop systems
func get_npc_data() -> Dictionary:
	return _npc_data


## Get NPC faction
func get_faction() -> String:
	return _npc_data.get("faction", "neutral")


## Get sprite ID for visual systems
func get_sprite_id() -> String:
	return _npc_data.get("sprite_id", "")
