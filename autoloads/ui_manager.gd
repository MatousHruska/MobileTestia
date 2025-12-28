extends CanvasLayer
## UIManager - Global UI manager for menus and overlays
## Instantiates menus on-demand and persists across scene changes

## Menu scene paths
const CHARACTER_MENU_SCENE := "res://scenes/ui/menu/character_menu.tscn"
const CHEST_MENU_SCENE := "res://scenes/ui/chest/chest_menu.tscn"

## Menu instances (created on-demand)
var character_menu: CharacterMenu = null
var chest_menu: ChestMenu = null


func _ready() -> void:
	layer = 100  # Always on top of game UI
	Debug.info("UI", "UIManager initialized")


## Character Menu

func open_character_menu() -> void:
	_ensure_character_menu()
	if character_menu:
		character_menu.open_menu()


func close_character_menu() -> void:
	if character_menu:
		character_menu.close_menu()


func toggle_character_menu() -> void:
	_ensure_character_menu()
	if character_menu:
		character_menu.toggle_menu()


func is_character_menu_open() -> bool:
	return character_menu != null and character_menu.is_open


func _ensure_character_menu() -> void:
	if character_menu == null:
		var scene := load(CHARACTER_MENU_SCENE)
		if scene:
			character_menu = scene.instantiate()
			add_child(character_menu)
			Debug.info("UI", "CharacterMenu instantiated")


## Chest Menu

func open_chest_menu(chest: ChestBase, contents: Dictionary) -> void:
	_ensure_chest_menu()
	if chest_menu:
		chest_menu.open_chest(chest, contents)


func close_chest_menu() -> void:
	if chest_menu:
		chest_menu.close_menu()


func is_chest_menu_open() -> bool:
	return chest_menu != null and chest_menu.visible


func _ensure_chest_menu() -> void:
	if chest_menu == null:
		var scene := load(CHEST_MENU_SCENE)
		if scene:
			chest_menu = scene.instantiate()
			add_child(chest_menu)
			Debug.info("UI", "ChestMenu instantiated")


## Utility

func is_any_menu_open() -> bool:
	return is_character_menu_open() or is_chest_menu_open()


func close_all_menus() -> void:
	close_character_menu()
	close_chest_menu()
