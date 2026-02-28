# P1: Cache Weapon Anchor Positions

## Problem

`character_visuals.gd:_find_weapon_anchors()` runs every frame in `_process()`. It calls `tex.get_image()` (GPU→CPU readback) then scans every pixel to find 2 colored markers. This is O(width × height) per frame per visible character.

For 64×64 sprites with 6 visible characters at 60 FPS = ~1.47 million pixel reads per second.

## Fix

Lazy cache keyed by `(animation_name, frame_index)`. First miss does the pixel scan; subsequent hits return cached result. Cache cleared when sprite_frames resource changes.

### Implementation

```gdscript
# New state
var _anchor_cache: Dictionary = {}  # "anim_name:frame_idx" → Dictionary

func _find_weapon_anchors() -> Dictionary:
    # ... existing null checks ...
    var cache_key := "%s:%d" % [current_anim, current_frame_idx]
    if _anchor_cache.has(cache_key):
        return _anchor_cache[cache_key]

    # ... existing pixel scan code ...

    _anchor_cache[cache_key] = result
    return result
```

Clear cache when animation set changes:
```gdscript
func _on_sprite_frames_changed() -> void:
    _anchor_cache.clear()
```

### Expected result

- Per-frame cost: Dictionary lookup (~0.001 ms) instead of GPU readback + 4096 pixel reads (~0.5-2 ms)
- First-frame cost per unique (anim, frame): unchanged (one-time scan)
- Memory: negligible (small Dictionary of Vector2 pairs)
- Typical cache size: ~100-200 entries (all animation frames seen during play)
