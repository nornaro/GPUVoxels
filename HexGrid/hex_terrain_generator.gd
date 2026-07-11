class_name HexTerrainGenerator
extends RefCounted


var _noise := FastNoiseLite.new()
var _last_seed := -1
var _last_freq := -1.0


func generate_terrain(cells: Array[Vector3i], noise_seed: float, noise_freq: float) -> Array[Dictionary]:
	if cells.is_empty():
		return []

	var seed_int := int(noise_seed)
	if seed_int != _last_seed or noise_freq != _last_freq:
		_noise.seed = seed_int
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = noise_freq
		_last_seed = seed_int
		_last_freq = noise_freq

	# Compute bounds
	var q_min := cells[0].x
	var q_max := cells[0].x
	var r_min := cells[0].y
	var r_max := cells[0].y
	for c in cells:
		if c.x < q_min: q_min = c.x
		if c.x > q_max: q_max = c.x
		if c.y < r_min: r_min = c.y
		if c.y > r_max: r_max = c.y

	var img_w := q_max - q_min + 1
	var img_h := r_max - r_min + 1

	# Batch noise: single call replaces 1024+ individual get_noise_2d()
	var img := _noise.get_image(img_w, img_h, false, false, true)

	var results: Array[Dictionary] = []
	for c in cells:
		var px := c.x - q_min
		var py := c.y - r_min
		var nval: float = img.get_pixel(px, py).r * 2.0 - 1.0

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
