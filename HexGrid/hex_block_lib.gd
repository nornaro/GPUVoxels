class_name HexBlockLib
extends RefCounted

const ASSETS_BASE := "res://assets/kaykit_medieval_hexagon_pack"

var block_material: StandardMaterial3D = null

var _categories: Dictionary = {}
var _category_names: PackedStringArray = []
var _items: Dictionary = {}

const SCAN_DIRS: Array[Array] = [
	["buildings/neutral", "Building", ""],
	["decoration/nature", "Nature", ""],
	["decoration/props", "Prop", ""],
]


func _init() -> void:
	_generate_material()
	_scan_asset_dirs()
	_generate_procedural_blocks()
	if _category_names.has("Blocks"):
		_category_names.erase("Blocks")
		_category_names.insert(0, "Blocks")


var category_names: PackedStringArray:
	get: return _category_names


func get_items(category: String) -> Array:
	return _categories.get(category, [])


func get_item(item_name: String) -> Dictionary:
	return _items.get(item_name, {})


func get_all_item_names() -> PackedStringArray:
	return PackedStringArray(_items.keys())


func get_item_count() -> int:
	return _items.size()


func get_category_count() -> int:
	return _category_names.size()


func get_hex_scale(item_name: String) -> float:
	var item: Dictionary = _items.get(item_name, {})
	if item.is_empty():
		return 1.0
	var aabb: AABB = item.get("aabb", AABB())
	var max_ext := maxf(aabb.size.x, aabb.size.z)
	if max_ext <= 0.0:
		return 1.0
	return 1.0 / (max_ext * 0.5)


func _generate_material() -> void:
	block_material = StandardMaterial3D.new()
	block_material.albedo_color = Color(0.65, 0.55, 0.45)
	block_material.metallic = 0.0
	block_material.roughness = 1.0
	block_material.uv1_world_triplanar = true
	block_material.uv1_triplanar_sharpness = 0.8


func set_textures(normal_map: Texture2D, _detail_noise: Texture2D) -> void:
	block_material.normal_enabled = true
	block_material.normal_texture = normal_map


func _scan_asset_dirs() -> void:
	for scan: Array in SCAN_DIRS:
		var dir_rel: String = scan[0]
		var prefix: String = scan[1]
		var suffix: String = scan[2]
		_scan_dir(ASSETS_BASE + "/" + dir_rel, prefix, suffix)


func _scan_dir(dir_path: String, prefix: String, suffix: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".tres") and not dir.current_is_dir():
			var tres_path := dir_path + "/" + fn
			var mesh_res := load(tres_path) as Mesh
			if mesh_res == null:
				fn = dir.get_next()
				continue
			var clean_name := fn.get_basename()
			clean_name = clean_name.replace("hex_", "")
			clean_name = clean_name.replace("building_", "")
			clean_name = clean_name.replace("_waterless", "")
			var item_name := prefix + "/" + clean_name + suffix
			var aabb := mesh_res.get_aabb()
			var preview_tex: Texture2D = null
			var webp_path := tres_path.replace(".tres", ".webp")
			if ResourceLoader.exists(webp_path):
				preview_tex = load(webp_path)
			_add_item(item_name, mesh_res.get_rid(), mesh_res, prefix, true, aabb, preview_tex)
		fn = dir.get_next()
	dir.list_dir_end()


func _add_item(item_name: String, mesh_rid: RID, mesh_res: Resource, category: String, has_own_mat: bool = false, aabb: AABB = AABB(), preview: Texture2D = null) -> void:
	if _items.has(item_name):
		return
	_items[item_name] = {
		"mesh_rid": mesh_rid,
		"mesh_res": mesh_res,
		"category": category,
		"has_own_material": has_own_mat,
		"aabb": aabb,
		"preview": preview,
	}
	if not _categories.has(category):
		_categories[category] = []
		_category_names.append(category)
	_categories[category].append(_items[item_name])


func _generate_procedural_blocks() -> void:
	var specs: Array[Dictionary] = [
		{"w": 0.50, "h": 1.5},  {"w": 0.50, "h": 1.75},  {"w": 0.50, "h": 2.0},
		{"w": 0.625, "h": 1.5}, {"w": 0.625, "h": 1.75}, {"w": 0.625, "h": 2.0},
		{"w": 0.75, "h": 1.5},  {"w": 0.75, "h": 1.75},  {"w": 0.75, "h": 2.0},
	]
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var mesh := _create_box(spec["w"], spec["h"])
		var item_name := "Blocks/Block_%dx%d" % [int(spec["w"] * 100), int(spec["h"] * 100)]
		_add_item(item_name, mesh.get_rid(), mesh, "Blocks", false, mesh.get_aabb(), null)


static func _create_box(width: float, height: float) -> ArrayMesh:
	var length := 1.0
	var hw := width * 0.5
	var hd := length * 0.5
	var verts: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []
	var corners := [
		Vector3(-hw, 0.0, -hd), Vector3(hw, 0.0, -hd),
		Vector3(hw, 0.0, hd), Vector3(-hw, 0.0, hd),
		Vector3(-hw, height, -hd), Vector3(hw, height, -hd),
		Vector3(hw, height, hd), Vector3(-hw, height, hd),
	]
	var faces := [
		{"verts": [0, 3, 2, 1], "normal": Vector3.DOWN,  "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
		{"verts": [4, 5, 6, 7], "normal": Vector3.UP,    "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
		{"verts": [3, 7, 6, 2], "normal": Vector3.FORWARD,"uvs": [Vector2(0,0), Vector2(0,1), Vector2(1,1), Vector2(1,0)]},
		{"verts": [1, 5, 4, 0], "normal": Vector3.BACK,  "uvs": [Vector2(0,0), Vector2(0,1), Vector2(1,1), Vector2(1,0)]},
		{"verts": [0, 4, 7, 3], "normal": Vector3.LEFT,  "uvs": [Vector2(0,0), Vector2(0,1), Vector2(1,1), Vector2(1,0)]},
		{"verts": [2, 6, 5, 1], "normal": Vector3.RIGHT, "uvs": [Vector2(0,0), Vector2(0,1), Vector2(1,1), Vector2(1,0)]},
	]
	for face in faces:
		var base := verts.size()
		for j in 4:
			verts.append(corners[face["verts"][j]])
			normals.append(face["normal"])
			uvs.append(face["uvs"][j])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh


func get_material() -> StandardMaterial3D:
	return block_material
