class_name AbilityVisualData
extends Resource
## AbilityVisualData - Defines a visual template for an ability.
##
## A named sequence of AbilityVisualPhase resources that describe exactly
## what happens visually when an ability is used: body animations, movements,
## damage events, projectile spawns, weapon visibility changes, and VFX.
##
## Saved as .tres files or constructed in code via AbilityVisualTemplates.

## Unique template ID (e.g., "melee_single", "spell_cast", "throw")
@export var template_id: String = ""

## Human-readable name for editor/debug
@export var display_name: String = ""

## The sequence of phases (executed in order)
@export var phases: Array[AbilityVisualPhase] = []

## Whether the character is movement-locked for the entire sequence
## (individual phases can override this)
@export var locks_movement: bool = true
