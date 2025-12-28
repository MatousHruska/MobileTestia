extends QuestTriggerBase
class_name NPCQuestTrigger
## Trigger that starts quests when talking to NPCs
## Attach as child of FriendlyNPC or use from dialogue system

## The NPC ID this trigger is attached to (auto-detected if parent is NPC)
@export var npc_id: String = ""

## Show quest indicator above NPC head
@export var show_indicator: bool = true

## Quest indicator node (created automatically)
var _indicator: Node2D = null

## Reference to parent NPC
var _npc: Node2D = null


func _ready() -> void:
	super._ready()
	_detect_npc()
	_setup_indicator()


func _detect_npc() -> void:
	## Auto-detect NPC from parent
	var parent := get_parent()
	if parent and parent.has_method("get") and parent.get("npc_id"):
		_npc = parent
		if npc_id.is_empty():
			npc_id = parent.npc_id
		Debug.log("Quest", "NPCQuestTrigger attached to NPC", npc_id)


func _setup_indicator() -> void:
	## Create quest indicator sprite
	if not show_indicator or not _npc:
		return

	# Simple indicator using a Label for now (replace with Sprite2D later)
	_indicator = Node2D.new()
	_indicator.name = "QuestIndicator"
	_indicator.position = Vector2(0, -24)  # Above NPC head

	var label := Label.new()
	label.text = "!"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.YELLOW)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-4, -8)
	_indicator.add_child(label)

	_npc.add_child(_indicator)
	_update_indicator()


func _process(_delta: float) -> void:
	if show_indicator and _indicator:
		_update_indicator()


func _update_indicator() -> void:
	if not _indicator:
		return

	# Check if NPC has available quests
	if not _has_quest_manager():
		_indicator.visible = false
		return

	var qm = get_node("/root/QuestManager")

	# Show "!" if NPC has new quest
	var available := qm.get_quests_for_npc(npc_id)
	# Show "?" if NPC has quest to turn in
	var turn_in := qm.has_quest_to_turn_in(npc_id)

	if turn_in:
		_indicator.visible = true
		_indicator.get_child(0).text = "?"
		_indicator.get_child(0).add_theme_color_override("font_color", Color.GOLD)
	elif not available.is_empty():
		_indicator.visible = true
		_indicator.get_child(0).text = "!"
		_indicator.get_child(0).add_theme_color_override("font_color", Color.YELLOW)
	else:
		_indicator.visible = false


func can_trigger() -> bool:
	## Check if quest can be started
	if not super.can_trigger():
		return false

	if not _has_quest_manager():
		return false

	var qm = get_node("/root/QuestManager")

	# Check if quest is available
	if qm.is_quest_active(quest_id) or qm.is_quest_completed(quest_id):
		return false

	return true


## Called when player interacts with NPC
func on_npc_interaction() -> void:
	if can_trigger():
		trigger()
