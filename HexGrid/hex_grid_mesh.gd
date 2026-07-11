class_name HexGridMesh
extends RefCounted


static func create_top_face(hex_size: float) -> RID:
	var mesh_rid := RenderingServer.mesh_create()
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []

	vertices.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))

	for i in 6:
		var angle_deg := 60.0 * float(i)
		var angle_rad := deg_to_rad(angle_deg)
		var vx := hex_size * cos(angle_rad)
		var vz := hex_size * sin(angle_rad)
		vertices.append(Vector3(vx, 0.0, vz))
		normals.append(Vector3.UP)
		uvs.append(Vector2(
			0.5 + 0.5 * cos(angle_rad),
			0.5 + 0.5 * sin(angle_rad),
		))

	for i in 6:
		indices.append(0)
		indices.append(i + 1)
		indices.append((i + 1) % 6 + 1)

	_upload_mesh(mesh_rid, vertices, normals, uvs, indices)
	return mesh_rid


static func create_prism(hex_size: float, prism_height: float) -> RID:
	var mesh_rid := RenderingServer.mesh_create()
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []

	var top_verts: Array[Vector3] = []
	var bot_verts: Array[Vector3] = []
	for i in 6:
		var angle_deg := 60.0 * float(i)
		var angle_rad := deg_to_rad(angle_deg)
		var vx := hex_size * cos(angle_rad)
		var vz := hex_size * sin(angle_rad)
		top_verts.append(Vector3(vx, prism_height, vz))
		bot_verts.append(Vector3(vx, 0.0, vz))

	var center_top := Vector3(0.0, prism_height, 0.0)
	var center_bot := Vector3.ZERO
	var idx := 0

	vertices.append(center_top)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 1.0))
	idx += 1

	for i in 6:
		var angle_rad := deg_to_rad(60.0 * float(i))
		vertices.append(top_verts[i])
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.5 + 0.5 * cos(angle_rad), 1.0))
		idx += 1

	for i in 6:
		indices.append(0)
		indices.append(i + 1)
		indices.append((i + 1) % 6 + 1)

	var top_row_start := idx
	for i in 6:
		var normal := Vector3(cos(deg_to_rad(60.0 * float(i))), 0.0, sin(deg_to_rad(60.0 * float(i)))).normalized()
		vertices.append(top_verts[i])
		normals.append(normal)
		uvs.append(Vector2(float(i) / 6.0, 1.0))
		idx += 1

	for i in 6:
		var normal := Vector3(cos(deg_to_rad(60.0 * float(i))), 0.0, sin(deg_to_rad(60.0 * float(i)))).normalized()
		vertices.append(bot_verts[i])
		normals.append(normal)
		uvs.append(Vector2(float(i) / 6.0, 0.0))
		idx += 1

	for i in 6:
		var tl := top_row_start + i
		var tr := top_row_start + (i + 1) % 6
		var bl := top_row_start + 6 + i
		var br := top_row_start + 6 + (i + 1) % 6
		indices.append(tl)
		indices.append(bl)
		indices.append(tr)
		indices.append(tr)
		indices.append(bl)
		indices.append(br)

	_upload_mesh(mesh_rid, vertices, normals, uvs, indices)
	return mesh_rid


static func create_bottom_face(hex_size: float, prism_height: float) -> RID:
	var mesh_rid := RenderingServer.mesh_create()
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []

	vertices.append(Vector3(0.0, prism_height, 0.0))
	normals.append(Vector3.DOWN)
	uvs.append(Vector2(0.5, 0.5))

	for i in 6:
		var angle_deg := 60.0 * float(i)
		var angle_rad := deg_to_rad(angle_deg)
		vertices.append(Vector3(
			hex_size * cos(angle_rad),
			prism_height,
			hex_size * sin(angle_rad),
		))
		normals.append(Vector3.DOWN)
		uvs.append(Vector2(
			0.5 + 0.5 * cos(angle_rad),
			0.5 + 0.5 * sin(angle_rad),
		))

	for i in 6:
		indices.append(0)
		indices.append((i + 1) % 6 + 1)
		indices.append(i + 1)

	_upload_mesh(mesh_rid, vertices, normals, uvs, indices)
	return mesh_rid


static func create_side_faces(hex_size: float, prism_height: float) -> RID:
	var mesh_rid := RenderingServer.mesh_create()
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []
	var idx := 0

	for i in 6:
		var angle_a := deg_to_rad(60.0 * float(i))
		var angle_b := deg_to_rad(60.0 * float((i + 1) % 6))

		var ax := hex_size * cos(angle_a)
		var az := hex_size * sin(angle_a)
		var bx := hex_size * cos(angle_b)
		var bz := hex_size * sin(angle_b)

		var edge_center := Vector3((ax + bx) * 0.5, prism_height * 0.5, (az + bz) * 0.5)
		var normal := edge_center.normalized()

		vertices.append(Vector3(ax, prism_height, az))
		normals.append(normal)
		uvs.append(Vector2(float(i) / 6.0, 1.0))

		vertices.append(Vector3(bx, prism_height, bz))
		normals.append(normal)
		uvs.append(Vector2(float(i + 1) / 6.0, 1.0))

		vertices.append(Vector3(ax, 0.0, az))
		normals.append(normal)
		uvs.append(Vector2(float(i) / 6.0, 0.0))

		vertices.append(Vector3(bx, 0.0, bz))
		normals.append(normal)
		uvs.append(Vector2(float(i + 1) / 6.0, 0.0))

		indices.append(idx + 0)
		indices.append(idx + 2)
		indices.append(idx + 1)
		indices.append(idx + 1)
		indices.append(idx + 2)
		indices.append(idx + 3)
		idx += 4

	_upload_mesh(mesh_rid, vertices, normals, uvs, indices)
	return mesh_rid


static func create_full_prism(hex_size: float, prism_height: float) -> RID:
	var mesh_rid := RenderingServer.mesh_create()
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []
	var idx := 0

	var top_center := Vector3(0.0, prism_height, 0.0)
	vertices.append(top_center)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 1.0))
	idx += 1

	var top_ring_start := idx
	for i in 6:
		var angle_rad := deg_to_rad(60.0 * float(i))
		vertices.append(Vector3(hex_size * cos(angle_rad), prism_height, hex_size * sin(angle_rad)))
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.5 + 0.5 * cos(angle_rad), 1.0))
		idx += 1

	for i in 6:
		indices.append(0)
		indices.append(top_ring_start + i)
		indices.append(top_ring_start + (i + 1) % 6)

	var side_top_start := idx
	for i in 6:
		var angle_rad := deg_to_rad(60.0 * float(i))
		var normal := Vector3(cos(angle_rad), 0.0, sin(angle_rad))
		vertices.append(Vector3(hex_size * cos(angle_rad), prism_height, hex_size * sin(angle_rad)))
		normals.append(normal)
		uvs.append(Vector2(float(i) / 6.0, 1.0))
		idx += 1

	for i in 6:
		var angle_rad := deg_to_rad(60.0 * float(i))
		var normal := Vector3(cos(angle_rad), 0.0, sin(angle_rad))
		vertices.append(Vector3(hex_size * cos(angle_rad), 0.0, hex_size * sin(angle_rad)))
		normals.append(normal)
		uvs.append(Vector2(float(i) / 6.0, 0.0))
		idx += 1

	for i in 6:
		var tl := side_top_start + i
		var tr := side_top_start + (i + 1) % 6
		var bl := side_top_start + 6 + i
		var br := side_top_start + 6 + (i + 1) % 6
		indices.append(tl)
		indices.append(bl)
		indices.append(tr)
		indices.append(tr)
		indices.append(bl)
		indices.append(br)

	_upload_mesh(mesh_rid, vertices, normals, uvs, indices)
	return mesh_rid


static func _upload_mesh(
	mesh_rid: RID,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	RenderingServer.mesh_add_surface_from_arrays(mesh_rid, RenderingServer.PRIMITIVE_TRIANGLES, arrays)
