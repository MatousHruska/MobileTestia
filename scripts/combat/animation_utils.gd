class_name AnimationUtils
## AnimationUtils - Shared animation name resolution with fallback chain.
##
## Single canonical implementation used by both AbilityVisualPlayer and
## CharacterVisuals to avoid duplicated fallback logic.


## Resolve an animation name with fallback chain:
## 1. "{base_name}_{direction}" (e.g., "melee_windup_down")
## 2. "{base_name}" (directionless)
## 3. "attack_{direction}" (legacy fallback)
## 4. "idle_{direction}" (final fallback)
##
## Logs a debug warning if no animation is found and the final idle fallback is used.
static func resolve_animation_name(sprite_frames: SpriteFrames, base_name: String, direction: String) -> String:
	if not sprite_frames:
		return "idle_%s" % direction

	var candidates: Array[String] = [
		"%s_%s" % [base_name, direction],
		base_name,
		"attack_%s" % direction,
		"idle_%s" % direction,
	]

	for candidate in candidates:
		if sprite_frames.has_animation(candidate):
			return candidate

	Debug.warn("AnimUtils", "No animation found for '%s' (dir=%s), falling back to idle" % [base_name, direction])
	return "idle_%s" % direction
