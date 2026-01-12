extends BaseModule
class_name TestModule
## TestModule - Simple module to verify the modular AI system works
## Logs output periodically to confirm processing is running

func _init() -> void:
	module_id = "mod_test"
	module_name = "Test Module"
	module_type = ModuleType.UTILITY
	priority = 50


func _process_module(context: EnemyContext, _delta: float) -> void:
	# Log every 60 frames to verify running
	if Engine.get_process_frames() % 60 == 0:
		print("TestModule running - owner at %s" % context.global_position)
