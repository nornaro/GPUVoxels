@tool
class_name HexGridManager
extends Node3D

signal flat_mode_changed(flat: bool)
signal chunk_loaded(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)

# Chunk configuration
@export_range(8, 256, 8) var chunk_size: int = 16:
	set(v):
		chunk_size = clampi(v, 8, 256)
		if is_inside_tree() and Engine.is_editor_hint():
			_rebuild_all()

@export_range(1, 16, 1) var visible_chunk_radius: int = 8:
	set(v):
		visible_chunk_radius = clampi(v, 1, 16)
		if is_inside_tree():
			_update_active_chunks()

@export var hex_size: float = 1.0:
	set(v):
		hex_size = v
		if is_inside_tree() and Engine.is_editor_hint():
			_rebuild_all()

@export var prism_height: float = 2.0
@export var flat_mode: bool = true:
	set(v):
		if flat_mode != v:
			flat_mode = v
			if is_inside_tree():
				_apply_flat_mode()
			flat_mode_changed.emit(flat_mode)

@export var tile_library: HexTileLibrary:
	set(v):
		tile_library = v
		if is_inside_tree():
			_rebuild_all()

# Camera reference for chunk culling
@export var camera: Camera3D = null

# Chunk storage
var _chunks: Dictionary = {}
var _active_chunk_coords: Array[Vector2i] = []

# Persistent tile data for chunk regeneration
var _persistent_tiles: Dictionary = {}

# Mesh caching
var _mesh_cache: Dictionary = {}
var _scenario_rid: RID = RID()

# Chunk border debug rendering
var _chunk_border_mesh_rid: RID = RID()
var _chunk_border_inst_rid: RID = RID()
var _chunk_border_mat: StandardMaterial3D = null
var _chunk_border_dirty: bool = true

# Batch update state
var _batching: bool = false
var _pending_transforms: Dictionary = {}

# === BACKGROUND TERRAIN GENERATION ===
var noise_seed: float = 0.0
var noise_freq: float = 0.05

# Type mapping: type_index from noise → mesh_id
var type_mapping: Array[int] = [0, 1, 2, 3, 4]

# Tiles per frame budget for placing results on main thread
@export_range(64, 65536, 64) var tiles_per_frame: int = 2048

# Lookahead: generate chunks beyond visible radius for smooth movement
@export_range(0, 8, 1) var gen_lookahead: int = 2

# Background thread
var _gen_thread: Thread = null
var _gen_running: bool = false

# Thread-safe work queue: chunks the bg thread should generate
var _gen_work_mutex: Mutex = Mutex.new()
var _gen_work: Array[Vector2i] = []
var _gen_work_set: Dictionary = {}

# Thread-safe results queue: completed chunks ready for main thread
var _gen_result_mutex: Mutex = Mutex.new()
var _gen_results: Array[Dictionary] = []

# Track which chunks need gen (to avoid double-queueing on main thread side)
var _needs_gen: Dictionary = {}


func _ready() -> void:
	_scenario_rid = get_world_3d().scenario
	if not Engine.is_editor_hint():
		_generate_initial_tiles_sync()
		_start_gen_thread()


func _process(_delta: float) -> void:
	_update_active_chunks()
	_drain_gen_results()
	if _chunk_border_dirty:
		_update_chunk_borders()


func _exit_tree() -> void:
	_stop_gen_thread()
	_clear_all_chunks()
	if _chunk_border_inst_rid.is_valid():
		RenderingServer.free_rid(_chunk_border_inst_rid)
	if _chunk_border_mesh_rid.is_valid():
		RenderingServer.free_rid(_chunk_border_mesh_rid)
	_chunk_border_mat = null


# ============================================================================
# BACKGROUND THREAD
# ============================================================================

func _start_gen_thread() -> void:
	if _gen_running:
		return
	_gen_running = true
	_gen_thread = Thread.new()
	_gen_thread.start(_gen_thread_func)


func _stop_gen_thread() -> void:
	_gen_running = false
	if _gen_thread != null and _gen_thread.is_started():
		_gen_thread.wait_to_finish()
	_gen_thread = null


func _generate_initial_tiles_sync() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = int(noise_seed)
	noise.frequency = noise_freq
	var center := Vector2i.ZERO
	var tiles := _generate_chunk_tiles(center, noise)
	_persistent_tiles[center] = {}
	for tile in tiles:
		var type_idx: int = tile["type_index"]
		var mesh_id: int = type_mapping[clampi(type_idx, 0, type_mapping.size() - 1)]
		_persistent_tiles[center][tile["coords"]] = {
			"mesh_id": mesh_id,
			"elevation": tile["elevation"],
			"layer": 0,
			"custom_data": Vector4.ZERO,
		}
	for ring_coords in HexGridMath.cube_ring(Vector3i.ZERO, 1):
		var cc := _get_chunk_coords(ring_coords)
		if _persistent_tiles.has(cc):
			continue
		var ring_tiles := _generate_chunk_tiles(cc, noise)
		_persistent_tiles[cc] = {}
		for tile in ring_tiles:
			var type_idx: int = tile["type_index"]
			var mesh_id: int = type_mapping[clampi(type_idx, 0, type_mapping.size() - 1)]
			_persistent_tiles[cc][tile["coords"]] = {
				"mesh_id": mesh_id,
				"elevation": tile["elevation"],
				"layer": 0,
				"custom_data": Vector4.ZERO,
			}


func _gen_thread_func() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = int(noise_seed)
	noise.frequency = noise_freq

	while _gen_running:
		_gen_work_mutex.lock()
		var batch: Array[Vector2i] = []
		while not _gen_work.is_empty() and batch.size() < 8:
			var item: Vector2i = _gen_work.pop_back()
			_gen_work_set.erase(item)
			batch.append(item)
		_gen_work_mutex.unlock()

		if batch.is_empty():
			OS.delay_usec(50)
			continue

		var s := int(noise_seed)
		if s != noise.seed:
			noise.seed = s
		if noise_freq != noise.frequency:
			noise.frequency = noise_freq

		_gen_result_mutex.lock()
		for item in batch:
			var tiles := _generate_chunk_tiles(item, noise)
			_gen_results.append({"chunk_coords": item, "tiles": tiles})
		_gen_result_mutex.unlock()


func _generate_chunk_tiles(chunk_coords: Vector2i, noise: FastNoiseLite) -> Array[Dictionary]:
	var q0: int = chunk_coords.x * chunk_size
	var r0: int = chunk_coords.y * chunk_size

	var tiles: Array[Dictionary] = []
	tiles.resize(chunk_size * chunk_size)
	var idx := 0

	for dq in chunk_size:
		for dr in chunk_size:
			var q: int = q0 + dq
			var r: int = r0 + dr
			var s_coord: int = -q - r

			var nval: float = noise.get_noise_2d(float(q), float(r))

			var elevation: float
			var type_idx: int
			if nval < -0.2:
				type_idx = 1
				elevation = _remap(nval, -1.0, -0.2, 0.15, 0.4)
			elif nval > 0.5:
				type_idx = 2
				elevation = _remap(nval, 0.5, 1.0, 1.8, 4.0)
			elif nval > 0.25:
				type_idx = 3
				elevation = _remap(nval, 0.25, 0.5, 1.0, 1.8)
			else:
				type_idx = 0
				elevation = _remap(nval, -0.2, 0.25, 0.6, 1.2)

			tiles[idx] = {
				"coords": Vector3i(q, r, s_coord),
				"type_index": type_idx,
				"elevation": elevation,
			}
			idx += 1

	return tiles


static func _remap(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	var t := clampf((value - in_min) / (in_max - in_min), 0.0, 1.0)
	return lerpf(out_min, out_max, t)


func _drain_gen_results() -> void:
	var budget := tiles_per_frame

	while budget > 0:
		_gen_result_mutex.lock()
		if _gen_results.is_empty():
			_gen_result_mutex.unlock()
			break
		var result: Dictionary = _gen_results.pop_front()
		_gen_result_mutex.unlock()

		var chunk_coords: Vector2i = result["chunk_coords"]
		var tiles: Array = result["tiles"]

		if not _chunks.has(chunk_coords):
			continue

		var chunk: HexChunk = _chunks[chunk_coords]
		var placed := 0

		if not chunk.can_add_tile():
			_needs_gen.erase(chunk_coords)
			continue

		for tile in tiles:
			if placed >= budget:
				_gen_result_mutex.lock()
				_gen_results.push_front({"chunk_coords": chunk_coords, "tiles": tiles.slice(placed)})
				_gen_result_mutex.unlock()
				break

			var type_idx: int = tile["type_index"]
			var mesh_id: int = type_mapping[clampi(type_idx, 0, type_mapping.size() - 1)]
			var coords: Vector3i = tile["coords"]
			var elevation: float = tile["elevation"]

			if not _persistent_tiles.has(chunk_coords):
				_persistent_tiles[chunk_coords] = {}
			_persistent_tiles[chunk_coords][coords] = {
				"mesh_id": mesh_id,
				"elevation": elevation,
				"layer": 0,
				"custom_data": Vector4.ZERO,
			}

			if not chunk.place_tile(coords, mesh_id, elevation):
				continue
			var cell := chunk.get_tile(coords)
			if cell != null:
				cell.distance_from_center = HexGridMath.cube_distance(Vector3i.ZERO, coords)
			placed += 1

		budget -= placed

	_chunk_border_dirty = true


func _place_tile_direct(chunk: HexChunk, coords: Vector3i, mesh_id: int, elevation: float) -> bool:
	if chunk.has_tile(coords):
		return false
	chunk.place_tile(coords, mesh_id, elevation)
	return true


# ============================================================================
# CHUNK MANAGEMENT
# ============================================================================

func _get_chunk_coords(hex_coords: Vector3i) -> Vector2i:
	return Vector2i(
		int(floorf(float(hex_coords.x) / float(chunk_size))),
		int(floorf(float(hex_coords.y) / float(chunk_size)))
	)


func _get_or_create_chunk(hex_coords: Vector3i) -> HexChunk:
	var chunk_coords := _get_chunk_coords(hex_coords)

	if not _chunks.has(chunk_coords):
		_chunks[chunk_coords] = _create_chunk(chunk_coords)

	return _chunks[chunk_coords]


func _update_active_chunks() -> void:
	if camera == null:
		for chunk_coords in _chunks:
			if not _active_chunk_coords.has(chunk_coords):
				_active_chunk_coords.append(chunk_coords)
		return

	var camera_pos := camera.global_transform.origin
	var camera_hex := HexGridMath.world_to_cube_flat_top(camera_pos, hex_size)
	var camera_chunk := _get_chunk_coords(camera_hex)

	var new_active: Array[Vector2i] = []

	# Visible chunks
	for x in range(-visible_chunk_radius, visible_chunk_radius + 1):
		for y in range(-visible_chunk_radius, visible_chunk_radius + 1):
			if absi(x + y) > visible_chunk_radius:
				continue
			var check_coords := Vector2i(camera_chunk.x + x, camera_chunk.y + y)
			new_active.append(check_coords)
			if not _chunks.has(check_coords):
				_chunks[check_coords] = _create_chunk(check_coords)
				chunk_loaded.emit(check_coords)

	# Lookahead chunks: queue for bg gen but don't create chunk nodes yet
	if gen_lookahead > 0:
		var look_radius := visible_chunk_radius + gen_lookahead
		for x in range(-look_radius, look_radius + 1):
			for y in range(-look_radius, look_radius + 1):
				if absi(x + y) > look_radius:
					continue
				var check_coords := Vector2i(camera_chunk.x + x, camera_chunk.y + y)
				if not new_active.has(check_coords) and not _needs_gen.has(check_coords):
					_queue_gen_work(check_coords)

	# Sort gen work by distance from camera (farthest first, thread pops from back = processes closest first)
	_gen_work_mutex.lock()
	var cam_c: Vector2i = camera_chunk
	_gen_work.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - cam_c).length_squared() > (b - cam_c).length_squared()
	)
	_gen_work_mutex.unlock()

	# Unload chunks that are no longer active
	var to_unload: Array[Vector2i] = []
	for old_coords in _active_chunk_coords:
		if not new_active.has(old_coords):
			to_unload.append(old_coords)

	for coords in to_unload:
		_unload_chunk(coords)

	_active_chunk_coords = new_active
	_chunk_border_dirty = true


func _create_chunk(chunk_coords: Vector2i) -> HexChunk:
	var chunk := HexChunk.new()
	chunk.name = "Chunk_%d_%d" % [chunk_coords.x, chunk_coords.y]
	chunk.chunk_coords = chunk_coords
	chunk.grid_manager = self
	chunk.chunk_capacity = chunk_size * chunk_size
	_chunks[chunk_coords] = chunk
	add_child(chunk)

	# Position chunk at world position of its origin tile
	var q0: int = chunk_coords.x * chunk_size
	var r0: int = chunk_coords.y * chunk_size
	var first_tile_coords := Vector3i(q0, r0, -q0 - r0)
	chunk.position = HexGridMath.cube_to_world_flat_top(first_tile_coords, hex_size)

	# Populate from persistent data if available, otherwise queue for bg gen
	if _persistent_tiles.has(chunk_coords):
		for coords in _persistent_tiles[chunk_coords]:
			var data: Dictionary = _persistent_tiles[chunk_coords][coords]
			chunk.place_tile(
				coords,
				data["mesh_id"],
				data["elevation"],
				data.get("layer", 0),
				data.get("custom_data", Vector4.ZERO),
			)
	else:
		_queue_gen_work(chunk_coords)

	return chunk


func _unload_chunk(chunk_coords: Vector2i) -> void:
	# Cancel pending generation
	_cancel_gen_work(chunk_coords)
	_needs_gen.erase(chunk_coords)

	if _chunks.has(chunk_coords):
		var chunk: HexChunk = _chunks[chunk_coords]
		chunk.clear_chunk()
		chunk.queue_free()
		_chunks.erase(chunk_coords)
		chunk_unloaded.emit(chunk_coords)


func _clear_all_chunks() -> void:
	# Clear gen queues
	_gen_work_mutex.lock()
	_gen_work.clear()
	_gen_work_set.clear()
	_gen_work_mutex.unlock()

	_gen_result_mutex.lock()
	_gen_results.clear()
	_gen_result_mutex.unlock()

	_needs_gen.clear()

	for chunk_coords in _chunks:
		var chunk: HexChunk = _chunks[chunk_coords]
		chunk.clear_chunk()
		chunk.queue_free()
	_chunks.clear()
	_active_chunk_coords.clear()
	_mesh_cache.clear()
	_persistent_tiles.clear()
	_chunk_border_dirty = true


func _queue_gen_work(chunk_coords: Vector2i) -> void:
	# Already has persistent data or already has results pending
	if _persistent_tiles.has(chunk_coords):
		return

	_needs_gen[chunk_coords] = true

	_gen_work_mutex.lock()
	if not _gen_work_set.has(chunk_coords):
		_gen_work.append(chunk_coords)
		_gen_work_set[chunk_coords] = true
	_gen_work_mutex.unlock()


func _cancel_gen_work(chunk_coords: Vector2i) -> void:
	_gen_work_mutex.lock()
	_gen_work.erase(chunk_coords)
	_gen_work_set.erase(chunk_coords)
	_gen_work_mutex.unlock()


func _update_chunk_borders() -> void:
	_chunk_border_dirty = false
	var verts: PackedVector3Array = []
	var y := 0.02
	for chunk_coords in _active_chunk_coords:
		var q0: int = chunk_coords.x * chunk_size
		var r0: int = chunk_coords.y * chunk_size
		var q1: int = (chunk_coords.x + 1) * chunk_size
		var r1: int = (chunk_coords.y + 1) * chunk_size
		var c0 := HexGridMath.cube_to_world_flat_top(Vector3i(q0, r0, -q0 - r0), hex_size)
		var c1 := HexGridMath.cube_to_world_flat_top(Vector3i(q1, r0, -q1 - r0), hex_size)
		var c2 := HexGridMath.cube_to_world_flat_top(Vector3i(q1, r1, -q1 - r1), hex_size)
		var c3 := HexGridMath.cube_to_world_flat_top(Vector3i(q0, r1, -q0 - r1), hex_size)
		c0.y = y; c1.y = y; c2.y = y; c3.y = y
		verts.append_array([c0, c1, c1, c2, c2, c3, c3, c0])

	if _chunk_border_mesh_rid.is_valid():
		RenderingServer.free_rid(_chunk_border_mesh_rid)
		_chunk_border_mesh_rid = RID()

	if verts.is_empty():
		if _chunk_border_inst_rid.is_valid():
			RenderingServer.instance_set_visible(_chunk_border_inst_rid, false)
		return

	_chunk_border_mesh_rid = RenderingServer.mesh_create()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	RenderingServer.mesh_add_surface_from_arrays(_chunk_border_mesh_rid, RenderingServer.PRIMITIVE_LINES, arrays)

	if not _chunk_border_inst_rid.is_valid():
		_chunk_border_inst_rid = RenderingServer.instance_create()
		RenderingServer.instance_set_scenario(_chunk_border_inst_rid, _scenario_rid)
		RenderingServer.instance_set_base(_chunk_border_inst_rid, _chunk_border_mesh_rid)
		_chunk_border_mat = StandardMaterial3D.new()
		_chunk_border_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.8)
		_chunk_border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_chunk_border_mat.no_depth_test = true
		RenderingServer.instance_set_surface_override_material(_chunk_border_inst_rid, 0, _chunk_border_mat.get_rid())
	else:
		RenderingServer.instance_set_base(_chunk_border_inst_rid, _chunk_border_mesh_rid)
	RenderingServer.instance_set_visible(_chunk_border_inst_rid, true)
	RenderingServer.instance_set_transform(_chunk_border_inst_rid, Transform3D.IDENTITY)


# ============================================================================
# PUBLIC API
# ============================================================================

func initialize(p_library: HexTileLibrary, p_hex_size: float = 1.0, p_flat: bool = false) -> void:
	tile_library = p_library
	hex_size = p_hex_size
	flat_mode = p_flat


# --- Tile Operations ---

func place_tile(coords: Vector3i, mesh_id: int = 0, elevation: float = 1.0, layer: int = 0, custom_data: Vector4 = Vector4.ZERO) -> bool:
	if not HexGridMath.is_valid_cube(coords):
		push_warning("HexGridManager: invalid cube coords %s (q+r+s must equal 0)" % coords)
		return false

	# Store persistent data
	var chunk_coords := _get_chunk_coords(coords)
	if not _persistent_tiles.has(chunk_coords):
		_persistent_tiles[chunk_coords] = {}
	if _persistent_tiles[chunk_coords].has(coords):
		return false
	_persistent_tiles[chunk_coords][coords] = {
		"mesh_id": mesh_id,
		"elevation": elevation,
		"layer": layer,
		"custom_data": custom_data,
	}

	# Place in active chunk
	var chunk := _get_or_create_chunk(coords)
	if chunk.has_tile(coords):
		return true
	return chunk.place_tile(coords, mesh_id, elevation, layer, custom_data)


func remove_tile(coords: Vector3i) -> bool:
	var chunk_coords := _get_chunk_coords(coords)
	if _persistent_tiles.has(chunk_coords):
		_persistent_tiles[chunk_coords].erase(coords)
		if _persistent_tiles[chunk_coords].is_empty():
			_persistent_tiles.erase(chunk_coords)
	if not _chunks.has(chunk_coords):
		return false
	return _chunks[chunk_coords].remove_tile(coords)


func has_tile(coords: Vector3i) -> bool:
	var chunk_coords := _get_chunk_coords(coords)
	if _persistent_tiles.has(chunk_coords) and _persistent_tiles[chunk_coords].has(coords):
		return true
	if _chunks.has(chunk_coords):
		return _chunks[chunk_coords].has_tile(coords)
	return false


func get_cell(coords: Vector3i) -> HexCellData:
	var chunk_coords := _get_chunk_coords(coords)
	if _chunks.has(chunk_coords):
		return _chunks[chunk_coords].get_tile(coords)
	if _persistent_tiles.has(chunk_coords) and _persistent_tiles[chunk_coords].has(coords):
		var data: Dictionary = _persistent_tiles[chunk_coords][coords]
		var cell := HexCellData.new()
		cell.coords = coords
		cell.mesh_id = data["mesh_id"]
		cell.elevation = data["elevation"]
		cell.layer = data.get("layer", 0)
		cell.custom_data = data.get("custom_data", Vector4.ZERO)
		return cell
	return null


func clear_grid() -> void:
	_clear_all_chunks()


func get_tile_count() -> int:
	var count := 0
	for chunk_coords in _persistent_tiles:
		count += _persistent_tiles[chunk_coords].size()
	return count


func get_all_cells() -> Array[HexCellData]:
	var result: Array[HexCellData] = []
	for chunk_coords in _persistent_tiles:
		for coords in _persistent_tiles[chunk_coords]:
			var data: Dictionary = _persistent_tiles[chunk_coords][coords]
			var cell := HexCellData.new()
			cell.coords = coords
			cell.mesh_id = data["mesh_id"]
			cell.elevation = data["elevation"]
			cell.layer = data.get("layer", 0)
			cell.custom_data = data.get("custom_data", Vector4.ZERO)
			result.append(cell)
	return result


func get_all_coords() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for chunk_coords in _persistent_tiles:
		for coords in _persistent_tiles[chunk_coords]:
			result.append(coords as Vector3i)
	return result


# --- Query Functions ---

func get_neighbors(coords: Vector3i) -> Array[HexCellData]:
	var result: Array[HexCellData] = []
	for n_coords in HexGridMath.cube_neighbors(coords):
		if has_tile(n_coords):
			result.append(get_cell(n_coords))
	return result


func get_tiles_in_radius(center: Vector3i, radius: int) -> Array[HexCellData]:
	var result: Array[HexCellData] = []
	for ring_coords in HexGridMath.cube_spiral(center, radius):
		if has_tile(ring_coords):
			result.append(get_cell(ring_coords))
	return result


func get_coords_in_radius(center: Vector3i, radius: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for c in HexGridMath.cube_spiral(center, radius):
		if has_tile(c):
			result.append(c)
	return result


# --- Modification Functions ---

func hide_tile(coords: Vector3i) -> void:
	var chunk_coords := _get_chunk_coords(coords)
	if _chunks.has(chunk_coords):
		var chunk: HexChunk = _chunks[chunk_coords]
		if chunk._instances.has(coords):
			chunk._set_instance_hidden(chunk._instances[coords] as RID, true)


func show_tile(coords: Vector3i) -> void:
	var chunk_coords := _get_chunk_coords(coords)
	if _chunks.has(chunk_coords):
		var chunk: HexChunk = _chunks[chunk_coords]
		if chunk._instances.has(coords):
			chunk._set_instance_hidden(chunk._instances[coords] as RID, false)


func highlight_tile(_coords: Vector3i, _active: bool) -> void:
	pass


func tint_tile(_coords: Vector3i, _color: Color) -> void:
	pass


# --- Mode Toggle ---

func set_flat_mode(flat: bool) -> void:
	flat_mode = flat


func _apply_flat_mode() -> void:
	if tile_library != null:
		tile_library.set_all_shader_parameter("flat_mode", 1.0 if flat_mode else 0.0)
	for chunk_coords in _chunks:
		if _chunks.has(chunk_coords):
			var chunk: HexChunk = _chunks[chunk_coords]
			for coords in chunk._cells:
				var cell := chunk._cells[coords] as HexCellData
				var inst_rid := chunk._instances[coords] as RID
				RenderingServer.instance_set_base(inst_rid, chunk._get_mesh_rid_for_cell(cell))
				RenderingServer.instance_set_surface_override_material(inst_rid, 0, chunk._get_material_rid_for_cell(cell))
				RenderingServer.instance_set_transform(inst_rid, chunk._make_transform(cell))


# --- Batch Operations ---

func begin_batch() -> void:
	_batching = true
	_pending_transforms.clear()


func end_batch() -> void:
	_batching = false
	_flush_batch()


func _flush_batch() -> void:
	for coords in _pending_transforms:
		var cell := _pending_transforms[coords] as HexCellData
		var chunk_coords := _get_chunk_coords(cell.coords)
		if _chunks.has(chunk_coords):
			var chunk: HexChunk = _chunks[chunk_coords]
			if chunk._instances.has(cell.coords):
				RenderingServer.instance_set_transform(
					chunk._instances[cell.coords] as RID,
					chunk._make_transform(cell)
				)
	_pending_transforms.clear()


# --- Raycasting ---

func raycast_hex(p_camera: Camera3D, mouse_position: Vector2) -> HexCellData:
	if p_camera == null:
		return null

	var ray_origin: Vector3 = p_camera.project_ray_origin(mouse_position)
	var ray_dir: Vector3 = p_camera.project_ray_normal(mouse_position)

	if absf(ray_dir.y) < 0.0001:
		return null

	var t: float = -ray_origin.y / ray_dir.y
	if t < 0.0:
		return null

	var world_point: Vector3 = ray_origin + ray_dir * t
	var cube_coords: Vector3i = HexGridMath.world_to_cube_flat_top(world_point, hex_size)

	if has_tile(cube_coords):
		return get_cell(cube_coords)

	var closest: HexCellData = null
	var closest_dist: float = INF
	for n in HexGridMath.cube_neighbors(cube_coords):
		if has_tile(n):
			var dist := HexGridMath.cube_distance(cube_coords, n)
			if float(dist) < closest_dist:
				closest_dist = float(dist)
				closest = get_cell(n)

	return closest


func raycast_hex_coords(p_camera: Camera3D, mouse_position: Vector2) -> Vector3i:
	var cell := raycast_hex(p_camera, mouse_position)
	if cell == null:
		return Vector3i.ZERO
	return cell.coords


# --- Rebuild / Cleanup ---

func _rebuild_all() -> void:
	_clear_all_chunks()


func rebuild_all() -> void:
	_rebuild_all()


# --- Utilities ---

func world_to_hex(world_pos: Vector3) -> Vector3i:
	return HexGridMath.world_to_cube_flat_top(world_pos, hex_size)


func hex_to_world(coords: Vector3i) -> Vector3:
	return HexGridMath.cube_to_world_flat_top(coords, hex_size)


func get_used_rect() -> Rect2i:
	if _persistent_tiles.is_empty():
		return Rect2i()

	var min_q: int = 999999
	var max_q: int = -999999
	var min_r: int = 999999
	var max_r: int = -999999

	for chunk_coords in _persistent_tiles:
		for coords in _persistent_tiles[chunk_coords]:
			var c: Vector3i = coords as Vector3i
			min_q = mini(min_q, c.x)
			max_q = maxi(max_q, c.x)
			min_r = mini(min_r, c.y)
			max_r = maxi(max_r, c.y)

	return Rect2i(min_q, min_r, max_q - min_q + 1, max_r - min_r + 1)


# --- Mesh Caching ---

func _get_or_create_mesh_pair(mesh_id: int) -> Dictionary:
	if _mesh_cache.has(mesh_id):
		return _mesh_cache[mesh_id] as Dictionary

	var top_rid: RID = RID()
	var side_rid: RID = RID()

	if tile_library != null and tile_library.has_tile(mesh_id):
		top_rid = tile_library.get_top_mesh_rid(mesh_id)
		side_rid = tile_library.get_side_mesh_rid(mesh_id)

	if not top_rid.is_valid():
		top_rid = _create_and_cache_mesh("top_%d" % mesh_id, func() -> RID:
			return HexGridMesh.create_top_face(hex_size)
		)

	if not side_rid.is_valid():
		side_rid = _create_and_cache_mesh("side_%d" % mesh_id, func() -> RID:
			return HexGridMesh.create_full_prism(hex_size, prism_height)
		)

	var pair: Dictionary = {"top": top_rid, "side": side_rid}
	_mesh_cache[mesh_id] = pair
	return pair


func _create_and_cache_mesh(key: String, creator: Callable) -> RID:
	if _mesh_cache.has(key):
		var cached = _mesh_cache[key]
		if cached is RID:
			return cached as RID
	return creator.call() as RID
