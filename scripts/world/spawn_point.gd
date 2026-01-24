extends Marker2D
class_name SpawnPoint
## SpawnPoint - Marks where players/entities can spawn in a zone

## Unique ID for this spawn point
@export var spawn_id: String = "default"

## Visual color for editor
@export var marker_color: Color = Color(0.2, 0.8, 0.2, 0.8)

## Size of visual marker
@export var marker_size: float = 16.0


func _ready() -> void:
	# Add to group for easy lookup
	add_to_group("spawn_points")
	Debug.log("Zone", "Spawn point ready: %s at %s" % [spawn_id, global_position])


func _draw() -> void:
	# Draw a visible marker in editor and debug
	draw_circle(Vector2.ZERO, marker_size / 2, marker_color)
	draw_circle(Vector2.ZERO, marker_size / 4, Color.WHITE)


func _process(_delta: float) -> void:
	# Only redraw in editor
	if Engine.is_editor_hint():
		queue_redraw()
