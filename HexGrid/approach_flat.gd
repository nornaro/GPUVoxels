extends Node3D

const HEX_SIZE: float = 1.1547
const GRID_RADIUS: int = 100

func _ready() -> void:
	var t := Time.get_ticks_msec()
	_generate()
	var elapsed := (Time.get_ticks_msec() - t) / 1000.0
	print("[Approach B] Done in %.2fs" % elapsed)


func _generate() -> void:
	var mesh := _create_hex_grid_mesh()
	var mmi := MeshInstance3D.new()
	mmi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/hex_flat.gdshader")
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	print("[Approach B] Flat hex grid mesh")


func _create_hex_grid_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var corners_x: PackedFloat32Array = PackedFloat32Array()
	var corners_z: PackedFloat32Array = PackedFloat32Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i))
		corners_x.append(cos(angle) * HEX_SIZE)
		corners_z.append(sin(angle) * HEX_SIZE)

	var n_up := Vector3(0, 1, 0)

	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			if absi(q + r) <= GRID_RADIUS:
				var cube := Vector3i(q, r, -q - r)
				var center := HexGridMath.cube_to_world_flat_top(cube, HEX_SIZE)
				_add_hex(st, center.x, center.z, corners_x, corners_z, n_up)

	st.generate_normals()
	return st.commit()


func _add_hex(st: SurfaceTool, cx: float, cz: float,
		corners_x: PackedFloat32Array, corners_z: PackedFloat32Array,
		n_up: Vector3) -> void:
	for i in 6:
		var next := (i + 1) % 6
		st.set_normal(n_up)
		st.add_vertex(Vector3(cx, 0.0, cz))
		st.set_normal(n_up)
		st.add_vertex(Vector3(cx + corners_x[next], 0.0, cz + corners_z[next]))
		st.set_normal(n_up)
		st.add_vertex(Vector3(cx + corners_x[i], 0.0, cz + corners_z[i]))
