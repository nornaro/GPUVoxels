@tool
class_name HexChunk
extends Node3D

# Each chunk stores data for a subset of the grid

var chunk_capacity: int = 16384  # Set dynamically from grid_manager.chunk_size

# Reference to the manager
var grid_manager = null

# Chunk coordinates in the chunk grid
var chunk_coords: Vector2i = Vector2i.ZERO

# Tile storage
var _cells: Dictionary = {}
var _instances: Dictionary = {}

# Rendering resources
var _scenario_rid: RID = RID()


func _ready() -> void:
	pass


func _exit_tree() -> void:
	_free_all_instances()


# === Tile Management ===

func can_add_tile() -> bool:
	return _cells.size() < chunk_capacity


func place_tile(coords: Vector3i, mesh_id: int, elevation: float, layer: int = 0, custom_data: Vector4 = Vector4.ZERO) -> bool:
	if not can_add_tile():
		push_warning("HexChunk: Cannot add more tiles, chunk is full (%d/%d)" % [_cells.size(), chunk_capacity])
		return false

	if _cells.has(coords):
		return false

	var cell := HexCellData.new()
	cell.coords = coords
	cell.mesh_id = mesh_id
	cell.elevation = elevation
	cell.layer = layer
	cell.custom_data = custom_data

	# Get mesh for this tile type
	var mesh_rid := _get_mesh_rid_for_cell(cell)
	if not mesh_rid.is_valid():
		push_error("HexChunk: Invalid mesh RID for mesh_id %d" % mesh_id)
		return false

	# Get material for this tile type
	var mat_rid := _get_material_rid_for_cell(cell)

	# Create instance
	var inst_rid: RID = RenderingServer.instance_create()
	RenderingServer.instance_set_scenario(inst_rid, _get_scenario_rid())
	RenderingServer.instance_set_base(inst_rid, mesh_rid)
	RenderingServer.instance_set_transform(inst_rid, _make_transform(cell))

	if mat_rid.is_valid():
		RenderingServer.instance_set_surface_override_material(inst_rid, 0, mat_rid)

	# Store references
	_cells[coords] = cell
	_instances[coords] = inst_rid

	return true


func remove_tile(coords: Vector3i) -> bool:
	if not _cells.has(coords):
		return false

	var inst_rid: RID = _instances[coords] as RID
	if inst_rid.is_valid():
		RenderingServer.free_rid(inst_rid)

	_instances.erase(coords)
	_cells.erase(coords)

	return true


func get_tile(coords: Vector3i) -> HexCellData:
	if _cells.has(coords):
		return _cells[coords] as HexCellData
	return null


func has_tile(coords: Vector3i) -> bool:
	return _cells.has(coords)


func clear_chunk() -> void:
	_free_all_instances()
	_cells.clear()
	_instances.clear()


# === Helpers ===

func _get_scenario_rid() -> RID:
	if _scenario_rid.is_valid():
		return _scenario_rid
	if is_inside_tree():
		_scenario_rid = get_world_3d().scenario
	return _scenario_rid


func _get_mesh_rid_for_cell(cell: HexCellData) -> RID:
	if grid_manager == null or grid_manager.tile_library == null:
		return RID()
	var library = grid_manager.tile_library
	if not library.has_tile(cell.mesh_id):
		return RID()
	if grid_manager.flat_mode:
		return library.get_top_mesh_rid(cell.mesh_id)
	else:
		return library.get_side_mesh_rid(cell.mesh_id)


func _get_material_rid_for_cell(cell: HexCellData) -> RID:
	if grid_manager != null and grid_manager.tile_library != null:
		var library = grid_manager.tile_library
		if library.has_tile(cell.mesh_id):
			return library.get_material_rid(cell.mesh_id)
	return RID()


func _make_transform(cell: HexCellData) -> Transform3D:
	var actual_hex_size: float = 1.0
	var actual_flat_mode: bool = false

	if grid_manager != null:
		actual_hex_size = grid_manager.hex_size
		actual_flat_mode = grid_manager.flat_mode

	var abs_pos: Vector3 = HexGridMath.cube_to_world_flat_top(cell.coords, actual_hex_size)

	if actual_flat_mode:
		abs_pos.y = 0.0
		return Transform3D(
			Basis(Vector3(actual_hex_size, 0, 0), Vector3(0, 1.0, 0), Vector3(0, 0, actual_hex_size)),
			abs_pos
		)

	var voxel_h := floorf(cell.elevation)
	return Transform3D(
		Basis(Vector3(actual_hex_size, 0, 0), Vector3(0, voxel_h, 0), Vector3(0, 0, actual_hex_size)),
		abs_pos
	)


func _free_all_instances() -> void:
	for coords in _instances:
		var rid: RID = _instances[coords] as RID
		if rid.is_valid():
			RenderingServer.free_rid(rid)
	_instances.clear()


func _set_instance_hidden(rid: RID, hidden: bool) -> void:
	if rid.is_valid():
		RenderingServer.instance_set_visible(rid, not hidden)
