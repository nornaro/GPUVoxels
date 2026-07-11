extends Node3D

const MAP_RADIUS := 50  # Now supports large maps with chunking!
const HEX_SIZE := 1.0

var env: Environment
var camera: Camera3D
var camera_pivot: Node3D
var grid: HexGridManager
var info_label: Label
var coord_label: Label

var cam_rot_x: float = -55.0
var cam_rot_y: float = 45.0
var cam_zoom: float = 25.0
var cam_pan := Vector2.ZERO
var last_mouse := Vector2.INF
var hovered_coords := Vector3i.ZERO
var _needs_redraw := true

var grass_id: int
var water_id: int
var stone_id: int
var dirt_id: int


func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_setup_lighting()
	_setup_grid()
	_setup_ui()
	call_deferred("_generate_map")


func _process(_delta: float) -> void:
	if _needs_redraw:
		_update_camera()
		_needs_redraw = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_hover(event)
	elif event is InputEventMouseButton:
		_handle_click(event)
	elif event is InputEventKey:
		_handle_key(event)


func _handle_hover(event: InputEventMouseMotion) -> void:
	if event.button_mask == MOUSE_BUTTON_RIGHT:
		if last_mouse != Vector2.INF:
			var delta := event.position - last_mouse
			cam_rot_y -= delta.x * 0.3
			cam_rot_x = clampf(cam_rot_x - delta.y * 0.3, -180, 180)
		last_mouse = event.position
		_needs_redraw = true
		return

	if event.button_mask == MOUSE_BUTTON_MIDDLE:
		if last_mouse != Vector2.INF:
			var delta := event.position - last_mouse
			cam_pan -= Vector2(delta.x, delta.y) * 0.05
		last_mouse = event.position
		_needs_redraw = true
		return

	last_mouse = event.position
	var cell := grid.raycast_hex(camera, event.position)
	if cell != null and cell.coords != hovered_coords:
		grid.highlight_tile(hovered_coords, false)
		hovered_coords = cell.coords
		grid.highlight_tile(hovered_coords, true)
		_update_info_label(cell)


func _handle_click(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return

	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			cam_zoom = clampf(cam_zoom - 2.0, 5.0, 80.0)
			_needs_redraw = true
		MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom = clampf(cam_zoom + 2.0, 5.0, 80.0)
			_needs_redraw = true
		MOUSE_BUTTON_LEFT:
			_place_at_cursor()
		MOUSE_BUTTON_RIGHT:
			pass


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	match event.keycode:
		KEY_R:
			grid.clear_grid()
			_generate_map()
		KEY_F:
			grid.set_flat_mode(not grid.flat_mode)
		KEY_G:
			_toggle_grid_lines()


func _place_at_cursor() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var cell := grid.raycast_hex(camera, mouse_pos)
	if cell == null:
		return
	var new_coords := cell.coords
	for n in HexGridMath.cube_neighbors(new_coords):
		if not grid.has_tile(n):
			var elevation := randf_range(0.6, 2.5)
			var mesh_id: int = [grass_id, stone_id, dirt_id].pick_random()
			grid.place_tile(n, mesh_id, elevation)


func _update_camera() -> void:
	var rad_x := deg_to_rad(cam_rot_x)
	var rad_y := deg_to_rad(cam_rot_y)
	var offset := Vector3(
		cam_zoom * cos(rad_x) * cos(rad_y),
		cam_zoom * sin(rad_x),
		cam_zoom * cos(rad_x) * sin(rad_y),
	)
	camera_pivot.position = Vector3(cam_pan.x, 0.0, cam_pan.y)
	camera.global_position = camera_pivot.global_position + offset
	camera.look_at(camera_pivot.global_position)


func _generate_map() -> void:
	var cells := HexGridMath.cube_spiral(Vector3i.ZERO, MAP_RADIUS)
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.15

	grid.begin_batch()
	for coords in cells:
		if coords == Vector3i.ZERO:
			continue
		var wx := float(coords.x)
		var wz := float(coords.y)
		var nval := noise.get_noise_2d(wx, wz)
		var elevation := remap(nval, -1.0, 1.0, 0.3, 3.0)
		var mesh_id := grass_id
		if nval < -0.2:
			mesh_id = water_id
			elevation = remap(nval, -1.0, -0.2, 0.15, 0.4)
		elif nval > 0.5:
			mesh_id = stone_id
			elevation = remap(nval, 0.5, 1.0, 1.8, 4.0)
		elif nval > 0.25:
			mesh_id = dirt_id
			elevation = remap(nval, 0.25, 0.5, 1.0, 1.8)
		else:
			elevation = remap(nval, -0.2, 0.25, 0.6, 1.2)
		grid.place_tile(coords, mesh_id, elevation)
	grid.end_batch()

	coord_label.text = "Tiles: %d | Press R=regen F=flat G=grid | LMB=expand RMB=rotate MMB=pan Scroll=zoom" % grid.get_tile_count()


func _update_info_label(cell: HexCellData) -> void:
	info_label.text = "Q:%d  R:%d  S:%d  |  Elev: %.2f  Mesh: %d  Layer: %d" % [
		cell.coords.x, cell.coords.y, cell.coords.z,
		cell.elevation, cell.mesh_id, cell.layer,
	]


func _toggle_grid_lines() -> void:
	var existing := get_node_or_null("GridLines")
	if existing:
		existing.queue_free()
		return
	var immediate := MeshInstance3D.new()
	immediate.name = "GridLines"
	add_child(immediate)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.set_color(Color(1, 1, 1, 0.15))
	for coords in grid.get_all_coords():
		var center := grid.hex_to_world(coords)
		center.y = 0.01
		for i in 6:
			var a_angle := deg_to_rad(60.0 * float(i))
			var b_angle := deg_to_rad(60.0 * float((i + 1) % 6))
			var a := center + Vector3(cos(a_angle), 0, sin(a_angle)) * HEX_SIZE * 0.95
			var b := center + Vector3(cos(b_angle), 0, sin(b_angle)) * HEX_SIZE * 0.95
			st.add_vertex(a)
			st.add_vertex(b)
	immediate.mesh = st.commit()


func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.35, 0.4)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.6, 0.7)
	env.fog_density = 0.008
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)


func _setup_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.name = "TestCamera"
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 500.0
	camera_pivot.add_child(camera)
	_update_camera()


func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.95, 0.9)
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.3
	fill.light_color = Color(0.6, 0.7, 0.9)
	fill.rotation_degrees = Vector3(20, 150, 0)
	add_child(fill)


func _setup_grid() -> void:
	var library := HexTileLibrary.new()

	var top_green := HexGridMesh.create_top_face(HEX_SIZE)
	var prism_green := HexGridMesh.create_full_prism(HEX_SIZE, 1.0)
	var mat_green := ShaderMaterial.new()
	mat_green.shader = preload("res://HexGrid/hex_tile.gdshader")
	mat_green.set_shader_parameter("base_color", Color(0.35, 0.62, 0.28))
	grass_id = library.register_tile("grass", top_green, prism_green, mat_green.get_rid())

	var top_blue := HexGridMesh.create_top_face(HEX_SIZE)
	var prism_blue := HexGridMesh.create_full_prism(HEX_SIZE, 1.0)
	var mat_blue := ShaderMaterial.new()
	mat_blue.shader = preload("res://HexGrid/hex_tile.gdshader")
	mat_blue.set_shader_parameter("base_color", Color(0.2, 0.4, 0.75))
	water_id = library.register_tile("water", top_blue, prism_blue, mat_blue.get_rid())

	var top_grey := HexGridMesh.create_top_face(HEX_SIZE)
	var prism_grey := HexGridMesh.create_full_prism(HEX_SIZE, 1.0)
	var mat_grey := ShaderMaterial.new()
	mat_grey.shader = preload("res://HexGrid/hex_tile.gdshader")
	mat_grey.set_shader_parameter("base_color", Color(0.55, 0.53, 0.5))
	stone_id = library.register_tile("stone", top_grey, prism_grey, mat_grey.get_rid())

	var top_brown := HexGridMesh.create_top_face(HEX_SIZE)
	var prism_brown := HexGridMesh.create_full_prism(HEX_SIZE, 1.0)
	var mat_brown := ShaderMaterial.new()
	mat_brown.shader = preload("res://HexGrid/hex_tile.gdshader")
	mat_brown.set_shader_parameter("base_color", Color(0.55, 0.4, 0.25))
	dirt_id = library.register_tile("dirt", top_brown, prism_brown, mat_brown.get_rid())

	grid = HexGridManager.new()
	grid.name = "HexGrid"
	grid.hex_size = HEX_SIZE
	grid.flat_mode = false
	grid.tile_library = library
	grid.camera = camera  # Set camera reference for chunk culling
	add_child(grid)


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.position = Vector2(16, 16)
	info_label.add_theme_font_size_override("font_size", 16)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	info_label.add_theme_constant_override("shadow_offset_x", 1)
	info_label.add_theme_constant_override("shadow_offset_y", 1)
	info_label.text = "Hovering: ---"
	canvas.add_child(info_label)

	coord_label = Label.new()
	coord_label.name = "CoordLabel"
	coord_label.position = Vector2(16, 44)
	coord_label.add_theme_font_size_override("font_size", 14)
	coord_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	coord_label.text = "Loading..."
	canvas.add_child(coord_label)
