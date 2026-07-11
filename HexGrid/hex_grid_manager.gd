@tool
class_name HexGridManager
extends Node3D

signal flat_mode_changed(flat: bool)
signal chunk_loaded(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)

# Chunk configuration - each chunk holds up to chunk_size x chunk_size tiles
@export_range(8, 256, 8) var chunk_size: int = 32:
	set(v):
		chunk_size = clampi(v, 8, 256)
		if is_inside_tree() and Engine.is_editor_hint():
			_rebuild_all()

@export_range(1, 16, 1) var visible_chunk_radius: int = 3:
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

# Persistent tile data for chunk regeneration
# Vector2i (chunk_coords) -> Dictionary { Vector3i (tile_coords) -> {mesh_id, elevation, layer, custom_data} }
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

# Lazy generation callback: called with chunk_coords when a chunk has no persistent data.
# The callback should generate terrain and call place_tile() for each cell in the chunk.
var chunk_generate_callback: Callable = Callable()

# Per-frame generation budget
@export_range(1, 16, 1) var chunks_per_frame: int = 4
var _gen_queue: Array[Vector2i] = []
var _gen_queue_set: Dictionary = {}  # O(1) dedup


func _ready() -> void:
	_scenario_rid = get_world_3d().scenario


func _process(_delta: float) -> void:
	_update_active_chunks()
	_drain_gen_queue()
	if _chunk_border_dirty:
		_update_chunk_borders()


func _drain_gen_queue() -> void:
	if _gen_queue.is_empty() or not chunk_generate_callback.is_valid():
		return
	var budget := chunks_per_frame
	while budget > 0 and not _gen_queue.is_empty():
		var coords: Vector2i = _gen_queue.pop_back()
		_gen_queue_set.erase(coords)
		chunk_generate_callback.call(coords)
		budget -= 1
	if not _gen_queue.is_empty():
		_chunk_border_dirty = true


func _exit_tree() -> void:
	_clear_all_chunks()
	if _chunk_border_inst_rid.is_valid():
		RenderingServer.free_rid(_chunk_border_inst_rid)
	if _chunk_border_mesh_rid.is_valid():
		RenderingServer.free_rid(_chunk_border_mesh_rid)
	_chunk_border_mat = null


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

	for x in range(-visible_chunk_radius, visible_chunk_radius + 1):
		for y in range(-visible_chunk_radius, visible_chunk_radius + 1):
			# Hex distance filter: only load chunks in a hex shape
			if absi(x + y) > visible_chunk_radius:
				continue
			var check_coords := Vector2i(camera_chunk.x + x, camera_chunk.y + y)
			new_active.append(check_coords)
			if not _chunks.has(check_coords):
				_chunks[check_coords] = _create_chunk(check_coords)
				chunk_loaded.emit(check_coords)

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
	_chunks[chunk_coords] = chunk
	add_child(chunk)

	# Position chunk at world position of its origin tile
	var q0: int = chunk_coords.x * chunk_size
	var r0: int = chunk_coords.y * chunk_size
	var first_tile_coords := Vector3i(q0, r0, -q0 - r0)
	chunk.position = HexGridMath.cube_to_world_flat_top(first_tile_coords, hex_size)

	# Populate: either from persistent data, or generate lazily via callback
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
	elif chunk_generate_callback.is_valid() and not _gen_queue_set.has(chunk_coords):
		_gen_queue.append(chunk_coords)
		_gen_queue_set[chunk_coords] = true

	return chunk


func _unload_chunk(chunk_coords: Vector2i) -> void:
	if _chunks.has(chunk_coords):
		var chunk: HexChunk = _chunks[chunk_coords]
		chunk.clear_chunk()
		chunk.queue_free()
		_chunks.erase(chunk_coords)
		chunk_unloaded.emit(chunk_coords)


func _clear_all_chunks() -> void:
	for chunk_coords in _chunks:
		var chunk: HexChunk = _chunks[chunk_coords]
		chunk.clear_chunk()
		chunk.queue_free()
	_chunks.clear()
	_active_chunk_coords.clear()
	_mesh_cache.clear()
	_persistent_tiles.clear()
	_gen_queue.clear()
	_gen_queue_set.clear()
	_chunk_border_dirty = true
	_chunk_border_dirty = true


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

	# Rebuild mesh
	if _chunk_border_mesh_rid.is_valid():
		RenderingServer.free_rid(_chunk_border_mesh_rid)
		_chunk_border_mesh_rid = RID()

	# Hide instance if no verts
	if verts.is_empty():
		if _chunk_border_inst_rid.is_valid():
			RenderingServer.instance_set_visible(_chunk_border_inst_rid, false)
		return

	_chunk_border_mesh_rid = RenderingServer.mesh_create()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	RenderingServer.mesh_add_surface_from_arrays(_chunk_border_mesh_rid, RenderingServer.PRIMITIVE_LINES, arrays)

	# Create instance on first use
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
		return false  # Already placed
	_persistent_tiles[chunk_coords][coords] = {
		"mesh_id": mesh_id,
		"elevation": elevation,
		"layer": layer,
		"custom_data": custom_data,
	}

	# Place in active chunk (creates chunk if needed, which auto-populates)
	var chunk := _get_or_create_chunk(coords)
	if chunk.has_tile(coords):
		return true  # Already placed by chunk auto-populate on creation
	return chunk.place_tile(coords, mesh_id, elevation, layer, custom_data)


func remove_tile(coords: Vector3i) -> bool:
	var chunk_coords := _get_chunk_coords(coords)
	# Remove from persistent data
	if _persistent_tiles.has(chunk_coords):
		_persistent_tiles[chunk_coords].erase(coords)
		if _persistent_tiles[chunk_coords].is_empty():
			_persistent_tiles.erase(chunk_coords)
	# Remove from active chunk
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
	# Reconstruct from persistent data if chunk not loaded
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
