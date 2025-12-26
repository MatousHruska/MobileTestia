extends CanvasLayer
class_name HUD
## HUD - Main game HUD controller
## Manages player stats display and mobile controls

## Signals
signal menu_button_pressed

## References (set in scene or found automatically)
@onready var joystick: VirtualJoystick = $Controls/JoystickArea/VirtualJoystick
@onready var attack_button: ActionButton = $Controls/ActionButtons/AttackButton
@onready var dodge_button: ActionButton = $Controls/ActionButtons/DodgeButton
@onready var health_bar: ProgressBar = $PlayerFrame/HealthBar
@onready var mana_bar: ProgressBar = $PlayerFrame/ManaBar
@onready var stamina_bar: ProgressBar = $PlayerFrame/StaminaBar
@onready var menu_button: Button = $MenuButton/Button

## Player reference
var player: PlayerController = null

## Character menu reference (set externally)
var character_menu: CharacterMenu = null


func _ready() -> void:
	Debug.info("UI", "HUD ready")
	_connect_to_game_manager()
	_setup_controls()


func _process(_delta: float) -> void:
	# Only process input when game is in PLAYING state
	if player and joystick and Game.is_playing:
		player.set_input_direction(joystick.get_direction())


func _connect_to_game_manager() -> void:
	if Game:
		Game.player_spawned.connect(_on_player_spawned)
		if Game.is_player_valid():
			_on_player_spawned(Game.player)


func _on_player_spawned(new_player: Node2D) -> void:
	if new_player is PlayerController:
		player = new_player as PlayerController
		Debug.info("UI", "HUD connected to player")


func _setup_controls() -> void:
	if attack_button:
		attack_button.pressed.connect(_on_attack_pressed)

	if dodge_button:
		dodge_button.pressed.connect(_on_dodge_pressed)

	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)


func _on_attack_pressed() -> void:
	if player and Game.can_player_attack:
		player.request_attack()


func _on_dodge_pressed() -> void:
	if player and Game.can_player_move:
		player.request_dodge()


func _on_menu_pressed() -> void:
	Debug.log("UI", "Menu button pressed")
	menu_button_pressed.emit()

	# Open character menu if available
	if character_menu:
		character_menu.toggle_menu()


## Public interface
func set_character_menu(menu: CharacterMenu) -> void:
	character_menu = menu
	Debug.info("UI", "Character menu linked to HUD")


func update_health(current: float, maximum: float) -> void:
	if health_bar:
		health_bar.max_value = maximum
		health_bar.value = current

func update_mana(current: float, maximum: float) -> void:
	if mana_bar:
		mana_bar.max_value = maximum
		mana_bar.value = current

func update_stamina(current: float, maximum: float) -> void:
	if stamina_bar:
		stamina_bar.max_value = maximum
		stamina_bar.value = current


## Debug
func print_state() -> void:
	Debug.snapshot("UI", "HUD State", {
		"player_connected": player != null,
		"joystick_active": joystick.is_pressed() if joystick else false,
		"joystick_direction": joystick.get_direction() if joystick else Vector2.ZERO,
		"menu_connected": character_menu != null,
	})
