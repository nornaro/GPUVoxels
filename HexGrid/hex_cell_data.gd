class_name HexCellData
extends Resource

@export var coords: Vector3i = Vector3i.ZERO
@export var elevation: float = 1.0
@export var mesh_id: int = 0
@export var layer: int = 0
@export var custom_data: Vector4 = Vector4.ZERO
@export var is_visible: bool = true


func to_vector4() -> Vector4:
	return Vector4(float(coords.x), float(coords.y), float(coords.z), float(layer))


func get_world_position(hex_size: float) -> Vector3:
	var pos := HexGridMath.cube_to_world_flat_top(coords, hex_size)
	pos.y = float(layer)
	return pos


func get_tile_key() -> Vector3i:
	return coords


func duplicate_data() -> HexCellData:
	var copy := HexCellData.new()
	copy.coords = coords
	copy.elevation = elevation
	copy.mesh_id = mesh_id
	copy.layer = layer
	copy.custom_data = custom_data
	copy.is_visible = is_visible
	return copy
