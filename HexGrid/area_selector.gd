class_name AreaSelector
extends RefCounted

var selected_hexes: Array[Vector3i] = []
var area_points: Array[Vector3i] = []
var area_ready: bool = false
var has_active_selection: bool = false


func clear() -> void:
	selected_hexes.clear()
	area_points.clear()
	area_ready = false
	has_active_selection = false


func select_base(hex: Vector3i) -> void:
	clear()
	area_points.append(hex)
	selected_hexes.append(hex)
	has_active_selection = true


func extend_selection(hex: Vector3i) -> void:
	if not has_active_selection:
		select_base(hex)
		return
	if hex in area_points:
		return
	area_points.append(hex)
	_rebuild_polygon_area()


func remove_last_point() -> void:
	if area_points.is_empty():
		return
	area_points.pop_back()
	if area_points.is_empty():
		clear()
		return
	_rebuild_polygon_area()


func _rebuild_polygon_area() -> void:
	selected_hexes.clear()
	has_active_selection = true

	if area_points.size() < 3:
		selected_hexes = area_points.duplicate()
		area_ready = false
		return

	area_ready = true
	var hull := _convex_hull(area_points)
	var min_q := 999999
	var max_q := -999999
	var min_r := 999999
	var max_r := -999999
	for p in hull:
		min_q = mini(min_q, p.x)
		max_q = maxi(max_q, p.x)
		min_r = mini(min_r, p.y)
		max_r = maxi(max_r, p.y)

	for q in range(min_q - 1, max_q + 2):
		for r in range(min_r - 1, max_r + 2):
			var hex := Vector3i(q, r, -q - r)
			if _point_in_polygon(hex, hull):
				selected_hexes.append(hex)


func _point_in_polygon(hex: Vector3i, polygon: Array[Vector3i]) -> bool:
	var n := polygon.size()
	if n < 3:
		return false
	var inside := false
	var j := n - 1
	for i in n:
		var pi := polygon[i]
		var pj := polygon[j]
		if ((pi.y > hex.y) != (pj.y > hex.y)) and \
			(hex.x < (pj.x - pi.x) * (hex.y - pi.y) / float(pj.y - pi.y) + pi.x):
			inside = not inside
		j = i
	return inside


func _convex_hull(points: Array[Vector3i]) -> Array[Vector3i]:
	if points.size() < 3:
		return points.duplicate()
	var sorted := points.duplicate()
	sorted.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)

	var lower: Array[Vector3i] = []
	for p in sorted:
		while lower.size() >= 2 and _cross(lower[lower.size() - 2], lower[lower.size() - 1], p) <= 0:
			lower.pop_back()
		lower.append(p)

	var upper: Array[Vector3i] = []
	for i in range(sorted.size() - 1, -1, -1):
		var p := sorted[i]
		while upper.size() >= 2 and _cross(upper[upper.size() - 2], upper[upper.size() - 1], p) <= 0:
			upper.pop_back()
		upper.append(p)

	lower.pop_back()
	upper.pop_back()
	return lower + upper


func _cross(o: Vector3i, a: Vector3i, b: Vector3i) -> int:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


func is_ready() -> bool:
	return area_ready


func get_hex_count() -> int:
	return selected_hexes.size()
