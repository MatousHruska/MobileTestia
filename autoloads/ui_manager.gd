extends CanvasLayer
## UIManager - Global UI manager for menus and overlays
## Instantiates menus on-demand and persists across scene changes

## Menu scene paths
const CHARACTER_MENU_SCENE := "res://scenes/ui/menu/character_menu.tscn"
const CHEST_MENU_SCENE := "res://scenes/ui/chest/chest_menu.tscn"

## Menu instances (created on-demand)
var character_menu: CharacterMenu = null
var chest_menu: ChestMenu = null

## Quest UI instances
var quest_reward_popup = null  # QuestRewardPopup
var quest_debug_overlay = null  # QuestDebugOverlay

## Debug overlay instances
var talent_debug_overlay = null  # TalentDebugOverlay


func _ready() -> void:
	layer = 100  # Always on top of game UI
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep processing when game is paused
	Debug.info("UI", "UIManager initialized")

	# Create quest UI elements
	call_deferred("_setup_quest_ui")


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


## Quest UI

func _setup_quest_ui() -> void:
	# Create reward popup
	var reward_popup_script = load("res://scripts/ui/quest/reward_popup.gd")
	if reward_popup_script:
		quest_reward_popup = reward_popup_script.new()
		quest_reward_popup.name = "QuestRewardPopup"
		add_child(quest_reward_popup)
		Debug.info("UI", "QuestRewardPopup created")

	# Create debug overlay
	var debug_overlay_script = load("res://scripts/quests/quest_debug_overlay.gd")
	if debug_overlay_script:
		quest_debug_overlay = debug_overlay_script.new()
		quest_debug_overlay.name = "QuestDebugOverlay"
		add_child(quest_debug_overlay)
		Debug.info("UI", "QuestDebugOverlay created")

	# Create talent debug overlay
	var talent_overlay_script = load("res://scripts/ui/debug/talent_debug_overlay.gd")
	if talent_overlay_script:
		talent_debug_overlay = talent_overlay_script.new()
		talent_debug_overlay.name = "TalentDebugOverlay"
		add_child(talent_debug_overlay)
		Debug.info("UI", "TalentDebugOverlay created")


func toggle_quest_debug() -> void:
	if quest_debug_overlay and quest_debug_overlay.has_method("toggle"):
		quest_debug_overlay.toggle()


func toggle_talent_debug() -> void:
	if talent_debug_overlay and talent_debug_overlay.has_method("toggle"):
		talent_debug_overlay.toggle()


## Utility

func is_any_menu_open() -> bool:
	return is_character_menu_open() or is_chest_menu_open()


func close_all_menus() -> void:
	close_character_menu()
	close_chest_menu()
