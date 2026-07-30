extends Node3D

const HEX_SIZE: float = 1.1547
const HEX_SIZE_X15: float = 1.73205
const HEX_SIZE_SQRT3: float = 2.0
const VIEW_CHUNKS: int = 13
const CUBE_DIRECTIONS: Array = [
	Vector3i(1, 0, -1), Vector3i(1, -1, 0), Vector3i(0, -1, 1),
	Vector3i(-1, 0, 1), Vector3i(-1, 1, 0), Vector3i(0, 1, -1),
]
const CORNER_NBORS: Array = [
	[0, 1], [0, 5], [5, 4], [4, 3], [3, 2], [2, 1],
]

var grid_radius: int = 100
var _shared_mat: ShaderMaterial
var _corners_x: PackedFloat64Array
var _corners_z: PackedFloat64Array
var _mesh_instance: MeshInstance3D
var _last_cam_chunk := Vector2i(999999, 999999)
var _needed_hexes: Array[Vector3i] = []


func _ready() -> void:
	grid_radius = get_meta("grid_radius", 100)
	_shared_mat = ShaderMaterial.new()
	_shared_mat.shader = load("res://shaders/hex_flat.gdshader")
	_corners_x = PackedFloat64Array()
	_corners_z = PackedFloat64Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i))
		_corners_x.append(cos(angle) * HEX_SIZE)
		_corners_z.append(sin(angle) * HEX_SIZE)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.material_override = _shared_mat
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh_instance)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var qf := cam.global_position.x / HEX_SIZE_X15
		var rf := cam.global_position.z / HEX_SIZE_SQRT3 - qf * 0.5
		_rebuild_all(Vector2i(floori(qf / 8), floori(rf / 8)))
	else:
		_rebuild_all(Vector2i(0, 0))


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var qf := cam.global_position.x / HEX_SIZE_X15
	var rf := cam.global_position.z / HEX_SIZE_SQRT3 - qf * 0.5
	var cc := Vector2i(floori(qf / 8), floori(rf / 8))
	if cc != _last_cam_chunk:
		_last_cam_chunk = cc
		_rebuild_all(cc)


func rebuild_chunk_for_hex(_hex: Vector3i) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var qf := cam.global_position.x / HEX_SIZE_X15
	var rf := cam.global_position.z / HEX_SIZE_SQRT3 - qf * 0.5
	_rebuild_all(Vector2i(floori(qf / 8), floori(rf / 8)))


func _is_valid_hex(hex: Vector3i) -> bool:
	return max(abs(hex.x), abs(hex.y), abs(hex.z)) <= grid_radius


func _rebuild_all(cam_chunk: Vector2i) -> void:
	_needed_hexes.clear()
	for dq in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
		for dr in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
			var cq := cam_chunk.x + dq
			var cr := cam_chunk.y + dr
			for q in range(cq * 8, (cq + 1) * 8):
				if q < -grid_radius or q > grid_radius:
					continue
				var r_min := maxi(maxi(-grid_radius, -q - grid_radius), cr * 8)
				var r_max := mini(mini(grid_radius, -q + grid_radius), (cr + 1) * 8 - 1)
				for ri in range(r_min, r_max + 1):
					if ri + q <= grid_radius and ri + q >= -grid_radius:
						_needed_hexes.append(Vector3i(q, ri, -q - ri))

	var cells: Dictionary = get_parent().get("cells") if get_parent() else {}
	var chunk_mgr = get_parent().get("chunk_manager") if get_parent() else null
	_batch_generate_cells(cells, chunk_mgr)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var total_hexes := _needed_hexes.size()
	for idx in total_hexes:
		var hex: Vector3i = _needed_hexes[idx]
		var q := hex.x
		var ri := hex.y
		var cx := HEX_SIZE_X15 * float(q)
		var z_off := HEX_SIZE_SQRT3 * float(q) * 0.5
		var cz := HEX_SIZE_SQRT3 * float(ri) + z_off
		var elevation := 0.0
		var biome := 0
		if cells.has(hex):
			var cell: HexCellData = cells[hex]
			elevation = cell.elevation
			biome = cell.biome
		var e_norm := clampf(elevation, 0.0, 1.0)
		var biome_norm := float(biome) / 10.0
		var center_attr := Color(e_norm, biome_norm, 0.0, 1.0)

		var corner_norms: Array[float] = []
		corner_norms.resize(6)
		for i in 6:
			var nbors = CORNER_NBORS[i] as Array
			var n1_dir = CUBE_DIRECTIONS[nbors[0]] as Vector3i
			var n2_dir = CUBE_DIRECTIONS[nbors[1]] as Vector3i
			var n1_hex := Vector3i(hex.x + n1_dir.x, hex.y + n1_dir.y, hex.z + n1_dir.z)
			var n2_hex := Vector3i(hex.x + n2_dir.x, hex.y + n2_dir.y, hex.z + n2_dir.z)
			var avg := e_norm
			var count := 1.0
			if _is_valid_hex(n1_hex) and cells.has(n1_hex):
				avg += clampf(cells[n1_hex].elevation, 0.0, 1.0)
				count += 1.0
			if _is_valid_hex(n2_hex) and cells.has(n2_hex):
				avg += clampf(cells[n2_hex].elevation, 0.0, 1.0)
				count += 1.0
			corner_norms[i] = avg / count

		for i in 6:
			var next := (i + 1) % 6
			st.set_normal(Vector3(0.0, 1.0, 0.0))
			st.set_custom(0, center_attr)
			st.add_vertex(Vector3(cx, 0.0, cz))
			st.set_normal(Vector3(0.0, 1.0, 0.0))
			st.set_custom(0, Color(corner_norms[next], biome_norm, 0.0, 1.0))
			st.add_vertex(Vector3(cx + _corners_x[next], 0.0, cz + _corners_z[next]))
			st.set_normal(Vector3(0.0, 1.0, 0.0))
			st.set_custom(0, Color(corner_norms[i], biome_norm, 0.0, 1.0))
			st.add_vertex(Vector3(cx + _corners_x[i], 0.0, cz + _corners_z[i]))

	var mesh := st.commit()
	_mesh_instance.mesh = mesh


func _batch_generate_cells(cells: Dictionary, chunk_mgr) -> void:
	if not chunk_mgr or not chunk_mgr.is_initialized():
		return
	var cm: ChunkManager = chunk_mgr
	var seen: Dictionary = {}
	var batch: Array = []
	for hex in _needed_hexes:
		if not cells.has(hex):
			var ck := Vector2i(floori(float(hex.x) / cm.CHUNK_SIZE), floori(float(hex.y) / cm.CHUNK_SIZE))
			if not seen.has(ck):
				seen[ck] = true
				batch.append(ck)
		for i in 6:
			var nbors = CORNER_NBORS[i] as Array
			var n1_dir = CUBE_DIRECTIONS[nbors[0]] as Vector3i
			var n2_dir = CUBE_DIRECTIONS[nbors[1]] as Vector3i
			var n1_hex := Vector3i(hex.x + n1_dir.x, hex.y + n1_dir.y, hex.z + n1_dir.z)
			var n2_hex := Vector3i(hex.x + n2_dir.x, hex.y + n2_dir.y, hex.z + n2_dir.z)
			if _is_valid_hex(n1_hex) and not cells.has(n1_hex):
				var ck1 := Vector2i(floori(float(n1_hex.x) / cm.CHUNK_SIZE), floori(float(n1_hex.y) / cm.CHUNK_SIZE))
				if not seen.has(ck1):
					seen[ck1] = true
					batch.append(ck1)
			if _is_valid_hex(n2_hex) and not cells.has(n2_hex):
				var ck2 := Vector2i(floori(float(n2_hex.x) / cm.CHUNK_SIZE), floori(float(n2_hex.y) / cm.CHUNK_SIZE))
				if not seen.has(ck2):
					seen[ck2] = true
					batch.append(ck2)
	if not batch.is_empty():
		cm.generate_batch(batch)
