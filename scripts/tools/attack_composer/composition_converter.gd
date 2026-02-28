class_name CompositionConverter
## Converts AttackCompositionData (editor format) to AbilityVisualData (runtime format).
## Groups consecutive frames with the same weapon state into BODY_ANIM phases,
## inserts WEAPON_VISIBILITY transitions, EFFECT phases, MOVEMENT phases, and
## DAMAGE_EVENT at the appropriate points.


## Convert a specific direction of an AttackCompositionData into AbilityVisualData.
static func convert(comp: AttackCompositionData, direction: String = "down") -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = comp.composition_id
	data.display_name = comp.display_name
	data.locks_movement = comp.locks_movement

	var seq := comp.get_sequence(direction)
	var phases: Array[AbilityVisualPhase] = []
	if seq == null or seq.frames.is_empty():
		data.phases = phases
		return data
	var frames := seq.frames

	# Collect per-frame alpha masks (weapon transparency painted in the composer)
	var alpha_mask_data: Array = []
	for i in range(frames.size()):
		var frame := frames[i]
		if frame.alpha_mask != null:
			alpha_mask_data.append({
				"frame_index": i,
				"width": frame.alpha_mask.get_width(),
				"height": frame.alpha_mask.get_height(),
				"data": frame.alpha_mask.get_data(),  # PackedByteArray
			})

	# Group consecutive frames by weapon_visible state
	var groups := _group_frames_by_weapon(frames)

	var prev_weapon_visible := false  # Default: weapon hidden at start

	for group in groups:
		var start_idx: int = group["start"]
		var end_idx: int = group["end"]  # inclusive
		var weapon_visible: bool = group["weapon_visible"]

		# Insert WEAPON_VISIBILITY if state changed
		if weapon_visible != prev_weapon_visible:
			phases.append(AbilityVisualPhase.create_weapon_visibility(weapon_visible))
		prev_weapon_visible = weapon_visible

		# Collect frame timings for this group
		var frame_timings: Array = []
		var total_ms := 0
		var echo_data: Array = []
		var effect_data: Array = []
		var prev_effect_id: String = ""
		var pending_effect: Dictionary = {}
		for i in range(start_idx, end_idx + 1):
			var frame := frames[i]
			frame_timings.append(frame.duration_ms)
			total_ms += frame.duration_ms
			if frame.echo_enabled:
				echo_data.append({
					"frame_index": i,
					"count": frame.echo_count,
					"opacity_start": frame.echo_opacity_start,
					"opacity_end": frame.echo_opacity_end,
					"spacing_px": frame.echo_spacing_px,
				})
			if not frame.effect_id.is_empty():
				if frame.effect_id != prev_effect_id:
					# New effect run — flush previous pending entry
					if not pending_effect.is_empty():
						effect_data.append(pending_effect)
					pending_effect = {
						"frame_index": i,
						"effect_id": frame.effect_id,
						"anchor": frame.effect_anchor,
						"offset": frame.effect_offset,
						"rotation_deg": frame.effect_rotation_deg,
						"z_index": frame.effect_z_index,
					}
				else:
					# Same run — pick up non-default properties from later frames
					# (user may configure properties on any frame in the run)
					if frame.effect_anchor != "weapon_tip":
						pending_effect["anchor"] = frame.effect_anchor
					if frame.effect_offset != Vector2.ZERO:
						pending_effect["offset"] = frame.effect_offset
					if frame.effect_rotation_deg != 0.0:
						pending_effect["rotation_deg"] = frame.effect_rotation_deg
					if frame.effect_z_index != 2:  # CompositionFrame default
						pending_effect["z_index"] = frame.effect_z_index
			else:
				# Gap in effect — flush pending entry
				if not pending_effect.is_empty():
					effect_data.append(pending_effect)
					pending_effect = {}
			prev_effect_id = frame.effect_id
		# Flush last pending effect run
		if not pending_effect.is_empty():
			effect_data.append(pending_effect)

		# Create BODY_ANIM phase with frame_timings in context_data
		var body_dur := total_ms / 1000.0
		var body_phase := AbilityVisualPhase.create_body_anim(
			comp.animation_name, body_dur, "composed_body")
		body_phase.context_data = {
			"frame_timings": frame_timings,
			"frame_start_index": start_idx,
		}
		if not echo_data.is_empty():
			body_phase.context_data["echo_data"] = echo_data
		if not effect_data.is_empty():
			body_phase.context_data["effect_data"] = effect_data

		# Embed damage frame index if it falls within this group
		if seq.damage_frame >= start_idx and seq.damage_frame <= end_idx:
			body_phase.context_data["damage_frame"] = seq.damage_frame

		# Collect per-frame weapon z-order data (frames where weapon goes behind body)
		var weapon_behind_frames: Array = []
		for i in range(start_idx, end_idx + 1):
			if not frames[i].weapon_z_front:
				weapon_behind_frames.append(i)
		if not weapon_behind_frames.is_empty():
			body_phase.context_data["weapon_behind_frames"] = weapon_behind_frames

		# Attach alpha masks that fall within this group
		var group_masks: Array = []
		for mask_entry in alpha_mask_data:
			if mask_entry["frame_index"] >= start_idx and mask_entry["frame_index"] <= end_idx:
				group_masks.append(mask_entry)
		if not group_masks.is_empty():
			body_phase.context_data["weapon_alpha_masks"] = group_masks

		# Check if movement overlaps this group
		var move_concurrent := false
		if seq.movement_type != "" and seq.movement_start_frame >= 0 and seq.movement_end_frame >= 0:
			if seq.movement_start_frame >= start_idx and seq.movement_start_frame <= end_idx:
				move_concurrent = true

		if move_concurrent:
			# Body anim is concurrent with movement
			body_phase.concurrent = true
			phases.append(body_phase)

			var move_dur := 0.0
			for i in range(seq.movement_start_frame, mini(seq.movement_end_frame + 1, frames.size())):
				move_dur += frames[i].duration_ms
			move_dur /= 1000.0
			var move_phase := AbilityVisualPhase.create_movement(
				"toward_target", seq.movement_distance, move_dur)
			phases.append(move_phase)
		else:
			phases.append(body_phase)

	# Hide weapon at end if it was visible
	if prev_weapon_visible:
		phases.append(AbilityVisualPhase.create_weapon_visibility(false))

	# Recovery phase
	phases.append(AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"))

	data.phases = phases
	return data


## Group consecutive frames by weapon_visible state.
## Returns Array of { "start": int, "end": int, "weapon_visible": bool }
static func _group_frames_by_weapon(frames: Array[CompositionFrame]) -> Array:
	var groups: Array = []
	if frames.is_empty():
		return groups

	var current_weapon := frames[0].weapon_visible
	var start_idx := 0

	for i in range(1, frames.size()):
		if frames[i].weapon_visible != current_weapon:
			groups.append({
				"start": start_idx,
				"end": i - 1,
				"weapon_visible": current_weapon,
			})
			current_weapon = frames[i].weapon_visible
			start_idx = i

	# Last group
	groups.append({
		"start": start_idx,
		"end": frames.size() - 1,
		"weapon_visible": current_weapon,
	})

	return groups


## Generate a human-readable phase list for debugging.
static func phases_to_string(data: AbilityVisualData) -> String:
	var lines: Array[String] = []
	for i in data.phases.size():
		var p := data.phases[i]
		var desc := ""
		match p.type:
			AbilityVisualPhase.PhaseType.BODY_ANIM:
				desc = "BODY_ANIM(\"%s\", %.3fs)" % [p.anim_name, p.duration]
				if p.context_data.has("frame_timings"):
					desc += " timings=%s" % str(p.context_data["frame_timings"])
				if p.context_data.has("damage_frame"):
					desc += " dmg@%d" % p.context_data["damage_frame"]
				if p.context_data.has("weapon_behind_frames"):
					desc += " z_behind=%s" % str(p.context_data["weapon_behind_frames"])
			AbilityVisualPhase.PhaseType.MOVEMENT:
				desc = "MOVEMENT(\"%s\", %.0fpx, %.3fs)" % [p.move_direction, p.move_distance, p.duration]
			AbilityVisualPhase.PhaseType.DAMAGE_EVENT:
				desc = "DAMAGE_EVENT"
			AbilityVisualPhase.PhaseType.WEAPON_VISIBILITY:
				desc = "WEAPON_VISIBILITY(%s)" % str(p.weapon_visible)
			AbilityVisualPhase.PhaseType.EFFECT:
				desc = "EFFECT(\"%s\")" % p.effect_id
			AbilityVisualPhase.PhaseType.WAIT:
				desc = "WAIT(%.3fs)" % p.duration
			_:
				desc = "UNKNOWN"
		if p.concurrent:
			desc += " [concurrent]"
		lines.append("  %d. %s" % [i + 1, desc])
	return "\n".join(lines)
