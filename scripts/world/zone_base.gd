extends Node2D
class_name ZoneBase
## ZoneBase - Base script for game zones
## Handles common zone setup like linking HUD to menu

@export var zone_name: String = "Unknown Zone"

## Auto-find references
@onready var hud: HUD = $HUD
@onready var character_menu: CharacterMenu = $CharacterMenu


func _ready() -> void:
	Debug.info("System", "Zone loaded", zone_name)

	# Link HUD to character menu
	if hud and character_menu:
		hud.set_character_menu(character_menu)
		Debug.log("System", "HUD linked to CharacterMenu")

	# Notify game manager
	Game.current_zone = zone_name

	# Add starting items from database
	Inventory.add_starting_items()
