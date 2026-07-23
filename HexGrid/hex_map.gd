extends Node3D

const HEX_SIZE: float = 1.1547
const SUB_HEX_SIZE: float = HEX_SIZE / 3.0
const SUB_HEX_DIST: float = HEX_SIZE * 0.57735026919
const WATER_HEIGHT: float = 0.3
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

var cells: Dictionary = {}
var chunk_manager: ChunkManager
var _terrain: Node3D = null
var _current_approach: String = ""

var camera: Camera3D
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

var _level_target: Vector3i = Vector3i(999999, 999999, -1999998)
var _flatten_target: float = 0.0
var _flatten_captured: bool = false

var _needs_rebuild: bool = false
var _needs_save: bool = false
var _needs_decoration_rebuild: bool = false

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
var _grid_slider: HSlider
var _grid_label: Label
var _radius_slider: HSlider
var _radius_label: Label
var _step_slider: HSlider
var _step_label: Label
var _exp_slider: HSlider
var _exp_label: Label


func _ready() -> void:
	chunk_manager = ChunkManager.new(cells)
	_setup_lighting()
	_setup_camera()
	_objects_container = Node3D.new()
	add_child(_objects_container)
	_overlay_mesh_instance = MeshInstance3D.new()
	var overlay_mat := StandardMaterial3D.new()
	overlay_mat.vertex_color_use_as_albedo = true
	overlay_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay_mesh_instance.material_override = overlay_mat
	add_child(_overlay_mesh_instance)
	_setup_ui()
	_update_camera_transform()
	print("Ready. Pick an approach from the menu.")


func _exit_tree() -> void:
	if chunk_manager:
		chunk_manager.cleanup()


func _process(delta: float) -> void:
	_handle_camera_input()

	if _tool_flash_timer > 0.0:
		_tool_flash_timer -= delta
		if _tool_flash_timer <= 0.0:
			_update_tool_ui()

	if _needs_rebuild:
		if _terrain:
			if _current_approach == "flat":
				_terrain.rebuild_all_chunks()
			elif _current_approach == "prisms":
				_terrain.rebuild_all_chunks()
		_rebuild_overlay_mesh()
		_needs_rebuild = false

	if tool_mode == 3:
		_update_ghost_position()
	_update_hover_info()


func _handle_camera_input() -> void:
	if Input.is_action_just_pressed("rmb") and not orbiting and not panning:
		if tool_mode == 3:
			_cancel_placement()
			return
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
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey:
		_handle_key(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var dir := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		cam_dist = clampf(cam_dist + dir * cam_dist * 0.08, 5.0, 200.0)
		_update_camera_transform()
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			painting = false
			return
		match tool_mode:
			0:
				pass
			1:
				painting = true
				_raise_at(event.position)
			2:
				painting = true
				_flatten_at(event.position)
			3:
				painting = true
				_level_at(event.position)
			4:
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
			_needs_decoration_rebuild = true
		KEY_ESCAPE:
			if tool_mode == 4:
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
				_tool_flash("Rotation: %.0f°" % _placement_rotation)
		KEY_X:
			if tool_mode == 4:
				_placement_rotation = wrapf(_placement_rotation + 60.0, 0.0, 360.0)
				_tool_flash("Rotation: %.0f°" % _placement_rotation)
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
	_level_target = Vector3i(999999, 999999, -1999998)
	_flatten_captured = false
	painting = false
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
	_needs_decoration_rebuild = true
	if _terrain:
		if _current_approach == "flat":
			_terrain.cells = cells
			_terrain.rebuild_all_chunks()
		elif _current_approach == "prisms":
			_terrain.cells = cells
			_terrain.rebuild_all_chunks()


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
	_needs_decoration_rebuild = true
	if _terrain:
		if _current_approach == "flat":
			_terrain.cells = cells
			_terrain.rebuild_all_chunks()
		elif _current_approach == "prisms":
			_terrain.cells = cells
			_terrain.rebuild_all_chunks()
	return true


func _tool_flash(msg: String) -> void:
	_tool_label.text = msg
	_tool_flash_timer = 1.5


func _screen_to_world_3d(screen_pos: Vector2) -> Vector3:
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	if absf(ray_dir.y) < 0.0001:
		return Vector3(INF, INF, INF)
	var t := -ray_origin.y / ray_dir.y
	if t < 0:
		return Vector3(INF, INF, INF)
	return ray_origin + ray_dir * t


func _get_mouse_hex() -> Vector3i:
	var world_pos := _screen_to_world_3d(get_viewport().get_mouse_position())
	if world_pos.x == INF:
		return Vector3i(999999, 999999, -1999998)
	return HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)


func _cell_exists(hex: Vector3i) -> bool:
	return cells.has(hex)


func _get_cell_height(cell: HexCellData) -> float:
	if _is_water_biome(cell.biome):
		return WATER_HEIGHT
	var hex_width: float = HEX_SIZE * 1.73205080757
	var step: float = ELEVATION_STEPS[elevation_step_idx]
	if step <= 0.0:
		return HEX_SIZE
	var e := maxf(cell.elevation, 0.0)
	var height := e * hex_width + HEX_SIZE
	return snappedf(height, step)


func _is_water_biome(biome: int) -> bool:
	return biome == BIOME_DEEP_WATER or biome == BIOME_WATER


func _update_hover_info() -> void:
	if tool_mode == 4:
		return
	var hex := _get_mouse_hex()
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
		_info_label.text = "Orbit: RMB | Pan: LMB | Zoom: Scroll | 1-5: Tools | H: Overlay | F: ElevStep | R: Regen"


func _update_tool_buttons() -> void:
	for i in _tool_buttons.size():
		_tool_buttons[i].button_pressed = (i == tool_mode)


func _update_ghost_position() -> void:
	if _ghost_instance == null:
		return
	var world_pos := _screen_to_world_3d(get_viewport().get_mouse_position())
	if world_pos.x == INF:
		_ghost_instance.visible = false
		return
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		_ghost_instance.visible = false
		return
	_ghost_instance.visible = true
	var cell: HexCellData = cells[hex]
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cell)
	_ghost_instance.position = Vector3(hpos.x, height, hpos.z)
	_ghost_instance.rotation_degrees.y = _placement_rotation
	_ghost_instance.scale = Vector3(_placement_scale, _placement_scale, _placement_scale)


func _create_ghost(model_path: String) -> void:
	_remove_ghost()
	if not ResourceLoader.exists(model_path):
		return
	var scene: PackedScene = load(model_path)
	if not scene:
		return
	_ghost_instance = scene.instantiate()
	_objects_container.add_child(_ghost_instance)
	_ghost_model_path = model_path
	_set_node_transparency(_ghost_instance, 0.5)


func _set_node_transparency(node: Node, alpha: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			for i in mi.get_surface_override_material_count():
				var mat = mi.get_surface_override_material(i)
				if mat == null and mi.mesh != null:
					mat = mi.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					var new_mat: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
					new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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


func _cancel_placement() -> void:
	_remove_ghost()
	selected_model_path = ""
	_placement_rotation = 0.0
	_placement_scale = _default_scale
	_set_tool(0)


# ============================================================================
# TERRAIN EDITING
# ============================================================================
func _raise_at(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
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


func _flatten_at(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		return
	var cell: HexCellData = cells[hex]
	if not _flatten_captured:
		_flatten_target = cell.elevation
		_flatten_captured = true
	cell.elevation = _flatten_target
	_needs_rebuild = true
	_rebuild_chunk_for_hex(hex)


func _level_at(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		return
	if _level_target == Vector3i(999999, 999999, -1999998):
		_level_target = hex
		_tool_flash("Level target set: (%d,%d,%d)" % [hex.x, hex.y, hex.z])
		return
	if hex == _level_target:
		return
	var target_cell: HexCellData = cells[_level_target]
	var cell: HexCellData = cells[hex]
	cell.elevation = target_cell.elevation
	_needs_rebuild = true
	_rebuild_chunk_for_hex(hex)


func _rebuild_chunk_for_hex(hex: Vector3i) -> void:
	if not _terrain:
		return
	var chunk_key := Vector2i(floori(float(hex.x) / 32), floori(float(hex.y) / 32))
	if _current_approach == "flat" and _terrain.has_method("rebuild_chunk"):
		_terrain.rebuild_chunk(chunk_key)
	elif _current_approach == "prisms" and _terrain.has_method("rebuild_chunk"):
		_terrain.rebuild_chunk(chunk_key)


# ============================================================================
# BUILDING / PLACEMENT
# ============================================================================
func _place_object_at(screen_pos: Vector2) -> void:
	if selected_model_path.is_empty():
		_tool_flash("No model selected")
		return
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		return
	_place_object_on_hex(hex, selected_model_path, _placement_rotation, _placement_scale)


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
	instance.rotation_degrees.y = rot
	instance.scale = Vector3(scl, scl, scl)
	_placed_object_instances[hex] = instance
	_needs_save = true


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


func _update_object_instances() -> void:
	for hex in placed_objects.keys():
		var obj_data: Variant = placed_objects[hex]
		var model_path: String
		var rot: float = 0.0
		var scl: float = 1.0
		if obj_data is String:
			model_path = obj_data
		elif obj_data is Dictionary:
			model_path = obj_data["path"]
			rot = obj_data.get("rotation", 0.0)
			scl = obj_data.get("scale", 1.0)
		else:
			continue
		if not _placed_object_instances.has(hex):
			_place_object_on_hex(hex, model_path, rot, scl)
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell)
		var inst: Node3D = _placed_object_instances[hex]
		inst.position = Vector3(hpos.x, height, hpos.z)
		inst.rotation_degrees.y = rot
		inst.scale = Vector3(scl, scl, scl)


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
					resource_type = "rock"
					model_path = RESOURCE_ROCK_MODELS[int(h * 5.0) % RESOURCE_ROCK_MODELS.size()]
				elif not in_rock_cluster and density > 0.94:
					resource_type = "rock"
					model_path = RESOURCE_ROCK_MODELS[int(h * 5.0) % RESOURCE_ROCK_MODELS.size()]
		if not resource_type.is_empty():
			resources.append({"sub_idx": sub_idx, "type": resource_type, "model": model_path})
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
			var basis: Basis = Basis()
			basis = basis.rotated(Vector3.UP, deg_to_rad(rot_step))
			basis = basis.scaled(Vector3(sx, scl, scl))
			var center_xz := Vector3(center.x, 0.0, center.z)
			var rotated_center := basis * center_xz
			var origin := Vector3(
				hpos.x + local.x - rotated_center.x,
				height - scl * aabb.position.y,
				hpos.z + local.y - rotated_center.z
			)
			model_instances[model_path].append(Transform3D(basis, origin))
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
		add_child(mi)
		_decoration_multimeshes[model_path] = mi


func _free_all_decorations() -> void:
	for model_path in _decoration_multimeshes:
		var mi: MultiMeshInstance3D = _decoration_multimeshes[model_path]
		if is_instance_valid(mi):
			mi.queue_free()
	_decoration_multimeshes.clear()


func _get_resource_counts(hex: Vector3i) -> Dictionary:
	var counts := {}
	if resource_cache.has(hex):
		for res in resource_cache[hex]:
			var rtype: String = res["type"]
			counts[rtype] = counts.get(rtype, 0) + 1
	return counts


func _get_resource_color(rtype: String) -> Color:
	match rtype:
		"tree": return Color(0.2, 0.7, 0.2, 0.5)
		"mountain": return Color(0.6, 0.5, 0.5, 0.5)
		"rock": return Color(0.5, 0.5, 0.4, 0.5)
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


func _vertex_key(hex: Vector3i, vi: int) -> int:
	var dirs: Array = VERTEX_NEIGHBORS[vi]
	var h1 := hex
	var h2 := hex + HexGridMath.cube_direction(dirs[0])
	var h3 := hex + HexGridMath.cube_direction(dirs[1])
	var hx: int = mini(mini(h1.x, h2.x), h3.x)
	var hy: int = mini(mini(h1.y, h2.y), h3.y)
	var hz: int = mini(mini(h1.z, h2.z), h3.z)
	return hx * 1000003 + hy * 1009 + hz


func _find_closest_sub_hex(hex: Vector3i, world_pos: Vector3) -> int:
	var hex_world := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var local := Vector2(world_pos.x - hex_world.x, world_pos.z - hex_world.z)
	var best_sub := 0
	var best_dist := INF
	for i in TOTAL_SUBS:
		var sub_pos := _get_sub_hex_local_pos(hex, i)
		var d := local.distance_to(sub_pos)
		if d < best_dist:
			best_dist = d
			best_sub = i
	return best_sub


# ============================================================================
# OVERLAY MESH
# ============================================================================
func _rebuild_overlay_mesh() -> void:
	var imm := ImmediateMesh.new()
	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	if show_overlay:
		for hex in cells:
			var cell: HexCellData = cells[hex]
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			var height := _get_cell_height(cell) + 0.03
			for i in TOTAL_SUBS:
				var local := _get_sub_hex_local_pos(hex, i)
				var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
				_add_flat_hex_wireframe(imm, center, SUB_HEX_SIZE, Color(1, 1, 1, 0.25))

	if show_resources:
		for hex in cells:
			if not resource_cache.has(hex):
				continue
			var cell: HexCellData = cells[hex]
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			var height := _get_cell_height(cell) + 0.04
			for res in resource_cache[hex]:
				var local := _get_sub_hex_local_pos(hex, res["sub_idx"])
				var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
				_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, _get_resource_color(res["type"]))

	if tool_mode == 4 and not selected_model_path.is_empty():
		var hex := _get_mouse_hex()
		if _cell_exists(hex):
			var cell: HexCellData = cells[hex]
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			var height := _get_cell_height(cell) + 0.06
			_add_flat_hex_tris(imm, Vector3(hpos.x, height, hpos.z), HEX_SIZE, Color(0.3, 0.8, 0.3, 0.25))

	imm.surface_end()
	_overlay_mesh_instance.mesh = imm


func _add_flat_hex_tris(imm: ImmediateMesh, center: Vector3, size: float, col: Color) -> void:
	for i in 6:
		var angle1 := deg_to_rad(60.0 * float(i))
		var angle2 := deg_to_rad(60.0 * float((i + 1) % 6))
		var v1 := center + Vector3(cos(angle1), 0.0, sin(angle1)) * size
		var v2 := center + Vector3(cos(angle2), 0.0, sin(angle2)) * size
		imm.surface_set_color(col)
		imm.surface_add_vertex(center)
		imm.surface_set_color(col)
		imm.surface_add_vertex(v1)
		imm.surface_set_color(col)
		imm.surface_add_vertex(v2)


func _add_flat_hex_wireframe(imm: ImmediateMesh, center: Vector3, size: float, col: Color) -> void:
	var up := Vector3.UP * 0.02
	var thin := 0.015
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
		imm.surface_set_color(col)
		imm.surface_add_vertex(a)
		imm.surface_set_color(col)
		imm.surface_add_vertex(b)
		imm.surface_set_color(col)
		imm.surface_add_vertex(c)
		imm.surface_set_color(col)
		imm.surface_add_vertex(a)
		imm.surface_set_color(col)
		imm.surface_add_vertex(c)
		imm.surface_set_color(col)
		imm.surface_add_vertex(d)


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


# ============================================================================
# APPROACH SWITCHING
# ============================================================================
func _on_radius_changed(value: float) -> void:
	_radius_label.text = "Radius: %d" % int(value)
	if _current_approach != "":
		_rebuild_terrain()


func _on_height_changed(value: float) -> void:
	_height_label.text = "Height: %d" % int(value)


func _on_exp_changed(value: float) -> void:
	_exp_label.text = "Height Curve: %.1f" % value


func _on_step_changed(value: float) -> void:
	_step_label.text = "Height Step: %.1f" % value


func _on_grid_changed(value: float) -> void:
	_grid_label.text = "Grid Lines: %.2f" % value


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
	_terrain.set_meta("cells", cells)
	_terrain.set_meta("chunk_manager", chunk_manager)
	_terrain.set_script(script)
	add_child(_terrain)
	_label.text = "Generating hex prisms..."
	call_deferred("_label_done", "Hex prisms ready.")


func _on_flat() -> void:
	_current_approach = "flat"
	_terrain_free()
	var script := load("res://HexGrid/approach_flat.gd") as GDScript
	_terrain = Node3D.new()
	_terrain.set_meta("grid_radius", int(_radius_slider.value))
	_terrain.set_meta("cells", cells)
	_terrain.set_meta("chunk_manager", chunk_manager)
	_terrain.set_script(script)
	add_child(_terrain)
	_label.text = "Generating flat grid..."
	call_deferred("_label_done", "Flat grid ready.")


func _label_done(msg: String) -> void:
	_label.text = msg


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
