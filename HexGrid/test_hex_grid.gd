extends Node3D

const HEX_SIZE := 1.0
const SAVE_PATH := "user://placed_blocks.json"
const HEX_ROTATION := 0.523599

var env: Environment
var camera: Camera3D
var camera_pivot: Node3D
var grid: HexGridManager
var info_label: Label
var coord_label: Label

var cam_rot_x: float = 65.0
var cam_rot_y: float = 45.0
var cam_zoom: float = 25.0
var cam_pan := Vector2.ZERO
var last_mouse := Vector2.INF
var hovered_coords := Vector3i.ZERO
var _needs_redraw := true

var _outline_mesh_rid: RID = RID()
var _outline_mat: StandardMaterial3D = null
var _outline_mat_rid: RID = RID()
var _outline_inst_rid: RID = RID()

var grass_id: int
var water_id: int
var stone_id: int
var dirt_id: int
var sand_id: int

const CAM_MOVE_SPEED := 30.0
const CAM_FAST_SPEED := 60.0

var _noise_seed: float
var _normal_map_tex: ImageTexture
var _detail_noise_tex: ImageTexture

var block_lib: HexBlockLib = null
var placement_mode := false
var delete_mode := false
var _placed_blocks: Dictionary = {}
var _last_left_click_time := 0.0
const DOUBLE_CLICK_THRESHOLD := 0.3
var _selected_item_name: String = ""
var _selected_category: String = ""
var _place_rotation: float = 0.0

var _loading_canvas: CanvasLayer = null
var _loading_label: Label = null
var _status_label: Label = null

var _ghost_inst: RID = RID()
var _ghost_mesh_name: String = ""
var _ghost_mat: StandardMaterial3D = null

var _menu_panel: PanelContainer = null
var _menu_visible := false
var _category_container: HBoxContainer = null
var _item_container: GridContainer = null
var _item_scroll: ScrollContainer = null
var _delete_btn: Button = null

var _road_cells: Dictionary = {}
var _river_cells: Dictionary = {}
var _tile_overlay_type: Dictionary = {}
var _road_instances: Dictionary = {}
var _river_instances: Dictionary = {}
var _painter_mode: String = ""
var _overlay_dot_rid: RID = RID()
var _overlay_strip_rid: RID = RID()
var _overlay_river_strip_rid: RID = RID()
var _road_mat: StandardMaterial3D = null
var _river_mat: StandardMaterial3D = null
var _road_btn: Button = null
var _river_btn: Button = null


func _ready() -> void:
	_show_loading_screen("Initializing...")
	call_deferred("_init_phase_1")


func _init_phase_1() -> void:
	_update_loading("Generating textures...")
	_noise_seed = randf() * 1000.0
	block_lib = HexBlockLib.new()
	_generate_normal_map()
	block_lib.set_textures(_normal_map_tex, _detail_noise_tex)
	call_deferred("_init_phase_2")


func _init_phase_2() -> void:
	_update_loading("Setting up world...")
	_setup_environment()
	_setup_camera()
	_setup_lighting()
	call_deferred("_init_phase_3")


func _init_phase_3() -> void:
	_update_loading("Building terrain...")
	_setup_grid()
	call_deferred("_init_phase_4")


func _init_phase_4() -> void:
	_update_loading("Finalizing...")
	_setup_ui()
	_setup_outline()
	_setup_ghost()
	_setup_overlay_meshes()
	_select_first_item()
	_hide_loading_screen()


func _process(delta: float) -> void:
	_handle_wasd(delta)
	if _needs_redraw:
		_update_camera()
		_needs_redraw = false
	if _menu_visible and _item_container and _item_scroll:
		var col_w := 56.0
		var avail_w := _item_scroll.size.x
		if avail_w > 0:
			var cols := maxi(1, int(avail_w / col_w))
			_item_container.columns = cols
	var mode_str := ""
	if _painter_mode != "":
		mode_str = " [%s painter]" % _painter_mode.capitalize()
	elif delete_mode:
		mode_str = " [DELETE]"
	elif placement_mode:
		mode_str = " [%s]" % _selected_item_name if _selected_item_name != "" else " [Place]"
	coord_label.text = "Tiles: %d | R=regen F=flat G=grid B=build%s | WASD RMB MMB Scroll" % [
		grid.get_tile_count(), mode_str,
	]
	if _status_label and _status_label.modulate.a > 0.0:
		_status_label.modulate.a = maxf(0.0, _status_label.modulate.a - delta * 0.3)


func _exit_tree() -> void:
	for coords in _placed_blocks:
		var entry: Dictionary = _placed_blocks[coords]
		var inst: RID = entry["rid"]
		if inst.is_valid():
			RenderingServer.free_rid(inst)
	_placed_blocks.clear()
	_clear_all_overlays()
	if _overlay_dot_rid.is_valid():
		RenderingServer.free_rid(_overlay_dot_rid)
	if _overlay_strip_rid.is_valid():
		RenderingServer.free_rid(_overlay_strip_rid)
	if _overlay_river_strip_rid.is_valid():
		RenderingServer.free_rid(_overlay_river_strip_rid)
	if _ghost_inst.is_valid():
		RenderingServer.free_rid(_ghost_inst)
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
		if placement_mode or delete_mode:
			_update_ghost(cell)
	elif cell == null:
		hovered_coords = Vector3i.ZERO
		RenderingServer.instance_set_visible(_outline_inst_rid, false)
		if placement_mode or delete_mode:
			RenderingServer.instance_set_visible(_ghost_inst, false)


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
			if _painter_mode != "":
				_handle_painter_click(event)
			elif placement_mode:
				_handle_block_place(event)
			elif delete_mode:
				_handle_block_delete(event)
			else:
				_place_at_cursor()


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	match event.keycode:
		KEY_R:
			_noise_seed = randf() * 1000.0
			grid.noise_seed = _noise_seed
			_clear_all_placed_blocks()
			_clear_all_overlays()
			grid.clear_grid()
		KEY_F:
			grid.set_flat_mode(not grid.flat_mode)
		KEY_G:
			_toggle_grid_lines()
		KEY_B:
			_toggle_build_menu()
		KEY_DELETE:
			_clear_all_placed_blocks()
		KEY_V:
			_place_rotation += deg_to_rad(60.0)
			if _place_rotation >= TAU:
				_place_rotation -= TAU
			_update_ghost_visibility()
		KEY_S:
			if event.ctrl_pressed:
				_save_placed_blocks()
		KEY_O:
			if event.ctrl_pressed:
				_load_placed_blocks()


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


# ============================================================================
# BLOCK PLACEMENT / DELETION
# ============================================================================

func _handle_block_place(_event: InputEventMouseButton) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_left_click_time > DOUBLE_CLICK_THRESHOLD:
		_last_left_click_time = now
		return
	_last_left_click_time = now
	var mouse_pos := get_viewport().get_mouse_position()
	var cell := grid.raycast_hex(camera, mouse_pos)
	if cell == null:
		return
	_place_block(cell)


func _handle_block_delete(_event: InputEventMouseButton) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_left_click_time > DOUBLE_CLICK_THRESHOLD:
		_last_left_click_time = now
		return
	_last_left_click_time = now
	var mouse_pos := get_viewport().get_mouse_position()
	var cell := grid.raycast_hex(camera, mouse_pos)
	if cell == null:
		return
	_delete_block(cell)


func _place_block(cell: HexCellData) -> void:
	if _selected_item_name == "" or not block_lib.get_item(_selected_item_name):
		return
	if _placed_blocks.has(cell.coords):
		return
	var item: Dictionary = block_lib.get_item(_selected_item_name)
	var world_pos := HexGridMath.cube_to_world_flat_top(cell.coords, HEX_SIZE)
	var inst := RenderingServer.instance_create()
	RenderingServer.instance_set_scenario(inst, get_world_3d().scenario)
	RenderingServer.instance_set_base(inst, item["mesh_rid"])
	if not item.get("has_own_material", false):
		RenderingServer.instance_set_surface_override_material(inst, 0, block_lib.get_material().get_rid())
	var scale_f := block_lib.get_hex_scale(_selected_item_name)
	var aabb: AABB = item.get("aabb", AABB())
	var y_offset := -aabb.position.y * scale_f
	var y: float
	if grid.flat_mode:
		y = y_offset
	else:
		y = cell.elevation + y_offset
	var rot_basis := Basis(Vector3.UP, _place_rotation + HEX_ROTATION)
	var scaled_basis := rot_basis.scaled(Vector3(scale_f, scale_f, scale_f))
	RenderingServer.instance_set_transform(inst, Transform3D(scaled_basis, Vector3(world_pos.x, y, world_pos.z)))
	_placed_blocks[cell.coords] = {"rid": inst, "item_name": _selected_item_name, "rotation": _place_rotation}


func _delete_block(cell: HexCellData) -> void:
	if not _placed_blocks.has(cell.coords):
		return
	var entry: Dictionary = _placed_blocks[cell.coords]
	var inst: RID = entry["rid"]
	if inst.is_valid():
		RenderingServer.free_rid(inst)
	_placed_blocks.erase(cell.coords)


func _clear_all_placed_blocks() -> void:
	for coords in _placed_blocks:
		var entry: Dictionary = _placed_blocks[coords]
		var inst: RID = entry["rid"]
		if inst.is_valid():
			RenderingServer.free_rid(inst)
	_placed_blocks.clear()


# ============================================================================
# GHOST PREVIEW
# ============================================================================

func _setup_ghost() -> void:
	_ghost_inst = RenderingServer.instance_create()
	RenderingServer.instance_set_scenario(_ghost_inst, get_world_3d().scenario)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(0.4, 0.8, 0.4, 0.35)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.no_depth_test = true
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	RenderingServer.instance_set_visible(_ghost_inst, false)


func _update_ghost(cell: HexCellData) -> void:
	var occupied := _placed_blocks.has(cell.coords)
	if delete_mode:
		_ghost_mat.albedo_color = Color(0.9, 0.2, 0.2, 0.5)
		_outline_mat.albedo_color = Color(1.0, 0.2, 0.2, 1.0)
	elif placement_mode:
		if occupied or _selected_item_name == "":
			_ghost_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.35)
			_outline_mat.albedo_color = Color(1.0, 0.2, 0.2, 1.0)
		else:
			_ghost_mat.albedo_color = Color(0.2, 1.0, 0.3, 0.4)
			_outline_mat.albedo_color = Color(0.2, 1.0, 0.3, 1.0)
	var want_name := ""
	if placement_mode and _selected_item_name != "":
		want_name = _selected_item_name
	if want_name != _ghost_mesh_name:
		if want_name != "" and block_lib.get_item(want_name):
			var item: Dictionary = block_lib.get_item(want_name)
			RenderingServer.instance_set_base(_ghost_inst, item["mesh_rid"])
			if item.get("has_own_material", false):
				RenderingServer.instance_set_surface_override_material(_ghost_inst, 0, RID())
			else:
				RenderingServer.instance_set_surface_override_material(_ghost_inst, 0, _ghost_mat.get_rid())
		_ghost_mesh_name = want_name
	var world_pos := HexGridMath.cube_to_world_flat_top(cell.coords, HEX_SIZE)
	var item_data: Dictionary = block_lib.get_item(_ghost_mesh_name)
	var scale_f := block_lib.get_hex_scale(_ghost_mesh_name) if not item_data.is_empty() else 1.0
	var aabb: AABB = item_data.get("aabb", AABB()) if not item_data else AABB()
	var y_offset := -aabb.position.y * scale_f
	var y: float
	if grid.flat_mode:
		y = y_offset
	else:
		y = cell.elevation + y_offset
	var rot_basis := Basis(Vector3.UP, _place_rotation + HEX_ROTATION)
	var scaled_basis := rot_basis.scaled(Vector3(scale_f, scale_f, scale_f))
	RenderingServer.instance_set_transform(_ghost_inst, Transform3D(scaled_basis, Vector3(world_pos.x, y, world_pos.z)))
	RenderingServer.instance_set_visible(_ghost_inst, true)


func _update_ghost_visibility() -> void:
	if _painter_mode != "":
		RenderingServer.instance_set_visible(_ghost_inst, false)
		return
	if placement_mode or delete_mode:
		var cell := grid.raycast_hex(camera, get_viewport().get_mouse_position())
		if cell:
			_update_ghost(cell)
	else:
		RenderingServer.instance_set_visible(_ghost_inst, false)


# ============================================================================
# ROAD / RIVER PAINTER
# ============================================================================

func _setup_overlay_meshes() -> void:
	var scenario := get_world_3d().scenario

	# --- Dot mesh (hexagonal patch) ---
	var dot_r := 0.25 * HEX_SIZE
	var dv: PackedVector3Array = []
	var dn: PackedVector3Array = []
	var du: PackedVector2Array = []
	var di: PackedInt32Array = []
	for i in 6:
		var angle := deg_to_rad(60.0 * i)
		dv.append(Vector3(dot_r * cos(angle), 0.0, dot_r * sin(angle)))
		dn.append(Vector3.UP)
		du.append(Vector2(cos(angle) * 0.5 + 0.5, sin(angle) * 0.5 + 0.5))
	dv.append(Vector3.ZERO)
	dn.append(Vector3.UP)
	du.append(Vector2(0.5, 0.5))
	for i in 6:
		di.append_array([6, i, (i + 1) % 6])
	_overlay_dot_rid = RenderingServer.mesh_create()
	var darr := []
	darr.resize(Mesh.ARRAY_MAX)
	darr[Mesh.ARRAY_VERTEX] = dv
	darr[Mesh.ARRAY_NORMAL] = dn
	darr[Mesh.ARRAY_TEX_UV] = du
	darr[Mesh.ARRAY_INDEX] = di
	RenderingServer.mesh_add_surface_from_arrays(_overlay_dot_rid, RenderingServer.PRIMITIVE_TRIANGLES, darr)

	# --- Strip mesh (rectangle along +X axis, length = edge-to-center distance) ---
	var strip_len := 0.9 * HEX_SIZE
	var hw := 0.175 * HEX_SIZE
	var sv: PackedVector3Array = []
	var sn: PackedVector3Array = []
	var su: PackedVector2Array = []
	var si: PackedInt32Array = []
	sv.append(Vector3(0.0, 0.0, -hw))
	sv.append(Vector3(0.0, 0.0, hw))
	sv.append(Vector3(strip_len, 0.0, hw))
	sv.append(Vector3(strip_len, 0.0, -hw))
	for _j in 4:
		sn.append(Vector3.UP)
	su.append_array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])
	si.append_array([0, 1, 2, 0, 2, 3])
	_overlay_strip_rid = RenderingServer.mesh_create()
	var sarr := []
	sarr.resize(Mesh.ARRAY_MAX)
	sarr[Mesh.ARRAY_VERTEX] = sv
	sarr[Mesh.ARRAY_NORMAL] = sn
	sarr[Mesh.ARRAY_TEX_UV] = su
	sarr[Mesh.ARRAY_INDEX] = si
	RenderingServer.mesh_add_surface_from_arrays(_overlay_strip_rid, RenderingServer.PRIMITIVE_TRIANGLES, sarr)

	# --- Curved river strip mesh (S-curve along +X axis) ---
	var rv_len := sqrt(3.0) * HEX_SIZE
	var rv_hw := 0.175 * HEX_SIZE
	var rv_half := rv_len * 0.5
	var rv_curve := 0.2 * HEX_SIZE
	var rv: PackedVector3Array = []
	var rn: PackedVector3Array = []
	var ru: PackedVector2Array = []
	var ri: PackedInt32Array = []
	for i in 8:
		var t := float(i) / 7.0
		var x := t * rv_len - rv_half
		var curve_z := rv_curve * sin(t * PI)
		rv.append(Vector3(x, 0.0, -rv_hw + curve_z))
		rn.append(Vector3.UP)
		ru.append(Vector2(t, 0.0))
	for i in 8:
		var t := float(i) / 7.0
		var x := t * rv_len - rv_half
		var curve_z := rv_curve * sin(t * PI)
		rv.append(Vector3(x, 0.0, rv_hw + curve_z))
		rn.append(Vector3.UP)
		ru.append(Vector2(t, 1.0))
	for i in 7:
		var bl := i
		var br := i + 8
		var tl := i + 1
		var tr := i + 9
		ri.append_array([bl, br, tl, tl, br, tr])
	_overlay_river_strip_rid = RenderingServer.mesh_create()
	var rarr := []
	rarr.resize(Mesh.ARRAY_MAX)
	rarr[Mesh.ARRAY_VERTEX] = rv
	rarr[Mesh.ARRAY_NORMAL] = rn
	rarr[Mesh.ARRAY_TEX_UV] = ru
	rarr[Mesh.ARRAY_INDEX] = ri
	RenderingServer.mesh_add_surface_from_arrays(_overlay_river_strip_rid, RenderingServer.PRIMITIVE_TRIANGLES, rarr)

	# --- Materials ---
	_road_mat = StandardMaterial3D.new()
	_road_mat.albedo_color = Color(0.45, 0.35, 0.22, 0.9)
	_road_mat.roughness = 0.95
	_road_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX

	_river_mat = StandardMaterial3D.new()
	_river_mat.albedo_color = Color(0.2, 0.45, 0.8, 0.85)
	_river_mat.roughness = 0.3
	_river_mat.metallic = 0.1
	_river_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX


func _set_painter_mode(mode: String) -> void:
	if _painter_mode == mode:
		_painter_mode = ""
	else:
		_painter_mode = mode
	placement_mode = false
	delete_mode = false
	_selected_item_name = ""
	_update_place_button()
	_update_ghost_visibility()
	_update_delete_button()
	_update_item_buttons()
	_update_painter_buttons()


func _update_painter_buttons() -> void:
	if _road_btn:
		_road_btn.modulate = Color(0.5, 1.0, 0.5) if _painter_mode == "road" else Color(1, 1, 1)
	if _river_btn:
		_river_btn.modulate = Color(0.5, 1.0, 0.5) if _painter_mode == "river" else Color(1, 1, 1)


func _handle_painter_click(event: InputEventMouseButton) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_left_click_time > DOUBLE_CLICK_THRESHOLD:
		_last_left_click_time = now
		return
	_last_left_click_time = now
	var mouse_pos := get_viewport().get_mouse_position()
	var cell := grid.raycast_hex(camera, mouse_pos)
	if cell == null:
		return
	var coords := cell.coords
	var current: String = _tile_overlay_type.get(coords, "")
	if current == _painter_mode:
		_remove_painted_cell(coords)
	elif _painter_mode == "road":
		_set_painted_cell(coords, "road")
	elif _painter_mode == "river":
		_set_painted_cell(coords, "river")
	for d in 6:
		var n := coords + HexGridMath.cube_direction(d)
		if _tile_overlay_type.has(n):
			_rebuild_painted_cell(n)


func _set_painted_cell(coords: Vector3i, ptype: String) -> void:
	_tile_overlay_type[coords] = ptype
	if ptype == "road":
		_road_cells[coords] = true
		_river_cells.erase(coords)
		_clear_overlay(coords, _river_instances)
	else:
		_river_cells[coords] = true
		_road_cells.erase(coords)
		_clear_overlay(coords, _road_instances)
	_rebuild_painted_cell(coords)


func _remove_painted_cell(coords: Vector3i) -> void:
	var ptype: String = _tile_overlay_type.get(coords, "")
	_tile_overlay_type.erase(coords)
	_road_cells.erase(coords)
	_river_cells.erase(coords)
	if ptype == "road":
		_clear_overlay(coords, _road_instances)
	else:
		_clear_overlay(coords, _river_instances)


func _rebuild_painted_cell(coords: Vector3i) -> void:
	var ptype: String = _tile_overlay_type.get(coords, "")
	if ptype == "road":
		_build_overlay(coords, _road_cells, _road_instances, _road_mat)
	elif ptype == "river":
		_build_overlay(coords, _river_cells, _river_instances, _river_mat)


func _build_overlay(coords: Vector3i, flag_dict: Dictionary, inst_dict: Dictionary, mat: StandardMaterial3D) -> void:
	_clear_overlay(coords, inst_dict)
	var cell := grid.get_cell(coords)
	if cell == null:
		return
	var world_pos := HexGridMath.cube_to_world_flat_top(coords, HEX_SIZE)
	var y := cell.elevation * 0.05 + 0.025 if grid.flat_mode else cell.elevation + 0.025

	var is_river: bool = flag_dict == _river_cells
	var strip_mesh := _overlay_river_strip_rid if is_river else _overlay_strip_rid

	var has_neighbor := false
	var neighbor_dirs: Array[int] = []
	for d in 6:
		var n := coords + HexGridMath.cube_direction(d)
		if flag_dict.has(n):
			has_neighbor = true
			neighbor_dirs.append(d)

	if not has_neighbor:
		_make_overlay_inst(_overlay_dot_rid, mat, world_pos, y, 0.0, inst_dict, coords)
		return

	for d in neighbor_dirs:
		var angle := deg_to_rad(30.0 - 60.0 * d)
		_make_overlay_inst(strip_mesh, mat, world_pos, y, angle, inst_dict, coords)

	if neighbor_dirs.size() == 2:
		var a0 := deg_to_rad(30.0 - 60.0 * neighbor_dirs[0])
		var a1 := deg_to_rad(30.0 - 60.0 * neighbor_dirs[1])
		var diff := angle_difference(a0, a1)
		if absf(diff) > deg_to_rad(60.0):
			var bisector := a0 + diff * 0.5
			_make_overlay_inst(_overlay_dot_rid, mat, world_pos, y, bisector, inst_dict, coords)


func _make_overlay_inst(mesh_rid: RID, mat: StandardMaterial3D, pos: Vector3, y: float, rot_y: float, inst_dict: Dictionary, coords: Vector3i) -> void:
	var inst := RenderingServer.instance_create()
	RenderingServer.instance_set_scenario(inst, get_world_3d().scenario)
	RenderingServer.instance_set_base(inst, mesh_rid)
	RenderingServer.instance_set_surface_override_material(inst, 0, mat.get_rid())
	var basis := Basis(Vector3.UP, rot_y)
	RenderingServer.instance_set_transform(inst, Transform3D(basis, Vector3(pos.x, y, pos.z)))
	if not inst_dict.has(coords):
		inst_dict[coords] = []
	inst_dict[coords].append(inst)


func _clear_overlay(coords: Vector3i, inst_dict: Dictionary) -> void:
	if inst_dict.has(coords):
		for inst in inst_dict[coords]:
			if inst.is_valid():
				RenderingServer.free_rid(inst)
		inst_dict.erase(coords)


func _clear_all_overlays() -> void:
	for coords in _road_instances:
		for inst in _road_instances[coords]:
			if inst.is_valid():
				RenderingServer.free_rid(inst)
	_road_instances.clear()
	_road_cells.clear()
	for coords in _river_instances:
		for inst in _river_instances[coords]:
			if inst.is_valid():
				RenderingServer.free_rid(inst)
	_river_instances.clear()
	_river_cells.clear()
	_tile_overlay_type.clear()


func _get_painter_overlay_y(cell: HexCellData) -> float:
	if grid.flat_mode:
		return cell.elevation * 0.05 + 0.025
	return cell.elevation + 0.025


func angle_difference(a: float, b: float) -> float:
	var diff := fmod(b - a, TAU)
	if diff > PI:
		diff -= TAU
	elif diff < -PI:
		diff += TAU
	return diff


# ============================================================================
# BUILDING MENU
# ============================================================================

func _toggle_build_menu() -> void:
	_menu_visible = not _menu_visible
	if _menu_panel:
		_menu_panel.visible = _menu_visible
	if not _menu_visible and not placement_mode:
		delete_mode = false
		_update_ghost_visibility()


func _select_first_item() -> void:
	if block_lib.get_category_count() > 0:
		var first_cat: String = block_lib.category_names[0]
		_select_category(first_cat)


func _select_category(category: String) -> void:
	_selected_category = category
	_rebuild_item_list()
	_update_category_buttons()


func _select_item(item_name: String) -> void:
	_selected_item_name = item_name
	placement_mode = true
	delete_mode = false
	_update_place_button()
	_update_ghost_visibility()
	_update_item_buttons()


func _toggle_delete_mode() -> void:
	delete_mode = not delete_mode
	if delete_mode:
		placement_mode = false
		_selected_item_name = ""
	_outline_mat.albedo_color = Color(1.0, 0.95, 0.3, 1.0)
	_update_place_button()
	_update_ghost_visibility()
	_update_delete_button()
	_update_item_buttons()


func _update_category_buttons() -> void:
	if _category_container == null:
		return
	for child in _category_container.get_children():
		if child is Button:
			child.modulate = Color(1, 1, 1) if child.text == _selected_category else Color(0.6, 0.6, 0.6)


func _update_item_buttons() -> void:
	if _item_container == null:
		return
	for child in _item_container.get_children():
		if child is Button:
			var iname: String = child.get_meta("item_name", "")
			if delete_mode:
				child.modulate = Color(1.0, 0.6, 0.6)
			elif iname == _selected_item_name:
				child.modulate = Color(0.5, 1.0, 0.5)
			else:
				child.modulate = Color(1, 1, 1)


func _rebuild_item_list() -> void:
	if _item_container == null:
		return
	for child in _item_container.get_children():
		child.queue_free()
	var items: Array = block_lib.get_items(_selected_category)
	var named_items: Array[Dictionary] = []
	for item_entry in items:
		var item_name := ""
		for n in block_lib.get_all_item_names():
			if block_lib.get_item(n) == item_entry:
				item_name = n
				break
		if item_name == "":
			continue
		named_items.append({"name": item_name, "entry": item_entry})
	named_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	for ni in named_items:
		var item_name: String = ni["name"]
		var item_entry: Dictionary = ni["entry"]
		var btn := Button.new()
		btn.text = item_name.get_file() if "/" in item_name else item_name
		btn.custom_minimum_size = Vector2(48, 56)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 9)
		btn.set_meta("item_name", item_name)
		var preview: Texture2D = item_entry.get("preview")
		if preview != null:
			btn.icon = preview
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			btn.expand_icon = true
		var captured_name := item_name
		btn.pressed.connect(func() -> void: _select_item(captured_name))
		_item_container.add_child(btn)
	_update_item_buttons()


func _update_place_button() -> void:
	var btn := get_node_or_null("UI/TopBar/PlaceModeBtn") as Button
	if btn:
		btn.button_pressed = placement_mode


func _update_delete_button() -> void:
	if _delete_btn:
		_delete_btn.button_pressed = delete_mode


func _on_placement_toggled(pressed: bool) -> void:
	if pressed:
		placement_mode = true
		delete_mode = false
	else:
		placement_mode = false
		_selected_item_name = ""
	_outline_mat.albedo_color = Color(1.0, 0.95, 0.3, 1.0)
	_update_ghost_visibility()
	_update_item_buttons()


func _on_category_pressed(category: String) -> void:
	_select_category(category)


# ============================================================================
# SAVE / LOAD
# ============================================================================

func _save_placed_blocks() -> void:
	var blocks: Array[Dictionary] = []
	for coords in _placed_blocks:
		var entry: Dictionary = _placed_blocks[coords]
		blocks.append({
			"q": coords.x, "r": coords.y, "s": coords.z,
			"item_name": entry["item_name"],
			"rotation": entry["rotation"],
		})
	var roads: Array[Dictionary] = []
	for coords in _road_cells:
		roads.append({"q": coords.x, "r": coords.y, "s": coords.z})
	var rivers: Array[Dictionary] = []
	for coords in _river_cells:
		rivers.append({"q": coords.x, "r": coords.y, "s": coords.z})
	var save_data: Dictionary = {
		"noise_seed": _noise_seed,
		"noise_freq": grid.noise_freq,
		"blocks": blocks,
		"roads": roads,
		"rivers": rivers,
	}
	var json_text := JSON.stringify(save_data, "\t")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		_show_status("FAILED to save!")
		return
	f.store_string(json_text)
	f.close()
	_show_status("Saved %d blocks, %d roads, %d rivers" % [blocks.size(), roads.size(), rivers.size()])


func _load_placed_blocks() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_show_status("No save file found")
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		_show_status("FAILED to open save file")
		return
	var json_text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(json_text)
	if parsed == null:
		_show_status("Invalid save file")
		return
	var blocks: Array = []
	if parsed is Dictionary:
		if parsed.has("noise_seed"):
			_noise_seed = float(parsed["noise_seed"])
			grid.noise_seed = _noise_seed
		if parsed.has("noise_freq"):
			grid.noise_freq = float(parsed["noise_freq"])
		_clear_all_placed_blocks()
		grid.clear_grid()
		blocks = parsed.get("blocks", [])
	elif parsed is Array:
		blocks = parsed
	else:
		_show_status("Invalid save file")
		return
	var loaded := 0
	for entry in blocks:
		var coords := Vector3i(int(entry["q"]), int(entry["r"]), int(entry["s"]))
		var item_name: String = entry.get("item_name", "")
		var rot_y: float = entry["rotation"]
		if _placed_blocks.has(coords):
			continue
		if item_name == "" or not block_lib.get_item(item_name):
			var mesh_idx: int = int(entry.get("mesh_idx", 0))
			var proc_items := block_lib.get_items("Blocks")
			if mesh_idx >= 0 and mesh_idx < proc_items.size():
				item_name = block_lib.get_all_item_names()[mesh_idx]
			else:
				continue
		var item: Dictionary = block_lib.get_item(item_name)
		var world_pos := HexGridMath.cube_to_world_flat_top(coords, HEX_SIZE)
		var cell := grid.get_cell(coords)
		var y_val := 0.0
		if cell != null:
			y_val = cell.elevation if not grid.flat_mode else 0.0
		var inst := RenderingServer.instance_create()
		RenderingServer.instance_set_scenario(inst, get_world_3d().scenario)
		RenderingServer.instance_set_base(inst, item["mesh_rid"])
		if not item.get("has_own_material", false):
			RenderingServer.instance_set_surface_override_material(inst, 0, block_lib.get_material().get_rid())
		var load_scale := block_lib.get_hex_scale(item_name)
		var aabb: AABB = item.get("aabb", AABB())
		var y_offset := -aabb.position.y * load_scale
		y_val += y_offset
		var rot_basis := Basis(Vector3.UP, rot_y + HEX_ROTATION)
		var scaled_basis := rot_basis.scaled(Vector3(load_scale, load_scale, load_scale))
		RenderingServer.instance_set_transform(inst, Transform3D(scaled_basis, Vector3(world_pos.x, y_val, world_pos.z)))
		_placed_blocks[coords] = {"rid": inst, "item_name": item_name, "rotation": rot_y}
		loaded += 1
	var roads_data: Array = parsed.get("roads", []) if parsed is Dictionary else []
	var rivers_data: Array = parsed.get("rivers", []) if parsed is Dictionary else []
	for entry in roads_data:
		var coords := Vector3i(int(entry["q"]), int(entry["r"]), int(entry["s"]))
		if grid.has_tile(coords) and not _road_cells.has(coords):
			_road_cells[coords] = true
			_tile_overlay_type[coords] = "road"
	for coords in _road_cells:
		_build_overlay(coords, _road_cells, _road_instances, _road_mat)
	for entry in rivers_data:
		var coords := Vector3i(int(entry["q"]), int(entry["r"]), int(entry["s"]))
		if grid.has_tile(coords) and not _river_cells.has(coords):
			_river_cells[coords] = true
			_tile_overlay_type[coords] = "river"
	for coords in _river_cells:
		_build_overlay(coords, _river_cells, _river_instances, _river_mat)
	_show_status("Loaded %d blocks, %d roads, %d rivers" % [loaded, roads_data.size(), rivers_data.size()])


# ============================================================================
# LOADING SCREEN
# ============================================================================

func _show_loading_screen(msg: String) -> void:
	_loading_canvas = CanvasLayer.new()
	_loading_canvas.layer = 100
	add_child(_loading_canvas)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_canvas.add_child(bg)
	_loading_label = Label.new()
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_label.add_theme_font_size_override("font_size", 32)
	_loading_label.add_theme_color_override("font_color", Color.WHITE)
	_loading_label.text = msg
	_loading_canvas.add_child(_loading_label)


func _update_loading(msg: String) -> void:
	if _loading_label:
		_loading_label.text = msg


func _hide_loading_screen() -> void:
	if _loading_canvas:
		_loading_canvas.queue_free()
		_loading_canvas = null
		_loading_label = null


func _show_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
		_status_label.modulate.a = 1.0


# ============================================================================
# CAMERA
# ============================================================================

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


func _update_outline(cell: HexCellData) -> void:
	var world_pos := HexGridMath.cube_to_world_flat_top(cell.coords, HEX_SIZE)
	var y := cell.elevation if not grid.flat_mode else 0.0
	RenderingServer.instance_set_transform(
		_outline_inst_rid, Transform3D(Basis.IDENTITY, Vector3(world_pos.x, y + 0.02, world_pos.z))
	)
	RenderingServer.instance_set_visible(_outline_inst_rid, true)


func _update_info_label(cell: HexCellData) -> void:
	var v4 := cell.to_vector4()
	var tile_names := ["grass", "water", "stone", "dirt", "sand"]
	var tname := "unknown"
	if cell.mesh_id >= 0 and cell.mesh_id < tile_names.size():
		tname = tile_names[cell.mesh_id]
	var placed := ""
	if _placed_blocks.has(cell.coords):
		var entry: Dictionary = _placed_blocks[cell.coords]
		placed = " | Built: %s" % entry.get("item_name", "?")
	info_label.text = "Vec4(%.0f, %.0f, %.0f, %.2f) | Dist: %d | %s %s%s" % [
		v4.x, v4.y, v4.z, v4.w,
		cell.distance_from_center,
		tname,
		"[FLAT]" if grid.flat_mode else "",
		placed,
	]


func _generate_normal_map() -> void:
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
			img.set_pixel(x, y, Color(nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5, 1.0))
	_normal_map_tex = ImageTexture.create_from_image(img)
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


# ============================================================================
# ENVIRONMENT / CAMERA / LIGHTING / GRID
# ============================================================================

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
	grid.flat_mode = true
	grid.tile_library = library
	grid.camera = camera
	grid.noise_seed = _noise_seed
	grid.noise_freq = 0.008
	add_child(grid)
	grid.type_mapping = [grass_id, water_id, stone_id, dirt_id, sand_id]


func _set_shared_shader_params(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("normal_map", _normal_map_tex)
	mat.set_shader_parameter("detail_noise", _detail_noise_tex)


# ============================================================================
# UI SETUP
# ============================================================================

func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.position = Vector2(16, 56)
	info_label.add_theme_font_size_override("font_size", 16)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	info_label.add_theme_constant_override("shadow_offset_x", 1)
	info_label.add_theme_constant_override("shadow_offset_y", 1)
	info_label.text = "Hovering: ---"
	canvas.add_child(info_label)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.position = Vector2(16, 80)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	_status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_status_label.add_theme_constant_override("shadow_offset_y", 1)
	_status_label.text = ""
	canvas.add_child(_status_label)

	coord_label = Label.new()
	coord_label.name = "CoordLabel"
	coord_label.position = Vector2(16, 32)
	coord_label.add_theme_font_size_override("font_size", 14)
	coord_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	coord_label.text = "Loading..."
	canvas.add_child(coord_label)

	_setup_top_bar(canvas)
	_setup_build_menu(canvas)


func _setup_top_bar(canvas: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.name = "TopBar"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 32.0
	canvas.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.name = "Controls"
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var regen_btn := Button.new()
	regen_btn.text = "Regen (R)"
	regen_btn.pressed.connect(_on_regen_pressed)
	hbox.add_child(regen_btn)

	var chunk_label := Label.new()
	chunk_label.text = "Chunk:"
	chunk_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(chunk_label)

	var chunk_spin := SpinBox.new()
	chunk_spin.name = "ChunkSizeSpin"
	chunk_spin.min_value = 8
	chunk_spin.max_value = 256
	chunk_spin.step = 8
	chunk_spin.value = grid.chunk_size
	chunk_spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chunk_spin.custom_minimum_size.x = 70
	chunk_spin.value_changed.connect(_on_chunk_size_changed)
	hbox.add_child(chunk_spin)

	var budget_label := Label.new()
	budget_label.text = "Budget:"
	budget_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(budget_label)

	var budget_spin := SpinBox.new()
	budget_spin.name = "BudgetSpin"
	budget_spin.min_value = 64
	budget_spin.max_value = 65536
	budget_spin.step = 64
	budget_spin.value = grid.tiles_per_frame
	budget_spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	budget_spin.custom_minimum_size.x = 70
	budget_spin.value_changed.connect(func(v: float) -> void: grid.tiles_per_frame = int(v))
	hbox.add_child(budget_spin)

	var sep := VSeparator.new()
	hbox.add_child(sep)

	var build_btn := Button.new()
	build_btn.text = "Build (B)"
	build_btn.pressed.connect(_toggle_build_menu)
	hbox.add_child(build_btn)

	var save_btn := Button.new()
	save_btn.text = "Save (Ctrl+S)"
	save_btn.pressed.connect(_save_placed_blocks)
	hbox.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load (Ctrl+O)"
	load_btn.pressed.connect(_load_placed_blocks)
	hbox.add_child(load_btn)


func _setup_build_menu(canvas: CanvasLayer) -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.name = "BuildMenu"
	_menu_panel.anchor_left = 0.0
	_menu_panel.anchor_top = 1.0
	_menu_panel.anchor_right = 1.0
	_menu_panel.anchor_bottom = 1.0
	_menu_panel.offset_left = 0.0
	_menu_panel.offset_top = -200.0
	_menu_panel.offset_right = 0.0
	_menu_panel.offset_bottom = 0.0
	_menu_panel.custom_minimum_size = Vector2(0, 200)
	_menu_panel.visible = false
	canvas.add_child(_menu_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_theme_constant_override("separation", 4)
	_menu_panel.add_child(outer_vbox)

	var title := Label.new()
	title.text = "BUILD"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	outer_vbox.add_child(title)

	var cat_bar := HBoxContainer.new()
	cat_bar.name = "CategoryBar"
	cat_bar.add_theme_constant_override("separation", 4)
	cat_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(cat_bar)

	_delete_btn = Button.new()
	_delete_btn.name = "DeleteBtn"
	_delete_btn.text = "DEL"
	_delete_btn.toggle_mode = true
	_delete_btn.custom_minimum_size = Vector2(40, 0)
	_delete_btn.pressed.connect(_toggle_delete_mode)
	cat_bar.add_child(_delete_btn)

	_road_btn = Button.new()
	_road_btn.name = "RoadBtn"
	_road_btn.text = "Road"
	_road_btn.custom_minimum_size = Vector2(48, 0)
	_road_btn.pressed.connect(func() -> void: _set_painter_mode("road"))
	cat_bar.add_child(_road_btn)

	_river_btn = Button.new()
	_river_btn.name = "RiverBtn"
	_river_btn.text = "River"
	_river_btn.custom_minimum_size = Vector2(48, 0)
	_river_btn.pressed.connect(func() -> void: _set_painter_mode("river"))
	cat_bar.add_child(_river_btn)

	_category_container = cat_bar
	for category in block_lib.category_names:
		var btn := Button.new()
		btn.text = category
		btn.custom_minimum_size = Vector2(0, 28)
		var captured := category
		btn.pressed.connect(func() -> void: _on_category_pressed(captured))
		cat_bar.add_child(btn)

	var sep := HSeparator.new()
	outer_vbox.add_child(sep)

	_item_scroll = ScrollContainer.new()
	_item_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(_item_scroll)

	_item_container = GridContainer.new()
	_item_container.columns = 10
	_item_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_container.add_theme_constant_override("h_separation", 4)
	_item_container.add_theme_constant_override("v_separation", 4)
	_item_scroll.add_child(_item_container)


func _on_chunk_size_changed(value: float) -> void:
	grid.clear_grid()
	grid.chunk_size = int(value)
	_noise_seed = randf() * 1000.0
	grid.noise_seed = _noise_seed


func _on_regen_pressed() -> void:
	_noise_seed = randf() * 1000.0
	grid.noise_seed = _noise_seed
	_clear_all_placed_blocks()
	_clear_all_overlays()
	grid.clear_grid()


# ============================================================================
# OUTLINE
# ============================================================================

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
