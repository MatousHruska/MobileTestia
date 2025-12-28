extends ItemData
class_name KeyData
## KeyData - Keys used to unlock doors
## The key's id must match the door's required_key_id

## Visual placeholder color for this key
@export var key_color: Color = Color(0.9, 0.75, 0.3)  # Gold/brass color


func _init() -> void:
	item_type = ItemType.KEY
	max_stack = 1
	rarity = Rarity.COMMON


## Factory to create a key
static func create(key_id: String, key_name: String, desc: String = "") -> KeyData:
	var key := KeyData.new()
	key.id = key_id
	key.item_name = key_name
	key.description = desc if desc else "A key that unlocks something."
	return key
