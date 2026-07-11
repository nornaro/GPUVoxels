class_name HexTileLibrary
extends Resource

var _top_rids: Dictionary = {}
var _side_rids: Dictionary = {}
var _mat_rids: Dictionary = {}
var _names: Dictionary = {}
var _next_id: int = 0


func register_tile(tile_name: String, top_mesh_rid: RID, side_mesh_rid: RID, material_rid: RID) -> int:
	var id: int = _next_id
	_next_id += 1
	_top_rids[id] = top_mesh_rid
	_side_rids[id] = side_mesh_rid
	_mat_rids[id] = material_rid
	_names[id] = tile_name
	return id


func get_top_mesh_rid(mesh_id: int) -> RID:
	if _top_rids.has(mesh_id):
		return _top_rids[mesh_id] as RID
	return RID()


func get_side_mesh_rid(mesh_id: int) -> RID:
	if _side_rids.has(mesh_id):
		return _side_rids[mesh_id] as RID
	return RID()


func get_material_rid(mesh_id: int) -> RID:
	if _mat_rids.has(mesh_id):
		return _mat_rids[mesh_id] as RID
	return RID()


func has_tile(mesh_id: int) -> bool:
	return _top_rids.has(mesh_id)


func remove_tile(mesh_id: int) -> void:
	_top_rids.erase(mesh_id)
	_side_rids.erase(mesh_id)
	_mat_rids.erase(mesh_id)
	_names.erase(mesh_id)


func clear() -> void:
	_top_rids.clear()
	_side_rids.clear()
	_mat_rids.clear()
	_names.clear()
	_next_id = 0
