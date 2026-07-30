extends Node3D

const HEX_SIZE: float = 1.1547
const HEX_SIZE_X15: float = 1.73205
const HEX_SIZE_SQRT3: float = 2.0
const CHUNK_HEXES: int = 32
const VIEW_CHUNKS: int = 6

var grid_radius: int = 100
var _hex_mesh: ArrayMesh
var _shared_mat: ShaderMaterial
var _chunks := {}
var _last_cam_chunk := Vector2i(999999, 999999)
var _chunk_queue: Array[Vector2i] = []
const CHUNKS_PER_FRAME: int = 1

func _ready() -> void:
	grid_radius = get_meta("grid_radius", 100)
	_hex_mesh = _create_hex_face_mesh()
	_shared_mat = ShaderMaterial.new()
	_shared_mat.shader = load("res://shaders/hex_prism.gdshader")
	var cam := get_viewport().get_camera_3d()
	if cam:
		var qf := cam.global_position.x / HEX_SIZE_X15
		var rf := cam.global_position.z / HEX_SIZE_SQRT3 - qf * 0.5
		var cq := floori(qf / CHUNK_HEXES)
		var cr := floori(rf / CHUNK_HEXES)
		_update_chunks(Vector2i(cq, cr), true)
	else:
		_update_chunks(Vector2i(999999, 999999), true)
	var t := Time.get_ticks_msec()
	var cells_dict: Dictionary = get_parent().get("cells") if get_parent() else {}
	var cm = get_parent().get("chunk_manager") if get_parent() else null
	for key in _chunk_queue:
		var q_lo := maxi(key.x * CHUNK_HEXES, -grid_radius)
		var q_hi := mini(q_lo + CHUNK_HEXES - 1, grid_radius)
		if key.x * CHUNK_HEXES < -grid_radius:
			q_lo = -grid_radius
			q_hi = mini(q_lo + CHUNK_HEXES - 1, grid_radius)
		var r_min_global := maxi(-grid_radius, key.y * CHUNK_HEXES)
		var r_max_global := mini(grid_radius, key.y * CHUNK_HEXES + CHUNK_HEXES - 1)
		_batch_generate_cells(q_lo, q_hi, r_min_global, r_max_global, cells_dict, cm)
	var elapsed := (Time.get_ticks_msec() - t) / 1000.0
	print("[Approach A] Queued %d chunks, pre-generated cells in %.2fs" % [_chunk_queue.size(), elapsed])


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var qf := cam.global_position.x / HEX_SIZE_X15
	var rf := cam.global_position.z / HEX_SIZE_SQRT3 - qf * 0.5
	var cq := floori(qf / CHUNK_HEXES)
	var cr := floori(rf / CHUNK_HEXES)
	var cc := Vector2i(cq, cr)
	if cc != _last_cam_chunk:
		_last_cam_chunk = cc
		_update_chunks(cc, false)
	for _i in CHUNKS_PER_FRAME:
		if _chunk_queue.is_empty():
			break
		_generate_chunk(_chunk_queue.pop_front())


func rebuild_chunk_for_hex(hex: Vector3i) -> void:
	var cq := floori(float(hex.x) / CHUNK_HEXES)
	var cr := floori(float(hex.y) / CHUNK_HEXES)
	var key := Vector2i(cq, cr)
	if key in _chunks:
		_chunks[key].queue_free()
		_chunks.erase(key)
	_generate_chunk(key)


func _update_chunks(cam_chunk: Vector2i, initial: bool) -> void:
	var needed := {}
	for dq in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
		for dr in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
			var key := Vector2i(cam_chunk.x + dq, cam_chunk.y + dr)
			if _chunk_has_hexes(key):
				needed[key] = true
				if key not in _chunks and key not in _chunk_queue:
					_chunk_queue.append(key)
	_chunk_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - cam_chunk).length_squared() < (b - cam_chunk).length_squared()
	)

	var to_remove: Array[Vector2i] = []
	for key in _chunks:
		if key not in needed:
			to_remove.append(key)
	for key in to_remove:
		_chunks[key].queue_free()
		_chunks.erase(key)

	if initial:
		print("[Approach A] %d chunks queued, %d total instances" % [_chunk_queue.size(), _count_instances()])


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


func _count_instances() -> int:
	var total := 0
	for key in _chunks:
		total += _chunks[key].multimesh.instance_count
	return total


func _batch_generate_cells(q_lo: int, q_hi: int, r_lo: int, r_max: int, cells: Dictionary, chunk_mgr) -> void:
	if not chunk_mgr or not chunk_mgr.is_initialized():
		return
	var cm: ChunkManager = chunk_mgr
	var seen: Dictionary = {}
	var batch: Array = []
	for q in range(q_lo, q_hi + 1):
		for ri in range(r_lo, r_max + 1):
			var hex := Vector3i(q, ri, -q - ri)
			if not cells.has(hex):
				var ck := Vector2i(floori(float(q) / cm.CHUNK_SIZE), floori(float(ri) / cm.CHUNK_SIZE))
				if not seen.has(ck):
					seen[ck] = true
					batch.append(ck)
	if not batch.is_empty():
		cm.generate_batch(batch)


func _generate_chunk(key: Vector2i) -> void:
	var q_lo := maxi(key.x * CHUNK_HEXES, -grid_radius)
	var q_hi := mini(q_lo + CHUNK_HEXES - 1, grid_radius)
	if key.x * CHUNK_HEXES < -grid_radius:
		q_lo = -grid_radius
		q_hi = mini(q_lo + CHUNK_HEXES - 1, grid_radius)

	var cells: Dictionary = get_parent().get("cells") if get_parent() else {}
	var chunk_mgr = get_parent().get("chunk_manager") if get_parent() else null

	var r_min_global := maxi(-grid_radius, key.y * CHUNK_HEXES)
	var r_max_global := mini(grid_radius, key.y * CHUNK_HEXES + CHUNK_HEXES - 1)
	_batch_generate_cells(q_lo, q_hi, r_min_global, r_max_global, cells, chunk_mgr)

	var transforms: Array[Transform3D] = []
	var custom_data: Array[Color] = []
	for q in range(q_lo, q_hi + 1):
		var qf := float(q)
		var x := HEX_SIZE_X15 * qf
		var z_off := HEX_SIZE_SQRT3 * qf * 0.5
		var r_min := maxi(maxi(-grid_radius, -q - grid_radius), key.y * CHUNK_HEXES)
		var r_max := mini(mini(grid_radius, -q + grid_radius), key.y * CHUNK_HEXES + CHUNK_HEXES - 1)
		for ri in range(r_min, r_max + 1):
			var cz := HEX_SIZE_SQRT3 * float(ri) + z_off
			var hex := Vector3i(q, ri, -q - ri)
			var elevation := 0.0
			var biome := 0
			if cells.has(hex):
				var cell: HexCellData = cells[hex]
				elevation = cell.elevation
				biome = cell.biome
			elif chunk_mgr and chunk_mgr.is_initialized():
				var cell: HexCellData = chunk_mgr.get_or_create_cell(hex)
				if cell:
					elevation = cell.elevation
					biome = cell.biome
			var e_norm := clampf(elevation, 0.0, 1.0)
			var biome_norm := float(biome) / 10.0
			transforms.append(Transform3D(Transform3D.IDENTITY.basis, Vector3(x, 0.0, cz)))
			custom_data.append(Color(e_norm, biome_norm, 0.0, 1.0))

	if transforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.mesh = _hex_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_custom_data(i, custom_data[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _shared_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	_chunks[key] = mmi


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
