# Silhouette Shadow System — Design Document

**Date:** 2026-03-04
**Status:** Approved (prototype phase)
**Goal:** Create a projected silhouette shadow system where 2D sprites cast ground shadows based on a global light direction.

## Approach

- Duplicate sprite as a child Sprite2D ("ShadowSprite")
- Shader converts all opaque pixels to flat shadow color (~0.3 alpha black)
- Node2D.skew shears the shadow onto the ground plane
- Shadow is flipped vertically and positioned at sprite base
- z_index = -1 to render behind decoration

## Prototype

- Test scene: `scenes/test/shadow_test.tscn`
- Shader: `shaders/silhouette_shadow.gdshader`
- Script: `scripts/environment/silhouette_shadow.gd`
- Uses pinetree2 decoration asset for testing
- Fixed shadow direction (lower-right, matching reference image)
