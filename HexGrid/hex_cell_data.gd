class_name HexCellData
extends RefCounted

var coords: Vector3i = Vector3i.ZERO
var biome: int = 0
var elevation: float = 0.0
var color: Color = Color.WHITE
var sub_heights: Array[float] = []  # 13 values, one per sub-hex (0=center, 1-6=ring, 7-12=vertex)


func _init(p_coords: Vector3i = Vector3i.ZERO, p_biome: int = 0, p_elevation: float = 0.0) -> void:
	coords = p_coords
	biome = p_biome
	elevation = p_elevation
	sub_heights.resize(13)
	sub_heights.fill(0.0)


func get_world_position(hex_size: float) -> Vector2:
	var pos := HexGridMath.cube_to_world_flat_top(coords, hex_size)
	return Vector2(pos.x, pos.z)
