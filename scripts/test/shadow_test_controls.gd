extends Control

var _shadows: Array[SilhouetteShadow] = []
var _values_label: Label
var _sun_active := false

func _ready() -> void:
	_find_shadows(get_parent())

	var panel := PanelContainer.new()
	panel.position = Vector2(10, 10)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 0)
	panel.add_child(vbox)

	# --- Sun simulation ---
	var sun_sep := HSeparator.new()
	vbox.add_child(sun_sep)

	var sun_label := Label.new()
	sun_label.text = "☀ Sun Simulation"
	sun_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(sun_label)

	_add_slider(vbox, "SunTime", 0.0, 1.0, 0.0, 0.01)

	var sun_btn := Button.new()
	sun_btn.text = "Auto Sun: OFF"
	sun_btn.name = "SunToggle"
	vbox.add_child(sun_btn)
	sun_btn.pressed.connect(_toggle_auto_sun)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	var manual_label := Label.new()
	manual_label.text = "Manual Overrides"
	manual_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(manual_label)

	# --- Manual sliders ---
	_add_slider(vbox, "Length", 0.1, 3.0, 1.0, 0.05)
	_add_slider(vbox, "Angle", -3.14, 3.14, 0.5, 0.05)
	_add_slider(vbox, "OffsetX", -100.0, 100.0, 0.0, 1.0)
	_add_slider(vbox, "OffsetY", -100.0, 100.0, 0.0, 1.0)
	_add_slider(vbox, "Opacity", 0.0, 1.0, 0.3, 0.05)
	_add_slider(vbox, "Overlap", 0.0, 0.5, 0.25, 0.01)

	_values_label = Label.new()
	_values_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_values_label)

	_update_label()


func _find_shadows(node: Node) -> void:
	if node is SilhouetteShadow:
		_shadows.append(node as SilhouetteShadow)
	for child in node.get_children():
		_find_shadows(child)


func _add_slider(parent: VBoxContainer, label_text: String, min_val: float, max_val: float, default: float, step: float) -> void:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(60, 0)
	label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = default
	slider.custom_minimum_size = Vector2(170, 0)
	slider.name = label_text
	hbox.add_child(slider)

	var val_label := Label.new()
	val_label.text = "%.2f" % default
	val_label.custom_minimum_size = Vector2(50, 0)
	val_label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(val_label)

	slider.value_changed.connect(func(val: float) -> void:
		val_label.text = "%.2f" % val
		_on_slider_changed()
	)


func _on_slider_changed() -> void:
	var params := _get_sun_params() if _sun_active else {
		"length": _get_slider_value("Length"),
		"angle": _get_slider_value("Angle"),
		"offset_x": _get_slider_value("OffsetX"),
		"offset_y": _get_slider_value("OffsetY"),
		"opacity": _get_slider_value("Opacity"),
		"overlap": _get_slider_value("Overlap"),
	}
	for shadow in _shadows:
		shadow.apply_params(params)
	_update_label()


## Compute shadow angle from a 0-1 sun time value.
## 0.0 = sunrise (east), 0.5 = noon, 1.0 = sunset (west).
## Only the angle changes — length, opacity, etc. stay manual.
func _get_sun_params() -> Dictionary:
	var t := _get_slider_value("SunTime")
	# Angle sweeps from ~135 deg (shadow right) at sunrise to ~45 deg (shadow left) at sunset
	var sun_angle := lerpf(PI * 0.75, PI * 0.25, t)
	return {
		"angle": sun_angle,
		"length": _get_slider_value("Length"),
		"offset_x": _get_slider_value("OffsetX"),
		"offset_y": _get_slider_value("OffsetY"),
		"opacity": _get_slider_value("Opacity"),
		"overlap": _get_slider_value("Overlap"),
	}


func _toggle_auto_sun() -> void:
	_sun_active = !_sun_active
	var btn := find_child("SunToggle", true, false) as Button
	if btn:
		btn.text = "Auto Sun: ON" if _sun_active else "Auto Sun: OFF"
	_on_slider_changed()


func _get_slider_value(slider_name: String) -> float:
	var slider := find_child(slider_name, true, false) as HSlider
	if slider:
		return slider.value
	return 0.0


func _update_label() -> void:
	if _shadows.is_empty():
		return
	var s := _shadows[0]
	var mode_text := "Mode: SUN (t=%.2f)" % _get_slider_value("SunTime") if _sun_active else "Mode: MANUAL"
	var time_hint := ""
	if _sun_active:
		var t := _get_slider_value("SunTime")
		if t < 0.15:
			time_hint = " (sunrise)"
		elif t < 0.35:
			time_hint = " (morning)"
		elif t < 0.65:
			time_hint = " (noon)"
		elif t < 0.85:
			time_hint = " (afternoon)"
		else:
			time_hint = " (sunset)"
	_values_label.text = "%s%s\nshadow_length = %.2f\nshadow_angle = %.2f\nshadow_offset_x = %.1f\nshadow_offset_y = %.1f\nshadow_opacity = %.2f\nshadow_overlap = %.2f" % [
		mode_text, time_hint, s.shadow_length, s.shadow_angle, s.shadow_offset_x, s.shadow_offset_y, s.shadow_opacity, s.shadow_overlap
	]
