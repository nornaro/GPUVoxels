class_name HexCellData
extends RefCounted

var coords: Vector3i = Vector3i.ZERO
var biome: int = 0
var elevation: float = 0.0
var color: Color = Color.WHITE
var sub_heights: Array[float] = []
var _corner_norms: Array[float] = []


func _init(p_coords: Vector3i = Vector3i.ZERO, p_biome: int = 0, p_elevation: float = 0.0) -> void:
	coords = p_coords
	biome = p_biome
	elevation = p_elevation
	sub_heights.resize(13)
	sub_heights.fill(0.0)


func get_cached_corner_norm(ci: int) -> float:
	if ci < _corner_norms.size():
		return _corner_norms[ci]
	return -1.0


func set_cached_corner_norm(ci: int, val: float) -> void:
	if ci >= _corner_norms.size():
		_corner_norms.resize(ci + 1)
	while _corner_norms.size() < 6:
		_corner_norms.append(-1.0)
	_corner_norms[ci] = val


func get_world_position(hex_size: float) -> Vector2:
	var pos := HexGridMath.cube_to_world_flat_top(coords, hex_size)
	return Vector2(pos.x, pos.z)


func get_world_position_3d(hex_size: float) -> Vector3:
	return HexGridMath.cube_to_world_flat_top(coords, hex_size)
