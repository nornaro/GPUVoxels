extends Node3D

const HEX_SIZE: float = 1.1547
const HEX_SIZE_X15: float = 1.73205
const HEX_SIZE_SQRT3: float = 2.0
const CHUNK_HEXES: int = 32
const VIEW_CHUNKS: int = 4
const WATER_LEVEL: float = 0.3

var grid_radius: int = 100
var cells: Dictionary = {}
var _hex_mesh: ArrayMesh
var _shared_mat: StandardMaterial3D
var _chunks := {}
var _last_cam_chunk := Vector2i(999999, 999999)

var chunk_manager: ChunkManager

func _ready() -> void:
	grid_radius = get_meta("grid_radius", 100)
	cells = get_meta("cells", {})
	chunk_manager = get_meta("chunk_manager", null)
	_hex_mesh = _create_hex_face_mesh()
	_shared_mat = StandardMaterial3D.new()
	_shared_mat.vertex_color_use_as_albedo = true
	_shared_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_generate_initial_cells()
	var t := Time.get_ticks_msec()
	_update_chunks(Vector2i(999999, 999999), true)
	var elapsed := (Time.get_ticks_msec() - t) / 1000.0
	print("[Approach A] Done in %.2fs" % elapsed)


func _generate_initial_cells() -> void:
	if not chunk_manager or not chunk_manager.is_initialized():
		return
	var cam := get_viewport().get_camera_3d()
	var center_hex := Vector3i.ZERO
	if cam:
		center_hex = HexGridMath.world_to_cube_flat_top(cam.global_position, HEX_SIZE)
	var chunk_radius := mini(VIEW_CHUNKS + 1, 6)
	var batch: Array[Vector2i] = []
	for dq in range(-chunk_radius, chunk_radius + 1):
		for dr in range(-chunk_radius, chunk_radius + 1):
			var ck := Vector2i(center_hex.x / 10 + dq, center_hex.y / 10 + dr)
			if not chunk_manager._loaded_chunk_origins.has(ck):
				batch.append(ck)
	if not batch.is_empty():
		chunk_manager.generate_batch(batch)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var cq := floori(cam.global_position.x / (HEX_SIZE_X15 * CHUNK_HEXES))
	var cr := floori(cam.global_position.z / (HEX_SIZE_SQRT3 * CHUNK_HEXES))
	var cc := Vector2i(cq, cr)
	if cc != _last_cam_chunk:
		_last_cam_chunk = cc
		_update_chunks(cc, false)


func _update_chunks(cam_chunk: Vector2i, initial: bool) -> void:
	var needed := {}
	for dq in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
		for dr in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
			var key := Vector2i(cam_chunk.x + dq, cam_chunk.y + dr)
			if _chunk_has_hexes(key):
				needed[key] = true
				if key not in _chunks:
					_generate_chunk(key)

	var to_remove: Array[Vector2i] = []
	for key in _chunks:
		if key not in needed:
			to_remove.append(key)
	for key in to_remove:
		_chunks[key].queue_free()
		_chunks.erase(key)

	if initial:
		print("[Approach A] %d chunks" % _chunks.size())


func rebuild_chunk(chunk_key: Vector2i) -> void:
	if chunk_key in _chunks:
		_chunks[chunk_key].queue_free()
		_chunks.erase(chunk_key)
	_generate_chunk(chunk_key)


func rebuild_all_chunks() -> void:
	var keys: Array[Vector2i] = []
	for key in _chunks:
		keys.append(key)
	for key in keys:
		_chunks[key].queue_free()
		_chunks.erase(key)
	_last_cam_chunk = Vector2i(999999, 999999)


func _chunk_has_hexes(key: Vector2i) -> bool:
	var q_lo := key.x * CHUNK_HEXES
	var q_hi := q_lo + CHUNK_HEXES - 1
	var r_lo := key.y * CHUNK_HEXES
	var r_hi := r_lo + CHUNK_HEXES - 1
	for q in [q_lo, q_hi]:
		for r in [r_lo, r_hi]:
			if q + r >= -grid_radius and q + r <= grid_radius and q >= -grid_radius and q <= grid_radius and r >= -grid_radius and r <= grid_radius:
				return true
	return false


func _generate_chunk(key: Vector2i) -> void:
	var q_lo := maxi(key.x * CHUNK_HEXES, -grid_radius)
	var q_hi := mini(q_lo + CHUNK_HEXES - 1, grid_radius)
	if key.x * CHUNK_HEXES < -grid_radius:
		q_lo = -grid_radius
		q_hi = mini(q_lo + CHUNK_HEXES - 1, grid_radius)

	var hex_data: Array = []
	for q in range(q_lo, q_hi + 1):
		var qf := float(q)
		var x := HEX_SIZE_X15 * qf
		var z_off := HEX_SIZE_SQRT3 * qf * 0.5
		var r_min := maxi(maxi(-grid_radius, -q - grid_radius), key.y * CHUNK_HEXES)
		var r_max := mini(mini(grid_radius, -q + grid_radius), key.y * CHUNK_HEXES + CHUNK_HEXES - 1)
		for ri in range(r_min, r_max + 1):
			var hex := Vector3i(q, ri, -q - ri)
			var cell: HexCellData = cells.get(hex, null)
			if cell == null:
				continue
			var height := _get_cell_height(cell)
			hex_data.append({"pos": Vector3(x, 0.0, HEX_SIZE_SQRT3 * float(ri) + z_off), "height": height, "color": cell.color})

	if hex_data.is_empty():
		return

	var mm := MultiMesh.new()
	mm.mesh = _hex_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = hex_data.size()
	for i in hex_data.size():
		var d: Dictionary = hex_data[i]
		var t := Transform3D(Basis().scaled(Vector3(HEX_SIZE, d["height"], HEX_SIZE)), d["pos"])
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, d["color"])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _shared_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	_chunks[key] = mmi


func _get_cell_height(cell: HexCellData) -> float:
	if _is_water_biome(cell.biome):
		return WATER_LEVEL
	var hex_width: float = HEX_SIZE * 1.73205080757
	var e := maxf(cell.elevation, 0.0)
	return e * hex_width + HEX_SIZE


func _is_water_biome(biome: int) -> bool:
	return biome == 0 or biome == 1


func _create_hex_face_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector3] = []
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i))
		corners.append(Vector3(cos(angle) * HEX_SIZE, 0.0, sin(angle) * HEX_SIZE))
	var n_up := Vector3(0, 1, 0)
	for i in 6:
		var next := (i + 1) % 6
		st.set_normal(n_up)
		st.add_vertex(Vector3(0, 0, 0))
		st.set_normal(n_up)
		st.add_vertex(corners[next])
		st.set_normal(n_up)
		st.add_vertex(corners[i])
	return st.commit()
