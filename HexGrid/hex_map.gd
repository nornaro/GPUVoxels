extends Node3D

const HEX_SIZE: float = 1.1547
const SUB_HEX_SIZE: float = HEX_SIZE / 3.0
const SUB_HEX_DIST: float = HEX_SIZE * 0.57735026919
const VERTEX_OFFSET: int = 7
const TOTAL_SUBS: int = 13

const VERTEX_NEIGHBORS: Array = [
	[0, 1], [0, 5], [5, 4], [4, 3], [3, 2], [2, 1],
]

const BIOME_DEEP_WATER := 0
const BIOME_WATER := 1
const BIOME_BEACH := 2
const BIOME_GRASS := 3
const BIOME_DIRT := 4
const BIOME_STONE := 5

const BIOME_NAMES := ["Deep Water", "Water", "Beach", "Grass", "Dirt", "Stone"]

const ELEVATION_STEPS: Array[float] = [1.0, 0.1, 0.01, 0.0]
const ELEVATION_STEP_NAMES: Array[String] = ["Step 1.0", "Step 0.1", "Step 0.01", "Flat"]
const TOOL_NAMES := ["Navigate", "Raise", "Flatten", "Level", "Place"]

const RESOURCE_TREE_MODELS := [
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/trees_A_large.tscn",
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/trees_B_large.tscn",
]
const RESOURCE_MOUNTAIN_MODELS := [
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/mountain_A.tscn",
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/mountain_B.tscn",
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/mountain_C.tscn",
]
const RESOURCE_ROCK_MODELS := [
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/rock_single_A.tscn",
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/rock_single_B.tscn",
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/rock_single_C.tscn",
]
const MINERAL_TYPES := ["silver", "gold", "tungsten", "titanium", "copper"]
const MINERAL_COLORS := {
	"silver": Color(0.75, 0.75, 0.8, 0.6),
	"gold": Color(0.95, 0.8, 0.2, 0.6),
	"tungsten": Color(0.4, 0.42, 0.5, 0.6),
	"titanium": Color(0.6, 0.65, 0.7, 0.6),
	"copper": Color(0.85, 0.5, 0.25, 0.6),
	"oil": Color(0.15, 0.15, 0.15, 0.6),
}
const RESOURCE_OIL_COLOR := Color(0.15, 0.15, 0.15, 0.6)

const INVALID_HEX := Vector3i(999999, 999999, -1999998)

const WALL_BASE := "res://assets/kaykit_medieval_hexagon_pack/buildings/neutral/"

const WALL_TYPE_STRAIGHT := 0
const WALL_TYPE_CORNER_A_IN := 1
const WALL_TYPE_CORNER_A_OUT := 2
const WALL_TYPE_CORNER_B_IN := 3
const WALL_TYPE_CORNER_B_OUT := 4

const WALL_MODEL_TYPES: Dictionary = {
	"wall_straight.tscn": WALL_TYPE_STRAIGHT,
	"wall_straight_gate.tscn": WALL_TYPE_STRAIGHT,
	"wall_straight_gate_door_left.tscn": WALL_TYPE_STRAIGHT,
	"wall_straight_gate_door_right.tscn": WALL_TYPE_STRAIGHT,
	"wall_corner_A_inside.tscn": WALL_TYPE_CORNER_A_IN,
	"wall_corner_A_outside.tscn": WALL_TYPE_CORNER_A_OUT,
	"wall_corner_A_gate.tscn": WALL_TYPE_CORNER_A_IN,
	"wall_corner_A_gate_door_left.tscn": WALL_TYPE_CORNER_A_IN,
	"wall_corner_A_gate_door_right.tscn": WALL_TYPE_CORNER_A_IN,
	"wall_corner_B_inside.tscn": WALL_TYPE_CORNER_B_IN,
	"wall_corner_B_outside.tscn": WALL_TYPE_CORNER_B_OUT,
}

var cells: Dictionary = {}
var chunk_manager: ChunkManager
var _terrain: Node3D = null
var _current_approach: String = ""
var _world: Node3D = null
var _gameplay: Node3D = null

var camera: Camera3D
var cam_yaw: float = 45.0
var cam_pitch: float = -55.0
var cam_dist: float = 500.0
var cam_pivot: Vector3 = Vector3.ZERO
var orbiting: bool = false
var orbit_start: Vector2 = Vector2.ZERO
var orbit_yaw_start: float = 0.0
var orbit_pitch_start: float = 0.0
var panning: bool = false
var pan_start: Vector2 = Vector2.ZERO
var pan_origin: Vector3 = Vector3.ZERO

var tool_mode: int = 0
var elevation_step_idx: int = 0
var elevation_step: float = 1.0
var painting: bool = false

var show_overlay: bool = false
var show_resources: bool = false

var resource_cache: Dictionary = {}
var _decoration_multimeshes: Dictionary = {}
var _decoration_mesh_cache: Dictionary = {}
var _objects_container: Node3D

var placed_objects: Dictionary = {}
var _placed_object_instances: Dictionary = {}
var selected_model_path: String = ""
var _placement_rotation: float = 0.0
var _placement_scale: float = 1.0
var _default_scale: float = 1.0
var _ghost_instance: Node3D = null
var _ghost_model_path: String = ""
var _ghost_indicators: Node3D = null
var _indicator_mesh: SphereMesh

var _level_target: Vector3i = INVALID_HEX
var _flatten_target: float = 0.0
var _flatten_captured: bool = false

var _area_selector: AreaSelector = AreaSelector.new()
var _tile_valuator: TileValuator = TileValuator.new()
var _show_tile_values: bool = false

var _needs_rebuild: bool = false
var _last_overlay_hex: Vector3i = INVALID_HEX
var _cached_mouse_hex: Vector3i = INVALID_HEX
var _mouse_hex_valid: bool = false
var _overlay_rebuild_timer: float = 0.0

var _overlay_mesh_instance: MeshInstance3D
var _tool_flash_timer: float = 0.0
var _last_hover_hex: Vector3i = Vector3i(999999, 999999, -1999998)

var _top_toolbar: HBoxContainer
var _tool_label: Label
var _info_label: Label
var _tool_buttons: Array[Button] = []
var _bottom_palette: PanelContainer
var _palette_tabs: TabContainer

var _label: Label
var _menu: Control
var _height_slider: HSlider
var _height_label: Label
var _height_input: LineEdit
var _grid_slider: HSlider
var _grid_label: Label
var _grid_input: LineEdit
var _radius_slider: HSlider
var _radius_label: Label
var _radius_input: LineEdit
var _exp_slider: HSlider
var _exp_label: Label
var _exp_input: LineEdit

var _cursor_instance: MeshInstance3D
var _last_cursor_hex: Vector3i = INVALID_HEX
var _enemy_manager: Node3D
var _spawn_rate_slider: HSlider
var _max_enemies_slider: HSlider
var _spawn_rate_label: Label
var _max_enemies_label: Label
var _spawn_batch_slider: HSlider
var _spawn_batch_label: Label
var _mob_print_timer: float = 10.0


func _ready() -> void:
	chunk_manager = ChunkManager.new(cells)

	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_setup_lighting()
	_setup_camera()

	_gameplay = Node3D.new()
	_gameplay.name = "Gameplay"
	add_child(_gameplay)

	_objects_container = Node3D.new()
	_gameplay.add_child(_objects_container)

	_enemy_manager = preload("res://HexGrid/enemy_manager.gd").new()
	_enemy_manager.name = "EnemyManager"
	_gameplay.add_child(_enemy_manager)
	_enemy_manager.setup(cells, chunk_manager)
	_enemy_manager.spawn_interval = 2.0
	_enemy_manager.max_enemies = 30
	_enemy_manager.spawn_batch_size = 1
	_enemy_manager.set_max_enemies(30)

	_ghost_indicators = Node3D.new()
	_ghost_indicators.name = "GhostIndicators"
	_gameplay.add_child(_ghost_indicators)
	_indicator_mesh = SphereMesh.new()
	_indicator_mesh.radius = 0.15
	_indicator_mesh.height = 0.3
	_overlay_mesh_instance = MeshInstance3D.new()
	var overlay_mat := StandardMaterial3D.new()
	overlay_mat.vertex_color_use_as_albedo = true
	overlay_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay_mesh_instance.material_override = overlay_mat
	add_child(_overlay_mesh_instance)
	_setup_cursor()
	_setup_ui()
	_update_camera_transform()
	call_deferred("_on_flat")
	if _height_slider:
		_enemy_manager.set_height_params(_height_slider.value, _exp_slider.value)
	print("Ready.")


func _exit_tree() -> void:
	if chunk_manager:
		chunk_manager.cleanup()


func _process(delta: float) -> void:
	_mouse_hex_valid = false

	var _t := Time.get_ticks_usec()
	_process_orbit()
	_process_pan()
	_process_wasd(delta)

	if _tool_flash_timer > 0.0:
		_tool_flash_timer -= delta
		if _tool_flash_timer <= 0.0:
			_update_tool_ui()

	var cur_hex := _get_mouse_hex()
	_mouse_hex_valid = true
	_cached_mouse_hex = cur_hex
	var t1 := Time.get_ticks_usec()

	_overlay_rebuild_timer -= delta

	if show_overlay or show_resources or (tool_mode == 4 and not selected_model_path.is_empty()):
		var chunk_size := 10
		var cur_ck := Vector2i(floori(float(cur_hex.x) / chunk_size), floori(float(cur_hex.y) / chunk_size))
		var last_ck := Vector2i(floori(float(_last_overlay_hex.x) / chunk_size), floori(float(_last_overlay_hex.y) / chunk_size))
		if (cur_ck != last_ck or _needs_rebuild) and _overlay_rebuild_timer <= 0.0:
			_rebuild_overlay_mesh()
			_last_overlay_hex = cur_hex
			_overlay_rebuild_timer = 0.08
		_needs_rebuild = false
	elif _needs_rebuild and _overlay_rebuild_timer <= 0.0:
		_rebuild_overlay_mesh()
		_needs_rebuild = false
		_overlay_rebuild_timer = 0.08
	var t2 := Time.get_ticks_usec()

	if tool_mode == 4:
		_update_ghost_position(cur_hex)
	_update_hover_info(cur_hex)
	_update_cursor(cur_hex)
	var t3 := Time.get_ticks_usec()

	_mob_print_timer -= delta
	if _mob_print_timer <= 0.0:
		_mob_print_timer = 60.0
		var c = _enemy_manager.get_enemy_count()
		if c > 0:
			print("Active mobs: %d / %d" % [c, _enemy_manager.max_enemies])

	var total_dt := Time.get_ticks_usec() - _t
	if total_dt > 3000:
		print("PERF: hex_map total=%dus" % [total_dt])


func _process_orbit() -> void:
	if not orbiting:
		return
	var mpos := get_viewport().get_mouse_position()
	var diff := mpos - orbit_start
	cam_yaw = orbit_yaw_start - diff.x * 0.3
	cam_pitch = clampf(orbit_pitch_start + diff.y * 0.3, -89.0, -5.0)
	_update_camera_transform()


func _process_pan() -> void:
	if not panning:
		return
	var mpos := get_viewport().get_mouse_position()
	var diff := mpos - pan_start
	var cam_basis := camera.global_transform.basis
	var flat_right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z)
	if flat_right.length_squared() > 0.001:
		flat_right = flat_right.normalized()
	else:
		flat_right = Vector3.RIGHT
	var flat_forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z)
	if flat_forward.length_squared() > 0.001:
		flat_forward = flat_forward.normalized()
	else:
		flat_forward = Vector3.FORWARD
	var pan_speed := cam_dist * 0.002
	cam_pivot = pan_origin - flat_right * diff.x * pan_speed + flat_forward * diff.y * pan_speed
	_update_camera_transform()


func _process_wasd(delta: float) -> void:
	var cam_basis := camera.global_transform.basis
	var flat_right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z)
	if flat_right.length_squared() > 0.001:
		flat_right = flat_right.normalized()
	else:
		flat_right = Vector3.RIGHT
	var flat_forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z)
	if flat_forward.length_squared() > 0.001:
		flat_forward = flat_forward.normalized()
	else:
		flat_forward = Vector3.FORWARD
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move += flat_forward
	if Input.is_key_pressed(KEY_S):
		move -= flat_forward
	if Input.is_key_pressed(KEY_A):
		move -= flat_right
	if Input.is_key_pressed(KEY_D):
		move += flat_right
	if move.length_squared() > 0.001:
		var speed := cam_dist * 3.0 * delta
		cam_pivot += move.normalized() * speed
		_update_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey:
		_handle_key(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = false
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if panning:
				panning = false
			painting = false
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		cam_dist = maxf(cam_dist * 0.85, 10.0)
		_update_camera_transform()
		return
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		cam_dist = minf(cam_dist * 1.18, 5000.0)
		_update_camera_transform()
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		if tool_mode == 3 or tool_mode == 4:
			_cancel_placement()
			return
		orbiting = true
		orbit_start = event.position
		orbit_yaw_start = cam_yaw
		orbit_pitch_start = cam_pitch
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if tool_mode == 0:
			panning = true
			pan_start = event.position
			pan_origin = cam_pivot
		else:
			var hex := _get_mouse_hex()
			if tool_mode >= 1 and tool_mode <= 3:
				if Input.is_key_pressed(KEY_SHIFT):
					_area_selector.extend_selection(hex)
					_needs_rebuild = true
					return
				elif not _area_selector.has_active_selection:
					_area_selector.select_base(hex)
					_needs_rebuild = true

				if _area_selector.has_active_selection and not Input.is_key_pressed(KEY_SHIFT):
					if _area_selector.is_ready():
						_apply_area_action()
					else:
						match tool_mode:
							1:
								painting = true
								_raise_hex(hex)
							2:
								painting = true
								_flatten_hex(hex)
							3:
								painting = true
								_level_hex(hex)
			if tool_mode == 4:
				_place_object_at(event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if painting and tool_mode == 1:
		_raise_at(event.position)
	elif painting and tool_mode == 2:
		_flatten_at(event.position)
	elif painting and tool_mode == 3:
		_level_at(event.position)


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	match event.keycode:
		KEY_1:
			_set_tool(0)
		KEY_2:
			_set_tool(1)
		KEY_3:
			_set_tool(2)
		KEY_4:
			_set_tool(3)
		KEY_5:
			_set_tool(4)
		KEY_H:
			show_overlay = not show_overlay
			_needs_rebuild = true
		KEY_J:
			show_resources = not show_resources
			_needs_rebuild = true
		KEY_TAB:
			_show_tile_values = not _show_tile_values
			_needs_rebuild = true
			_tool_flash("Tile values: %s" % ["ON" if _show_tile_values else "OFF"])
		KEY_ENTER:
			if _area_selector.is_ready():
				_apply_area_action()
		KEY_ESCAPE:
			if _area_selector.has_active_selection:
				_area_selector.remove_last_point()
				_needs_rebuild = true
			elif tool_mode == 4:
				_cancel_placement()
			else:
				_set_tool(0)
			painting = false
		KEY_F:
			elevation_step_idx = (elevation_step_idx + 1) % ELEVATION_STEPS.size()
			elevation_step = ELEVATION_STEPS[elevation_step_idx]
			_tool_flash("Elevation: " + ELEVATION_STEP_NAMES[elevation_step_idx])
		KEY_R:
			_regenerate_map()
		KEY_F6:
			_quick_save()
		KEY_F7:
			_quick_load()
		KEY_Z:
			if tool_mode == 4:
				_placement_rotation = wrapf(_placement_rotation - 60.0, 0.0, 360.0)
				_tool_flash("Rotation: %.0f° sides %s" % [_placement_rotation, str(_get_wall_connections(selected_model_path, _placement_rotation))])
		KEY_X:
			if tool_mode == 4:
				_placement_rotation = wrapf(_placement_rotation + 60.0, 0.0, 360.0)
				_tool_flash("Rotation: %.0f° sides %s" % [_placement_rotation, str(_get_wall_connections(selected_model_path, _placement_rotation))])
		KEY_KP_ADD:
			if tool_mode == 4:
				_placement_scale = clampf(_placement_scale + 0.05, 0.75, 1.25)
				_tool_flash("Scale: %.0f%%" % (_placement_scale * 100))
		KEY_KP_SUBTRACT:
			if tool_mode == 4:
				_placement_scale = clampf(_placement_scale - 0.05, 0.75, 1.25)
				_tool_flash("Scale: %.0f%%" % (_placement_scale * 100))


func _set_tool(mode: int) -> void:
	if tool_mode == 4 and mode != 4:
		_remove_ghost()
	tool_mode = mode
	_level_target = INVALID_HEX
	_flatten_captured = false
	painting = false
	_area_selector.clear()
	_needs_rebuild = true
	_update_tool_buttons()
	_update_tool_ui()


func _regenerate_map() -> void:
	_remove_ghost()
	cells.clear()
	chunk_manager.cells = cells
	chunk_manager._loaded_chunk_origins.clear()
	chunk_manager.randomize_seeds()
	resource_cache.clear()
	_free_all_decorations()
	_free_all_object_instances()
	placed_objects.clear()
	_needs_rebuild = true
	if _enemy_manager:
		_enemy_manager.invalidate_all_paths()
	if _current_approach != "":
		if _current_approach == "flat":
			_on_flat()
		elif _current_approach == "prisms":
			_on_prisms()


func _quick_save() -> void:
	_save_map()
	_tool_flash("Quick Saved")


func _quick_load() -> void:
	if _load_map_from("res://map_save.json"):
		_tool_flash("Quick Loaded")


func _save_map() -> void:
	chunk_manager.save_map("res://map_save.json", {}, {}, {}, {}, [], {}, placed_objects, resource_cache)


func _load_map_from(path: String) -> bool:
	var loaded: Dictionary = chunk_manager.load_map(path)
	if loaded.is_empty():
		return false
	placed_objects = loaded.get("objects", {})
	_rebuild_object_instances()
	resource_cache = loaded.get("resource_cache", {})
	_recompute_all_resources()
	_needs_rebuild = true
	if _enemy_manager:
		_enemy_manager.invalidate_all_paths()
	if _current_approach != "":
		if _current_approach == "flat":
			_on_flat()
		elif _current_approach == "prisms":
			_on_prisms()
	return true


func _tool_flash(msg: String) -> void:
	_tool_label.text = msg
	_tool_flash_timer = 1.5


func _screen_to_world_at_height(screen_pos: Vector2, y: float) -> Vector3:
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	if absf(ray_dir.y) < 0.0001:
		return Vector3(INF, INF, INF)
	var t := (y - ray_origin.y) / ray_dir.y
	if t < 0:
		return Vector3(INF, INF, INF)
	return ray_origin + ray_dir * t


func _screen_to_world_3d(screen_pos: Vector2) -> Vector3:
	return _screen_to_world_at_height(screen_pos, 0.0)


func _get_mouse_hex() -> Vector3i:
	var screen_pos := get_viewport().get_mouse_position()
	var world_pos := _screen_to_world_at_height(screen_pos, 0.0)
	if world_pos.x == INF:
		return INVALID_HEX
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	for _i in 8:
		if not cells.has(hex):
			break
		var cell: HexCellData = cells[hex]
		var height := _get_cell_height(cell)
		var refined := _screen_to_world_at_height(screen_pos, height)
		if refined.x == INF:
			break
		var new_hex := HexGridMath.world_to_cube_flat_top(refined, HEX_SIZE)
		if new_hex == hex:
			break
		hex = new_hex
	return hex


func _cell_exists(hex: Vector3i) -> bool:
	return cells.has(hex)


func _get_cell_height(cell: HexCellData) -> float:
	var step_size := _height_slider.value if _height_slider else 3.0
	var exp_val := _exp_slider.value if _exp_slider else 1.0
	var e_norm := clampf(cell.elevation / 4.0, 0.0, 1.0)
	return pow(maxf(step_size * e_norm, 0.001), exp_val)


func _is_water_biome(biome: int) -> bool:
	return biome == BIOME_DEEP_WATER or biome == BIOME_WATER


func _is_sub_hex_water(hex: Vector3i, _sub_idx: int) -> bool:
	if not _cell_exists(hex):
		return false
	var c: HexCellData = cells[hex]
	if _is_water_biome(c.biome):
		return true
	return false


func _update_hover_info(hex: Vector3i) -> void:
	if tool_mode == 4:
		return
	if hex == _last_hover_hex:
		return
	_last_hover_hex = hex
	if _cell_exists(hex):
		var cell: HexCellData = cells[hex]
		var biome_name: String = BIOME_NAMES[cell.biome] if cell.biome < BIOME_NAMES.size() else "?"
		var world_pos := _screen_to_world_3d(get_viewport().get_mouse_position())
		var hex_world := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var local := world_pos - hex_world
		var best_sub := 0
		var best_dist := INF
		for i in TOTAL_SUBS:
			var sub_pos := _get_sub_hex_local_pos(hex, i)
			var d := Vector2(local.x, local.z).distance_to(sub_pos)
			if d < best_dist:
				best_dist = d
				best_sub = i
		var labels := ""
		if placed_objects.has(hex):
			var obj_data: Variant = placed_objects[hex]
			if obj_data is Dictionary:
				labels += "  |  OBJ rot:%.0f° scale:%.0f%%" % [obj_data.get("rotation", 0.0), obj_data.get("scale", 1.0) * 100]
		var display_h: float = _get_cell_height(cell)
		_info_label.text = "Hex: (%d,%d,%d)  |  %s  |  Sub %d  |  Elev: %.2f  |  H: %.1f%s" % [
			hex.x, hex.y, hex.z, biome_name, best_sub, cell.elevation, display_h, labels
		]
	else:
		_info_label.text = "Hex: none"


func _update_tool_ui() -> void:
	var tool_name: String = TOOL_NAMES[tool_mode] if tool_mode < TOOL_NAMES.size() else "?"
	_tool_label.text = "Tool: %s" % tool_name
	if tool_mode == 4:
		_info_label.text = "Place: LMB | Cancel: RMB/Esc | Rotate: Z/X | Scale: +/-"
	else:
		_info_label.text = "Pan: LMB | Orbit: RMB | Zoom: Scroll | 1-5: Tools | H: Overlay | F: ElevStep | R: Regen"


func _update_tool_buttons() -> void:
	for i in _tool_buttons.size():
		_tool_buttons[i].button_pressed = (i == tool_mode)


func _get_wall_type(model_path: String) -> int:
	var fname := model_path.get_file()
	return WALL_MODEL_TYPES.get(fname, WALL_TYPE_STRAIGHT)


func _get_wall_connections(model_path: String, rot_deg: float) -> Array:
	var wtype := _get_wall_type(model_path)
	var r := int(rot_deg / 60.0) % 6
	if r < 0:
		r += 6
	var base: int = (6 - r) % 6
	match wtype:
		WALL_TYPE_STRAIGHT:
			return [base, (base + 3) % 6]
		WALL_TYPE_CORNER_A_IN:
			return [base, (base + 2) % 6]
		WALL_TYPE_CORNER_A_OUT:
			return [base, (base + 4) % 6]
		WALL_TYPE_CORNER_B_IN:
			return [base, (base + 1) % 6]
		WALL_TYPE_CORNER_B_OUT:
			return [base, (base + 5) % 6]
	return []


func _is_wall_connection_valid(hex: Vector3i, model_path: String, rot_deg: float) -> bool:
	var sides := _get_wall_connections(model_path, rot_deg)
	if sides.is_empty():
		return false
	for s in sides:
		var si: int = int(s)
		var neighbor := hex + HexGridMath.cube_direction(si)
		if not cells.has(neighbor):
			continue
		if not placed_objects.has(neighbor):
			continue
		var n_data: Variant = placed_objects[neighbor]
		if not n_data is Dictionary:
			continue
		var n_path: String = n_data.get("path", "")
		var n_rot: float = n_data.get("rotation", 0.0)
		var n_sides := _get_wall_connections(n_path, n_rot)
		var opposite: int = (int(s) + 3) % 6
		if opposite in n_sides:
			continue
		return false
	return true


func _update_ghost_position(hex: Vector3i) -> void:
	if _ghost_instance == null:
		return
	if not _cell_exists(hex):
		_ghost_instance.visible = false
		_clear_indicators()
		return
	_ghost_instance.visible = true
	var cell: HexCellData = cells[hex]
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cell)
	_ghost_instance.position = Vector3(hpos.x, height, hpos.z)
	_ghost_instance.rotation_degrees.y = _placement_rotation
	_ghost_instance.scale = Vector3(_placement_scale, _placement_scale, _placement_scale)
	_update_indicators(hex)


func _clear_indicators() -> void:
	for c in _ghost_indicators.get_children():
		c.queue_free()


func _update_indicators(hex: Vector3i) -> void:
	_clear_indicators()
	if selected_model_path.is_empty():
		return
	var sides := _get_wall_connections(selected_model_path, _placement_rotation)
	var hex_pos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cells[hex])
	for s in sides:
		var si: int = int(s)
		var dir := HexGridMath.cube_direction(si)
		var n_hex := hex + dir
		var n_pos := HexGridMath.cube_to_world_flat_top(n_hex, HEX_SIZE)
		var mid := Vector3((hex_pos.x + n_pos.x) * 0.5, height + 0.5, (hex_pos.z + n_pos.z) * 0.5)
		var mi := MeshInstance3D.new()
		mi.mesh = _indicator_mesh
		var mat := StandardMaterial3D.new()
		var connected := false
		if placed_objects.has(n_hex):
			var n_data: Variant = placed_objects[n_hex]
			if n_data is Dictionary:
				var n_sides := _get_wall_connections(n_data.get("path", ""), n_data.get("rotation", 0.0))
				if (int(s) + 3) % 6 in n_sides:
					connected = true
		if connected:
			mat.albedo_color = Color(0.2, 1.0, 0.2, 0.9)
		else:
			mat.albedo_color = Color(1.0, 0.3, 0.2, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		mi.position = mid
		_ghost_indicators.add_child(mi)


func _create_ghost(model_path: String) -> void:
	_remove_ghost()
	if not ResourceLoader.exists(model_path):
		push_warning("Ghost: model not found: %s" % model_path)
		return
	var scene: PackedScene = load(model_path)
	if not scene:
		push_warning("Ghost: failed to load scene: %s" % model_path)
		return
	_ghost_instance = scene.instantiate()
	_objects_container.add_child(_ghost_instance)
	_ghost_model_path = model_path
	_set_node_transparency(_ghost_instance, 0.5)
	print("Ghost created: %s (children: %d)" % [model_path.get_file(), _ghost_instance.get_child_count()])


func _set_node_transparency(node: Node, alpha: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			var surf_count := 0
			if mi.mesh:
				surf_count = mi.mesh.get_surface_count()
			for i in surf_count:
				var mat = mi.get_surface_override_material(i)
				if mat == null and mi.mesh != null:
					mat = mi.mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					var new_mat: BaseMaterial3D = mat.duplicate() as BaseMaterial3D
					new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					var col := new_mat.albedo_color
					col.a = alpha
					new_mat.albedo_color = col
					mi.set_surface_override_material(i, new_mat)
		_set_node_transparency(child, alpha)


func _remove_ghost() -> void:
	if _ghost_instance and is_instance_valid(_ghost_instance):
		_ghost_instance.queue_free()
	_ghost_instance = null
	_ghost_model_path = ""
	_clear_indicators()


func _cancel_placement() -> void:
	_remove_ghost()
	selected_model_path = ""
	_placement_rotation = 0.0
	_placement_scale = _default_scale
	_set_tool(0)


# ============================================================================
# TERRAIN EDITING
# ============================================================================
func _raise_at(_screen_pos: Vector2) -> void:
	var hex := _get_mouse_hex()
	if not _cell_exists(hex):
		return
	_raise_hex(hex)


func _flatten_at(_screen_pos: Vector2) -> void:
	var hex := _get_mouse_hex()
	if not _cell_exists(hex):
		return
	if not _flatten_captured:
		var cell: HexCellData = cells[hex]
		_flatten_target = cell.elevation
		_flatten_captured = true
	_flatten_hex(hex)


func _level_at(_screen_pos: Vector2) -> void:
	var hex := _get_mouse_hex()
	if not _cell_exists(hex):
		return
	if _level_target == INVALID_HEX:
		_level_target = hex
		_tool_flash("Level target set: (%d,%d,%d)" % [hex.x, hex.y, hex.z])
		return
	_level_hex(hex)


func _raise_hex(hex: Vector3i) -> void:
	if not _cell_exists(hex):
		return
	var cell: HexCellData = cells[hex]
	var hex_width: float = HEX_SIZE * 1.73205080757
	var step := elevation_step if elevation_step > 0.0 else 0.1
	var delta := step / hex_width
	if Input.is_key_pressed(KEY_SHIFT):
		cell.elevation -= delta
	else:
		cell.elevation += delta
	cell.elevation = clampf(cell.elevation, -1.0, 2.0)
	_needs_rebuild = true
	_rebuild_chunk_for_hex(hex)
	if _enemy_manager:
		_enemy_manager.notify_cell_changed(hex)


func _flatten_hex(hex: Vector3i) -> void:
	if not _cell_exists(hex):
		return
	var cell: HexCellData = cells[hex]
	cell.elevation = _flatten_target
	_needs_rebuild = true
	_rebuild_chunk_for_hex(hex)
	if _enemy_manager:
		_enemy_manager.notify_cell_changed(hex)


func _level_hex(hex: Vector3i) -> void:
	if not _cell_exists(hex):
		return
	if hex == _level_target:
		return
	if not cells.has(_level_target):
		_level_target = INVALID_HEX
		return
	var target_cell: HexCellData = cells[_level_target]
	var cell: HexCellData = cells[hex]
	cell.elevation = target_cell.elevation
	_needs_rebuild = true
	_rebuild_chunk_for_hex(hex)
	if _enemy_manager:
		_enemy_manager.notify_cell_changed(hex)


func _apply_area_action() -> void:
	if not _area_selector.is_ready():
		return
	var hexes := _area_selector.selected_hexes
	match tool_mode:
		1:
			for hex in hexes:
				_raise_hex(hex)
			_tool_flash("Raised %d hexes" % hexes.size())
		2:
			for hex in hexes:
				_flatten_hex(hex)
			_tool_flash("Flattened %d hexes" % hexes.size())
		3:
			for hex in hexes:
				_level_hex(hex)
			_tool_flash("Leveled %d hexes to target" % hexes.size())
	_area_selector.clear()
	_needs_rebuild = true


func _rebuild_chunk_for_hex(hex: Vector3i) -> void:
	if _terrain and _terrain.has_method("rebuild_chunk_for_hex"):
		_terrain.rebuild_chunk_for_hex(hex)


func _apply_uniform(uniform_name: String, value: Variant) -> void:
	if not _terrain:
		return
	for child in _terrain.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override
			if mat is ShaderMaterial:
				mat.set_shader_parameter(uniform_name, value)
		elif child is MultiMeshInstance3D:
			var mat = child.material_override
			if mat is ShaderMaterial:
				mat.set_shader_parameter(uniform_name, value)


func _apply_all_uniforms() -> void:
	_apply_uniform("height_step", _height_slider.value)
	_apply_uniform("height_exp", _exp_slider.value)
	_apply_uniform("grid_line_width", _grid_slider.value)
	if chunk_manager:
		_apply_uniform("noise_freq", chunk_manager.noise_freq)
		_apply_uniform("noise_seed", float(chunk_manager.noise_seed))
		_apply_uniform("noise_octaves", chunk_manager.fractal_octaves)
		_apply_uniform("noise_lacunarity", chunk_manager.fractal_lacunarity)
		_apply_uniform("noise_gain", chunk_manager.fractal_gain)


# ============================================================================
# BUILDING / PLACEMENT
# ============================================================================
func _place_object_at(_screen_pos: Vector2) -> void:
	if selected_model_path.is_empty():
		_tool_flash("No model selected")
		return
	var hex := _get_mouse_hex()
	if not _cell_exists(hex):
		print("Place: cell %s does not exist" % hex)
		return
	var sides := _get_wall_connections(selected_model_path, _placement_rotation)
	_place_object_on_hex(hex, selected_model_path, _placement_rotation, _placement_scale)
	var connected := 0
	for s in sides:
		var si: int = int(s)
		var neighbor := hex + HexGridMath.cube_direction(si)
		if placed_objects.has(neighbor):
			var n_data: Variant = placed_objects[neighbor]
			if n_data is Dictionary:
				var n_sides := _get_wall_connections(n_data.get("path", ""), n_data.get("rotation", 0.0))
				if (int(s) + 3) % 6 in n_sides:
					connected += 1
	_tool_flash("Placed %s sides%s connected:%d" % [selected_model_path.get_file().get_basename(), str(sides), connected])
	print("Place: %s at %s rot=%.0f sides=%s" % [selected_model_path.get_file(), hex, _placement_rotation, str(sides)])


func _get_hex_normal(hex: Vector3i) -> Vector3:
	var center_pos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var center_h := 0.0
	if cells.has(hex):
		center_h = _get_cell_height(cells[hex])
	var dir_a := Vector3i(1, 0, -1)
	var dir_b := Vector3i(0, -1, 1)
	var hex_a := hex + dir_a
	var hex_b := hex + dir_b
	var pos_a := HexGridMath.cube_to_world_flat_top(hex_a, HEX_SIZE)
	var pos_b := HexGridMath.cube_to_world_flat_top(hex_b, HEX_SIZE)
	var h_a := 0.0
	var h_b := 0.0
	if cells.has(hex_a):
		h_a = _get_cell_height(cells[hex_a])
	if cells.has(hex_b):
		h_b = _get_cell_height(cells[hex_b])
	var tangent_a := Vector3(pos_a.x - center_pos.x, h_a - center_h, pos_a.z - center_pos.z)
	var tangent_b := Vector3(pos_b.x - center_pos.x, h_b - center_h, pos_b.z - center_pos.z)
	var n := tangent_a.cross(tangent_b)
	if n.length_squared() < 0.0001:
		return Vector3.UP
	return n.normalized()


func _place_object_on_hex(hex: Vector3i, model_path: String, rot: float = 0.0, scl: float = 1.0) -> void:
	_remove_object_at(hex)
	placed_objects[hex] = {"path": model_path, "rotation": rot, "scale": scl}
	if not ResourceLoader.exists(model_path):
		return
	var scene: PackedScene = load(model_path)
	if not scene:
		return
	var instance: Node3D = scene.instantiate()
	_objects_container.add_child(instance)
	var cell: HexCellData = cells[hex]
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cell)
	instance.position = Vector3(hpos.x, height, hpos.z)
	var normal := _get_hex_normal(hex)
	var axis := Vector3.UP.cross(normal)
	var angle := acos(clampf(Vector3.UP.dot(normal), -1.0, 1.0))
	var tilt_quat := Quaternion(axis.normalized(), angle) if axis.length_squared() > 0.0001 else Quaternion.IDENTITY
	var yaw_quat := Quaternion(Vector3.UP, deg_to_rad(rot))
	instance.basis = Basis(tilt_quat * yaw_quat)
	instance.scale = Vector3(scl, scl, scl)
	_placed_object_instances[hex] = instance


func _remove_object_at(hex: Vector3i) -> void:
	placed_objects.erase(hex)
	if _placed_object_instances.has(hex):
		var inst: Node3D = _placed_object_instances[hex]
		_placed_object_instances.erase(hex)
		if is_instance_valid(inst):
			inst.queue_free()


func _free_all_object_instances() -> void:
	for hex in _placed_object_instances:
		var inst: Node3D = _placed_object_instances[hex]
		if is_instance_valid(inst):
			inst.queue_free()
	_placed_object_instances.clear()


func _rebuild_object_instances() -> void:
	_free_all_object_instances()
	for hex in placed_objects.keys():
		var obj_data: Variant = placed_objects[hex]
		if obj_data is String:
			_place_object_on_hex(hex, obj_data)
		elif obj_data is Dictionary:
			_place_object_on_hex(hex, obj_data["path"], obj_data.get("rotation", 0.0), obj_data.get("scale", 1.0))


# ============================================================================
# RESOURCE / DECORATION SYSTEM
# ============================================================================
func _resource_noise(hash_val: float) -> float:
	var x := sin(hash_val * 127.1 + hash_val * 311.7) * 43758.5453
	return x - floor(x)


func _resource_noise2(hash_val: float) -> float:
	var x := sin(hash_val * 419.2 + hash_val * 371.9) * 21458.3134
	return x - floor(x)


func _compute_resources_for_hex(hex: Vector3i) -> Array[Dictionary]:
	var resources: Array[Dictionary] = []
	if not _cell_exists(hex):
		return resources
	var cell: HexCellData = cells[hex]
	if cell.biome == BIOME_DEEP_WATER or cell.biome == BIOME_WATER or cell.biome == BIOME_BEACH:
		return resources
	var hex_h := float(hex.x) * 0.7 + float(hex.y) * 1.3
	var cluster := _resource_noise(hex_h)
	var in_tree_cluster := cluster < 0.10
	var in_mountain_cluster := cluster > 0.88 and cluster < 0.95
	var in_rock_cluster := cluster > 0.62 and cluster < 0.67
	var used_subs: Array[int] = []
	for sub_idx in TOTAL_SUBS:
		var h := float(hex.x) * 12.9898 + float(hex.y) * 78.233 + float(sub_idx) * 45.164
		var density := _resource_noise(h)
		var model_path := ""
		var resource_type := ""
		match cell.biome:
			BIOME_GRASS:
				if in_tree_cluster and density > 0.40:
					resource_type = "tree"
					model_path = RESOURCE_TREE_MODELS[int(h * 3.0) % RESOURCE_TREE_MODELS.size()]
				elif not in_tree_cluster and density > 0.93:
					resource_type = "tree"
					model_path = RESOURCE_TREE_MODELS[int(h * 3.0) % RESOURCE_TREE_MODELS.size()]
			BIOME_STONE:
				if in_mountain_cluster and density > 0.35:
					resource_type = "mountain"
					model_path = RESOURCE_MOUNTAIN_MODELS[int(h * 7.0) % RESOURCE_MOUNTAIN_MODELS.size()]
				elif not in_mountain_cluster and density > 0.92:
					resource_type = "mountain"
					model_path = RESOURCE_MOUNTAIN_MODELS[int(h * 7.0) % RESOURCE_MOUNTAIN_MODELS.size()]
			BIOME_DIRT:
				if in_rock_cluster and density > 0.45:
					var rock_model: String = RESOURCE_ROCK_MODELS[int(h * 5.0) % RESOURCE_ROCK_MODELS.size()]
					var mineral_roll := _resource_noise(h + 500.0)
					if mineral_roll > 0.6:
						var mineral_idx := int(_resource_noise(h + 700.0) * MINERAL_TYPES.size()) % MINERAL_TYPES.size()
						resource_type = MINERAL_TYPES[mineral_idx]
						model_path = rock_model
					else:
						resource_type = "rock"
						model_path = rock_model
				elif not in_rock_cluster and density > 0.94:
					var rock_model: String = RESOURCE_ROCK_MODELS[int(h * 5.0) % RESOURCE_ROCK_MODELS.size()]
					var mineral_roll := _resource_noise(h + 500.0)
					if mineral_roll > 0.6:
						var mineral_idx := int(_resource_noise(h + 700.0) * MINERAL_TYPES.size()) % MINERAL_TYPES.size()
						resource_type = MINERAL_TYPES[mineral_idx]
						model_path = rock_model
					else:
						resource_type = "rock"
						model_path = rock_model
		if not resource_type.is_empty():
			resources.append({"sub_idx": sub_idx, "type": resource_type, "model": model_path})
			used_subs.append(sub_idx)
		elif sub_idx >= 1 and used_subs.size() < 7:
			var oil_roll := _resource_noise(h + 2000.0)
			if oil_roll > 0.92 and not _is_sub_hex_water(hex, sub_idx):
				resources.append({"sub_idx": sub_idx, "type": "oil", "model": RESOURCE_ROCK_MODELS[int(h * 3.0) % RESOURCE_ROCK_MODELS.size()]})
	return resources


func _recompute_all_resources() -> void:
	resource_cache.clear()
	for hex in cells:
		var res := _compute_resources_for_hex(hex)
		if not res.is_empty():
			resource_cache[hex] = res


func _load_decoration_mesh(model_path: String) -> Mesh:
	if _decoration_mesh_cache.has(model_path):
		return _decoration_mesh_cache[model_path]
	if not ResourceLoader.exists(model_path):
		return null
	var scene: PackedScene = load(model_path)
	if not scene:
		return null
	var root := scene.instantiate()
	var mesh: Mesh = _extract_mesh_from_node(root)
	_free_scene_children(root)
	if mesh:
		_decoration_mesh_cache[model_path] = mesh
	return mesh


func _extract_mesh_from_node(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for child in node.get_children():
		var m := _extract_mesh_from_node(child)
		if m:
			return m
	return null


func _free_scene_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
	node.queue_free()


func _rebuild_decorations() -> void:
	_free_all_decorations()
	var model_instances: Dictionary = {}
	for hex in cells:
		if not resource_cache.has(hex):
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell)
		for res in resource_cache[hex]:
			var model_path: String = res["model"]
			if model_path.is_empty():
				continue
			var sub_idx: int = res["sub_idx"]
			if not model_instances.has(model_path):
				model_instances[model_path] = []
			var local := _get_sub_hex_local_pos(hex, sub_idx)
			var h1 := _resource_noise(float(hex.x) * 99.1 + float(hex.y) * 67.3 + float(sub_idx) * 23.7)
			var h2 := _resource_noise2(float(hex.x) * 47.3 + float(hex.y) * 83.1 + float(sub_idx) * 12.9)
			var rot_step := int(h1 * 6.0) * 60.0
			var mirror_x := h2 > 0.5
			var mesh := _load_decoration_mesh(model_path)
			if not mesh:
				continue
			var aabb: AABB = mesh.get_aabb()
			var center := aabb.position + aabb.size * 0.5
			var max_horiz := maxf(aabb.size.x, aabb.size.z)
			var scl: float = SUB_HEX_SIZE * 0.925 / maxf(max_horiz, 0.01)
			var sx: float = -scl if mirror_x else scl
			var mat_basis := Basis()
			mat_basis = mat_basis.rotated(Vector3.UP, deg_to_rad(rot_step))
			mat_basis = mat_basis.scaled(Vector3(sx, scl, scl))
			var center_xz := Vector3(center.x, 0.0, center.z)
			var rotated_center := mat_basis * center_xz
			var origin := Vector3(
				hpos.x + local.x - rotated_center.x,
				height - scl * aabb.position.y,
				hpos.z + local.y - rotated_center.z
			)
			model_instances[model_path].append(Transform3D(mat_basis, origin))
	for model_path in model_instances:
		var mesh := _load_decoration_mesh(model_path)
		if not mesh:
			continue
		var transforms: Array = model_instances[model_path]
		var mm := MultiMesh.new()
		mm.mesh = mesh
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		_objects_container.add_child(mi)
		_decoration_multimeshes[model_path] = mi


func _free_all_decorations() -> void:
	for model_path in _decoration_multimeshes:
		var mi: MultiMeshInstance3D = _decoration_multimeshes[model_path]
		if is_instance_valid(mi):
			mi.queue_free()
	_decoration_multimeshes.clear()


func _get_resource_color(rtype: String) -> Color:
	if MINERAL_COLORS.has(rtype):
		return MINERAL_COLORS[rtype]
	match rtype:
		"tree": return Color(0.2, 0.7, 0.2, 0.5)
		"mountain": return Color(0.6, 0.5, 0.5, 0.5)
		"rock": return Color(0.5, 0.5, 0.4, 0.5)
		"oil": return RESOURCE_OIL_COLOR
	return Color.WHITE


# ============================================================================
# SUB-HEX POSITIONS
# ============================================================================
func _get_sub_hex_local_pos(_parent_hex: Vector3i, sub_idx: int) -> Vector2:
	if sub_idx == 0:
		return Vector2.ZERO
	elif sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var angle := deg_to_rad(60.0 * float(vi))
		return Vector2(cos(angle), sin(angle)) * HEX_SIZE
	else:
		var angle := deg_to_rad(30.0 + 60.0 * float(sub_idx - 1))
		return Vector2(cos(angle), sin(angle)) * SUB_HEX_DIST


func _get_corner_enorm(cell: HexCellData, corner_idx: int) -> float:
	var avg_e: float = cell.elevation
	var count: int = 1
	var hex: Vector3i = cell.hex
	var n1: Vector3i = hex + HexGridMath.cube_direction(VERTEX_NEIGHBORS[corner_idx][0])
	var n2: Vector3i = hex + HexGridMath.cube_direction(VERTEX_NEIGHBORS[corner_idx][1])
	if cells.has(n1):
		avg_e += cells[n1].elevation
		count += 1
	if cells.has(n2):
		avg_e += cells[n2].elevation
		count += 1
	return clampf(avg_e / float(count) / 4.0, 0.0, 1.0)


func _get_height_at_local_offset(cell: HexCellData, lx: float, lz: float) -> float:
	var step_size := _height_slider.value if _height_slider else 3.0
	var exp_val := _exp_slider.value if _exp_slider else 1.0
	var center_en := clampf(cell.elevation / 4.0, 0.0, 1.0)
	if absf(lx) < 0.001 and absf(lz) < 0.001:
		return pow(maxf(step_size * center_en, 0.001), exp_val)
	var angle_deg := rad_to_deg(atan2(lz, lx))
	if angle_deg < 0.0:
		angle_deg += 360.0
	var sector := int(angle_deg / 60.0) % 6
	var c_a := sector
	var c_b := (sector + 1) % 6
	var en_a := _get_corner_enorm(cell, c_a)
	var en_b := _get_corner_enorm(cell, c_b)
	var a_angle := deg_to_rad(60.0 * c_a)
	var b_angle := deg_to_rad(60.0 * c_b)
	var ax := cos(a_angle) * HEX_SIZE
	var az := sin(a_angle) * HEX_SIZE
	var bx := cos(b_angle) * HEX_SIZE
	var bz := sin(b_angle) * HEX_SIZE
	var det := ax * bz - az * bx
	if absf(det) < 0.0001:
		return pow(maxf(step_size * center_en, 0.001), exp_val)
	var v := (lx * bz - lz * bx) / det
	var w := (lz * ax - lx * az) / det
	var u := 1.0 - v - w
	u = clampf(u, 0.0, 1.0)
	v = clampf(v, 0.0, 1.0)
	w = clampf(w, 0.0, 1.0)
	var en_interp := u * center_en + v * en_a + w * en_b
	return pow(maxf(step_size * clampf(en_interp, 0.0, 1.0), 0.001), exp_val)


func _get_sub_hex_deformed_height(hex: Vector3i, cell: HexCellData, sub_idx: int) -> float:
	var local := _get_sub_hex_local_pos(hex, sub_idx)
	return _get_height_at_local_offset(cell, local.x, local.y)


# ============================================================================
# OVERLAY MESH
# ============================================================================
func _rebuild_overlay_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var n_up := Vector3.UP
	st.set_normal(n_up)

	var mouse_hex := _cached_mouse_hex if _mouse_hex_valid else _get_mouse_hex()
	var chunk_size := 10
	var ck_q := floori(float(mouse_hex.x) / chunk_size)
	var ck_r := floori(float(mouse_hex.y) / chunk_size)

	if show_overlay:
		for q in range(ck_q * chunk_size, (ck_q + 1) * chunk_size):
			for r in range(ck_r * chunk_size, (ck_r + 1) * chunk_size):
				var hex := Vector3i(q, r, -q - r)
				if not cells.has(hex):
					continue
				var cell: HexCellData = cells[hex]
				var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
				for i in TOTAL_SUBS:
					var local := _get_sub_hex_local_pos(hex, i)
					var height := _get_sub_hex_deformed_height(hex, cell, i) + 0.03
					var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
					_add_flat_hex_wireframe(st, center, SUB_HEX_SIZE, Color(1, 1, 1, 0.25))

	if show_resources:
		for q in range(ck_q * chunk_size, (ck_q + 1) * chunk_size):
			for r in range(ck_r * chunk_size, (ck_r + 1) * chunk_size):
				var hex := Vector3i(q, r, -q - r)
				if not cells.has(hex):
					continue
				if not resource_cache.has(hex):
					continue
				var cell: HexCellData = cells[hex]
				var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
				for res in resource_cache[hex]:
					var sub_i: int = int(res["sub_idx"])
					var local := _get_sub_hex_local_pos(hex, sub_i)
					var height := _get_sub_hex_deformed_height(hex, cell, sub_i) + 0.04
					var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
					_add_flat_hex_tris(st, center, SUB_HEX_SIZE, _get_resource_color(res["type"]))

	if tool_mode == 4 and not selected_model_path.is_empty():
		var hex := _cached_mouse_hex if _mouse_hex_valid else _get_mouse_hex()
		if _cell_exists(hex):
			var cell: HexCellData = cells[hex]
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			var height := _get_cell_height(cell) + 0.06
			_add_flat_hex_tris(st, Vector3(hpos.x, height, hpos.z), HEX_SIZE, Color(0.3, 0.8, 0.3, 0.25))

	if _show_tile_values:
		for q in range(ck_q * chunk_size, (ck_q + 1) * chunk_size):
			for r in range(ck_r * chunk_size, (ck_r + 1) * chunk_size):
				var hex := Vector3i(q, r, -q - r)
				if not cells.has(hex):
					continue
				var cell: HexCellData = cells[hex]
				var val := _tile_valuator.compute_tile_value(hex, cell.elevation)
				var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
				var height := _get_cell_height(cell) + 0.05
				var center := Vector3(hpos.x, height, hpos.z)
				var intensity := val * 0.7 + 0.3
				var col := Color(intensity * 0.2, intensity, intensity * 0.1, 0.5)
				_add_flat_hex_tris(st, center, HEX_SIZE, col)

	if _area_selector.has_active_selection:
		for hex in _area_selector.selected_hexes:
			if not cells.has(hex):
				continue
			var cell: HexCellData = cells[hex]
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			var height := _get_cell_height(cell) + 0.07
			var col := Color(0.9, 0.9, 0.2, 0.3) if _area_selector.is_ready() else Color(0.2, 0.6, 0.9, 0.4)
			_add_flat_hex_tris(st, Vector3(hpos.x, height, hpos.z), HEX_SIZE, col)

	var mesh := st.commit()
	_overlay_mesh_instance.mesh = mesh


func _add_flat_hex_tris(st: SurfaceTool, center: Vector3, size: float, col: Color) -> void:
	st.set_color(col)
	for i in 6:
		var angle1 := deg_to_rad(60.0 * float(i))
		var angle2 := deg_to_rad(60.0 * float((i + 1) % 6))
		var v1 := center + Vector3(cos(angle1), 0.0, sin(angle1)) * size
		var v2 := center + Vector3(cos(angle2), 0.0, sin(angle2)) * size
		st.add_vertex(center)
		st.add_vertex(v1)
		st.add_vertex(v2)


func _add_flat_hex_wireframe(st: SurfaceTool, center: Vector3, size: float, col: Color) -> void:
	var up := Vector3.UP * 0.02
	var thin := 0.015
	st.set_color(col)
	for i in 6:
		var angle1 := deg_to_rad(60.0 * float(i))
		var angle2 := deg_to_rad(60.0 * float((i + 1) % 6))
		var v1 := center + Vector3(cos(angle1), 0.0, sin(angle1)) * size
		var v2 := center + Vector3(cos(angle2), 0.0, sin(angle2)) * size
		var edge := v2 - v1
		var perp := Vector3(-edge.z, 0.0, edge.x).normalized() * thin
		var a := v1 + perp + up
		var b := v1 - perp + up
		var c := v2 - perp + up
		var d := v2 + perp + up
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(d)


# ============================================================================
# CURSOR HIGHLIGHT
# ============================================================================
func _setup_cursor() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_up := Vector3(0, 1, 0)
	var corners: Array[Vector3] = []
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i))
		corners.append(Vector3(cos(angle) * HEX_SIZE, 0.0, sin(angle) * HEX_SIZE))
	for i in 6:
		var next := (i + 1) % 6
		st.set_normal(n_up)
		st.add_vertex(Vector3(0, 0.02, 0))
		st.set_normal(n_up)
		st.add_vertex(corners[next] + Vector3(0, 0.02, 0))
		st.set_normal(n_up)
		st.add_vertex(corners[i] + Vector3(0, 0.02, 0))
	var mesh := st.commit()
	_cursor_instance = MeshInstance3D.new()
	_cursor_instance.mesh = mesh
	var cursor_mat := StandardMaterial3D.new()
	cursor_mat.albedo_color = Color(1.0, 1.0, 0.3, 0.25)
	cursor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cursor_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cursor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor_mat.no_depth_test = true
	_cursor_instance.material_override = cursor_mat
	_cursor_instance.visible = false
	add_child(_cursor_instance)


func _update_cursor(hex: Vector3i) -> void:
	_last_cursor_hex = hex
	if hex == INVALID_HEX or not cells.has(hex):
		_cursor_instance.visible = false
		return
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var cell: HexCellData = cells[hex]
	var height := _get_cell_height(cell)
	_cursor_instance.position = Vector3(hpos.x, height + 0.15, hpos.z)
	_cursor_instance.visible = true


# ============================================================================
# UI SETUP
# ============================================================================
func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	_tool_label = Label.new()
	_tool_label.position = Vector2(10, 10)
	_tool_label.add_theme_font_size_override("font_size", 16)
	_tool_label.add_theme_color_override("font_color", Color(1, 1, 0.3))
	_tool_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_tool_label.add_theme_constant_override("shadow_offset_x", 1)
	_tool_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(_tool_label)

	_info_label = Label.new()
	_info_label.position = Vector2(10, 32)
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.add_theme_color_override("font_color", Color.WHITE)
	_info_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_info_label.add_theme_constant_override("shadow_offset_x", 1)
	_info_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(_info_label)

	_setup_top_toolbar(canvas)
	_setup_left_menu(canvas)
	_setup_bottom_palette(canvas)
	_update_tool_ui()


func _setup_top_toolbar(canvas: CanvasLayer) -> void:
	var screen_size := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.position = Vector2(220, 0)
	panel.size = Vector2(screen_size.x - 230, 32)
	var toolbar_style := StyleBoxFlat.new()
	toolbar_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	toolbar_style.corner_radius_bottom_left = 4
	toolbar_style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", toolbar_style)
	canvas.add_child(panel)

	_top_toolbar = HBoxContainer.new()
	_top_toolbar.add_theme_constant_override("separation", 4)
	panel.add_child(_top_toolbar)

	var tool_defs := [
		["Nav [1]", 0],
		["Raise [2]", 1],
		["Flatten [3]", 2],
		["Level [4]", 3],
		["Place [5]", 4],
	]
	for td in tool_defs:
		var btn := Button.new()
		btn.text = td[0]
		btn.toggle_mode = true
		btn.pressed.connect(_set_tool.bind(td[1]))
		btn.custom_minimum_size = Vector2(90, 26)
		_top_toolbar.add_child(btn)
		_tool_buttons.append(btn)

	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(8, 26)
	_top_toolbar.add_child(sep)

	var overlay_btn := Button.new()
	overlay_btn.text = "Overlay [H]"
	overlay_btn.toggle_mode = true
	overlay_btn.pressed.connect(func():
		show_overlay = not show_overlay
		overlay_btn.button_pressed = show_overlay
		_needs_rebuild = true
	)
	overlay_btn.custom_minimum_size = Vector2(90, 26)
	_top_toolbar.add_child(overlay_btn)

	var res_btn := Button.new()
	res_btn.text = "Resources [J]"
	res_btn.toggle_mode = true
	res_btn.pressed.connect(func():
		show_resources = not show_resources
		res_btn.button_pressed = show_resources
		_needs_rebuild = true
	)
	res_btn.custom_minimum_size = Vector2(90, 26)
	_top_toolbar.add_child(res_btn)

	var val_btn := Button.new()
	val_btn.text = "Values [Tab]"
	val_btn.toggle_mode = true
	val_btn.pressed.connect(func():
		_show_tile_values = not _show_tile_values
		val_btn.button_pressed = _show_tile_values
		_needs_rebuild = true
	)
	val_btn.custom_minimum_size = Vector2(90, 26)
	_top_toolbar.add_child(val_btn)


func _setup_left_menu(canvas: CanvasLayer) -> void:
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_menu.custom_minimum_size = Vector2(210, 0)
	_menu.position.y = 50
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
	_radius_label.text = "Radius:"
	_radius_label.add_theme_font_size_override("font_size", 12)
	_radius_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radius_input = LineEdit.new()
	_radius_input.text = "300"
	_radius_input.custom_minimum_size = Vector2(60, 0)
	_radius_input.size_flags_horizontal = Control.SIZE_SHRINK_END
	_radius_input.text_submitted.connect(_on_radius_input)
	var _radius_row := HBoxContainer.new()
	_radius_row.add_child(_radius_label)
	_radius_row.add_child(_radius_input)
	vbox.add_child(_radius_row)

	_radius_slider = HSlider.new()
	_radius_slider.min_value = 10.0
	_radius_slider.max_value = 10000.0
	_radius_slider.step = 10.0
	_radius_slider.value = 300.0
	_radius_slider.custom_minimum_size = Vector2(180, 0)
	_radius_slider.value_changed.connect(_on_radius_changed)
	vbox.add_child(_radius_slider)

	var sep_h := HSeparator.new()
	vbox.add_child(sep_h)

	_height_label = Label.new()
	_height_label.text = "Step:"
	_height_label.add_theme_font_size_override("font_size", 12)
	_height_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_height_input = LineEdit.new()
	_height_input.text = "3.0"
	_height_input.custom_minimum_size = Vector2(60, 0)
	_height_input.size_flags_horizontal = Control.SIZE_SHRINK_END
	_height_input.text_submitted.connect(_on_height_input)
	var _height_row := HBoxContainer.new()
	_height_row.add_child(_height_label)
	_height_row.add_child(_height_input)
	vbox.add_child(_height_row)

	_height_slider = HSlider.new()
	_height_slider.min_value = 0.5
	_height_slider.max_value = 5.0
	_height_slider.step = 0.1
	_height_slider.value = 3.0
	_height_slider.custom_minimum_size = Vector2(180, 0)
	_height_slider.value_changed.connect(_on_height_changed)
	vbox.add_child(_height_slider)

	var sep_exp := HSeparator.new()
	vbox.add_child(sep_exp)

	_exp_label = Label.new()
	_exp_label.text = "Curve:"
	_exp_label.add_theme_font_size_override("font_size", 12)
	_exp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_exp_input = LineEdit.new()
	_exp_input.text = "1.0"
	_exp_input.custom_minimum_size = Vector2(60, 0)
	_exp_input.size_flags_horizontal = Control.SIZE_SHRINK_END
	_exp_input.text_submitted.connect(_on_exp_input)
	var _exp_row := HBoxContainer.new()
	_exp_row.add_child(_exp_label)
	_exp_row.add_child(_exp_input)
	vbox.add_child(_exp_row)

	_exp_slider = HSlider.new()
	_exp_slider.min_value = 0.0
	_exp_slider.max_value = 4.0
	_exp_slider.step = 0.1
	_exp_slider.value = 1.0
	_exp_slider.custom_minimum_size = Vector2(180, 0)
	_exp_slider.value_changed.connect(_on_exp_changed)
	vbox.add_child(_exp_slider)

	var sep_grid := HSeparator.new()
	vbox.add_child(sep_grid)

	_grid_label = Label.new()
	_grid_label.text = "Grid Lines:"
	_grid_label.add_theme_font_size_override("font_size", 12)
	_grid_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_input = LineEdit.new()
	_grid_input.text = "0.08"
	_grid_input.custom_minimum_size = Vector2(60, 0)
	_grid_input.size_flags_horizontal = Control.SIZE_SHRINK_END
	_grid_input.text_submitted.connect(_on_grid_input)
	var _grid_row := HBoxContainer.new()
	_grid_row.add_child(_grid_label)
	_grid_row.add_child(_grid_input)
	vbox.add_child(_grid_row)

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

	_spawn_rate_label = Label.new()
	_spawn_rate_label.text = "Spawn Rate: 2.0s"
	_spawn_rate_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_spawn_rate_label)
	_spawn_rate_slider = HSlider.new()
	_spawn_rate_slider.min_value = 0.2
	_spawn_rate_slider.max_value = 10.0
	_spawn_rate_slider.step = 0.1
	_spawn_rate_slider.value = 2.0
	_spawn_rate_slider.custom_minimum_size = Vector2(180, 0)
	_spawn_rate_slider.value_changed.connect(func(val: float) -> void:
		_spawn_rate_label.text = "Spawn Rate: %.1fs" % val
		_enemy_manager.spawn_interval = val
	)
	vbox.add_child(_spawn_rate_slider)

	_max_enemies_label = Label.new()
	_max_enemies_label.text = "Max Enemies: 30"
	_max_enemies_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_max_enemies_label)
	_max_enemies_slider = HSlider.new()
	_max_enemies_slider.min_value = 0
	_max_enemies_slider.max_value = 20000
	_max_enemies_slider.step = 100
	_max_enemies_slider.value = 30
	_max_enemies_slider.custom_minimum_size = Vector2(180, 0)
	_max_enemies_slider.value_changed.connect(func(val: float) -> void:
		_max_enemies_label.text = "Max Enemies: %d" % int(val)
		_enemy_manager.set_max_enemies(int(val))
	)
	vbox.add_child(_max_enemies_slider)

	_spawn_batch_label = Label.new()
	_spawn_batch_label.text = "Spawn Batch: 1"
	_spawn_batch_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_spawn_batch_label)
	_spawn_batch_slider = HSlider.new()
	_spawn_batch_slider.min_value = 0
	_spawn_batch_slider.max_value = 10000
	_spawn_batch_slider.step = 100
	_spawn_batch_slider.value = 1
	_spawn_batch_slider.custom_minimum_size = Vector2(180, 0)
	_spawn_batch_slider.value_changed.connect(func(val: float) -> void:
		_spawn_batch_label.text = "Spawn Batch: %d" % int(val)
		_enemy_manager.spawn_batch_size = int(val)
	)
	vbox.add_child(_spawn_batch_slider)

	var sep4 := HSeparator.new()
	vbox.add_child(sep4)

	_label = Label.new()
	_label.text = "Pick an approach"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_label)


func _setup_bottom_palette(canvas: CanvasLayer) -> void:
	var screen_size := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.position = Vector2(4, screen_size.y - 134)
	panel.size = Vector2(screen_size.x - 8, 130)
	canvas.add_child(panel)
	_bottom_palette = panel

	_palette_tabs = TabContainer.new()
	_palette_tabs.size = Vector2(screen_size.x - 8, 130)
	_palette_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tab_style := StyleBoxFlat.new()
	tab_style.bg_color = Color(0.15, 0.15, 0.15, 0.85)
	tab_style.corner_radius_top_left = 4
	tab_style.corner_radius_top_right = 4
	tab_style.content_margin_left = 4
	tab_style.content_margin_right = 4
	tab_style.content_margin_top = 2
	tab_style.content_margin_bottom = 2
	_palette_tabs.add_theme_stylebox_override("panel", tab_style)
	_palette_tabs.add_theme_stylebox_override("tab_selected", tab_style)
	var tab_unsel := tab_style.duplicate()
	tab_unsel.bg_color = Color(0.25, 0.25, 0.25, 0.7)
	_palette_tabs.add_theme_stylebox_override("tab_unselected", tab_unsel)
	_palette_tabs.add_theme_font_size_override("font_size", 12)
	panel.add_child(_palette_tabs)

	_add_palette_tab("neutral", "res://assets/kaykit_medieval_hexagon_pack/buildings/neutral/")
	_add_palette_tab("nature", "res://assets/kaykit_medieval_hexagon_pack/decoration/nature/")
	_add_palette_tab("props", "res://assets/kaykit_medieval_hexagon_pack/decoration/props/")


func _add_palette_tab(tab_name: String, dir_path: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette_tabs.add_child(scroll)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	scroll.add_child(grid)

	var cancel_btn := Button.new()
	cancel_btn.text = "X"
	cancel_btn.custom_minimum_size = Vector2(12, 12)
	cancel_btn.tooltip_text = "Cancel placement"
	var cancel_style := StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.5, 0.15, 0.15, 0.7)
	cancel_style.corner_radius_top_left = 3
	cancel_style.corner_radius_top_right = 3
	cancel_style.corner_radius_bottom_left = 3
	cancel_style.corner_radius_bottom_right = 3
	cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	var cancel_hover := cancel_style.duplicate()
	cancel_hover.bg_color = Color(0.7, 0.2, 0.2, 0.9)
	cancel_btn.add_theme_stylebox_override("hover", cancel_hover)
	cancel_btn.pressed.connect(_cancel_placement)
	grid.add_child(cancel_btn)

	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	var items: Array[String] = []
	while fname != "":
		if fname.ends_with(".tscn") and not fname.begins_with("."):
			items.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	items.sort()

	for tscn_name in items:
		var base_name := tscn_name.get_basename()
		var icon_path := dir_path + base_name + ".webp"
		var scene_path := dir_path + tscn_name

		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(72, 72)
		btn.size = Vector2(72, 72)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.2, 0.2, 0.2, 0.6)
		btn_style.corner_radius_top_left = 2
		btn_style.corner_radius_top_right = 2
		btn_style.corner_radius_bottom_left = 2
		btn_style.corner_radius_bottom_right = 2
		btn_style.content_margin_left = 1
		btn_style.content_margin_right = 1
		btn_style.content_margin_top = 1
		btn_style.content_margin_bottom = 1
		btn.add_theme_stylebox_override("normal", btn_style)
		var btn_hover := btn_style.duplicate()
		btn_hover.bg_color = Color(0.35, 0.35, 0.4, 0.8)
		btn.add_theme_stylebox_override("hover", btn_hover)
		var btn_pressed := btn_style.duplicate()
		btn_pressed.bg_color = Color(0.2, 0.4, 0.6, 0.9)
		btn.add_theme_stylebox_override("pressed", btn_pressed)

		if ResourceLoader.exists(icon_path):
			var tex := load(icon_path) as Texture2D
			if tex:
				btn.texture_normal = tex

		btn.pressed.connect(_on_palette_item_selected.bind(scene_path))
		btn.tooltip_text = base_name
		grid.add_child(btn)


func _on_palette_item_selected(path: String) -> void:
	selected_model_path = path
	_placement_scale = _default_scale
	_placement_rotation = 0.0
	_set_tool(4)
	_create_ghost(path)
	_tool_flash("Select: " + path.get_file().get_basename())
	print("Palette selected: tool_mode=%d path=%s" % [tool_mode, path])


# ============================================================================
# APPROACH SWITCHING
# ============================================================================
func _on_radius_changed(value: float) -> void:
	_radius_input.text = "%d" % int(value)
	if _current_approach != "":
		_rebuild_terrain()


func _on_height_changed(value: float) -> void:
	_height_input.text = "%.1f" % value
	_apply_uniform("height_step", value)
	if _enemy_manager:
		_enemy_manager.set_height_params(value, _exp_slider.value)
		_enemy_manager.invalidate_all_paths()


func _on_exp_changed(value: float) -> void:
	_exp_input.text = "%.1f" % value
	_apply_uniform("height_exp", value)
	if _enemy_manager:
		_enemy_manager.set_height_params(_height_slider.value, value)
		_enemy_manager.invalidate_all_paths()


func _on_grid_changed(value: float) -> void:
	_grid_input.text = "%.2f" % value
	_apply_uniform("grid_line_width", value)


func _on_radius_input(text: String) -> void:
	var val := text.to_float()
	if val >= 10.0:
		_radius_slider.value = val


func _on_height_input(text: String) -> void:
	var val := text.to_float()
	_height_slider.value = clampf(val, 0.5, 5.0)


func _on_exp_input(text: String) -> void:
	var val := text.to_float()
	_exp_slider.value = clampf(val, 0.0, 4.0)


func _on_grid_input(text: String) -> void:
	var val := text.to_float()
	_grid_slider.value = clampf(val, 0.0, 0.3)


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
	_terrain.name = "Terrain"
	_terrain.set_meta("grid_radius", int(_radius_slider.value))
	_terrain.set_script(script)
	add_child(_terrain)
	move_child(_terrain, _world.get_index() + 1)
	move_child(_gameplay, get_child_count() - 1)
	move_child(_overlay_mesh_instance, get_child_count() - 1)
	move_child(_cursor_instance, get_child_count() - 1)
	_label.text = "Generating hex prisms..."
	call_deferred("_on_terrain_ready", "Hex prisms ready.")


func _on_flat() -> void:
	_current_approach = "flat"
	_terrain_free()
	var script := load("res://HexGrid/approach_flat.gd") as GDScript
	_terrain = Node3D.new()
	_terrain.name = "Terrain"
	_terrain.set_meta("grid_radius", int(_radius_slider.value))
	_terrain.set_script(script)
	add_child(_terrain)
	move_child(_terrain, _world.get_index() + 1)
	move_child(_gameplay, get_child_count() - 1)
	move_child(_overlay_mesh_instance, get_child_count() - 1)
	move_child(_cursor_instance, get_child_count() - 1)
	_label.text = "Generating flat grid..."
	call_deferred("_on_terrain_ready", "Flat grid ready.")


func _on_terrain_ready(msg: String) -> void:
	_label.text = msg
	_apply_all_uniforms()
	_recompute_all_resources()
	_rebuild_decorations()


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


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 60.0
	camera.near = 0.1
	camera.far = 5000.0
	_world.add_child(camera)


func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	_world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(30, 150, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.8, 0.85, 1.0)
	_world.add_child(fill)

	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.4)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_world.add_child(world_env)
