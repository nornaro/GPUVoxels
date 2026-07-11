@tool
class_name HexGridManager
extends Node3D

signal tile_placed(coords: Vector3i)
signal tile_removed(coords: Vector3i)
signal tile_edited(coords: Vector3i)
signal flat_mode_changed(flat: bool)
signal chunk_loaded(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)

# Chunk configuration - each chunk holds up to CHUNK_SIZE x CHUNK_SIZE tiles
const CHUNK_SIZE := 128  # 128x128 = 16,384 tiles per chunk
const MAX_TILES_PER_CHUNK := CHUNK_SIZE * CHUNK_SIZE
const VISIBLE_CHUNK_RADIUS := 3  # Load chunks within 3 chunks of camera

@export var hex_size: float = 1.0:
	set(v):
		hex_size = v
		if is_inside_tree() and Engine.is_editor_hint():
			_rebuild_all()

@export var prism_height: float = 2.0
@export var flat_mode: bool = false:
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

# Chunk storage: chunk_coords (Vector2i) -> HexChunk
var _chunks: Dictionary = {}
var _active_chunk_coords: Array[Vector2i] = []

# Mesh caching
var _mesh_cache: Dictionary = {}
var _scenario_rid: RID = RID()

# Batch update state
var _batching: bool = false
var _pending_transforms: Dictionary = {}


func _ready() -> void:
	_scenario_rid = get_world_3d().scenario
	# Will be managed by chunk system


func _process(_delta: float) -> void:
	# Update active chunks based on camera position
	_update_active_chunks()


func _exit_tree() -> void:
	_clear_all_chunks()


# ============================================================================
# CHUNK MANAGEMENT
# ============================================================================

func _get_chunk_coords(hex_coords: Vector3i) -> Vector2i:
	# Use cube coordinates directly, dividing Q and R by CHUNK_SIZE
	# For cube coords (q, r, s), we use q and r as the basis for chunking
	return Vector2i(
		int(floorf(float(hex_coords.x) / float(CHUNK_SIZE))),
		int(floorf(float(hex_coords.y) / float(CHUNK_SIZE)))
	)


func _get_or_create_chunk(hex_coords: Vector3i) -> HexChunk:
	var chunk_coords := _get_chunk_coords(hex_coords)
	
	if not _chunks.has(chunk_coords):
		_chunks[chunk_coords] = _create_chunk(chunk_coords)
	
	return _chunks[chunk_coords]


func _update_active_chunks() -> void:
	if camera == null:
		# No camera - activate all existing chunks
		for chunk_coords in _chunks:
			if not _active_chunk_coords.has(chunk_coords):
				_active_chunk_coords.append(chunk_coords)
		return

	# Get camera position in hex coordinates
	var camera_pos := camera.global_transform.origin
	var camera_hex := HexGridMath.world_to_cube_flat_top(camera_pos, hex_size)
	var camera_chunk := _get_chunk_coords(camera_hex)

	# Build list of chunks that should be active
	var new_active: Array[Vector2i] = []

	for x in range(-VISIBLE_CHUNK_RADIUS, VISIBLE_CHUNK_RADIUS + 1):
		for y in range(-VISIBLE_CHUNK_RADIUS, VISIBLE_CHUNK_RADIUS + 1):
			var check_coords := Vector2i(camera_chunk.x + x, camera_chunk.y + y)
			new_active.append(check_coords)
			# Create chunk if it doesn't exist
			if not _chunks.has(check_coords):
				_chunks[check_coords] = _create_chunk(check_coords)
				chunk_loaded.emit(check_coords)

	# Unload chunks that are no longer active
	for old_coords in _active_chunk_coords:
		if not new_active.has(old_coords):
			_unload_chunk(old_coords)

	_active_chunk_coords = new_active


func _create_chunk(chunk_coords: Vector2i) -> HexChunk:
	var chunk := HexChunk.new()
	chunk.name = "Chunk_%d_%d" % [chunk_coords.x, chunk_coords.y]
	chunk.chunk_coords = chunk_coords
	chunk.grid_manager = self
	add_child(chunk)
	# Position chunk at correct world position using HexGridMath
	# The chunk's origin is at the center of the first tile in the chunk
	# First tile in chunk (0,0) is at hex coords (chunk_coords.x * CHUNK_SIZE, chunk_coords.y * CHUNK_SIZE, 0)
	var first_tile_coords := Vector3i(chunk_coords.x * CHUNK_SIZE, chunk_coords.y * CHUNK_SIZE, 0)
	chunk.position = HexGridMath.cube_to_world_flat_top(first_tile_coords, hex_size)
	return chunk


func _unload_chunk(chunk_coords: Vector2i) -> void:
	if _chunks.has(chunk_coords):
		var chunk: HexChunk = _chunks[chunk_coords]
		chunk.clear_chunk()
		chunk_unloaded.emit(chunk_coords)
		# Keep chunk in memory but clear its data
		# Optionally: chunk.queue_free(); _chunks.erase(chunk_coords)


func _clear_all_chunks() -> void:
	for chunk_coords in _chunks:
		_unload_chunk(chunk_coords)
	_chunks.clear()
	_active_chunk_coords.clear()
	_mesh_cache.clear()


func _chunk_loaded(chunk_coords: Vector2i) -> void:
	pass  # Can connect signal here


func _chunk_unloaded(chunk_coords: Vector2i) -> void:
	pass  # Can connect signal here


# ============================================================================
# PUBLIC API - Maintains backward compatibility
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

	var chunk := _get_or_create_chunk(coords)
	return chunk.place_tile(coords, mesh_id, elevation, layer, custom_data)


func remove_tile(coords: Vector3i) -> bool:
	var chunk_coords := _get_chunk_coords(coords)
	if not _chunks.has(chunk_coords):
		return false
	return _chunks[chunk_coords].remove_tile(coords)


func has_tile(coords: Vector3i) -> bool:
	var chunk_coords := _get_chunk_coords(coords)
	if not _chunks.has(chunk_coords):
		return false
	return _chunks[chunk_coords].has_tile(coords)


func get_cell(coords: Vector3i) -> HexCellData:
	var chunk_coords := _get_chunk_coords(coords)
	if not _chunks.has(chunk_coords):
		return null
	return _chunks[chunk_coords].get_tile(coords)


func clear_grid() -> void:
	_clear_all_chunks()


func get_tile_count() -> int:
	var count := 0
	for chunk_coords in _chunks:
		if _chunks.has(chunk_coords):
			count += _chunks[chunk_coords]._cells.size()
	return count


func get_all_cells() -> Array[HexCellData]:
	var result: Array[HexCellData] = []
	for chunk_coords in _chunks:
		if _chunks.has(chunk_coords):
			var chunk: HexChunk = _chunks[chunk_coords]
			for key in chunk._cells:
				result.append(chunk._cells[key] as HexCellData)
	return result


func get_all_coords() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for chunk_coords in _chunks:
		if _chunks.has(chunk_coords):
			for key in _chunks[chunk_coords]._cells:
				result.append(key as Vector3i)
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


func highlight_tile(coords: Vector3i, active: bool) -> void:
	# For now, highlighting is not implemented
	# It will be added when GPU instancing with data texture is implemented
	pass


func tint_tile(coords: Vector3i, color: Color) -> void:
	pass  # Can be implemented with material overrides


# --- Mode Toggle ---

func set_flat_mode(flat: bool) -> void:
	flat_mode = flat


func _apply_flat_mode() -> void:
	for chunk_coords in _chunks:
		if _chunks.has(chunk_coords):
			var chunk: HexChunk = _chunks[chunk_coords]
			for coords in chunk._cells:
				var cell := chunk._cells[coords] as HexCellData
				var inst_rid := chunk._instances[coords] as RID
				if flat_mode:
					RenderingServer.instance_set_base(inst_rid, chunk._get_mesh_rid_for_cell(cell))
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

func raycast_hex(camera: Camera3D, mouse_position: Vector2) -> HexCellData:
	if camera == null:
		return null

	var ray_origin: Vector3 = camera.project_ray_origin(mouse_position)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_position)

	if absf(ray_dir.y) < 0.0001:
		return null

	var t: float = -ray_origin.y / ray_dir.y
	if t < 0.0:
		return null

	var world_point: Vector3 = ray_origin + ray_dir * t
	var cube_coords: Vector3i = HexGridMath.world_to_cube_flat_top(world_point, hex_size)

	# Check direct hit
	if has_tile(cube_coords):
		return get_cell(cube_coords)

	# Check neighbors
	var closest: HexCellData = null
	var closest_dist: float = INF
	for n in HexGridMath.cube_neighbors(cube_coords):
		if has_tile(n):
			var dist := HexGridMath.cube_distance(cube_coords, n)
			if float(dist) < closest_dist:
				closest_dist = float(dist)
				closest = get_cell(n)

	return closest


func raycast_hex_coords(camera: Camera3D, mouse_position: Vector2) -> Vector3i:
	var cell := raycast_hex(camera, mouse_position)
	if cell == null:
		return Vector3i.ZERO
	return cell.coords


# --- Rebuild / Cleanup ---

func _rebuild_all() -> void:
	_clear_all_chunks()
	# Rebuild from saved data would go here


func rebuild_all() -> void:
	_rebuild_all()


# --- Utilities ---

func world_to_hex(world_pos: Vector3) -> Vector3i:
	return HexGridMath.world_to_cube_flat_top(world_pos, hex_size)


func hex_to_world(coords: Vector3i) -> Vector3:
	return HexGridMath.cube_to_world_flat_top(coords, hex_size)


func get_used_rect() -> Rect2i:
	if _chunks.is_empty():
		return Rect2i()

	var min_q: int = 999999
	var max_q: int = -999999
	var min_r: int = 999999
	var max_r: int = -999999

	for chunk_coords in _chunks:
		if _chunks.has(chunk_coords):
			var chunk: HexChunk = _chunks[chunk_coords]
			for coords in chunk._cells:
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
