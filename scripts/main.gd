extends Control
## Main scene script for MobileTestia
## Entry point for the mobile application

func _ready() -> void:
	print("MobileTestia initialized")
	_connect_signals()

func _connect_signals() -> void:
	var start_button = $VBoxContainer/StartButton
	if start_button:
		start_button.pressed.connect(_on_start_pressed)

func _on_start_pressed() -> void:
	print("Start button pressed")
	# TODO: Transition to game scene
