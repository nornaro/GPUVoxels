extends Node3D

const HEX_SIZE: float = 1.1547
const GRID_RADIUS: int = 100

func _ready() -> void:
	var t := Time.get_ticks_msec()
	_generate()
	var elapsed := (Time.get_ticks_msec() - t) / 1000.0
	print("[Approach A] Done in %.2fs" % elapsed)


func _generate() -> void:
	var mesh := _create_hex_face_mesh()
	var positions := _generate_grid()
	var count := positions.size()

	var mm := MultiMesh.new()
	mm.mesh = mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = count

	for i in count:
		var pos: Vector3 = positions[i]
		var t := Transform3D(Basis.IDENTITY, pos)
		mm.set_instance_transform(i, t)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/hex_prism.gdshader")
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	print("[Approach A] %d hex prisms" % count)


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


func _generate_grid() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			if absi(q + r) <= GRID_RADIUS:
				var cube := Vector3i(q, r, -q - r)
				result.append(HexGridMath.cube_to_world_flat_top(cube, HEX_SIZE))
	return result
