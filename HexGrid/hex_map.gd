extends Node2D

# ============================================================================
# CONFIG
# ============================================================================
const HEX_SIZE: float = 24.0
const SUB_HEX_SIZE: float = HEX_SIZE / 3.0
const SUB_HEX_DIST: float = HEX_SIZE * 0.57735026919

# Biome indices
const BIOME_DEEP_WATER := 0
const BIOME_WATER := 1
const BIOME_BEACH := 2
const BIOME_GRASS := 3
const BIOME_DIRT := 4
const BIOME_STONE := 5

const BIOME_NAMES := ["Deep Water", "Water", "Beach", "Grass", "Dirt", "Stone"]

var BIOME_COLORS: Array[Color] = [
	Color(0.18, 0.35, 0.65),  # deep water
	Color(0.28, 0.52, 0.78),  # water
	Color(0.82, 0.77, 0.55),  # beach
	Color(0.35, 0.55, 0.28),  # grass
	Color(0.55, 0.42, 0.28),  # dirt
	Color(0.48, 0.48, 0.48),  # stone
]

# ============================================================================
# STATE
# ============================================================================
var camera_pos: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0
var cells: Dictionary = {}  # Vector3i -> HexCellData
var noise: FastNoiseLite

# Sub-hex overlay: Vector3i -> Array[int] (painted sub-hex indices 0-6)
var river_cells: Dictionary = {}
var show_overlay: bool = false
var show_grid: bool = false

# Roads: Array of {from: Vector3i, to: Vector3i}
var roads: Array[Dictionary] = []

# Tool mode: 0=neutral, 1=river, 2=road
var tool_mode: int = 0
const TOOL_NAMES := ["Navigate", "River", "Road"]

# River paint state
var painting: bool = false
var erasing: bool = false

# Road placement
var road_start: Vector3i = Vector3i(999999, 999999, -1999998)

# UI
var info_label: Label
var tool_label: Label

# Pan state
var panning: bool = false
var pan_start: Vector2 = Vector2.ZERO

# Visible margin in pixels
const VIEW_MARGIN: float = 100.0

# Noise
var noise_seed: int = 42
var noise_freq: float = 0.04


func _ready() -> void:
	_setup_noise()
	_setup_ui()
	queue_redraw()


func _setup_noise() -> void:
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = noise_freq
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.3


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	info_label = Label.new()
	info_label.position = Vector2(10, 10)
	info_label.add_theme_font_size_override("font_size", 14)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	info_label.add_theme_constant_override("shadow_offset_x", 1)
	info_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(info_label)

	tool_label = Label.new()
	tool_label.position = Vector2(10, 35)
	tool_label.add_theme_font_size_override("font_size", 16)
	tool_label.add_theme_color_override("font_color", Color(1, 1, 0.3))
	tool_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	tool_label.add_theme_constant_override("shadow_offset_x", 1)
	tool_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(tool_label)

	_update_ui()


func _update_ui() -> void:
	tool_label.text = "Tool: %s [1/2/3]" % TOOL_NAMES[tool_mode]
	info_label.text = "Pan: WASD/MMB | Zoom: Scroll | Grid: G | Overlay: H | Esc: Cancel"


func _process(_delta: float) -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var world_pos := _screen_to_world(mouse_pos)
	var hex := _world_to_hex(world_pos)
	if _cell_exists(hex):
		var cell: HexCellData = cells[hex]
		var biome_name: String = BIOME_NAMES[cell.biome]
		# Find closest sub-hex for water neighbor display
		var best_sub := 0
		var best_dist := INF
		for i in 7:
			var d := _get_sub_hex_world_pos(hex, i).distance_to(world_pos)
			if d < best_dist:
				best_dist = d
				best_sub = i
		var wn := _count_sub_hex_water_neighbors(hex, best_sub)
		var sub_info := ""
		if river_cells.has(hex):
			sub_info = "  |  River: %d/7" % river_cells[hex].size()
		info_label.text = "Hex: (%d,%d,%d)  |  %s  |  Sub %d  |  Water nb: %d%s  |  Zoom: %.1f" % [
			hex.x, hex.y, hex.z, biome_name, best_sub, wn, sub_info, camera_zoom
		]
	else:
		info_label.text = "Hex: none  |  Zoom: %.1f" % camera_zoom


# ============================================================================
# INPUT
# ============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey:
		_handle_key(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# Zoom
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_zoom = clampf(camera_zoom * 0.9, 0.2, 5.0)
		queue_redraw()
		return
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_zoom = clampf(camera_zoom * 1.1, 0.2, 5.0)
		queue_redraw()
		return

	# Middle mouse pan
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		panning = event.pressed
		if event.pressed:
			pan_start = event.position
		return

	# RMB
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if tool_mode == 1 and event.pressed:
			erasing = true
			_paint_river_at(event.position, true)
		elif not event.pressed:
			erasing = false
		if tool_mode == 0 or tool_mode == 2:
			panning = event.pressed
			if event.pressed:
				pan_start = event.position
		return

	# LMB
	if event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			painting = false
			return
		match tool_mode:
			0:
				pass
			1:
				painting = true
				_paint_river_at(event.position, false)
			2:
				_place_road_at(event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	# Pan with MMB or RMB in navigate/road mode
	if panning:
		var delta := event.position - pan_start
		camera_pos -= delta / camera_zoom
		pan_start = event.position
		queue_redraw()
		return

	# River paint drag
	if painting and tool_mode == 1:
		_paint_river_at(event.position, false)
		return
	elif erasing and tool_mode == 1:
		_paint_river_at(event.position, true)
		return

	# Only redraw on mouse motion when road preview or river debug is active
	if tool_mode == 2 and road_start != Vector3i(999999, 999999, -1999998):
		queue_redraw()
	elif tool_mode == 1:
		queue_redraw()


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	match event.keycode:
		KEY_1:
			tool_mode = 0
			_update_ui()
		KEY_2:
			tool_mode = 1
			_update_ui()
		KEY_3:
			tool_mode = 2
			road_start = Vector3i(999999, 999999, -1999998)
			_update_ui()
		KEY_H:
			show_overlay = not show_overlay
			queue_redraw()
		KEY_G:
			show_grid = not show_grid
			queue_redraw()
		KEY_ESCAPE:
			tool_mode = 0
			road_start = Vector3i(999999, 999999, -1999998)
			painting = false
			erasing = false
			_update_ui()


func _paint_river_at(screen_pos: Vector2, erase: bool) -> void:
	var world_pos := _screen_to_world(screen_pos)
	var hex := _world_to_hex(world_pos)
	if erase:
		# Find closest sub-hex in the clicked hex and erase it
		if _cell_exists(hex):
			var best_sub := 0
			var best_dist := INF
			for i in 7:
				var d := _get_sub_hex_world_pos(hex, i).distance_to(world_pos)
				if d < best_dist:
					best_dist = d
					best_sub = i
			_river_erase(hex, best_sub)
	else:
		# Validate on the hex directly under the cursor
		if not _cell_exists(hex):
			queue_redraw()
			return
		# Find closest sub-hex within the clicked hex only
		var best_sub := 0
		var best_dist := INF
		for i in 7:
			var d := _get_sub_hex_world_pos(hex, i).distance_to(world_pos)
			if d < best_dist:
				best_dist = d
				best_sub = i
		# Sub-hex must have 1-2 water sub-hex neighbors
		var wn := _count_sub_hex_water_neighbors(hex, best_sub)
		if wn < 1 or wn > 2:
			queue_redraw()
			return
		# Must not push any existing river sub-hex neighbor past 2
		for nb in _get_sub_hex_neighbors(hex, best_sub):
			if river_cells.has(nb["hex"]) and nb["sub"] in river_cells[nb["hex"]]:
				if _count_sub_hex_water_neighbors(nb["hex"], nb["sub"]) + 1 > 2:
					queue_redraw()
					return
		_river_paint(hex, best_sub)
	queue_redraw()


func _river_paint(hex: Vector3i, sub_idx: int) -> void:
	if not river_cells.has(hex):
		river_cells[hex] = []
	if sub_idx not in river_cells[hex]:
		river_cells[hex].append(sub_idx)


func _river_erase(hex: Vector3i, sub_idx: int) -> void:
	if river_cells.has(hex):
		river_cells[hex].erase(sub_idx)
		if river_cells[hex].is_empty():
			river_cells.erase(hex)


func _count_water_neighbors(hex: Vector3i) -> int:
	var count := 0
	for n in HexGridMath.cube_neighbors(hex):
		if _cell_exists(n):
			var c: HexCellData = cells[n]
			if c.biome == BIOME_WATER or c.biome == BIOME_DEEP_WATER or river_cells.has(n):
				count += 1
	return count


func _is_sub_hex_water(hex: Vector3i, sub_idx: int) -> bool:
	if not _cell_exists(hex):
		return false
	var c: HexCellData = cells[hex]
	if c.biome == BIOME_WATER or c.biome == BIOME_DEEP_WATER:
		return true
	if river_cells.has(hex) and sub_idx in river_cells[hex]:
		return true
	return false


func _get_sub_hex_neighbors(parent_hex: Vector3i, sub_idx: int) -> Array:
	var result: Array = []
	if sub_idx == 0:
		# Center sub-hex: neighbors with all 6 ring subs
		for i in 6:
			result.append({"hex": parent_hex, "sub": i + 1})
	else:
		# Ring sub-hex i: center + 2 adjacent ring + 1 cross-hex
		result.append({"hex": parent_hex, "sub": 0})
		# Adjacent ring subs within same hex
		var prev_sub: int = ((sub_idx - 2) % 6) + 1
		var next_sub: int = (sub_idx % 6) + 1
		result.append({"hex": parent_hex, "sub": prev_sub})
		result.append({"hex": parent_hex, "sub": next_sub})
		# Cross-hex neighbor
		var dir: int = (7 - sub_idx) % 6
		var opp_sub: int = ((sub_idx + 2) % 6) + 1
		var neighbor_hex: Vector3i = parent_hex + HexGridMath.cube_direction(dir)
		result.append({"hex": neighbor_hex, "sub": opp_sub})
	return result


func _count_sub_hex_water_neighbors(parent_hex: Vector3i, sub_idx: int) -> int:
	var count := 0
	for nb in _get_sub_hex_neighbors(parent_hex, sub_idx):
		if _is_sub_hex_water(nb["hex"], nb["sub"]):
			count += 1
	return count


func _can_place_river(hex: Vector3i, sub_idx: int) -> Array:
	if not _cell_exists(hex):
		return [false, "No terrain"]
	if river_cells.has(hex) and sub_idx in river_cells[hex]:
		return [true, ""]
	var wn := _count_sub_hex_water_neighbors(hex, sub_idx)
	if wn < 1:
		return [false, "No water nb (%d)" % wn]
	if wn > 2:
		return [false, "Too many water (%d)" % wn]
	for nb in _get_sub_hex_neighbors(hex, sub_idx):
		if river_cells.has(nb["hex"]) and nb["sub"] in river_cells[nb["hex"]]:
			if _count_sub_hex_water_neighbors(nb["hex"], nb["sub"]) + 1 > 2:
				return [false, "Would overflow nb"]
	return [true, "OK"]


func _place_road_at(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	var hex := _world_to_hex(world_pos)
	if not _cell_exists(hex):
		return

	if road_start == Vector3i(999999, 999999, -1999998):
		road_start = hex
		queue_redraw()
	else:
		if hex != road_start:
			# Find path from road_start to hex using cube_line (step by step)
			var path := HexGridMath.cube_line(road_start, hex)
			for i in range(path.size() - 1):
				roads.append({"from": path[i], "to": path[i + 1]})
		road_start = Vector3i(999999, 999999, -1999998)
		queue_redraw()


# ============================================================================
# COORDINATE CONVERSION
# ============================================================================
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	return (screen_pos - center) / camera_zoom + camera_pos


func _world_to_screen(world_pos: Vector2) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	return (world_pos - camera_pos) * camera_zoom + center


func _world_to_hex(world_pos: Vector2) -> Vector3i:
	var q := HexGridMath.TWO_THIRDS * world_pos.x / HEX_SIZE
	var r := HexGridMath.INV_SQRT3 * world_pos.y / HEX_SIZE - HexGridMath.ONE_THIRD * world_pos.x / HEX_SIZE
	var cube := Vector3(q, r, -q - r)
	return HexGridMath.cube_round(cube)


func _cell_exists(hex: Vector3i) -> bool:
	return cells.has(hex)


func _get_or_create_cell(hex: Vector3i) -> HexCellData:
	if cells.has(hex):
		return cells[hex]
	var elevation := noise.get_noise_2d(float(hex.x), float(hex.y))
	var biome := _elevation_to_biome(elevation)
	var cell := HexCellData.new(hex, biome, elevation)
	cell.color = BIOME_COLORS[biome]
	cells[hex] = cell
	return cell


func _elevation_to_biome(n: float) -> int:
	if n < -0.3:
		return BIOME_DEEP_WATER
	elif n < -0.1:
		return BIOME_WATER
	elif n < 0.1:
		return BIOME_BEACH
	elif n < 0.4:
		return BIOME_GRASS
	elif n < 0.6:
		return BIOME_DIRT
	else:
		return BIOME_STONE


# ============================================================================
# SUB-HEX POSITIONS
# ============================================================================
func _get_sub_hex_world_pos(parent_hex: Vector3i, sub_idx: int) -> Vector2:
	var parent_world := HexGridMath.cube_to_world_flat_top(parent_hex, HEX_SIZE)
	var parent_2d := Vector2(parent_world.x, parent_world.z)
	if sub_idx == 0:
		return parent_2d
	# Flat-top neighbor angles: 30°, 90°, 150°, 210°, 270°, 330°
	var angle := deg_to_rad(30.0 + 60.0 * float(sub_idx - 1))
	return parent_2d + Vector2(cos(angle), sin(angle)) * SUB_HEX_DIST


func _get_sub_hex_screen_pos(parent_hex: Vector3i, sub_idx: int) -> Vector2:
	return _world_to_screen(_get_sub_hex_world_pos(parent_hex, sub_idx))


# ============================================================================
# HEX POLYGON POINTS
# ============================================================================
func _hex_corners(center: Vector2, size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(6)
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i))
		points[i] = center + Vector2(cos(angle), sin(angle)) * size
	return points


# ============================================================================
# VISIBLE HEX RANGE
# ============================================================================
func _get_visible_hex_range() -> Array[Vector3i]:
	var viewport_size := get_viewport().get_visible_rect().size
	var half_view := viewport_size * 0.5 / camera_zoom
	var margin := VIEW_MARGIN / camera_zoom

	var tl := camera_pos - half_view - Vector2(margin, margin)
	var br := camera_pos + half_view + Vector2(margin, margin)

	# Convert all 4 screen corners to hex coords for proper bounding box
	var c00 := _world_to_hex(tl)
	var c10 := _world_to_hex(Vector2(br.x, tl.y))
	var c01 := _world_to_hex(Vector2(tl.x, br.y))
	var c11 := _world_to_hex(br)

	# Also check center for good measure
	var center_hex := _world_to_hex(camera_pos)

	var all_corners := [c00, c10, c01, c11, center_hex]
	var min_q := center_hex.x
	var max_q := center_hex.x
	var min_r := center_hex.y
	var max_r := center_hex.y
	for c in all_corners:
		min_q = mini(min_q, c.x)
		max_q = maxi(max_q, c.x)
		min_r = mini(min_r, c.y)
		max_r = maxi(max_r, c.y)

	# Extra margin of 2 hexes on each side
	min_q -= 2
	max_q += 2
	min_r -= 2
	max_r += 2

	var result: Array[Vector3i] = []
	for q in range(min_q, max_q + 1):
		for r in range(min_r, max_r + 1):
			var s := -q - r
			var hex := Vector3i(q, r, s)
			# Verify this hex is actually in the visible area
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			var hpos2d := Vector2(hpos.x, hpos.z)
			if hpos2d.x >= tl.x - HEX_SIZE and hpos2d.x <= br.x + HEX_SIZE and \
			   hpos2d.y >= tl.y - HEX_SIZE and hpos2d.y <= br.y + HEX_SIZE:
				result.append(hex)
	return result


# ============================================================================
# RENDERING
# ============================================================================
func _draw() -> void:
	var visible_hexes := _get_visible_hex_range()

	# Draw terrain
	for hex in visible_hexes:
		var cell := _get_or_create_cell(hex)
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var screen_pos := _world_to_screen(Vector2(hpos.x, hpos.z))
		var corners := _hex_corners(screen_pos, HEX_SIZE * camera_zoom)
		draw_colored_polygon(corners, cell.color)
		if show_grid:
			var grid_color := Color(0, 0, 0, 0.15)
			draw_polyline(corners + PackedVector2Array([corners[0]]), grid_color, 1.0)

	# Draw sub-hex overlay
	if show_overlay:
		for hex in visible_hexes:
			_draw_sub_hex_overlay(hex)

	# Draw rivers
	for hex in river_cells:
		_draw_river_hex(hex)

	# Draw roads (segment by segment)
	for road in roads:
		_draw_road_line(road["from"], road["to"])

	# Draw road preview
	if tool_mode == 2 and road_start != Vector3i(999999, 999999, -1999998):
		var mouse_screen := get_viewport().get_mouse_position()
		var mouse_world := _screen_to_world(mouse_screen)
		var mouse_hex := _world_to_hex(mouse_world)
		if _cell_exists(mouse_hex):
			# Preview path step-by-step
			var path := HexGridMath.cube_line(road_start, mouse_hex)
			for i in range(path.size() - 1):
				_draw_road_line(path[i], path[i + 1], Color(1, 1, 0.5, 0.4))
		# Highlight start
		var start_screen := _world_to_screen(Vector2(cells[road_start].get_world_position(HEX_SIZE)))
		draw_circle(start_screen, 6.0, Color(1, 1, 0.2, 0.8))

	# River placement debug overlay
	if tool_mode == 1:
		_draw_river_debug()


func _draw_river_debug() -> void:
	var mouse_screen := get_viewport().get_mouse_position()
	var mouse_world := _screen_to_world(mouse_screen)
	var hex := _world_to_hex(mouse_world)
	if not _cell_exists(hex):
		return
	# Find closest sub-hex
	var best_sub := 0
	var best_dist := INF
	for i in 7:
		var d := _get_sub_hex_world_pos(hex, i).distance_to(mouse_world)
		if d < best_dist:
			best_dist = d
			best_sub = i
	# Draw all 7 sub-hexes with green/red
	for i in 7:
		var result: Array = _can_place_river(hex, i)
		var ok: bool = result[0]
		var sub_screen := _get_sub_hex_screen_pos(hex, i)
		var sub_corners := _hex_corners(sub_screen, SUB_HEX_SIZE * camera_zoom)
		if ok:
			var fill := Color(0.2, 0.8, 0.2, 0.25)
			if i == best_sub:
				fill = Color(0.2, 0.9, 0.2, 0.4)
			draw_colored_polygon(sub_corners, fill)
			var outline_col := Color(0.2, 0.9, 0.2, 0.5) if i == best_sub else Color(0.2, 0.7, 0.2, 0.3)
			draw_polyline(sub_corners + PackedVector2Array([sub_corners[0]]), outline_col, 1.5)
		else:
			var fill := Color(0.8, 0.2, 0.2, 0.25)
			if i == best_sub:
				fill = Color(0.9, 0.2, 0.2, 0.4)
			draw_colored_polygon(sub_corners, fill)
			var outline_col := Color(0.9, 0.2, 0.2, 0.5) if i == best_sub else Color(0.7, 0.2, 0.2, 0.3)
			draw_polyline(sub_corners + PackedVector2Array([sub_corners[0]]), outline_col, 1.5)
	# Draw reason text for closest sub-hex if blocked
	if not _can_place_river(hex, best_sub)[0]:
		var reason: String = _can_place_river(hex, best_sub)[1]
		var hex_screen := _world_to_screen(Vector2(
			HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE).x,
			HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE).z
		))
		var font := ThemeDB.fallback_font
		var text_pos := hex_screen + Vector2(0, HEX_SIZE * camera_zoom * 0.5 + 14)
		draw_string(font, text_pos, reason, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color.BLACK)
		draw_string(font, text_pos + Vector2(-1, -1), reason, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color.WHITE)


func _draw_sub_hex_overlay(hex: Vector3i) -> void:
	if not _cell_exists(hex):
		return
	var color := BIOME_COLORS[cells[hex].biome]
	for i in 7:
		var sub_screen := _get_sub_hex_screen_pos(hex, i)
		var sub_corners := _hex_corners(sub_screen, SUB_HEX_SIZE * camera_zoom)
		# Transparent fill
		var fill := Color(color.r, color.g, color.b, 0.05)
		draw_colored_polygon(sub_corners, fill)
		# Outline
		draw_polyline(sub_corners + PackedVector2Array([sub_corners[0]]), Color(1, 1, 1, 0.2), 1.0)


func _draw_river_hex(hex: Vector3i) -> void:
	if not river_cells.has(hex) or not _cell_exists(hex):
		return
	for sub_idx in river_cells[hex]:
		var sub_screen := _get_sub_hex_screen_pos(hex, sub_idx)
		var sub_corners := _hex_corners(sub_screen, SUB_HEX_SIZE * camera_zoom)
		draw_colored_polygon(sub_corners, Color(0.2, 0.45, 0.75, 0.7))
		draw_polyline(sub_corners + PackedVector2Array([sub_corners[0]]), Color(0.15, 0.3, 0.6, 0.9), 1.5)


func _draw_road_line(from_hex: Vector3i, to_hex: Vector3i, col: Color = Color(0.6, 0.35, 0.15, 0.9)) -> void:
	if not _cell_exists(from_hex) or not _cell_exists(to_hex):
		return

	var diff := to_hex - from_hex
	var dir := -1
	for d in 6:
		if HexGridMath.cube_direction(d) == diff:
			dir = d
			break

	# Draw center sub-hex of from_hex
	_draw_filled_sub(from_hex, 0, col)

	if dir >= 0:
		# Draw exit sub-hex of from_hex
		var exit_sub := ((6 - dir) % 6) + 1
		_draw_filled_sub(from_hex, exit_sub, col)
		# Draw entry sub-hex of to_hex
		var entry_dir := (dir + 3) % 6
		var entry_sub := ((6 - entry_dir) % 6) + 1
		_draw_filled_sub(to_hex, entry_sub, col)

	# Draw center sub-hex of to_hex
	_draw_filled_sub(to_hex, 0, col)


func _draw_filled_sub(hex: Vector3i, sub_idx: int, col: Color) -> void:
	var sub_screen := _get_sub_hex_screen_pos(hex, sub_idx)
	var sub_corners := _hex_corners(sub_screen, SUB_HEX_SIZE * camera_zoom)
	draw_colored_polygon(sub_corners, col)
