class_name HexTerrainGenerator
extends RefCounted


func generate_terrain(cells: Array[Vector3i], noise_seed: float, noise_freq: float) -> Array[Dictionary]:
	if cells.is_empty():
		return []
	return _fallback_cpu(cells, noise_seed, noise_freq)


func _fallback_cpu(cells: Array[Vector3i], noise_seed: float, noise_freq: float) -> Array[Dictionary]:
	var noise := FastNoiseLite.new()
	noise.seed = int(noise_seed)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = noise_freq

	var results: Array[Dictionary] = []
	for c in cells:
		var nval := noise.get_noise_2d(float(c.x), float(c.y))
		var elevation := _remap(nval, -1.0, 1.0, 0.3, 3.0)
		var type_idx := 0
		if nval < -0.2:
			type_idx = 1
			elevation = _remap(nval, -1.0, -0.2, 0.15, 0.4)
		elif nval > 0.5:
			type_idx = 2
			elevation = _remap(nval, 0.5, 1.0, 1.8, 4.0)
		elif nval > 0.25:
			type_idx = 3
			elevation = _remap(nval, 0.25, 0.5, 1.0, 1.8)
		else:
			type_idx = 0
			elevation = _remap(nval, -0.2, 0.25, 0.6, 1.2)
		results.append({
			"coords": c,
			"elevation": elevation,
			"type_index": type_idx,
			"noise_val": nval,
			"detail": 0.0,
		})
	return results


static func _remap(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	var t := clampf((value - in_min) / (in_max - in_min), 0.0, 1.0)
	return lerpf(out_min, out_max, t)
