extends Node3D

const HEX_SIZE := 1.0

var env: Environment
var camera: Camera3D
var camera_pivot: Node3D
var grid: HexGridManager
var info_label: Label
var coord_label: Label
var terrain_gen: HexTerrainGenerator

var cam_rot_x: float = 65.0
var cam_rot_y: float = 45.0
var cam_zoom: float = 25.0
var cam_pan := Vector2.ZERO
var last_mouse := Vector2.INF
var hovered_coords := Vector3i.ZERO
var _needs_redraw := true

# Hover outline
var _outline_mesh_rid: RID = RID()
var _outline_mat: StandardMaterial3D = null
var _outline_mat_rid: RID = RID()
var _outline_inst_rid: RID = RID()

var grass_id: int
var water_id: int
var stone_id: int
var dirt_id: int
var sand_id: int

# WASD movement speed
const CAM_MOVE_SPEED := 30.0
const CAM_FAST_SPEED := 60.0

# Noise seeds for compute shader
var _noise_seed: float
var _normal_map_tex: ImageTexture
var _detail_noise_tex: ImageTexture


func _ready() -> void:
	_noise_seed = randf() * 1000.0
	terrain_gen = HexTerrainGenerator.new()
	_generate_normal_map()
	_setup_environment()
	_setup_camera()
	_setup_lighting()
	_setup_grid()
	_setup_ui()
	_setup_outline()


func _process(delta: float) -> void:
	_handle_wasd(delta)
	if _needs_redraw:
		_update_camera()
		_needs_redraw = false
	coord_label.text = "Tiles: %d | R=regen F=flat G=grid | WASD=move RMB=rot MMB=pan Scroll=zoom" % grid.get_tile_count()


func _exit_tree() -> void:
	if _outline_inst_rid.is_valid():
		RenderingServer.free_rid(_outline_inst_rid)
	if _outline_mesh_rid.is_valid():
		RenderingServer.free_rid(_outline_mesh_rid)
	if _outline_mat_rid.is_valid():
		RenderingServer.free_rid(_outline_mat_rid)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_hover(event)
	elif event is InputEventMouseButton:
		_handle_click(event)
	elif event is InputEventKey:
		_handle_key(event)


func _handle_wasd(delta: float) -> void:
	var speed := CAM_MOVE_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		speed = CAM_FAST_SPEED
	speed *= delta

	var look_dir := (camera_pivot.global_position - camera.global_position)
	look_dir.y = 0.0
	look_dir = look_dir.normalized()
	var right_dir := look_dir.cross(Vector3.UP).normalized()

	var moved := false
	if Input.is_action_pressed("MoveForward"):
		cam_pan += Vector2(look_dir.x, look_dir.z) * speed
		moved = true
	if Input.is_action_pressed("MoveBackwards"):
		cam_pan -= Vector2(look_dir.x, look_dir.z) * speed
		moved = true
	if Input.is_action_pressed("MoveLeft"):
		cam_pan -= Vector2(right_dir.x, right_dir.z) * speed
		moved = true
	if Input.is_action_pressed("MoveRight"):
		cam_pan += Vector2(right_dir.x, right_dir.z) * speed
		moved = true

	if moved:
		_needs_redraw = true


func _handle_hover(event: InputEventMouseMotion) -> void:
	if event.button_mask == MOUSE_BUTTON_RIGHT:
		if last_mouse != Vector2.INF:
			var delta := event.position - last_mouse
			cam_rot_y -= delta.x * 0.3
			cam_rot_x -= delta.y * 0.3
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
		hovered_coords = cell.coords
		_update_outline(cell)
		_update_info_label(cell)
	elif cell == null:
		hovered_coords = Vector3i.ZERO
		RenderingServer.instance_set_visible(_outline_inst_rid, false)


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
			_noise_seed = randf() * 1000.0
			grid.clear_grid()
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


func _generate_chunk_terrain(chunk_coords: Vector2i) -> void:
	var type_to_mesh := [grass_id, water_id, stone_id, dirt_id, sand_id]

	var q_min := chunk_coords.x * grid.chunk_size
	var q_max := (chunk_coords.x + 1) * grid.chunk_size - 1
	var r_min := chunk_coords.y * grid.chunk_size
	var r_max := (chunk_coords.y + 1) * grid.chunk_size - 1

	var cells: Array[Vector3i] = []
	for q in range(q_min, q_max + 1):
		for r in range(r_min, r_max + 1):
			cells.append(Vector3i(q, r, -q - r))

	if cells.is_empty():
		return

	var results := terrain_gen.generate_terrain(cells, _noise_seed, 0.15)

	for result in results:
		var idx: int = result["type_index"]
		if idx < 0 or idx >= type_to_mesh.size():
			idx = 0
		var mesh_id: int = type_to_mesh[idx]
		grid.place_tile(result["coords"], mesh_id, result["elevation"])


func _update_outline(cell: HexCellData) -> void:
	var world_pos := HexGridMath.cube_to_world_flat_top(cell.coords, HEX_SIZE)
	var y := cell.elevation if not grid.flat_mode else 0.0
	RenderingServer.instance_set_transform(
		_outline_inst_rid, Transform3D(Basis.IDENTITY, Vector3(world_pos.x, y + 0.02, world_pos.z))
	)
	RenderingServer.instance_set_visible(_outline_inst_rid, true)


func _update_info_label(cell: HexCellData) -> void:
	var v4 := cell.to_vector4()
	var dist := HexGridMath.cube_distance(Vector3i.ZERO, cell.coords)
	var tile_names := ["grass", "water", "stone", "dirt", "sand"]
	var tname := "unknown"
	if cell.mesh_id >= 0 and cell.mesh_id < tile_names.size():
		tname = tile_names[cell.mesh_id]
	info_label.text = "Vec4(%.0f, %.0f, %.0f, %.2f) | Dist from center: %d | %s %s" % [
		v4.x, v4.y, v4.z, v4.w,
		dist,
		tname,
		"[FLAT]" if grid.flat_mode else "",
	]


func _generate_normal_map() -> void:
	# Generate a tiled normal map texture from noise
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 42
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05

	var strength := 3.0
	for y in size:
		for x in size:
			var px := float(x) / float(size)
			var py := float(y) / float(size)
			var h := noise.get_noise_2d(px * 10.0, py * 10.0)
			var hx := noise.get_noise_2d((px + 0.004) * 10.0, py * 10.0)
			var hy := noise.get_noise_2d(px * 10.0, (py + 0.004) * 10.0)
			var nx := (h - hx) * strength
			var ny := (h - hy) * strength
			var nz := 1.0
			var nrm := sqrt(nx * nx + ny * ny + nz * nz)
			nx /= nrm
			ny /= nrm
			nz /= nrm
			# Pack to 0-1 range
			img.set_pixel(x, y, Color(nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5, 1.0))

	_normal_map_tex = ImageTexture.create_from_image(img)

	# Generate detail noise texture
	var detail_img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var dnoise := FastNoiseLite.new()
	dnoise.seed = 137
	dnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dnoise.frequency = 0.08
	for y in size:
		for x in size:
			var px := float(x) / float(size)
			var py := float(y) / float(size)
			var v := dnoise.get_noise_2d(px * 10.0, py * 10.0) * 0.5 + 0.5
			detail_img.set_pixel(x, y, Color(v, v, v, 1.0))

	_detail_noise_tex = ImageTexture.create_from_image(detail_img)


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

	# Create materials with the shared shader but different params
	var top_green := HexGridMesh.create_top_face(HEX_SIZE)
	var prism_green := HexGridMesh.create_full_prism(HEX_SIZE, 1.0)
	var mat_green := ShaderMaterial.new()
	mat_green.shader = preload("res://HexGrid/hex_tile.gdshader")
	mat_green.set_shader_parameter("base_color", Color(0.35, 0.62, 0.28))
	mat_green.set_shader_parameter("tile_type", 0.0)
	_set_shared_shader_params(mat_green)
	grass_id = library.register_tile("grass", top_green, prism_green, mat_green)

	var top_blue := HexGridMesh.create_top_face(HEX_SIZE)
	var prism_blue := HexGridMesh.create_full_prism(HEX_SIZE, 1.0)
	var mat_blue := ShaderMaterial.new()
	mat_blue.shader = preload("res://HexGrid/hex_tile.gdshader")
	mat_blue.set_shader_parameter("base_color", Color(0.2, 0.4, 0.75))
	mat_blue.set_shader_parameter("tile_type", 1.0)
	_set_shared_shader_params(mat_blue)
	water_id = library.register_tile("water", top_blue, prism_blue, mat_blue)

	var top_grey := HexGridMesh.create_top_face(HEX_SIZE)
	var prism_grey := HexGridMesh.create_full_prism(HEX_SIZE, 1.0)
	var mat_grey := ShaderMaterial.new()
	mat_grey.shader = preload("res://HexGrid/hex_tile.gdshader")
	mat_grey.set_shader_parameter("base_color", Color(0.55, 0.53, 0.5))
	mat_grey.set_shader_parameter("tile_type", 2.0)
	mat_grey.set_shader_parameter("roughness_val", 0.9)
	_set_shared_shader_params(mat_grey)
	stone_id = library.register_tile("stone", top_grey, prism_grey, mat_grey)

	var top_brown := HexGridMesh.create_top_face(HEX_SIZE)
	var prism_brown := HexGridMesh.create_full_prism(HEX_SIZE, 1.0)
	var mat_brown := ShaderMaterial.new()
	mat_brown.shader = preload("res://HexGrid/hex_tile.gdshader")
	mat_brown.set_shader_parameter("base_color", Color(0.55, 0.4, 0.25))
	mat_brown.set_shader_parameter("tile_type", 3.0)
	_set_shared_shader_params(mat_brown)
	dirt_id = library.register_tile("dirt", top_brown, prism_brown, mat_brown)

	var top_sand := HexGridMesh.create_top_face(HEX_SIZE)
	var prism_sand := HexGridMesh.create_full_prism(HEX_SIZE, 1.0)
	var mat_sand := ShaderMaterial.new()
	mat_sand.shader = preload("res://HexGrid/hex_tile.gdshader")
	mat_sand.set_shader_parameter("base_color", Color(0.76, 0.7, 0.5))
	mat_sand.set_shader_parameter("tile_type", 4.0)
	_set_shared_shader_params(mat_sand)
	sand_id = library.register_tile("sand", top_sand, prism_sand, mat_sand)

	grid = HexGridManager.new()
	grid.name = "HexGrid"
	grid.hex_size = HEX_SIZE
	grid.flat_mode = false
	grid.tile_library = library
	grid.camera = camera
	grid.chunk_generate_callback = _generate_chunk_terrain
	add_child(grid)


func _set_shared_shader_params(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("normal_map", _normal_map_tex)
	mat.set_shader_parameter("detail_noise", _detail_noise_tex)


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

	# Controls panel at bottom
	var panel := PanelContainer.new()
	panel.name = "ControlsPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = -48.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	canvas.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.name = "Controls"
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var chunk_label := Label.new()
	chunk_label.text = "Chunk Size:"
	chunk_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(chunk_label)

	var chunk_spin := SpinBox.new()
	chunk_spin.name = "ChunkSizeSpin"
	chunk_spin.min_value = 8
	chunk_spin.max_value = 256
	chunk_spin.step = 8
	chunk_spin.value = grid.chunk_size
	chunk_spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chunk_spin.custom_minimum_size.x = 80
	chunk_spin.value_changed.connect(_on_chunk_size_changed)
	hbox.add_child(chunk_spin)

	var regen_btn := Button.new()
	regen_btn.text = "Regen (R)"
	regen_btn.pressed.connect(_on_regen_pressed)
	hbox.add_child(regen_btn)

	var budget_label := Label.new()
	budget_label.text = "Per Frame:"
	budget_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(budget_label)

	var budget_spin := SpinBox.new()
	budget_spin.name = "BudgetSpin"
	budget_spin.min_value = 1
	budget_spin.max_value = 16
	budget_spin.step = 1
	budget_spin.value = grid.chunks_per_frame
	budget_spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	budget_spin.custom_minimum_size.x = 60
	budget_spin.value_changed.connect(func(v: float) -> void: grid.chunks_per_frame = int(v))
	hbox.add_child(budget_spin)


func _on_chunk_size_changed(value: float) -> void:
	grid.clear_grid()
	grid.chunk_size = int(value)
	_noise_seed = randf() * 1000.0


func _on_regen_pressed() -> void:
	_noise_seed = randf() * 1000.0
	grid.clear_grid()


func _setup_outline() -> void:
	var outer := HEX_SIZE * 1.03
	var inner := HEX_SIZE * 0.88
	var verts: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var indices: PackedInt32Array = []

	for i in 6:
		var a_outer := deg_to_rad(60.0 * float(i))
		var b_outer := deg_to_rad(60.0 * float((i + 1) % 6))
		var a_inner := deg_to_rad(60.0 * float(i))
		var b_inner := deg_to_rad(60.0 * float((i + 1) % 6))

		var o0 := Vector3(outer * cos(a_outer), 0.0, outer * sin(a_outer))
		var o1 := Vector3(outer * cos(b_outer), 0.0, outer * sin(b_outer))
		var i0 := Vector3(inner * cos(a_inner), 0.0, inner * sin(a_inner))
		var i1 := Vector3(inner * cos(b_inner), 0.0, inner * sin(b_inner))

		var base := verts.size()
		verts.append(o0)
		verts.append(o1)
		verts.append(i0)
		verts.append(i1)
		for _j in 4:
			normals.append(Vector3.UP)
		indices.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])

	_outline_mesh_rid = RenderingServer.mesh_create()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	RenderingServer.mesh_add_surface_from_arrays(_outline_mesh_rid, RenderingServer.PRIMITIVE_TRIANGLES, arrays)

	_outline_mat = StandardMaterial3D.new()
	_outline_mat.albedo_color = Color(1.0, 0.95, 0.3, 1.0)
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.no_depth_test = true
	_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_outline_mat_rid = _outline_mat.get_rid()

	_outline_inst_rid = RenderingServer.instance_create()
	RenderingServer.instance_set_scenario(_outline_inst_rid, get_world_3d().scenario)
	RenderingServer.instance_set_base(_outline_inst_rid, _outline_mesh_rid)
	RenderingServer.instance_set_surface_override_material(_outline_inst_rid, 0, _outline_mat_rid)
	RenderingServer.instance_set_visible(_outline_inst_rid, false)
