extends RefCounted
## Player settings, saved to user://settings.cfg. No autoload (autoloads can't ship in
## an update pack) — everything is static; use preload("res://main/settings.gd").

const PATH := "user://settings.cfg"

static var loaded := false
static var fullscreen := false
static var sensitivity := 0.06
static var fov := 75.0
static var volume := 100.0
static var map_light := "sunny" # "sunny" (training-lab sun) | "soft" (no sun, ambient only)

static func load_cfg() -> void:
	if loaded: return
	loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		fullscreen = cfg.get_value("video", "fullscreen", false)
		sensitivity = cfg.get_value("input", "sensitivity", 0.06)
		fov = cfg.get_value("video", "fov", 75.0)
		volume = cfg.get_value("audio", "volume", 100.0)
		map_light = cfg.get_value("video", "map_light", "sunny")
	apply_global()

static func save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("video", "map_light", map_light)
	cfg.save(PATH)

static func apply_global() -> void:
	var mode := DisplayServer.window_get_mode()
	if fullscreen and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(volume, 0.0, 100.0) / 100.0))
	AudioServer.set_bus_mute(bus, volume <= 0.5)

## Builds the settings panel UI. Call from the menu or the pause screen.
static func make_panel() -> PanelContainer:
	load_cfg()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	v.add_child(title)
	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	fs.button_pressed = fullscreen
	fs.toggled.connect(func(on):
		fullscreen = on
		apply_global()
		save_cfg())
	v.add_child(fs)
	v.add_child(_slider_row("Mouse sensitivity", 0.01, 0.2, 0.005, sensitivity, "%.3f",
		func(val): sensitivity = val))
	v.add_child(_slider_row("Field of view", 60.0, 100.0, 1.0, fov, "%.0f",
		func(val): fov = val))
	v.add_child(_slider_row("Volume", 0.0, 100.0, 1.0, volume, "%.0f",
		func(val):
			volume = val
			apply_global()))
	var ml_row := HBoxContainer.new()
	var ml_lbl := Label.new()
	ml_lbl.text = "Map lighting"
	ml_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ml_row.add_child(ml_lbl)
	var ml := OptionButton.new()
	ml.add_item("Sunny (like training)", 0)
	ml.add_item("Soft (no sun)", 1)
	ml.selected = 1 if map_light == "soft" else 0
	ml.item_selected.connect(func(i):
		map_light = "soft" if i == 1 else "sunny"
		save_cfg())
	ml_row.add_child(ml)
	v.add_child(ml_row)
	return panel

static func _slider_row(text: String, minv: float, maxv: float, step: float, value: float, fmt: String, on_change: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var val_lbl := Label.new()
	val_lbl.text = fmt % value
	row.add_child(val_lbl)
	box.add_child(row)
	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.value = value
	slider.value_changed.connect(func(val):
		val_lbl.text = fmt % val
		on_change.call(val)
		save_cfg())
	box.add_child(slider)
	return box
