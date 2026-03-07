# Shadow Stacking Fix — Deep Investigation Plan

## Problem
Overlapping shadows stack darker. Two shadows at 30% opacity produce ~51% darkening at overlap instead of staying at 30%.

## Goal
Overlapping shadows should merge visually — the overlap area should look the same as a single shadow.

## Correct Technique
Render all shadows at **full opacity** into a shared buffer. Then composite that buffer onto the scene at the desired opacity (e.g., 30%). Full-alpha shadows merge to full-alpha (max(1.0, 1.0) = 1.0), so overlaps don't darken further.

---

## Architecture Context

### Scene Tree Structure
```
Root
└── MainGame (main_game.tscn)
    └── SubViewportContainer
        └── SubViewport (768×432)          ← game_viewport
            ├── world_root (Node2D)        ← zones loaded here
            │   └── Zone (y_sort_enabled)
            │       ├── Player
            │       │   ├── AnimatedSprite2D (position.y = -20)
            │       │   │   └── SilhouetteShadow (show_behind_parent)
            │       │   └── CharacterVisuals
            │       ├── NPC
            │       │   ├── AnimatedSprite2D (position.y = -20)
            │       │   │   └── SilhouetteShadow
            │       │   └── CharacterVisuals
            │       └── Decoration (from decoration_spawner)
            │           └── Sprite2D
            │               └── SilhouetteShadow
            ├── ZoneAmbient (CanvasModulate)
            └── ZoneBloom (WorldEnvironment)
```

### Key Constraints
- **DualViewportManager**: Game world is inside a `SubViewport` (768×432). `get_viewport()` for any game node returns this SubViewport, NOT the root viewport.
- **Y-sort**: Zone root has `y_sort_enabled = true`. Shadows use `show_behind_parent = true` and inherit their parent's y-sort position. Any solution must preserve y-sort ordering OR accept that all shadows render below all sprites.
- **Shader overrides self_modulate**: The silhouette shader writes `COLOR = vec4(...)` in fragment(), which discards the initial `COLOR` value. Since `self_modulate` is applied as the initial `COLOR`, it has no effect when a custom shader is active.
- **Per-direction masks**: Shadows use `shadow_mask` + `frame_uv_rect` uniforms to sample per-direction alpha masks from atlas UVs. Any buffer-based solution must preserve this.

### Previous CanvasGroup Failures (3 Attempts)

**Attempt 1**: Reparented shadows into a CanvasGroup added to the SubViewport directly.
- Result: Shadows solid black (100% opaque, not invisible).
- Likely cause: Shadows rendered at full alpha into CanvasGroup buffer. `self_modulate` on CanvasGroup had no effect because children use custom shader. No material was applied to the CanvasGroup itself to reduce opacity.

**Attempt 2**: Added CanvasGroup to `game_viewport` (SubViewport) with a shader material for group opacity.
- Result: Shadows invisible.
- Hypothesis: CanvasGroup inside SubViewport may not composite correctly, or the CanvasGroup was not in the right z-order/layer.

**Attempt 3**: Added CanvasGroup to zone root (y_sort_enabled node), with shader material, `fit_margin=200`, `z_index=-10`.
- Result: Shadows invisible.
- Hypothesis: CanvasGroup inside y_sort_enabled parent may have rendering issues, or the shader/material was misconfigured.

**Root cause unknown.** We never isolated whether the problem is:
1. CanvasGroup + SubViewport incompatibility
2. CanvasGroup + y_sort_enabled incompatibility
3. CanvasGroup + custom shader on children
4. CanvasGroup material/self_modulate misconfiguration
5. Reparenting breaking texture references or transform chain
6. Something else entirely

---

## Phase 1: Minimal CanvasGroup Repro (Standalone)

**Goal**: Confirm CanvasGroup works at all, in isolation, before testing inside the game.

### Step 1: Standalone CanvasGroup test
Create `scenes/test/canvas_group_test.tscn`:
- Root: `Node2D`
- Child: `CanvasGroup` named "ShadowGroup"
  - `self_modulate.a = 0.3`
- Two overlapping `ColorRect` children inside ShadowGroup (e.g., 100×100, offset 50px)
  - Both solid black

Run with F6. Expected: two overlapping black rects at 30% opacity, overlap area same darkness as single rect.

**If this fails**: CanvasGroup basics are broken in our Godot version — skip to Phase 2 Approach B/C.

### Step 2: CanvasGroup + custom shader on children
Same scene, but add a ShaderMaterial to each ColorRect:
```gdshader
shader_type canvas_item;
void fragment() {
    COLOR = vec4(0.0, 0.0, 0.0, 1.0);
}
```
CanvasGroup still has `self_modulate.a = 0.3`.

Expected: Same result as Step 1.

**If children go invisible or opaque**: The custom shader discards the CanvasGroup's modulation. This would explain Attempt 1 (opaque) if self_modulate was being ignored.

### Step 3: CanvasGroup + shader material on the group itself
Replace `self_modulate` with a ShaderMaterial on the CanvasGroup:
```gdshader
shader_type canvas_item;
uniform float group_opacity = 0.3;
void fragment() {
    vec4 c = texture(TEXTURE, UV);
    COLOR = vec4(c.rgb, c.a * group_opacity);
}
```
Children still have their custom shader from Step 2.

Expected: Overlapping area at 30%, no stacking.

**This tests whether a material on the CanvasGroup controls the final buffer opacity.**

### Step 4: CanvasGroup inside a SubViewport
Create `scenes/test/canvas_group_viewport_test.tscn`:
- Root: `Control` (or Node2D)
- Child: `SubViewportContainer` (size 768×432)
  - Child: `SubViewport` (size 768×432)
    - Child: `CanvasGroup` (whichever configuration worked from Steps 1-3)
      - Two overlapping ColorRects with custom shaders

Run with F6. Expected: Same visual as standalone.

**If shadows disappear here**: The SubViewport is the problem. Document exactly what changes.

### Step 5: CanvasGroup inside y_sort_enabled parent
Same as Step 4, but add a `Node2D` with `y_sort_enabled = true` between the SubViewport and the CanvasGroup:
```
SubViewport → Node2D(y_sort) → CanvasGroup → children
```

**If shadows disappear here**: y_sort_enabled is the problem. Try placing CanvasGroup as sibling of the y_sort node instead.

### Step 6: CanvasGroup with actual SilhouetteShadow shader
Replace the simple black shader with the real `silhouette_shadow.gdshader`, using a static texture and shadow_mask. Test inside SubViewport + y_sort.

**Deliverable**: A table showing which combinations work:

| CanvasGroup config | Standalone | + Shader children | + CG material | + SubViewport | + y_sort | + real shader |
|---|---|---|---|---|---|---|
| self_modulate | ? | ? | N/A | ? | ? | ? |
| ShaderMaterial | N/A | N/A | ? | ? | ? | ? |

---

## Phase 2: Implement Working Solution

Based on Phase 1 findings, implement one of these approaches:

### Approach A: CanvasGroup (if Phase 1 identifies working config)

- All SilhouetteShadow nodes reparented into a shared CanvasGroup at runtime
- Shadow shader outputs full-alpha black (change `shadow_color.a` to 1.0 inside shader, or set uniform to `Color(0,0,0,1)`)
- CanvasGroup opacity controlled by whichever mechanism worked in Phase 1
- Shadow nodes track original parent's `global_position` each frame (since they're no longer children)
- CanvasGroup placed at the correct tree position per Phase 1 findings

**Y-sort consideration**: If CanvasGroup must be outside y_sort, all shadows render at the same z-layer (below everything). This is acceptable for ground shadows but means shadows won't interleave with sprites. Confirm with user.

**Reparenting details**:
- `SilhouetteShadow._ready()`: find or create the shared CanvasGroup, reparent self into it
- Store reference to original parent to track position
- `_process()`: `global_position = _original_parent.global_position + _calculated_offset`
- On `_exit_tree()` of original parent: queue_free the shadow too

### Approach B: Dedicated Shadow SubViewport

If CanvasGroup doesn't work inside the game's SubViewport:

- Create a second `SubViewport` (768×432) dedicated to shadows
- All shadows render into this viewport at full alpha
- A `TextureRect` or `Sprite2D` displays the shadow viewport's texture at reduced opacity
- This display node sits inside the game SubViewport at `z_index = -1`
- Shadow viewport camera mirrors game camera position/zoom every frame

**Pros**: Complete control. Guaranteed no stacking. Works regardless of CanvasGroup bugs.
**Cons**: Extra viewport = extra draw calls. Camera sync complexity. Shadows won't interleave with y-sorted sprites.

**Implementation sketch**:
```
game_viewport (SubViewport 768×432)
├── ShadowDisplay (Sprite2D, z_index=-1, modulate.a=0.3)
│   └── texture = shadow_viewport.get_texture()
├── world_root
│   └── Zone (y_sort)
│       └── sprites (NO shadow children)
└── shadow_viewport (SubViewport 768×432, transparent_bg=true)
    └── shadow copies (full alpha, positioned to match parent sprites)
```

Camera sync: Each frame, copy `game_viewport.get_camera_2d().global_position` to a Camera2D inside `shadow_viewport`.

### Approach C: Screen-Space Max-Blend Shader

Keep shadows where they are (as children of sprites). Change the blend mode so overlapping shadows don't add up.

**Concept**: Instead of alpha blending (which accumulates), use a shader that reads the screen behind the shadow and applies `max(existing_darkness, shadow_darkness)`.

```gdshader
shader_type canvas_item;
render_mode blend_disabled; // We handle blending manually

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.3);
uniform sampler2D shadow_mask : hint_default_white;
uniform vec4 frame_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    float a = texture(TEXTURE, UV).a;
    vec2 mask_uv = (UV - frame_uv_rect.xy) / frame_uv_rect.zw;
    float m = texture(shadow_mask, mask_uv).r;
    float shadow_a = shadow_color.a * a * m;

    vec4 screen = texture(screen_texture, SCREEN_UV);
    // Darken: multiply screen by (1 - shadow_a)
    // But use max with existing darkness to prevent stacking
    vec3 darkened = screen.rgb * (1.0 - shadow_a);
    COLOR = vec4(darkened, screen.a);
}
```

**Problem**: `SCREEN_TEXTURE` reads the framebuffer as rendered so far. If shadow A renders first and darkens the screen, shadow B reads the already-darkened screen and darkens further — stacking still happens because draw order matters.

**Possible fix**: Use a two-pass approach or a separate buffer. But this gets complicated.

**Pros**: No reparenting. Shadows stay as children, y-sort preserved.
**Cons**: `SCREEN_TEXTURE` is expensive. Draw-order-dependent stacking still possible. May not work in SubViewport.

**Verdict**: Approach C is risky. Only attempt if A and B both fail.

---

## Phase 3: Integration

### Step 1: Update SilhouetteShadow
Apply the chosen approach. Key changes depend on approach:
- **A**: Add reparenting logic, position tracking, CanvasGroup creation
- **B**: Add shadow viewport management, camera sync, shadow mirroring
- **C**: Swap shader, add screen_texture sampling

### Step 2: Update EnvironmentManager
`_apply_shadow_params()` currently sets `shadow_color` uniform per-shadow. With buffer approaches (A/B), opacity moves to the CanvasGroup/display node. The uniform should be `Color(0,0,0,1)` and opacity is on the group.

### Step 3: Verify Pipeline Preview
The sprite pipeline's shadow preview (Step 6 in `sprite_pipeline.gd`) runs in its own SubViewport. It should continue using per-shadow opacity since it only shows one shadow at a time. No changes needed unless the shader changes break single-shadow rendering.

### Step 4: Test All Shadow Types
- Player character shadow (AnimatedSprite2D, per-direction, flip_h)
- NPC/enemy shadows (AnimatedSprite2D via BaseCharacter)
- Decoration shadows (static Sprite2D, from decoration_spawner)
- Overlapping: player + decoration, player + NPC, decoration + decoration
- Zone transitions: shadows cleaned up when zone changes (DualViewportManager.clear_world)

### Step 5: Commit
Single commit with the working anti-stacking solution.

---

## Decision Tree Summary

```
Phase 1 Results → Decision
─────────────────────────
CanvasGroup works in SubViewport + y_sort → Approach A (CanvasGroup)
CanvasGroup works in SubViewport only    → Approach A (place outside y_sort)
CanvasGroup fails in SubViewport         → Approach B (Shadow SubViewport)
Both A and B fail                        → Approach C (Screen-space) or rethink
```

## Estimated Effort
- Phase 1 (investigation): Create test scenes, run each, document results
- Phase 2 (implementation): Depends on which approach — A is simplest, B is most work
- Phase 3 (integration): Wire into existing systems, test all combinations
