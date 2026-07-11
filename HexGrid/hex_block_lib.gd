class_name HexBlockLib
extends RefCounted


var block_material: StandardMaterial3D = null
var _meshlib: MeshLibrary = null

# Category -> Array of {name, mesh_rid, mesh_res}
var _categories: Dictionary = {}
# Ordered list of category names
var _category_names: PackedStringArray = []
# name -> {mesh_rid, mesh_res, category}
var _items: Dictionary = {}


func _init() -> void:
	_generate_material()
	_load_meshlib()
	_generate_procedural_blocks()
	# Ensure "Blocks" is first if it exists
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


func _load_meshlib() -> void:
	_meshlib = load("res://HexGrid/hex_mesh_library.meshlib") as MeshLibrary
	if _meshlib == null:
		return
	var items := _meshlib.get_item_list()
	if items.is_empty():
		return
	for idx in items:
		var item_name := _meshlib.get_item_name(idx)
		var category := _get_category_from_name(item_name)
		var mesh := _meshlib.get_item_mesh(idx)
		if mesh == null:
			continue
		var mesh_rid := mesh.get_rid()
		_add_item(item_name, mesh_rid, mesh, category)


func _get_category_from_name(item_name: String) -> String:
	var lower := item_name.to_lower()
	var prefixes := ["road", "river", "coast", "wall", "floor", "roof", "fence", "tree", "rock", "deco"]
	for prefix in prefixes:
		if lower.begins_with(prefix):
			return prefix.capitalize()
	return "Misc"


func _generate_procedural_blocks() -> void:
	var specs := [
		{"w": 0.50, "h": 1.5},  {"w": 0.50, "h": 1.75},  {"w": 0.50, "h": 2.0},
		{"w": 0.625, "h": 1.5}, {"w": 0.625, "h": 1.75}, {"w": 0.625, "h": 2.0},
		{"w": 0.75, "h": 1.5},  {"w": 0.75, "h": 1.75},  {"w": 0.75, "h": 2.0},
	]
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var mesh := _create_box(spec["w"], spec["h"])
		var item_name := "Block_%dx%d" % [int(spec["w"] * 100), int(spec["h"] * 100)]
		_add_item(item_name, mesh.get_rid(), mesh, "Blocks")


func _add_item(item_name: String, mesh_rid: RID, mesh_res: Resource, category: String) -> void:
	if _items.has(item_name):
		return
	var entry := {"mesh_rid": mesh_rid, "mesh_res": mesh_res, "category": category}
	_items[item_name] = entry
	if not _categories.has(category):
		_categories[category] = []
		_category_names.append(category)
	_categories[category].append(entry)


static func _create_box(width: float, height: float) -> ArrayMesh:
	var length := 1.0
	var hw := width * 0.5
	var hd := length * 0.5

	var verts: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []

	var corners := [
		Vector3(-hw, 0.0, -hd),
		Vector3( hw, 0.0, -hd),
		Vector3( hw, 0.0,  hd),
		Vector3(-hw, 0.0,  hd),
		Vector3(-hw, height, -hd),
		Vector3( hw, height, -hd),
		Vector3( hw, height,  hd),
		Vector3(-hw, height,  hd),
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
		for i in 4:
			verts.append(corners[face["verts"][i]])
			normals.append(face["normal"])
			uvs.append(face["uvs"][i])
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
