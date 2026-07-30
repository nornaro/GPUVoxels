class_name TileValuator
extends RefCounted

const TARGET_CENTER := Vector3i.ZERO
const TARGET_RADIUS: int = 2

var show_values: bool = false
var random_factor: float = 0.05


func compute_tile_value(hex: Vector3i, elevation: float) -> float:
	var dist := maxi(maxi(absi(hex.x), absi(hex.y)), absi(hex.z))
	var dist_score := 1.0 - clampf(float(dist - TARGET_RADIUS) / 50.0, 0.0, 1.0)

	var elev_norm := clampf(elevation, 0.0, 1.0)
	var elev_score := elev_norm

	var value := dist_score * 0.7 + elev_score * 0.3

	if random_factor > 0.0:
		var h := hash_val(float(hex.x) * 73.1 + float(hex.y) * 97.3)
		value += (h - 0.5) * random_factor

	return clampf(value, 0.0, 1.0)


func hash_val(v: float) -> float:
	var x := sin(v * 127.1 + v * 311.7) * 43758.5453
	return x - floor(x)
