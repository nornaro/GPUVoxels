extends Node3D

const HEX_SIZE: float = 1.1547
const HEX_SIZE_X15: float = 1.73205
const HEX_SIZE_SQRT3: float = 2.0
const CHUNK_HEXES: int = 32
const VIEW_CHUNKS: int = 4

var grid_radius: int = 100
var _shared_mat: ShaderMaterial
var _corners_x: PackedFloat64Array
var _corners_z: PackedFloat64Array
var _chunks := {}
var _last_cam_chunk := Vector2i(999999, 999999)

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
	var t := Time.get_ticks_msec()
	_update_chunks(Vector2i(999999, 999999), true)
	var elapsed := (Time.get_ticks_msec() - t) / 1000.0
	print("[Approach B] Done in %.2fs" % elapsed)


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
		print("[Approach B] %d chunks" % _chunks.size())


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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_up := Vector3(0, 1, 0)
	var q_lo := maxi(key.x * CHUNK_HEXES, -grid_radius)
	var q_hi := mini(q_lo + CHUNK_HEXES - 1, grid_radius)
	if key.x * CHUNK_HEXES < -grid_radius:
		q_lo = -grid_radius
		q_hi = mini(q_lo + CHUNK_HEXES - 1, grid_radius)

	for q in range(q_lo, q_hi + 1):
		var qf := float(q)
		var cx := HEX_SIZE_X15 * qf
		var z_off := HEX_SIZE_SQRT3 * qf * 0.5
		var r_min := maxi(maxi(-grid_radius, -q - grid_radius), key.y * CHUNK_HEXES)
		var r_max := mini(mini(grid_radius, -q + grid_radius), key.y * CHUNK_HEXES + CHUNK_HEXES - 1)
		for ri in range(r_min, r_max + 1):
			var cz := HEX_SIZE_SQRT3 * float(ri) + z_off
			for i in 6:
				var next := (i + 1) % 6
				st.set_normal(n_up)
				st.add_vertex(Vector3(cx, 0.0, cz))
				st.set_normal(n_up)
				st.add_vertex(Vector3(cx + _corners_x[next], 0.0, cz + _corners_z[next]))
				st.set_normal(n_up)
				st.add_vertex(Vector3(cx + _corners_x[i], 0.0, cz + _corners_z[i]))

	st.generate_normals()
	var mesh := st.commit()
	var mmi := MeshInstance3D.new()
	mmi.mesh = mesh
	mmi.material_override = _shared_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	_chunks[key] = mmi
