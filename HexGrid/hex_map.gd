extends Node3D

const HEX_SIZE: float = 1.1547
const SUB_HEX_SIZE: float = HEX_SIZE / 3.0
const SUB_HEX_DIST: float = HEX_SIZE * 0.57735026919
const HEIGHT_SCALE: float = 15.0
const WATER_HEIGHT: float = 0.3

const VERTEX_NEIGHBORS: Array = [
	[0, 1],
	[0, 5],
	[5, 4],
	[4, 3],
	[3, 2],
	[2, 1],
]

const VERTEX_OFFSET: int = 7
const TOTAL_SUBS: int = 13

const BIOME_DEEP_WATER := 0
const BIOME_WATER := 1
const BIOME_BEACH := 2
const BIOME_GRASS := 3
const BIOME_DIRT := 4
const BIOME_STONE := 5
const BIOME_LAKE := 6

const BIOME_NAMES := ["Deep Water", "Water", "Beach", "Grass", "Dirt", "Stone", "Lake"]

var BIOME_COLORS: Array[Color] = [
	Color(0.18, 0.35, 0.65),
	Color(0.28, 0.52, 0.78),
	Color(0.82, 0.77, 0.55),
	Color(0.35, 0.55, 0.28),
	Color(0.55, 0.42, 0.28),
	Color(0.48, 0.48, 0.48),
	Color(0.32, 0.55, 0.82),
]

const WATER_LEVEL: float = -0.3
const LAKE_LEVEL: float = -0.2

const ELEVATION_STEPS: Array[float] = [1.0, 0.1, 0.0]
const ELEVATION_STEP_NAMES: Array[String] = ["Step 1.0", "Step 0.1", "Flat"]
var elevation_step_idx: int = 0

var cells: Dictionary = {}
var chunk_manager: ChunkManager

var river_cells: Dictionary = {}
var road_cells: Dictionary = {}
var vertex_subs: Dictionary = {}

## Toggle sub-hex overlay (H key). Shows the13 sub-hex grid on each hex for river/road painting.
@export var show_overlay: bool = false

## Toggle grid lines (G key). Shows a wireframe grid on the terrain.
@export var show_grid: bool = false

## Toggle height labels (V key). Shows elevation height text on each hex.
@export var show_height: bool = false

## Toggle elevation shading (Insert key). Colors hexes by elevation value.
@export var show_elevation_shade: bool = false

## Current tool: 0=Navigate, 1=River, 2=Road, 3=Block. Change with keys 1/2/3/9 or Escape to deselect.
@export_range(0, 3) var tool_mode: int = 0:
	set(v):
		tool_mode = v
		if is_inside_tree():
			_update_ui()

## Elevation step precision (F key). 1.0=integer, 0.1=tenth, 0.0=flat.
@export var elevation_step: float = 1.0:
	set(v):
		elevation_step = v
		if ELEVATION_STEPS.has(v):
			elevation_step_idx = ELEVATION_STEPS.find(v)

var roads: Array[Dictionary] = []
const TOOL_NAMES := ["Navigate", "River", "Road", "Block"]

var painting: bool = false
var erasing: bool = false

var road_start: Vector3i = Vector3i(999999, 999999, -1999998)
var placed_blocks: Dictionary = {}

var info_label: Label
var tool_label: Label

var panning: bool = false
var pan_start: Vector2 = Vector2.ZERO
var orbiting: bool = false
var orbit_start: Vector2 = Vector2.ZERO

const VIEW_MARGIN: float = 5.0

var chunks_with_rivers: Dictionary = {}
const CHUNK_SIZE: int = 10
const RIVER_SOURCE_PERCENTILE: float = 0.97
const MAX_RIVERS_PER_CHUNK: int = 1
const MIN_LAKE_SIZE: int = 10

var _pending_chunks: Array[Vector2i] = []
var _pending_rivers: Array[Vector2i] = []
const MAX_TERRAIN_PER_FRAME: int = 32
const MAX_RIVERS_PER_FRAME: int = 8
const MAX_NEW_CHUNKS_QUEUED_PER_FRAME: int = 64

var _cached_visible_hexes: Array[Vector3i] = []
var _cached_visible_set: Dictionary = {}
var _cached_visible_rivers: Array = []
var _cached_visible_vertex_rivers: Array = []
var _needs_save: bool = false
var _tool_flash_timer: float = 0.0
var _last_hover_hex: Vector3i = Vector3i(999999, 999999, -1999998)
var _last_debug_hover_hex: Vector3i = Vector3i(999999, 999999, -1999998)
var _cached_chunk_min: Vector2i = Vector2i.ZERO
var _cached_chunk_max: Vector2i = Vector2i.ZERO

var camera: Camera3D
var hex_multimesh_instance: MultiMeshInstance3D
var overlay_mesh_instance: MeshInstance3D
var grid_lines_mesh_instance: MeshInstance3D

var camera_yaw: float = 45.0
var camera_pitch: float = -55.0
var camera_distance: float = 25.0
var camera_pivot: Vector3 = Vector3.ZERO

var _hex_prism_mesh: ArrayMesh = null
var _hex_grass_mesh: ArrayMesh = preload("res://assets/kaykit_medieval_hexagon_pack/tiles/base/hex_grass.mesh")
var _blocks_container: Node3D
var _block_instances: Dictionary = {}
var _needs_rebuild: bool = true
var _needs_overlay_rebuild: bool = true

var _cached_camera_yaw: float = NAN
var _cached_camera_pitch: float = NAN
var _cached_camera_distance: float = NAN
var _cached_camera_pivot: Vector3 = Vector3(NAN, NAN, NAN)


func _ready() -> void:
	chunk_manager = ChunkManager.new(cells)
	_setup_3d()
	_setup_ui()
	var save_path := "res://map_save.json"
	if FileAccess.file_exists(save_path):
		if _load_map_from(save_path):
			return
	_needs_rebuild = true


func _exit_tree() -> void:
	if chunk_manager:
		chunk_manager.cleanup()


func _setup_3d() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 60.0
	camera.near = 0.01
	camera.far = 500.0
	add_child(camera)
	_update_camera_transform()

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

	hex_multimesh_instance = MultiMeshInstance3D.new()
	var hex_mat := StandardMaterial3D.new()
	hex_mat.vertex_color_use_as_albedo = true
	hex_multimesh_instance.material_override = hex_mat
	add_child(hex_multimesh_instance)

	overlay_mesh_instance = MeshInstance3D.new()
	var overlay_mat := StandardMaterial3D.new()
	overlay_mat.vertex_color_use_as_albedo = true
	overlay_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay_mesh_instance.material_override = overlay_mat
	add_child(overlay_mesh_instance)

	grid_lines_mesh_instance = MeshInstance3D.new()
	var grid_mat := StandardMaterial3D.new()
	grid_mat.vertex_color_use_as_albedo = true
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_lines_mesh_instance.material_override = grid_mat
	add_child(grid_lines_mesh_instance)

	_blocks_container = Node3D.new()
	add_child(_blocks_container)

	_hex_prism_mesh = _create_hex_prism_mesh()


func _update_camera_transform() -> void:
	var yaw_rad := deg_to_rad(camera_yaw)
	var pitch_rad := deg_to_rad(camera_pitch)
	var offset := Vector3(
		cos(pitch_rad) * sin(yaw_rad),
		-sin(pitch_rad),
		cos(pitch_rad) * cos(yaw_rad)
	) * camera_distance
	camera.global_position = camera_pivot + offset
	camera.look_at(camera_pivot, Vector3.UP)


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	info_label = Label.new()
	info_label.position = Vector2(10, 10)
	info_label.add_theme_font_size_override("font_size", 14)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	info_label.add_theme_constant_override("shadow_offset_x", 1)
	info_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(info_label)

	tool_label = Label.new()
	tool_label.position = Vector2(10, 35)
	tool_label.add_theme_font_size_override("font_size", 16)
	tool_label.add_theme_color_override("font_color", Color(1, 1, 0.3))
	tool_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	tool_label.add_theme_constant_override("shadow_offset_x", 1)
	tool_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(tool_label)

	_update_ui()


func _update_ui() -> void:
	tool_label.text = "Tool: %s [1/2/3]" % TOOL_NAMES[tool_mode]
	info_label.text = "Orbit: MMB | Pan: WASD/RMB | Zoom: Scroll | Rot: Q/E | Grid: G | Overlay: H | ElevStep: F | Block: 9 | Regen: R | QSave: F6 | QLoad: F7 | Save: F8 | Load: F9 | Esc: Cancel"


# ============================================================================
# FRAME PROCESSING
# ============================================================================
func _process(delta: float) -> void:
	_discover_visible_chunks()
	_process_pending_batch()
	_process_pending_rivers()
	if _tool_flash_timer > 0.0:
		_tool_flash_timer -= delta
		if _tool_flash_timer <= 0.0:
			_update_ui()
	if not _pending_chunks.is_empty() or not _pending_rivers.is_empty():
		if chunk_manager._last_batch_generated:
			_needs_rebuild = true
			chunk_manager._last_batch_generated = false
	else:
		if _needs_save:
			_save_map()
			_needs_save = false
		_update_hover_info()

	if _needs_rebuild:
		_rebuild_hex_multimesh()
		_rebuild_overlay_mesh()
		_rebuild_grid_lines()
		_update_block_instances()
		_needs_rebuild = false
		_needs_overlay_rebuild = false
	elif _needs_overlay_rebuild:
		_rebuild_overlay_mesh()
		_needs_overlay_rebuild = false

	if tool_mode == 1:
		var hover := _get_mouse_hex()
		if hover != _last_debug_hover_hex:
			_last_debug_hover_hex = hover
			_needs_overlay_rebuild = true


func _update_hover_info() -> void:
	var hex := _get_mouse_hex()
	if hex == _last_hover_hex:
		return
	_last_hover_hex = hex
	if _cell_exists(hex):
		var cell: HexCellData = cells[hex]
		var biome_name: String = BIOME_NAMES[cell.biome]
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
		var wn := _count_sub_hex_water_neighbors(hex, best_sub)
		var sub_type := "Sub"
		if best_sub >= VERTEX_OFFSET:
			sub_type = "Vertex"
		var sub_h: float = cell.sub_heights[best_sub]
		var display_h: float = _get_cell_height(cell)
		var labels := ""
		if _is_hex_river(hex):
			labels += "  |  RIVER(%d)" % _hex_river_count(hex)
		if _is_hex_road(hex):
			labels += "  |  ROAD(%d)" % _hex_road_count(hex)
		info_label.text = "Hex: (%d,%d,%d)  |  %s  |  %s %d  |  Elev: %.2f  |  Height: %.1f  |  Water nb: %d%s  |  Q:%d R:%d" % [
			hex.x, hex.y, hex.z, biome_name, sub_type, best_sub, cell.elevation, display_h, wn, labels,
			_pending_chunks.size(), _pending_rivers.size()
		]
	else:
		info_label.text = "Hex: none  |  Q:%d R:%d" % [_pending_chunks.size(), _pending_rivers.size()]


func _discover_visible_chunks() -> void:
	_ensure_draw_cache()
	for cq in range(_cached_chunk_min.x, _cached_chunk_max.x + 1):
		for cr in range(_cached_chunk_min.y, _cached_chunk_max.y + 1):
			var ck := Vector2i(cq, cr)
			if not chunk_manager._loaded_chunk_origins.has(ck):
				if not _pending_chunks.has(ck) and _pending_chunks.size() < MAX_NEW_CHUNKS_QUEUED_PER_FRAME:
					_pending_chunks.append(ck)


func _process_pending_batch() -> void:
	if _pending_chunks.is_empty():
		return
	var count := mini(_pending_chunks.size(), MAX_TERRAIN_PER_FRAME)
	var batch: Array[Vector2i] = _pending_chunks.slice(0, count)
	_pending_chunks = _pending_chunks.slice(count)
	chunk_manager.generate_batch(batch)
	for ck in batch:
		if _chunk_has_cells(ck) and not chunks_with_rivers.has(ck):
			_pending_rivers.append(ck)
	if _pending_chunks.is_empty():
		_needs_save = true


func _process_pending_rivers() -> void:
	var processed := 0
	var remaining: Array[Vector2i] = []
	for ck in _pending_rivers:
		if chunks_with_rivers.has(ck):
			continue
		if processed < MAX_RIVERS_PER_FRAME and _chunk_all_neighbors_loaded(ck):
			_ensure_chunk_rivers(ck)
			processed += 1
		else:
			remaining.append(ck)
	_pending_rivers = remaining
	if processed > 0 and _pending_rivers.is_empty():
		_needs_save = true


func _chunk_has_cells(ck: Vector2i) -> bool:
	for q in range(ck.x * CHUNK_SIZE, (ck.x + 1) * CHUNK_SIZE):
		for r in range(ck.y * CHUNK_SIZE, (ck.y + 1) * CHUNK_SIZE):
			if cells.has(Vector3i(q, r, -q - r)):
				return true
	return false


func _chunk_all_neighbors_loaded(ck: Vector2i) -> bool:
	for dq in range(-1, 2):
		for dr in range(-1, 2):
			var nck := Vector2i(ck.x + dq, ck.y + dr)
			if not chunk_manager._loaded_chunk_origins.has(nck):
				return false
	return true


# ============================================================================
# DRAW CACHE
# ============================================================================
func _invalidate_draw_cache() -> void:
	_cached_camera_yaw = NAN
	_cached_camera_pitch = NAN
	_cached_camera_distance = NAN
	_cached_camera_pivot = Vector3(NAN, NAN, NAN)


func _ensure_draw_cache() -> void:
	if _cached_camera_yaw == camera_yaw and _cached_camera_pitch == camera_pitch and \
	   _cached_camera_distance == camera_distance and _cached_camera_pivot == camera_pivot:
		return
	_cached_camera_yaw = camera_yaw
	_cached_camera_pitch = camera_pitch
	_cached_camera_distance = camera_distance
	_cached_camera_pivot = camera_pivot
	_cached_visible_hexes = _get_visible_hex_range()
	_cached_visible_set.clear()
	for hex in _cached_visible_hexes:
		_cached_visible_set[hex] = true
	if not _cached_visible_hexes.is_empty():
		_cached_chunk_min = _chunk_key(_cached_visible_hexes[0])
		_cached_chunk_max = _cached_chunk_min
		for hex in _cached_visible_hexes:
			var ck := _chunk_key(hex)
			_cached_chunk_min.x = mini(_cached_chunk_min.x, ck.x)
			_cached_chunk_max.x = maxi(_cached_chunk_max.x, ck.x)
			_cached_chunk_min.y = mini(_cached_chunk_min.y, ck.y)
			_cached_chunk_max.y = maxi(_cached_chunk_max.y, ck.y)
	_cached_visible_rivers.clear()
	for hex in river_cells:
		if _cached_visible_set.has(hex):
			_cached_visible_rivers.append(hex)
	_cached_visible_vertex_rivers.clear()
	for key in vertex_subs:
		var vdata: Dictionary = vertex_subs[key]
		if vdata["river"] and vdata.has("hex") and _cached_visible_set.has(vdata["hex"]):
			_cached_visible_vertex_rivers.append(key)
	_needs_rebuild = true


# ============================================================================
# INPUT
# ============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey:
		_handle_key(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_distance = clampf(camera_distance * 0.85, 2.0, 100.0)
		_update_camera_transform()
		_invalidate_draw_cache()
		return
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_distance = clampf(camera_distance * 1.15, 2.0, 100.0)
		_update_camera_transform()
		_invalidate_draw_cache()
		return

	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			orbiting = true
			orbit_start = event.position
		else:
			orbiting = false
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		if tool_mode == 1 and event.pressed:
			erasing = true
			_paint_river_at(event.position, true)
		elif not event.pressed:
			erasing = false
		if tool_mode == 0 or tool_mode == 2:
			panning = event.pressed
			if event.pressed:
				pan_start = event.position
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
				_paint_river_at(event.position, false)
			2:
				_place_road_at(event.position)
			3:
				_place_block_at(event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if orbiting:
		var delta := event.position - orbit_start
		camera_yaw += delta.x * 0.3
		camera_pitch = clampf(camera_pitch + delta.y * 0.3, -85.0, -10.0)
		orbit_start = event.position
		_update_camera_transform()
		_invalidate_draw_cache()
		return

	if panning:
		var delta := event.position - pan_start
		var forward := -camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		var pan_speed := camera_distance * 0.004
		camera_pivot += (right * delta.x + forward * -delta.y) * pan_speed
		pan_start = event.position
		_update_camera_transform()
		_invalidate_draw_cache()
		return

	if painting and tool_mode == 1:
		_paint_river_at(event.position, false)
		return
	elif erasing and tool_mode == 1:
		_paint_river_at(event.position, true)
		return


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	match event.keycode:
		KEY_1:
			tool_mode = 0
			_last_debug_hover_hex = Vector3i(999999, 999999, -1999998)
			_needs_overlay_rebuild = true
			_update_ui()
		KEY_2:
			tool_mode = 1
			_last_debug_hover_hex = Vector3i(999999, 999999, -1999998)
			_needs_overlay_rebuild = true
			_update_ui()
		KEY_3:
			tool_mode = 2
			road_start = Vector3i(999999, 999999, -1999998)
			_last_debug_hover_hex = Vector3i(999999, 999999, -1999998)
			_needs_overlay_rebuild = true
			_update_ui()
		KEY_9:
			tool_mode = 3
			_last_debug_hover_hex = Vector3i(999999, 999999, -1999998)
			_needs_overlay_rebuild = true
			_update_ui()
		KEY_H:
			show_overlay = not show_overlay
			_needs_overlay_rebuild = true
		KEY_G:
			show_grid = not show_grid
			_needs_overlay_rebuild = true
		KEY_V:
			show_height = not show_height
			_needs_rebuild = true
		KEY_INSERT:
			show_elevation_shade = not show_elevation_shade
			_needs_rebuild = true
		KEY_ESCAPE:
			tool_mode = 0
			road_start = Vector3i(999999, 999999, -1999998)
			painting = false
			erasing = false
			_last_debug_hover_hex = Vector3i(999999, 999999, -1999998)
			_needs_overlay_rebuild = true
			_update_ui()
		KEY_Q:
			camera_yaw -= 15.0
			_update_camera_transform()
			_invalidate_draw_cache()
		KEY_E:
			camera_yaw += 15.0
			_update_camera_transform()
			_invalidate_draw_cache()
		KEY_R:
			_regenerate_map()
		KEY_F:
			elevation_step_idx = (elevation_step_idx + 1) % ELEVATION_STEPS.size()
			elevation_step = ELEVATION_STEPS[elevation_step_idx]
			_needs_rebuild = true
			_tool_flash("Elevation: " + ELEVATION_STEP_NAMES[elevation_step_idx])
		KEY_F6:
			_quick_save()
		KEY_F7:
			_quick_load()
		KEY_F8:
			_save()
		KEY_F9:
			_load()


func _regenerate_map() -> void:
	cells.clear()
	chunk_manager.cells = cells
	chunk_manager._loaded_chunk_origins.clear()
	chunk_manager.randomize_seeds()
	chunks_with_rivers.clear()
	river_cells.clear()
	road_cells.clear()
	vertex_subs.clear()
	roads.clear()
	placed_blocks.clear()
	_free_all_block_instances()
	_pending_chunks.clear()
	_pending_rivers.clear()
	_needs_save = false
	_invalidate_draw_cache()
	_needs_rebuild = true


# ============================================================================
# SAVE / LOAD
# ============================================================================
func _save_map() -> void:
	var save_path := "res://map_save.json"
	chunk_manager.save_map(save_path, river_cells, road_cells, vertex_subs, chunks_with_rivers, roads, placed_blocks)


func _load_map_from(path: String) -> bool:
	var loaded: Dictionary = chunk_manager.load_map(path)
	if loaded.is_empty():
		return false
	river_cells = loaded.get("river_cells", {})
	road_cells = loaded.get("road_cells", {})
	vertex_subs = loaded.get("vertex_subs", {})
	chunks_with_rivers = loaded.get("chunks_with_rivers", {})
	roads.clear()
	for r in loaded.get("roads", []):
		roads.append(r)
	placed_blocks = loaded.get("blocks", {})
	_rebuild_block_instances()
	_invalidate_draw_cache()
	_needs_rebuild = true
	return true


func _quick_save() -> void:
	_save_map()
	_tool_flash("Quick Saved")


func _quick_load() -> void:
	if _load_map_from("res://map_save.json"):
		_tool_flash("Quick Loaded")


func _save() -> void:
	chunk_manager.save_map("res://map_save_slot.json", river_cells, road_cells, vertex_subs, chunks_with_rivers, roads, placed_blocks)
	_tool_flash("Saved")


func _load() -> void:
	if _load_map_from("res://map_save_slot.json"):
		_tool_flash("Loaded")


func _tool_flash(msg: String) -> void:
	tool_label.text = msg
	_tool_flash_timer = 1.5


# ============================================================================
# COORDINATE CONVERSION
# ============================================================================
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


func _get_or_create_cell(hex: Vector3i) -> HexCellData:
	if cells.has(hex):
		return cells[hex]
	return null


func _elevation_to_biome(n: float) -> int:
	if n < -0.5:
		return BIOME_DEEP_WATER
	elif n < -0.3:
		return BIOME_WATER
	elif n < -0.15:
		return BIOME_BEACH
	elif n < 0.2:
		return BIOME_GRASS
	elif n < 0.4:
		return BIOME_DIRT
	else:
		return BIOME_STONE


func _elevation_to_color(e: float) -> Color:
	var t: float = clampf((e + 1.0) * 0.5, 0.0, 1.0)
	return Color(t, t, t, 0.4)


func _get_cell_height(cell: HexCellData) -> float:
	if _is_water_biome(cell.biome):
		return WATER_HEIGHT
	var step: float = ELEVATION_STEPS[elevation_step_idx]
	if step <= 0.0:
		return HEX_SIZE
	var hex_width: float = HEX_SIZE * HexGridMath.SQRT3
	var e := maxf(cell.elevation, 0.0)
	var height := e * hex_width + HEX_SIZE
	return snappedf(height, step)


# ============================================================================
# RIVER PAINTING
# ============================================================================
func _paint_river_at(screen_pos: Vector2, erase: bool) -> void:
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if world_pos.x == INF:
		return
	if erase:
		if _cell_exists(hex):
			var best_sub := _find_closest_sub_hex(hex, world_pos)
			_river_erase(hex, best_sub)
	else:
		if not _cell_exists(hex):
			_needs_overlay_rebuild = true
			return
		var best_sub := _find_closest_sub_hex(hex, world_pos)
		var wn := _count_sub_hex_water_neighbors(hex, best_sub)
		if wn < 1 or wn > 2:
			_needs_overlay_rebuild = true
			return
		for nb in _get_sub_hex_neighbors(hex, best_sub):
			if river_cells.has(nb["hex"]) and nb["sub"] in river_cells[nb["hex"]]:
				if _count_sub_hex_water_neighbors(nb["hex"], nb["sub"]) + 1 > 2:
					_needs_overlay_rebuild = true
					return
		_river_paint(hex, best_sub)
	_needs_overlay_rebuild = true


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


func _river_paint(hex: Vector3i, sub_idx: int) -> void:
	if sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var key := _vertex_key(hex, vi)
		if not vertex_subs.has(key):
			vertex_subs[key] = {"river": false, "road": false, "hex": hex, "vi": vi}
		vertex_subs[key]["river"] = true
		vertex_subs[key]["road"] = false
		return
	if not river_cells.has(hex):
		river_cells[hex] = []
	if sub_idx not in river_cells[hex]:
		river_cells[hex].append(sub_idx)
	if road_cells.has(hex) and sub_idx in road_cells[hex]:
		road_cells[hex].erase(sub_idx)
		if road_cells[hex].is_empty():
			road_cells.erase(hex)


func _river_erase(hex: Vector3i, sub_idx: int) -> void:
	if sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var key := _vertex_key(hex, vi)
		if vertex_subs.has(key):
			vertex_subs[key]["river"] = false
		return
	if river_cells.has(hex):
		river_cells[hex].erase(sub_idx)
		if river_cells[hex].is_empty():
			river_cells.erase(hex)


func _count_water_neighbors(hex: Vector3i) -> int:
	var count := 0
	for n in HexGridMath.cube_neighbors(hex):
		if _cell_exists(n):
			var c: HexCellData = cells[n]
			if _is_water_biome(c.biome) or river_cells.has(n):
				count += 1
	return count


func _hex_river_count(hex: Vector3i) -> int:
	return river_cells.get(hex, []).size()


func _hex_road_count(hex: Vector3i) -> int:
	return road_cells.get(hex, []).size()


func _is_hex_river(hex: Vector3i) -> bool:
	return _hex_river_count(hex) >= 2


func _is_hex_road(hex: Vector3i) -> bool:
	return _hex_road_count(hex) >= 2


func _is_sub_hex_water(hex: Vector3i, sub_idx: int) -> bool:
	if sub_idx >= VERTEX_OFFSET:
		return _is_vertex_river(hex, sub_idx - VERTEX_OFFSET)
	if not _cell_exists(hex):
		return false
	var c: HexCellData = cells[hex]
	if _is_water_biome(c.biome):
		return true
	if river_cells.has(hex) and sub_idx in river_cells[hex]:
		return true
	return false


func _get_sub_hex_neighbors(parent_hex: Vector3i, sub_idx: int) -> Array:
	var result: Array = []
	if sub_idx == 0:
		for i in 6:
			result.append({"hex": parent_hex, "sub": i + 1})
	elif sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var ring_a: int = ((vi + 5) % 6) + 1
		var ring_b: int = (vi % 6) + 1
		result.append({"hex": parent_hex, "sub": ring_a})
		result.append({"hex": parent_hex, "sub": ring_b})
	else:
		result.append({"hex": parent_hex, "sub": 0})
		var prev_sub: int = ((sub_idx - 2) % 6) + 1
		var next_sub: int = (sub_idx % 6) + 1
		result.append({"hex": parent_hex, "sub": prev_sub})
		result.append({"hex": parent_hex, "sub": next_sub})
		var dir: int = (7 - sub_idx) % 6
		var opp_sub: int = ((sub_idx + 2) % 6) + 1
		var neighbor_hex: Vector3i = parent_hex + HexGridMath.cube_direction(dir)
		result.append({"hex": neighbor_hex, "sub": opp_sub})
		var vi_a: int = sub_idx - 1
		var vi_b: int = sub_idx % 6
		result.append({"hex": parent_hex, "sub": VERTEX_OFFSET + vi_a})
		result.append({"hex": parent_hex, "sub": VERTEX_OFFSET + vi_b})
	return result


func _count_sub_hex_water_neighbors(parent_hex: Vector3i, sub_idx: int) -> int:
	var count := 0
	for nb in _get_sub_hex_neighbors(parent_hex, sub_idx):
		if _is_sub_hex_water(nb["hex"], nb["sub"]):
			count += 1
	return count


func _can_place_river(hex: Vector3i, sub_idx: int) -> Array:
	if sub_idx >= VERTEX_OFFSET:
		return _can_place_river_vertex(hex, sub_idx - VERTEX_OFFSET)
	if not _cell_exists(hex):
		return [false, "No terrain"]
	if river_cells.has(hex) and sub_idx in river_cells[hex]:
		return [true, ""]
	var wn := _count_sub_hex_water_neighbors(hex, sub_idx)
	if wn < 1:
		return [false, "No water nb (%d)" % wn]
	if wn > 2:
		return [false, "Too many water (%d)" % wn]
	for nb in _get_sub_hex_neighbors(hex, sub_idx):
		if river_cells.has(nb["hex"]) and nb["sub"] in river_cells[nb["hex"]]:
			if _count_sub_hex_water_neighbors(nb["hex"], nb["sub"]) + 1 > 2:
				return [false, "Would overflow nb"]
	return [true, "OK"]


func _can_place_river_vertex(hex: Vector3i, vi: int) -> Array:
	var key := _vertex_key(hex, vi)
	var vdata := _get_vertex_data(key)
	if vdata["river"]:
		return [true, ""]
	var ring_a: int = ((vi + 5) % 6) + 1
	var ring_b: int = (vi % 6) + 1
	var wn := 0
	if _is_sub_hex_water(hex, ring_a):
		wn += 1
	if _is_sub_hex_water(hex, ring_b):
		wn += 1
	if wn < 1:
		return [false, "No water nb (%d)" % wn]
	for ring_sub in [ring_a, ring_b]:
		if river_cells.has(hex) and ring_sub in river_cells[hex]:
			if _count_sub_hex_water_neighbors(hex, ring_sub) + 1 > 2:
				return [false, "Would overflow nb"]
	return [true, "OK"]


func _is_sub_hex_river(hex: Vector3i, sub_idx: int) -> bool:
	if sub_idx >= VERTEX_OFFSET:
		return _is_vertex_river(hex, sub_idx - VERTEX_OFFSET)
	return river_cells.has(hex) and sub_idx in river_cells[hex]


# ============================================================================
# ROAD PAINTING
# ============================================================================
func _road_paint(hex: Vector3i, sub_idx: int) -> void:
	if _is_sub_hex_water(hex, sub_idx):
		return
	if sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var key := _vertex_key(hex, vi)
		if not vertex_subs.has(key):
			vertex_subs[key] = {"river": false, "road": false, "hex": hex, "vi": vi}
		vertex_subs[key]["road"] = true
		return
	if not road_cells.has(hex):
		road_cells[hex] = []
	if sub_idx not in road_cells[hex]:
		road_cells[hex].append(sub_idx)


func _place_road_at(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		return

	if road_start == Vector3i(999999, 999999, -1999998):
		road_start = hex
		_needs_overlay_rebuild = true
	else:
		if hex != road_start:
			var path := HexGridMath.cube_line(road_start, hex)
			for i in range(path.size() - 1):
				roads.append({"from": path[i], "to": path[i + 1]})
				var from_hex: Vector3i = path[i]
				var to_hex: Vector3i = path[i + 1]
				_road_paint(from_hex, 0)
				_road_paint(to_hex, 0)
				var diff := to_hex - from_hex
				for d in 6:
					if HexGridMath.cube_direction(d) == diff:
						var exit_sub: int = ((6 - d) % 6) + 1
						_road_paint(from_hex, exit_sub)
						var entry_dir: int = (d + 3) % 6
						var entry_sub: int = ((6 - entry_dir) % 6) + 1
						_road_paint(to_hex, entry_sub)
						break
		road_start = Vector3i(999999, 999999, -1999998)
		_needs_overlay_rebuild = true


func _place_block_at(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		return
	if placed_blocks.has(hex):
		placed_blocks.erase(hex)
		_free_block_instance(hex)
	else:
		placed_blocks[hex] = true
		_create_block_instance(hex)
	_needs_overlay_rebuild = true


func _create_block_instance(hex: Vector3i) -> void:
	if _block_instances.has(hex):
		return
	var cell: HexCellData = cells[hex]
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cell)
	var mi := MeshInstance3D.new()
	mi.mesh = _hex_grass_mesh
	mi.rotation_degrees.y = 30.0
	mi.position = Vector3(hpos.x, height, hpos.z)
	mi.scale.y = maxf(height, 0.05)
	_blocks_container.add_child(mi)
	_block_instances[hex] = mi


func _free_block_instance(hex: Vector3i) -> void:
	if _block_instances.has(hex):
		var mi: MeshInstance3D = _block_instances[hex]
		_block_instances.erase(hex)
		if is_instance_valid(mi):
			mi.queue_free()


func _free_all_block_instances() -> void:
	for hex in _block_instances:
		var mi: MeshInstance3D = _block_instances[hex]
		if is_instance_valid(mi):
			mi.queue_free()
	_block_instances.clear()


func _rebuild_block_instances() -> void:
	_free_all_block_instances()
	for hex in placed_blocks:
		_create_block_instance(hex)


func _update_block_instances() -> void:
	for hex in placed_blocks:
		if not _block_instances.has(hex):
			_create_block_instance(hex)
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell)
		var mi: MeshInstance3D = _block_instances[hex]
		mi.position = Vector3(hpos.x, height, hpos.z)
		mi.scale.y = maxf(height, 0.05)


# ============================================================================
# CHUNK RIVER GENERATION
# ============================================================================
func _chunk_key(hex: Vector3i) -> Vector2i:
	return Vector2i(floori(float(hex.x) / CHUNK_SIZE), floori(float(hex.y) / CHUNK_SIZE))


func _ensure_chunk_rivers(chunk_origin: Vector2i) -> void:
	var key := chunk_origin
	if chunks_with_rivers.has(key):
		return
	chunks_with_rivers[key] = true

	if not chunk_manager._loaded_chunk_origins.has(chunk_origin):
		chunk_manager.generate_batch([chunk_origin])

	var cells_in_chunk: Array[Vector3i] = []
	for q in range(chunk_origin.x * CHUNK_SIZE, (chunk_origin.x + 1) * CHUNK_SIZE):
		for r in range(chunk_origin.y * CHUNK_SIZE, (chunk_origin.y + 1) * CHUNK_SIZE):
			var hex := Vector3i(q, r, -q - r)
			if _cell_exists(hex):
				cells_in_chunk.append(hex)

	if cells_in_chunk.is_empty():
		return

	var elevations: Array[float] = []
	for hex in cells_in_chunk:
		elevations.append(cells[hex].elevation)
	elevations.sort()
	var threshold_idx: int = int(elevations.size() * RIVER_SOURCE_PERCENTILE)
	if threshold_idx >= elevations.size():
		threshold_idx = elevations.size() - 1
	var threshold: float = elevations[threshold_idx]

	var candidates: Array[Vector3i] = []
	for hex in cells_in_chunk:
		var c: HexCellData = cells[hex]
		if c.elevation >= threshold and not _is_water_biome(c.biome):
			var adj_water: bool = false
			for nb in HexGridMath.cube_neighbors(hex):
				if _cell_exists(nb) and _is_water_biome(cells[nb].biome):
					adj_water = true
					break
			if not adj_water:
				candidates.append(hex)

	candidates.shuffle()
	var chunk_paths: Array[Array] = []
	var rivers_placed: int = 0
	for source in candidates:
		if rivers_placed >= MAX_RIVERS_PER_CHUNK:
			break
		var path := _flow_river(source)
		if path.size() >= 3:
			var end_cell: HexCellData = cells[path[-1]]
			var reached_water: bool = _is_water_biome(end_cell.biome)
			if not reached_water:
				var basin := _flood_fill_basin(path[-1])
				if basin.size() >= MIN_LAKE_SIZE:
					for whex in basin:
						var wc: HexCellData = cells[whex]
						wc.biome = BIOME_LAKE
						wc.color = BIOME_COLORS[BIOME_LAKE]
						_set_flat_water_heights(wc, LAKE_LEVEL)
						river_cells.erase(whex)
						road_cells.erase(whex)
						for vi in 6:
							var vkey := _vertex_key(whex, vi)
							if vertex_subs.has(vkey):
								vertex_subs[vkey]["river"] = false
								vertex_subs[vkey]["road"] = false
			_paint_river_path(path)
			chunk_paths.append(path)
			rivers_placed += 1

	_post_process_rivers(chunk_paths, cells_in_chunk)


func _is_water_biome(biome: int) -> bool:
	return biome == BIOME_WATER or biome == BIOME_DEEP_WATER or biome == BIOME_LAKE


func _set_flat_water_heights(cell: HexCellData, level: float) -> void:
	for i in TOTAL_SUBS:
		cell.sub_heights[i] = snappedf(level, 0.1)
	cell.elevation = snappedf(level, 0.1)


func _post_process_rivers(chunk_paths: Array[Array], cells_in_chunk: Array[Vector3i]) -> void:
	if chunk_paths.is_empty():
		return

	var total_len: int = 0
	for p in chunk_paths:
		total_len += p.size()
	var avg_len: float = float(total_len) / float(chunk_paths.size())

	for path in chunk_paths:
		var end_cell: HexCellData = cells[path[-1]]
		var reaches_water: bool = _is_water_biome(end_cell.biome)
		if not reaches_water or float(path.size()) <= avg_len:
			_undo_river_path(path)
		else:
			_convert_river_to_water(path)

	var changed := true
	while changed:
		changed = false
		var to_water: Array[Vector3i] = []
		for hex in cells_in_chunk:
			if not _cell_exists(hex):
				continue
			if _is_water_biome(cells[hex].biome):
				continue
			var wn := 0
			for nb in HexGridMath.cube_neighbors(hex):
				if _cell_exists(nb) and _is_water_biome(cells[nb].biome):
					wn += 1
			if wn >= 5:
				to_water.append(hex)
		for hex in to_water:
			var c: HexCellData = cells[hex]
			c.biome = BIOME_WATER
			c.color = BIOME_COLORS[BIOME_WATER]
			_set_flat_water_heights(c, WATER_LEVEL)
			river_cells.erase(hex)
			road_cells.erase(hex)
			for vi in 6:
				var vkey := _vertex_key(hex, vi)
				if vertex_subs.has(vkey):
					vertex_subs[vkey]["river"] = false
					vertex_subs[vkey]["road"] = false
		if to_water.size() > 0:
			changed = true

	var ocean_connected: Dictionary = {}
	var queue: Array[Vector3i] = []
	for hex in cells_in_chunk:
		if not _cell_exists(hex):
			continue
		if cells[hex].biome == BIOME_DEEP_WATER:
			ocean_connected[hex] = true
			queue.append(hex)
	for hex in cells_in_chunk:
		if not _cell_exists(hex):
			continue
		if cells[hex].biome == BIOME_WATER and not ocean_connected.has(hex):
			var adj_ocean: bool = false
			for nb in HexGridMath.cube_neighbors(hex):
				if _cell_exists(nb) and cells[nb].biome == BIOME_DEEP_WATER:
					adj_ocean = true
					break
			if adj_ocean:
				ocean_connected[hex] = true
				queue.append(hex)
	while queue.size() > 0:
		var h: Vector3i = queue.pop_back()
		for nb in HexGridMath.cube_neighbors(h):
			if ocean_connected.has(nb):
				continue
			if not _cell_exists(nb):
				continue
			if cells[nb].biome == BIOME_WATER:
				ocean_connected[nb] = true
				queue.append(nb)
	for hex in cells_in_chunk:
		if ocean_connected.has(hex):
			continue
		if not _cell_exists(hex):
			continue
		var c: HexCellData = cells[hex]
		if c.biome == BIOME_WATER:
			c.biome = BIOME_LAKE
			c.color = BIOME_COLORS[BIOME_LAKE]
			_set_flat_water_heights(c, LAKE_LEVEL)

	for hex in cells_in_chunk:
		if not _cell_exists(hex):
			continue
		if not _is_water_biome(cells[hex].biome):
			continue
		river_cells.erase(hex)
		for vi in 6:
			var vkey := _vertex_key(hex, vi)
			if vertex_subs.has(vkey):
				vertex_subs[vkey]["river"] = false


func _undo_river_path(path: Array[Vector3i]) -> void:
	for idx in path.size():
		var hex: Vector3i = path[idx]
		if not _cell_exists(hex):
			continue
		if _is_water_biome(cells[hex].biome):
			continue
		_river_erase(hex, 0)
		if idx < path.size() - 1:
			var diff: Vector3i = path[idx + 1] - hex
			for d in 6:
				if HexGridMath.cube_direction(d) == diff:
					_river_erase(hex, ((6 - d) % 6) + 1)
					break
		if idx > 0:
			var diff: Vector3i = hex - path[idx - 1]
			for d in 6:
				if HexGridMath.cube_direction(d) == diff:
					var entry_dir: int = (d + 3) % 6
					_river_erase(hex, ((6 - entry_dir) % 6) + 1)
					break


func _convert_river_to_water(path: Array[Vector3i]) -> void:
	for hex in path:
		if not _cell_exists(hex):
			continue
		if _is_water_biome(cells[hex].biome):
			continue
		var c: HexCellData = cells[hex]
		c.biome = BIOME_WATER
		c.color = BIOME_COLORS[BIOME_WATER]
		_set_flat_water_heights(c, WATER_LEVEL)


func _flood_fill_basin(start: Vector3i) -> Array[Vector3i]:
	var MAX_BASIN: int = MIN_LAKE_SIZE * 3
	var basin: Array[Vector3i] = []
	var queue: Array[Vector3i] = [start]
	var visited: Dictionary = {start: true}
	var max_elev: float = cells[start].elevation
	while queue.size() > 0:
		if basin.size() >= MAX_BASIN:
			break
		var h: Vector3i = queue.pop_back()
		basin.append(h)
		for nb in HexGridMath.cube_neighbors(h):
			if visited.has(nb):
				continue
			if not _cell_exists(nb):
				continue
			var nc: HexCellData = cells[nb]
			if _is_water_biome(nc.biome):
				continue
			if nc.elevation <= max_elev:
				visited[nb] = true
				queue.append(nb)
	return basin


func _flow_river(start: Vector3i) -> Array[Vector3i]:
	if _cell_exists(start) and _is_water_biome(cells[start].biome):
		return []

	var path: Array[Vector3i] = [start]
	var current := start
	var visited: Dictionary = {start: true}
	var UP_PENALTY: float = 8.0
	var MAX_STEPS: int = 150

	for _step in MAX_STEPS:
		var c: HexCellData = cells[current]

		if _is_water_biome(c.biome):
			return path

		var neighbors: Array = []
		for nb in HexGridMath.cube_neighbors(current):
			if _cell_exists(nb):
				neighbors.append(nb)
		if neighbors.is_empty():
			break
		neighbors.sort_custom(func(a, b): return cells[a].elevation < cells[b].elevation)

		var found_downhill: bool = false
		for nb in neighbors:
			if visited.has(nb):
				continue
			if cells[nb].elevation < c.elevation:
				visited[nb] = true
				path.append(nb)
				current = nb
				found_downhill = true
				break

		if found_downhill:
			continue

		var basin_path := _flow_escape_basin(current, visited, UP_PENALTY)
		if basin_path.size() > 1:
			for i in range(1, basin_path.size()):
				var nh: Vector3i = basin_path[i]
				visited[nh] = true
				path.append(nh)
				current = nh
				if _is_water_biome(cells[current].biome):
					return path
		else:
			break

	return path


func _flow_escape_basin(from: Vector3i, global_visited: Dictionary, up_penalty: float) -> Array[Vector3i]:
	var MAX_ESCAPE: int = 50
	var open: Array = []
	var g_cost: Dictionary = {from: 0.0}
	var came_from: Dictionary = {}
	var closed: Dictionary = {}
	var lowest_hex: Vector3i = from
	var lowest_elev: float = cells[from].elevation

	open.append([0.0, from])

	while open.size() > 0:
		var best_idx: int = 0
		for i in range(1, open.size()):
			if open[i][0] < open[best_idx][0]:
				best_idx = i
		var current: Vector3i = open[best_idx][1]
		open.remove_at(best_idx)

		if closed.has(current):
			continue
		closed[current] = true

		if global_visited.has(current) and current != from:
			continue

		var c_cell: HexCellData = cells[current]

		if _is_water_biome(c_cell.biome):
			var result: Array[Vector3i] = [current]
			var trace := current
			while came_from.has(trace):
				trace = came_from[trace]
				result.append(trace)
			result.reverse()
			return result

		if c_cell.elevation < lowest_elev:
			lowest_elev = c_cell.elevation
			lowest_hex = current

		if closed.size() >= MAX_ESCAPE:
			break

		for nb in HexGridMath.cube_neighbors(current):
			if closed.has(nb) or global_visited.has(nb):
				continue
			if not _cell_exists(nb):
				continue
			var nb_cell: HexCellData = cells[nb]
			var elev_diff: float = nb_cell.elevation - c_cell.elevation
			var move_cost: float = 1.0 + maxf(0.0, elev_diff) * up_penalty
			var new_g: float = g_cost[current] + move_cost
			if not g_cost.has(nb) or new_g < g_cost[nb]:
				g_cost[nb] = new_g
				came_from[nb] = current
				open.append([new_g, nb])

	if lowest_hex != from and came_from.has(lowest_hex):
		var result: Array[Vector3i] = [lowest_hex]
		var trace := lowest_hex
		while came_from.has(trace):
			trace = came_from[trace]
			result.append(trace)
		result.reverse()
		return result

	return []


func _paint_river_path(path: Array[Vector3i]) -> void:
	for idx in path.size():
		var hex: Vector3i = path[idx]
		if not _cell_exists(hex):
			continue
		var c: HexCellData = cells[hex]
		if _is_water_biome(c.biome):
			continue
		_river_paint(hex, 0)
		if idx < path.size() - 1:
			var next_hex: Vector3i = path[idx + 1]
			var diff := next_hex - hex
			for d in 6:
				if HexGridMath.cube_direction(d) == diff:
					var exit_sub: int = ((6 - d) % 6) + 1
					_river_paint(hex, exit_sub)
					break
		if idx > 0:
			var prev: Vector3i = path[idx - 1]
			var diff := hex - prev
			for d in 6:
				if HexGridMath.cube_direction(d) == diff:
					var entry_dir: int = (d + 3) % 6
					var entry_sub: int = ((6 - entry_dir) % 6) + 1
					_river_paint(hex, entry_sub)
					break


# ============================================================================
# SUB-HEX POSITIONS
# ============================================================================
func _get_sub_hex_local_pos(parent_hex: Vector3i, sub_idx: int) -> Vector2:
	if sub_idx == 0:
		return Vector2.ZERO
	elif sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var angle := deg_to_rad(60.0 * float(vi))
		return Vector2(cos(angle), sin(angle)) * HEX_SIZE
	else:
		var angle := deg_to_rad(30.0 + 60.0 * float(sub_idx - 1))
		return Vector2(cos(angle), sin(angle)) * SUB_HEX_DIST


func _get_sub_hex_world_pos(parent_hex: Vector3i, sub_idx: int) -> Vector3:
	var hex_world := HexGridMath.cube_to_world_flat_top(parent_hex, HEX_SIZE)
	var local := _get_sub_hex_local_pos(parent_hex, sub_idx)
	return Vector3(hex_world.x + local.x, 0.0, hex_world.z + local.y)


func _vertex_key(hex: Vector3i, vi: int) -> int:
	var dirs: Array = VERTEX_NEIGHBORS[vi]
	var h1 := hex
	var h2 := hex + HexGridMath.cube_direction(dirs[0])
	var h3 := hex + HexGridMath.cube_direction(dirs[1])
	var hx: int = mini(mini(h1.x, h2.x), h3.x)
	var hy: int = mini(mini(h1.y, h2.y), h3.y)
	var hz: int = mini(mini(h1.z, h2.z), h3.z)
	return hx * 1000003 + hy * 1009 + hz


func _get_vertex_data(key: int) -> Dictionary:
	if vertex_subs.has(key):
		return vertex_subs[key]
	return {"river": false, "road": false}


func _is_vertex_river(hex: Vector3i, vi: int) -> bool:
	return _get_vertex_data(_vertex_key(hex, vi))["river"]


func _is_vertex_road(hex: Vector3i, vi: int) -> bool:
	return _get_vertex_data(_vertex_key(hex, vi))["road"]


# ============================================================================
# VISIBLE HEX RANGE
# ============================================================================
func _get_visible_hex_range() -> Array[Vector3i]:
	var viewport_size := get_viewport().get_visible_rect().size

	var corners := [
		Vector2(0, 0),
		Vector2(viewport_size.x, 0),
		Vector2(0, viewport_size.y),
		Vector2(viewport_size.x, viewport_size.y),
		Vector2(viewport_size.x * 0.5, viewport_size.y * 0.5),
	]
	var ground_points: Array[Vector3] = []
	for corner in corners:
		var gp := _screen_to_world_3d(corner)
		if gp.x != INF:
			ground_points.append(gp)

	if ground_points.is_empty():
		var center_hex := HexGridMath.world_to_cube_flat_top(camera_pivot, HEX_SIZE)
		return _spiral_range(center_hex, 5)

	var min_x := ground_points[0].x
	var max_x := ground_points[0].x
	var min_z := ground_points[0].z
	var max_z := ground_points[0].z
	for p in ground_points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)

	var span := maxf(max_x - min_x, max_z - min_z)
	var margin := maxf(HEX_SIZE * 3.0, span * 0.3)
	min_x -= margin
	max_x += margin
	min_z -= margin
	max_z += margin

	var c_min := HexGridMath.world_to_cube_flat_top(Vector3(min_x, 0, min_z), HEX_SIZE)
	var c_max := HexGridMath.world_to_cube_flat_top(Vector3(max_x, 0, max_z), HEX_SIZE)
	var range_min_q := mini(c_min.x, c_max.x) - 2
	var range_max_q := maxi(c_min.x, c_max.x) + 2
	var range_min_r := mini(c_min.y, c_max.y) - 2
	var range_max_r := maxi(c_min.y, c_max.y) + 2

	var result: Array[Vector3i] = []
	for q in range(range_min_q, range_max_q + 1):
		for r in range(range_min_r, range_max_r + 1):
			var hex := Vector3i(q, r, -q - r)
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			if hpos.x >= min_x - HEX_SIZE and hpos.x <= max_x + HEX_SIZE and \
			   hpos.z >= min_z - HEX_SIZE and hpos.z <= max_z + HEX_SIZE:
				result.append(hex)
	return result


func _spiral_range(center: Vector3i, radius: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = [center]
	for r in range(1, radius + 1):
		result.append_array(HexGridMath.cube_ring(center, r))
	return result


# ============================================================================
# 3D MESH: HEX PRISM TEMPLATE
# ============================================================================
func _create_hex_prism_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var top_verts: PackedVector3Array = PackedVector3Array()
	var bot_verts: PackedVector3Array = PackedVector3Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i))
		var x := cos(angle)
		var z := sin(angle)
		top_verts.append(Vector3(x, 1.0, z))
		bot_verts.append(Vector3(x, 0.0, z))

	var top_center := Vector3(0.0, 1.0, 0.0)
	for i in 6:
		var next_i := (i + 1) % 6
		st.add_vertex(top_center)
		st.add_vertex(top_verts[i])
		st.add_vertex(top_verts[next_i])

	var bot_center := Vector3(0.0, 0.0, 0.0)
	for i in 6:
		var next_i := (i + 1) % 6
		st.add_vertex(bot_center)
		st.add_vertex(bot_verts[next_i])
		st.add_vertex(bot_verts[i])

	for i in 6:
		var next_i := (i + 1) % 6
		st.add_vertex(bot_verts[i])
		st.add_vertex(top_verts[i])
		st.add_vertex(top_verts[next_i])
		st.add_vertex(bot_verts[i])
		st.add_vertex(top_verts[next_i])
		st.add_vertex(bot_verts[next_i])

	st.generate_normals()
	return st.commit()


# ============================================================================
# 3D MESH: REBUILD MULTIMESH
# ============================================================================
func _rebuild_hex_multimesh() -> void:
	var visible_hexes := _cached_visible_hexes
	var hex_count := 0
	for hex in visible_hexes:
		if _cell_exists(hex):
			hex_count += 1
	if hex_count == 0:
		hex_multimesh_instance.multimesh = null
		return

	var mm := MultiMesh.new()
	mm.mesh = _hex_prism_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = hex_count

	var idx := 0
	for hex in visible_hexes:
		if not _cell_exists(hex):
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell)
		var draw_color := cell.color
		if show_elevation_shade:
			var elev_col := _elevation_to_color(cell.elevation)
			draw_color = draw_color.lerp(elev_col, 0.4)
		if show_height:
			var brightness: float = lerpf(0.4, 1.6, (cell.elevation + 1.0) * 0.5)
			var height_col := Color(brightness, brightness, brightness, 0.35)
			draw_color = draw_color.lerp(height_col, 0.35)

		var t := Transform3D(Basis().scaled(Vector3(HEX_SIZE, height, HEX_SIZE)), Vector3(hpos.x, 0.0, hpos.z))
		mm.set_instance_transform(idx, t)
		mm.set_instance_color(idx, draw_color)
		idx += 1

	hex_multimesh_instance.multimesh = mm


# ============================================================================
# 3D MESH: REBUILD OVERLAY (rivers, roads, debug)
# ============================================================================
func _rebuild_overlay_mesh() -> void:
	var imm := ImmediateMesh.new()
	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	for hex in _cached_visible_rivers:
		if not river_cells.has(hex) or not _cell_exists(hex):
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell) + 0.05
		for sub_idx in river_cells[hex]:
			var local := _get_sub_hex_local_pos(hex, sub_idx)
			var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
			_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, Color(0.2, 0.45, 0.75, 0.75))

	for key in _cached_visible_vertex_rivers:
		var vdata: Dictionary = _get_vertex_data(key)
		if not vdata.has("hex") or not vdata.has("vi"):
			continue
		var hex: Vector3i = vdata["hex"]
		var vi: int = vdata["vi"]
		if not _cell_exists(hex):
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell) + 0.05
		var local := _get_sub_hex_local_pos(hex, VERTEX_OFFSET + vi)
		var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
		_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, Color(0.2, 0.45, 0.75, 0.75))

	for road in roads:
		var from_hex: Vector3i = road["from"]
		var to_hex: Vector3i = road["to"]
		if not _cell_exists(from_hex) or not _cell_exists(to_hex):
			continue
		_add_road_overlay_tris(imm, from_hex, to_hex, Color(0.6, 0.35, 0.15, 0.9))

	if show_overlay:
		for hex in _cached_visible_hexes:
			if not _cell_exists(hex):
				continue
			var cell: HexCellData = cells[hex]
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			var height := _get_cell_height(cell) + 0.03
			for i in TOTAL_SUBS:
				var local := _get_sub_hex_local_pos(hex, i)
				var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
				_add_flat_hex_wireframe(imm, center, SUB_HEX_SIZE, Color(1, 1, 1, 0.25))

	if tool_mode == 1:
		_add_river_debug_overlay_tris(imm)

	imm.surface_end()
	overlay_mesh_instance.mesh = imm


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


func _add_road_overlay_tris(imm: ImmediateMesh, from_hex: Vector3i, to_hex: Vector3i, col: Color) -> void:
	var diff := to_hex - from_hex
	var dir := -1
	for d in 6:
		if HexGridMath.cube_direction(d) == diff:
			dir = d
			break

	if not _is_sub_hex_water(from_hex, 0):
		_add_sub_hex_fill_tris(imm, from_hex, 0, col)
	if dir >= 0:
		var exit_sub := ((6 - dir) % 6) + 1
		if not _is_sub_hex_water(from_hex, exit_sub):
			_add_sub_hex_fill_tris(imm, from_hex, exit_sub, col)
		var entry_dir := (dir + 3) % 6
		var entry_sub := ((6 - entry_dir) % 6) + 1
		if not _is_sub_hex_water(to_hex, entry_sub):
			_add_sub_hex_fill_tris(imm, to_hex, entry_sub, col)
	if not _is_sub_hex_water(to_hex, 0):
		_add_sub_hex_fill_tris(imm, to_hex, 0, col)


func _add_sub_hex_fill_tris(imm: ImmediateMesh, hex: Vector3i, sub_idx: int, col: Color) -> void:
	if not _cell_exists(hex):
		return
	var cell: HexCellData = cells[hex]
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cell) + 0.06
	var local := _get_sub_hex_local_pos(hex, sub_idx)
	var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
	_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, col)


func _add_river_debug_overlay_tris(imm: ImmediateMesh) -> void:
	var hex := _get_mouse_hex()
	if not _cell_exists(hex):
		return
	var cell: HexCellData = cells[hex]
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cell) + 0.08

	var world_pos := _screen_to_world_3d(get_viewport().get_mouse_position())
	var local := Vector2(world_pos.x - hpos.x, world_pos.z - hpos.z)
	var best_sub := 0
	var best_dist := INF
	for i in TOTAL_SUBS:
		var sub_pos := _get_sub_hex_local_pos(hex, i)
		var d := local.distance_to(sub_pos)
		if d < best_dist:
			best_dist = d
			best_sub = i

	for i in TOTAL_SUBS:
		var result: Array = _can_place_river(hex, i)
		var ok: bool = result[0]
		var sub_pos := _get_sub_hex_local_pos(hex, i)
		var center := Vector3(hpos.x + sub_pos.x, height, hpos.z + sub_pos.y)
		if ok:
			var fill_col := Color(0.2, 0.8, 0.2, 0.3)
			if i == best_sub:
				fill_col = Color(0.2, 0.9, 0.2, 0.5)
			_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, fill_col)
		else:
			var fill_col := Color(0.8, 0.2, 0.2, 0.3)
			if i == best_sub:
				fill_col = Color(0.9, 0.2, 0.2, 0.5)
			_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, fill_col)


# ============================================================================
# 3D MESH: GRID LINES
# ============================================================================
func _rebuild_grid_lines() -> void:
	if not show_grid:
		grid_lines_mesh_instance.mesh = null
		return

	var imm := ImmediateMesh.new()
	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_LINES)

	var grid_col := Color(0, 0, 0, 0.2)
	for hex in _cached_visible_hexes:
		if not _cell_exists(hex):
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell) + 0.02
		var cos_arr: PackedFloat32Array = PackedFloat32Array()
		var sin_arr: PackedFloat32Array = PackedFloat32Array()
		for i in 6:
			var angle := deg_to_rad(60.0 * float(i))
			cos_arr.append(cos(angle))
			sin_arr.append(sin(angle))
		for i in 6:
			var next_i := (i + 1) % 6
			var x1 := hpos.x + cos_arr[i] * HEX_SIZE
			var z1 := hpos.z + sin_arr[i] * HEX_SIZE
			var x2 := hpos.x + cos_arr[next_i] * HEX_SIZE
			var z2 := hpos.z + sin_arr[next_i] * HEX_SIZE
			imm.surface_set_color(grid_col)
			imm.surface_add_vertex(Vector3(x1, height, z1))
			imm.surface_set_color(grid_col)
			imm.surface_add_vertex(Vector3(x2, height, z2))

	imm.surface_end()
	grid_lines_mesh_instance.mesh = imm
