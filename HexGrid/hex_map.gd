extends Node3D

var camera: Camera3D
var _terrain: Node3D = null
var _label: Label
var _menu: Control
var _height_slider: HSlider
var _height_label: Label
var _grid_slider: HSlider
var _grid_label: Label
var _radius_slider: HSlider
var _radius_label: Label
var _step_slider: HSlider
var _step_label: Label
var _exp_slider: HSlider
var _exp_label: Label

var cam_yaw: float = 45.0
var cam_pitch: float = -55.0
var cam_dist: float = 300.0
var cam_pivot: Vector3 = Vector3.ZERO
var orbiting: bool = false
var orbit_start: Vector2 = Vector2.ZERO
var orbit_yaw_start: float = 0.0
var orbit_pitch_start: float = 0.0
var panning: bool = false
var pan_start: Vector2 = Vector2.ZERO
var pan_origin: Vector3 = Vector3.ZERO

var _current_approach: String = ""

func _ready() -> void:
	_setup_lighting()
	_setup_camera()
	_setup_ui()
	_update_camera_transform()
	print("Ready. Pick an approach from the menu.")


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("rmb") and not orbiting:
		orbiting = true
		orbit_start = get_viewport().get_mouse_position()
		orbit_yaw_start = cam_yaw
		orbit_pitch_start = cam_pitch
	if Input.is_action_just_pressed("lmb") and not panning:
		var mpos := get_viewport().get_mouse_position()
		if mpos.x > 220:
			panning = true
			pan_start = mpos
			pan_origin = cam_pivot
	if Input.is_action_just_released("rmb") and orbiting:
		orbiting = false
	if Input.is_action_just_released("lmb") and panning:
		panning = false

	if orbiting:
		var mpos := get_viewport().get_mouse_position()
		var diff := mpos - orbit_start
		cam_yaw = orbit_yaw_start - diff.x * 0.3
		cam_pitch = clampf(orbit_pitch_start + diff.y * 0.3, -89.0, -5.0)
		_update_camera_transform()

	if panning:
		var mpos := get_viewport().get_mouse_position()
		var diff := mpos - pan_start
		var right := -camera.global_transform.basis.z.cross(Vector3.UP).normalized()
		var up := Vector3.UP
		var pan_speed := cam_dist * 0.002
		cam_pivot = pan_origin - right * diff.x * pan_speed + up * diff.y * pan_speed
		_update_camera_transform()

	var wheel := Input.get_axis("ZoomIn", "ZoomOut")
	if wheel != 0.0:
		cam_dist = clampf(cam_dist * (1.0 - wheel * 0.1), 5.0, 200.0)
		_update_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var dir := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			cam_dist = clampf(cam_dist + dir * cam_dist * 0.08, 5.0, 200.0)
			_update_camera_transform()


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 60.0
	camera.near = 0.1
	camera.far = 2000.0
	add_child(camera)


func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(30, 150, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.8, 0.85, 1.0)
	add_child(fill)

	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.4)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_menu.custom_minimum_size = Vector2(210, 0)
	canvas.add_child(_menu)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size = Vector2(200, 0)
	_menu.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Hex Terrain"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	var btn_a := Button.new()
	btn_a.text = "A: Hex Prisms (MultiMesh)"
	btn_a.pressed.connect(_on_prisms)
	vbox.add_child(btn_a)

	var btn_b := Button.new()
	btn_b.text = "B: Flat Grid (Single Mesh)"
	btn_b.pressed.connect(_on_flat)
	vbox.add_child(btn_b)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	_radius_label = Label.new()
	_radius_label.text = "Radius: 100"
	_radius_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_radius_label)

	_radius_slider = HSlider.new()
	_radius_slider.min_value = 10.0
	_radius_slider.max_value = 10000.0
	_radius_slider.step = 10.0
	_radius_slider.value = 100.0
	_radius_slider.custom_minimum_size = Vector2(180, 0)
	_radius_slider.value_changed.connect(_on_radius_changed)
	vbox.add_child(_radius_slider)

	var sep_h := HSeparator.new()
	vbox.add_child(sep_h)

	_height_label = Label.new()
	_height_label.text = "Height: 100"
	_height_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_height_label)

	_height_slider = HSlider.new()
	_height_slider.min_value = 0.0
	_height_slider.max_value = 400.0
	_height_slider.step = 1.0
	_height_slider.value = 100.0
	_height_slider.custom_minimum_size = Vector2(180, 0)
	_height_slider.value_changed.connect(_on_height_changed)
	vbox.add_child(_height_slider)

	var sep_exp := HSeparator.new()
	vbox.add_child(sep_exp)

	_exp_label = Label.new()
	_exp_label.text = "Height Curve: 1.0"
	_exp_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_exp_label)

	_exp_slider = HSlider.new()
	_exp_slider.min_value = 0.1
	_exp_slider.max_value = 5.0
	_exp_slider.step = 0.1
	_exp_slider.value = 1.0
	_exp_slider.custom_minimum_size = Vector2(180, 0)
	_exp_slider.value_changed.connect(_on_exp_changed)
	vbox.add_child(_exp_slider)

	var sep_s := HSeparator.new()
	vbox.add_child(sep_s)

	_step_label = Label.new()
	_step_label.text = "Height Step: 0"
	_step_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_step_label)

	_step_slider = HSlider.new()
	_step_slider.min_value = 0.0
	_step_slider.max_value = 20.0
	_step_slider.step = 0.5
	_step_slider.value = 0.0
	_step_slider.custom_minimum_size = Vector2(180, 0)
	_step_slider.value_changed.connect(_on_step_changed)
	vbox.add_child(_step_slider)

	var sep_grid := HSeparator.new()
	vbox.add_child(sep_grid)

	_grid_label = Label.new()
	_grid_label.text = "Grid Lines: 0.08"
	_grid_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_grid_label)

	_grid_slider = HSlider.new()
	_grid_slider.min_value = 0.0
	_grid_slider.max_value = 0.3
	_grid_slider.step = 0.01
	_grid_slider.value = 0.08
	_grid_slider.custom_minimum_size = Vector2(180, 0)
	_grid_slider.value_changed.connect(_on_grid_changed)
	vbox.add_child(_grid_slider)

	var sep3 := HSeparator.new()
	vbox.add_child(sep3)

	_label = Label.new()
	_label.text = "Pick an approach"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_label)


func _log(msg: String) -> void:
	_label.text = msg
	print(msg)


func _apply_uniform(param: String, value: float) -> void:
	if _terrain:
		for child in _terrain.get_children():
			if child is MeshInstance3D or child is MultiMeshInstance3D:
				var mat = child.material_override as ShaderMaterial
				if mat:
					mat.set_shader_parameter(param, value)


func _on_radius_changed(value: float) -> void:
	_radius_label.text = "Radius: %d" % int(value)
	if _current_approach != "":
		_rebuild_terrain()


func _on_height_changed(value: float) -> void:
	_height_label.text = "Height: %d" % int(value)
	_apply_uniform("max_height", value)


func _on_exp_changed(value: float) -> void:
	_exp_label.text = "Height Curve: %.1f" % value
	_apply_uniform("height_exp", value)


func _on_step_changed(value: float) -> void:
	_step_label.text = "Height Step: %.1f" % value
	_apply_uniform("height_step", value)


func _on_grid_changed(value: float) -> void:
	_grid_label.text = "Grid Lines: %.2f" % value
	_apply_uniform("grid_line_width", value)


func _rebuild_terrain() -> void:
	if _current_approach == "prisms":
		_on_prisms()
	elif _current_approach == "flat":
		_on_flat()


func _on_prisms() -> void:
	_current_approach = "prisms"
	_terrain_free()
	var script := load("res://HexGrid/approach_prisms.gd") as GDScript
	_terrain = Node3D.new()
	_terrain.set_meta("grid_radius", int(_radius_slider.value))
	_terrain.set_script(script)
	add_child(_terrain)
	_log("Generating hex prisms...")
	call_deferred("_log", "Hex prisms ready.")


func _on_flat() -> void:
	_current_approach = "flat"
	_terrain_free()
	var script := load("res://HexGrid/approach_flat.gd") as GDScript
	_terrain = Node3D.new()
	_terrain.set_meta("grid_radius", int(_radius_slider.value))
	_terrain.set_script(script)
	add_child(_terrain)
	_log("Generating flat grid...")
	call_deferred("_log", "Flat grid ready.")


func _terrain_free() -> void:
	if _terrain:
		_terrain.queue_free()
		_terrain = null


func _update_camera_transform() -> void:
	var yaw_rad := deg_to_rad(cam_yaw)
	var pitch_rad := deg_to_rad(cam_pitch)
	var offset := Vector3(
		cos(pitch_rad) * sin(yaw_rad),
		-sin(pitch_rad),
		cos(pitch_rad) * cos(yaw_rad)
	) * cam_dist
	camera.global_position = cam_pivot + offset
	camera.look_at(cam_pivot, Vector3.UP)
