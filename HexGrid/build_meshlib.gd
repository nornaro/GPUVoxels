@tool
extends EditorScript

const ASSETS_DIR := "res://assets/kaykit_medieval_hexagon_pack"
const OUTPUT_PATH := "res://HexGrid/hex_mesh_library.meshlib"

var hex_rot := Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)))


func _run() -> void:
	# Debug: test loading one mesh
	var test_path := ASSETS_DIR + "/tiles/roads/hex_road_A.tres"
	var test_mesh := load(test_path)
	print("Test load '%s': %s" % [test_path, str(test_mesh)])
	if test_mesh:
		print("  Type: %s, surfaces: %d" % [test_mesh.get_class(), test_mesh.get_surface_count()])

	# Try DirAccess scan
	var dir := DirAccess.open(ASSETS_DIR + "/tiles/roads")
	if dir == null:
		print("Cannot open roads dir")
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	var count := 0
	while fn != "":
		if fn.ends_with(".tres"):
			count += 1
			var m := load(ASSETS_DIR + "/tiles/roads/" + fn)
			print("  '%s' -> %s" % [fn, "OK" if m else "NULL"])
		fn = dir.get_next()
	dir.list_dir_end()
	print("Found %d .tres files" % count)

	# Build meshlib
	var meshlib := MeshLibrary.new()
	var idx := 0
	idx = _scan_dir(meshlib, idx, ASSETS_DIR + "/tiles/base", "tile", "")
	idx = _scan_dir(meshlib, idx, ASSETS_DIR + "/tiles/roads", "road", "")
	idx = _scan_dir(meshlib, idx, ASSETS_DIR + "/tiles/rivers", "river", "")
	idx = _scan_dir(meshlib, idx, ASSETS_DIR + "/tiles/rivers/waterless", "river", "_dry")
	idx = _scan_dir(meshlib, idx, ASSETS_DIR + "/tiles/coast", "coast", "")
	idx = _scan_dir(meshlib, idx, ASSETS_DIR + "/tiles/coast/waterless", "coast", "_dry")
	for color in ["blue", "green", "red", "yellow", "neutral"]:
		idx = _scan_dir(meshlib, idx, ASSETS_DIR + "/buildings/" + color, "building", "_" + color)
	idx = _scan_dir(meshlib, idx, ASSETS_DIR + "/decoration/nature", "nature", "")
	idx = _scan_dir(meshlib, idx, ASSETS_DIR + "/decoration/props", "prop", "")

	var err := ResourceSaver.save(meshlib, OUTPUT_PATH)
	print("Saved %d items, err=%s" % [idx, error_string(err)])


func _scan_dir(meshlib: MeshLibrary, start_idx: int, dir_path: String, prefix: String, suffix: String) -> int:
	var idx := start_idx
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Cannot open: %s" % dir_path)
		return idx
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".tres") and not dir.current_is_dir():
			var mesh_res := load(dir_path + "/" + fn) as Mesh
			if mesh_res == null:
				fn = dir.get_next()
				continue
			var clean_name := fn.get_basename().replace("hex_", "").replace("building_", "").replace("_waterless", "")
			var item_name := prefix + "/" + clean_name + suffix
			meshlib.set_item_name(idx, item_name)
			meshlib.set_item_mesh(idx, mesh_res)
			meshlib.set_item_mesh_transform(idx, hex_rot)
			var nav := _make_nav_mesh(mesh_res)
			if nav:
				meshlib.set_item_nav_mesh(idx, nav)
			idx += 1
		fn = dir.get_next()
	dir.list_dir_end()
	return idx


func _make_nav_mesh(mesh: Mesh) -> NavigationMesh:
	var nav := NavigationMesh.new()
	nav.agent_radius = 0.3
	nav.cell_size = 0.1
	nav.cell_height = 0.1
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if verts.is_empty():
			continue
		nav.add_vertices(verts)
		if indices.size() > 0:
			for i in range(0, indices.size(), 3):
				if i + 2 < indices.size():
					nav.add_face(PackedInt32Array([indices[i], indices[i + 1], indices[i + 2]]))
		else:
			for i in range(0, verts.size(), 3):
				if i + 2 < verts.size():
					nav.add_face(PackedInt32Array([i, i + 1, i + 2]))
	return nav
