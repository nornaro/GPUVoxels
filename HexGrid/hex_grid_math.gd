class_name HexGridMath
extends RefCounted

const SQRT3: float = 1.73205080757
const INV_SQRT3: float = 0.57735026919
const TWO_THIRDS: float = 0.66666666667
const ONE_THIRD: float = 0.33333333333

const DIR_E  := Vector3i( 1,  0, -1)
const DIR_SE := Vector3i( 1, -1,  0)
const DIR_SW := Vector3i( 0, -1,  1)
const DIR_W  := Vector3i(-1,  0,  1)
const DIR_NW := Vector3i(-1,  1,  0)
const DIR_NE := Vector3i( 0,  1, -1)


static func axial_to_cube(q: int, r: int) -> Vector3i:
	return Vector3i(q, r, -q - r)


static func cube_to_axial(cube: Vector3i) -> Vector2i:
	return Vector2i(cube.x, cube.y)


static func cube_distance(a: Vector3i, b: Vector3i) -> int:
	var diff := a - b
	return maxi(maxi(absi(diff.x), absi(diff.y)), absi(diff.z))


static func cube_direction(index: int) -> Vector3i:
	match index:
		0: return DIR_E
		1: return DIR_SE
		2: return DIR_SW
		3: return DIR_W
		4: return DIR_NW
		5: return DIR_NE
	return Vector3i.ZERO


static func cube_ring(center: Vector3i, radius: int) -> Array[Vector3i]:
	var results: Array[Vector3i] = []
	if radius <= 0:
		results.append(center)
		return results
	var cube: Vector3i = center + DIR_NW * radius
	for i in 6:
		var dir: Vector3i = cube_direction(i)
		for j in radius:
			results.append(cube)
			cube += dir
	return results


static func cube_spiral(center: Vector3i, radius: int) -> Array[Vector3i]:
	var results: Array[Vector3i] = [center]
	for r in range(1, radius + 1):
		results.append_array(cube_ring(center, r))
	return results


static func cube_to_world_flat_top(cube: Vector3i, hex_size: float) -> Vector3:
	var x: float = hex_size * 1.5 * float(cube.x)
	var z: float = hex_size * SQRT3 * (float(cube.y) + float(cube.x) * 0.5)
	return Vector3(x, 0.0, z)


static func world_to_cube_flat_top(world_pos: Vector3, hex_size: float) -> Vector3i:
	var q: float = TWO_THIRDS * world_pos.x / hex_size
	var r: float = (-ONE_THIRD * world_pos.x + INV_SQRT3 * world_pos.z) / hex_size
	return cube_round(Vector3(q, r, -q - r))


static func cube_round(frac: Vector3) -> Vector3i:
	var rx: float = roundf(frac.x)
	var ry: float = roundf(frac.y)
	var rz: float = roundf(frac.z)
	var x_diff: float = absf(rx - frac.x)
	var y_diff: float = absf(ry - frac.y)
	var z_diff: float = absf(rz - frac.z)
	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector3i(int(rx), int(ry), int(rz))


static func cube_lerp(a: Vector3i, b: Vector3i, t: float) -> Vector3:
	return Vector3(
		lerp(float(a.x), float(b.x), t),
		lerp(float(a.y), float(b.y), t),
		lerp(float(a.z), float(b.z), t),
	)


static func cube_line(a: Vector3i, b: Vector3i) -> Array[Vector3i]:
	var dist: int = cube_distance(a, b)
	var results: Array[Vector3i] = []
	var inv: float = 1.0 / maxf(float(dist), 1.0)
	for i in range(dist + 1):
		results.append(cube_round(cube_lerp(a, b, float(i) * inv)))
	return results


static func cube_neighbors(cube: Vector3i) -> Array[Vector3i]:
	return [
		cube + DIR_E,
		cube + DIR_SE,
		cube + DIR_SW,
		cube + DIR_W,
		cube + DIR_NW,
		cube + DIR_NE,
	]


static func is_valid_cube(cube: Vector3i) -> bool:
	return cube.x + cube.y + cube.z == 0


static func hex_corners_flat_top(center: Vector3, hex_size: float) -> Array[Vector2]:
	var corners: Array[Vector2] = []
	for i in 6:
		var angle_deg: float = 60.0 * float(i)
		var angle_rad: float = deg_to_rad(angle_deg)
		corners.append(Vector2(
			center.x + hex_size * cos(angle_rad),
			center.z + hex_size * sin(angle_rad),
		))
	return corners
