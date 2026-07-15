extends Node2D

const HEX_SIZE: float = 24.0
const SUB_HEX_SIZE: float = HEX_SIZE / 3.0
const SUB_HEX_DIST: float = HEX_SIZE * 0.57735026919

const VERTEX_NEIGHBORS: Array = [
	[0, 1],
	[0, 5],
	[5, 4],
	[4, 3],
	[3, 2],
	[2, 1],
]

const VERTEX_OFFSET: int = 7
const TOTAL_SUBS: int = 13

const BIOME_DEEP_WATER := 0
const BIOME_WATER := 1
const BIOME_BEACH := 2
const BIOME_GRASS := 3
const BIOME_DIRT := 4
const BIOME_STONE := 5
const BIOME_LAKE := 6

const BIOME_NAMES := ["Deep Water", "Water", "Beach", "Grass", "Dirt", "Stone", "Lake"]

var BIOME_COLORS: Array[Color] = [
	Color(0.18, 0.35, 0.65),
	Color(0.28, 0.52, 0.78),
	Color(0.82, 0.77, 0.55),
	Color(0.35, 0.55, 0.28),
	Color(0.55, 0.42, 0.28),
	Color(0.48, 0.48, 0.48),
	Color(0.32, 0.55, 0.82),
]

const WATER_LEVEL: float = -0.3
const LAKE_LEVEL: float = -0.2

var camera_pos: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0
var cells: Dictionary = {}
var chunk_manager: ChunkManager

var river_cells: Dictionary = {}
var road_cells: Dictionary = {}
var vertex_subs: Dictionary = {}
var show_overlay: bool = false
var show_grid: bool = false
var show_height: bool = false
var show_elevation_shade: bool = false

var roads: Array[Dictionary] = []

var tool_mode: int = 0
const TOOL_NAMES := ["Navigate", "River", "Road"]

var painting: bool = false
var erasing: bool = false

var road_start: Vector3i = Vector3i(999999, 999999, -1999998)

var info_label: Label
var tool_label: Label

var panning: bool = false
var pan_start: Vector2 = Vector2.ZERO

const VIEW_MARGIN: float = 100.0

var chunks_with_rivers: Dictionary = {}
const CHUNK_SIZE: int = 10
const RIVER_SOURCE_PERCENTILE: float = 0.97
const MAX_RIVERS_PER_CHUNK: int = 1
const MIN_LAKE_SIZE: int = 10

# Generation queues
var _pending_chunks: Array[Vector2i] = []
var _pending_rivers: Array[Vector2i] = []
const MAX_TERRAIN_PER_FRAME: int = 4
const MAX_RIVERS_PER_FRAME: int = 2
const MAX_NEW_CHUNKS_QUEUED_PER_FRAME: int = 8

# Draw cache — invalidated only on camera change or paint
var _cached_visible_hexes: Array[Vector3i] = []
var _cached_visible_set: Dictionary = {}
var _cached_visible_rivers: Array = []
var _cached_visible_vertex_rivers: Array = []
var _needs_save: bool = false
var _tool_flash_timer: float = 0.0
var _cached_camera_pos: Vector2 = Vector2(NAN, NAN)
var _cached_camera_zoom: float = NAN
var _last_hover_hex: Vector3i = Vector3i(999999, 999999, -1999998)
var _last_debug_hover_hex: Vector3i = Vector3i(999999, 999999, -1999998)


func _ready() -> void:
	chunk_manager = ChunkManager.new(cells)
	_setup_ui()
	var save_path := "res://map_save.json"
	if FileAccess.file_exists(save_path):
		if _load_map_from(save_path):
			return
	queue_redraw()


func _exit_tree() -> void:
	if chunk_manager:
		chunk_manager.cleanup()


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
	info_label.text = "Pan: WASD/MMB | Zoom: Scroll | Grid: G | Overlay: H | Height: V | ElevShade: Ins | Regen: R | QSave: F6 | QLoad: F7 | Save: F8 | Load: F9 | Esc: Cancel"


func _process(delta: float) -> void:
	_discover_visible_chunks()
	_process_pending_batch()
	_process_pending_rivers()
	if _tool_flash_timer > 0.0:
		_tool_flash_timer -= delta
		if _tool_flash_timer <= 0.0:
			_update_ui()
	if not _pending_chunks.is_empty() or not _pending_rivers.is_empty():
		_invalidate_draw_cache()
		queue_redraw()
	else:
		if _needs_save:
			_save_map()
			_needs_save = false
		_update_hover_info()


func _update_hover_info() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var world_pos := _screen_to_world(mouse_pos)
	var hex := _world_to_hex(world_pos)
	if hex == _last_hover_hex:
		return
	_last_hover_hex = hex
	if _cell_exists(hex):
		var cell: HexCellData = cells[hex]
		var biome_name: String = BIOME_NAMES[cell.biome]
		var best_sub := 0
		var best_dist := INF
		for i in TOTAL_SUBS:
			var d := _get_sub_hex_world_pos(hex, i).distance_to(world_pos)
			if d < best_dist:
				best_dist = d
				best_sub = i
		var wn := _count_sub_hex_water_neighbors(hex, best_sub)
		var sub_type := "Sub"
		if best_sub >= VERTEX_OFFSET:
			sub_type = "Vertex"
		var sub_h: float = cell.sub_heights[best_sub]
		var labels := ""
		if _is_hex_river(hex):
			labels += "  |  RIVER(%d)" % _hex_river_count(hex)
		if _is_hex_road(hex):
			labels += "  |  ROAD(%d)" % _hex_road_count(hex)
		info_label.text = "Hex: (%d,%d,%d)  |  %s  |  %s %d  |  H: %.1f (avg %.1f)  |  Water nb: %d%s  |  Zoom: %.1f  |  Q:%d R:%d" % [
			hex.x, hex.y, hex.z, biome_name, sub_type, best_sub, sub_h, cell.elevation, wn, labels, camera_zoom,
			_pending_chunks.size(), _pending_rivers.size()
		]
	else:
		info_label.text = "Hex: none  |  Zoom: %.1f  |  Q:%d R:%d" % [camera_zoom, _pending_chunks.size(), _pending_rivers.size()]


func _discover_visible_chunks() -> void:
	_ensure_draw_cache()
	for hex in _cached_visible_hexes:
		var ck := _chunk_key(hex)
		if not chunk_manager._loaded_chunk_origins.has(ck):
			if not _pending_chunks.has(ck) and _pending_chunks.size() < MAX_NEW_CHUNKS_QUEUED_PER_FRAME:
				_pending_chunks.append(ck)


func _process_pending_batch() -> void:
	if _pending_chunks.is_empty():
		return
	var batch: Array[Vector2i] = []
	var count := mini(_pending_chunks.size(), MAX_TERRAIN_PER_FRAME)
	for i in count:
		batch.append(_pending_chunks[i])
	_pending_chunks = _pending_chunks.slice(count)
	chunk_manager.generate_batch(batch)
	for ck in batch:
		if _chunk_has_cells(ck) and not chunks_with_rivers.has(ck):
			_pending_rivers.append(ck)
	if _pending_chunks.is_empty():
		_needs_save = true


func _process_pending_rivers() -> void:
	var processed := 0
	var i := 0
	while i < _pending_rivers.size() and processed < MAX_RIVERS_PER_FRAME:
		var ck: Vector2i = _pending_rivers[i]
		if chunks_with_rivers.has(ck):
			_pending_rivers.remove_at(i)
			continue
		if _chunk_all_neighbors_loaded(ck):
			_ensure_chunk_rivers(ck)
			processed += 1
		_pending_rivers.remove_at(i)
		i += 1
	if processed > 0 and _pending_rivers.is_empty():
		_needs_save = true


func _chunk_has_cells(ck: Vector2i) -> bool:
	for q in range(ck.x * CHUNK_SIZE, (ck.x + 1) * CHUNK_SIZE):
		for r in range(ck.y * CHUNK_SIZE, (ck.y + 1) * CHUNK_SIZE):
			if cells.has(Vector3i(q, r, -q - r)):
				return true
	return false


func _chunk_all_neighbors_loaded(ck: Vector2i) -> bool:
	for dq in range(-1, 2):
		for dr in range(-1, 2):
			var nck := Vector2i(ck.x + dq, ck.y + dr)
			if not chunk_manager._loaded_chunk_origins.has(nck):
				return false
	return true


func _invalidate_draw_cache() -> void:
	_cached_camera_pos = Vector2(NAN, NAN)
	_cached_camera_zoom = NAN


func _ensure_draw_cache() -> void:
	if _cached_camera_pos == camera_pos and _cached_camera_zoom == camera_zoom:
		return
	_cached_camera_pos = camera_pos
	_cached_camera_zoom = camera_zoom
	_cached_visible_hexes = _get_visible_hex_range()
	_cached_visible_set.clear()
	for hex in _cached_visible_hexes:
		_cached_visible_set[hex] = true
	_cached_visible_rivers.clear()
	for hex in river_cells:
		if _cached_visible_set.has(hex):
			_cached_visible_rivers.append(hex)
	_cached_visible_vertex_rivers.clear()
	for key in vertex_subs:
		var vdata: Dictionary = vertex_subs[key]
		if vdata["river"] and vdata.has("hex") and _cached_visible_set.has(vdata["hex"]):
			_cached_visible_vertex_rivers.append(key)


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
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_zoom = clampf(camera_zoom * 0.9, 0.2, 5.0)
		_invalidate_draw_cache()
		queue_redraw()
		return
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_zoom = clampf(camera_zoom * 1.1, 0.2, 5.0)
		_invalidate_draw_cache()
		queue_redraw()
		return

	if event.button_index == MOUSE_BUTTON_MIDDLE:
		panning = event.pressed
		if event.pressed:
			pan_start = event.position
		return

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
	if panning:
		var delta := event.position - pan_start
		camera_pos -= delta / camera_zoom
		pan_start = event.position
		_invalidate_draw_cache()
		queue_redraw()
		return

	if painting and tool_mode == 1:
		_paint_river_at(event.position, false)
		return
	elif erasing and tool_mode == 1:
		_paint_river_at(event.position, true)
		return

	# Idle hover: only redraw when hovered hex changes
	if tool_mode == 2 or tool_mode == 1:
		var world_pos := _screen_to_world(event.position)
		var hex := _world_to_hex(world_pos)
		if hex != _last_debug_hover_hex:
			_last_debug_hover_hex = hex
			queue_redraw()


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	match event.keycode:
		KEY_1:
			tool_mode = 0
			_last_debug_hover_hex = Vector3i(999999, 999999, -1999998)
			_invalidate_draw_cache()
			_update_ui()
			queue_redraw()
		KEY_2:
			tool_mode = 1
			_last_debug_hover_hex = Vector3i(999999, 999999, -1999998)
			_invalidate_draw_cache()
			_update_ui()
			queue_redraw()
		KEY_3:
			tool_mode = 2
			road_start = Vector3i(999999, 999999, -1999998)
			_last_debug_hover_hex = Vector3i(999999, 999999, -1999998)
			_invalidate_draw_cache()
			_update_ui()
			queue_redraw()
		KEY_H:
			show_overlay = not show_overlay
			queue_redraw()
		KEY_G:
			show_grid = not show_grid
			queue_redraw()
		KEY_V:
			show_height = not show_height
			queue_redraw()
		KEY_INSERT:
			show_elevation_shade = not show_elevation_shade
			queue_redraw()
		KEY_ESCAPE:
			tool_mode = 0
			road_start = Vector3i(999999, 999999, -1999998)
			painting = false
			erasing = false
			_last_debug_hover_hex = Vector3i(999999, 999999, -1999998)
			_invalidate_draw_cache()
			_update_ui()
			queue_redraw()
		KEY_R:
			_regenerate_map()
		KEY_F6:
			_quick_save()
		KEY_F7:
			_quick_load()
		KEY_F8:
			_save()
		KEY_F9:
			_load()


func _regenerate_map() -> void:
	cells.clear()
	chunk_manager.cells = cells
	chunk_manager._loaded_chunk_origins.clear()
	chunk_manager.randomize_seeds()
	chunks_with_rivers.clear()
	river_cells.clear()
	road_cells.clear()
	vertex_subs.clear()
	roads.clear()
	_pending_chunks.clear()
	_pending_rivers.clear()
	_needs_save = false
	_invalidate_draw_cache()
	queue_redraw()


func _save_map() -> void:
	var save_path := "res://map_save.json"
	chunk_manager.save_map(save_path, river_cells, road_cells, vertex_subs, chunks_with_rivers, roads)
	_save_map_image()


func _load_map_from(path: String) -> bool:
	var loaded: Dictionary = chunk_manager.load_map(path)
	if loaded.is_empty():
		return false
	river_cells = loaded.get("river_cells", {})
	road_cells = loaded.get("road_cells", {})
	vertex_subs = loaded.get("vertex_subs", {})
	chunks_with_rivers = loaded.get("chunks_with_rivers", {})
	roads.clear()
	for r in loaded.get("roads", []):
		roads.append(r)
	_invalidate_draw_cache()
	queue_redraw()
	return true


func _quick_save() -> void:
	_save_map()
	_tool_flash("Quick Saved")


func _quick_load() -> void:
	if _load_map_from("res://map_save.json"):
		_tool_flash("Quick Loaded")


func _save() -> void:
	chunk_manager.save_map("res://map_save_slot.json", river_cells, road_cells, vertex_subs, chunks_with_rivers, roads)
	_save_map_image()
	_tool_flash("Saved")


func _load() -> void:
	if _load_map_from("res://map_save_slot.json"):
		_tool_flash("Loaded")


func _tool_flash(msg: String) -> void:
	tool_label.text = msg
	_tool_flash_timer = 1.5


func _save_map_image() -> void:
	if cells.is_empty():
		return
	var min_q := 999999
	var max_q := -999999
	var min_r := 999999
	var max_r := -999999
	for hex in cells:
		var hq: int = int(hex.x)
		var hr: int = int(hex.y)
		min_q = mini(min_q, hq)
		max_q = maxi(max_q, hq)
		min_r = mini(min_r, hr)
		max_r = maxi(max_r, hr)
	var img_size := 8
	var w := (max_q - min_q + 1) * img_size
	var h := (max_r - min_r + 1) * img_size
	w = clampi(w, 1, 4096)
	h = clampi(h, 1, 4096)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	for hex in cells:
		var c: HexCellData = cells[hex]
		var px: int = (int(hex.x) - min_q) * img_size
		var py: int = (int(hex.y) - min_r) * img_size
		for dx in img_size:
			for dy in img_size:
				var sx: int = clampi(px + dx, 0, w - 1)
				var sy: int = clampi(py + dy, 0, h - 1)
				img.set_pixel(sx, sy, c.color)
	img.save_png("res://map_image.png")


func _paint_river_at(screen_pos: Vector2, erase: bool) -> void:
	var world_pos := _screen_to_world(screen_pos)
	var hex := _world_to_hex(world_pos)
	if erase:
		if _cell_exists(hex):
			var best_sub := 0
			var best_dist := INF
			for i in TOTAL_SUBS:
				var d := _get_sub_hex_world_pos(hex, i).distance_to(world_pos)
				if d < best_dist:
					best_dist = d
					best_sub = i
			_river_erase(hex, best_sub)
	else:
		if not _cell_exists(hex):
			_invalidate_draw_cache()
			queue_redraw()
			return
		var best_sub := 0
		var best_dist := INF
		for i in TOTAL_SUBS:
			var d := _get_sub_hex_world_pos(hex, i).distance_to(world_pos)
			if d < best_dist:
				best_dist = d
				best_sub = i
		var wn := _count_sub_hex_water_neighbors(hex, best_sub)
		if wn < 1 or wn > 2:
			_invalidate_draw_cache()
			queue_redraw()
			return
		for nb in _get_sub_hex_neighbors(hex, best_sub):
			if river_cells.has(nb["hex"]) and nb["sub"] in river_cells[nb["hex"]]:
				if _count_sub_hex_water_neighbors(nb["hex"], nb["sub"]) + 1 > 2:
					_invalidate_draw_cache()
					queue_redraw()
					return
		_river_paint(hex, best_sub)
	_invalidate_draw_cache()
	queue_redraw()


func _river_paint(hex: Vector3i, sub_idx: int) -> void:
	if sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var key := _vertex_key(hex, vi)
		if not vertex_subs.has(key):
			vertex_subs[key] = {"river": false, "road": false, "hex": hex, "vi": vi}
		vertex_subs[key]["river"] = true
		vertex_subs[key]["road"] = false
		return
	if not river_cells.has(hex):
		river_cells[hex] = []
	if sub_idx not in river_cells[hex]:
		river_cells[hex].append(sub_idx)
	if road_cells.has(hex) and sub_idx in road_cells[hex]:
		road_cells[hex].erase(sub_idx)
		if road_cells[hex].is_empty():
			road_cells.erase(hex)


func _river_erase(hex: Vector3i, sub_idx: int) -> void:
	if sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var key := _vertex_key(hex, vi)
		if vertex_subs.has(key):
			vertex_subs[key]["river"] = false
		return
	if river_cells.has(hex):
		river_cells[hex].erase(sub_idx)
		if river_cells[hex].is_empty():
			river_cells.erase(hex)


func _count_water_neighbors(hex: Vector3i) -> int:
	var count := 0
	for n in HexGridMath.cube_neighbors(hex):
		if _cell_exists(n):
			var c: HexCellData = cells[n]
			if _is_water_biome(c.biome) or river_cells.has(n):
				count += 1
	return count


func _hex_river_count(hex: Vector3i) -> int:
	return river_cells.get(hex, []).size()


func _hex_road_count(hex: Vector3i) -> int:
	return road_cells.get(hex, []).size()


func _is_hex_river(hex: Vector3i) -> bool:
	return _hex_river_count(hex) >= 2


func _is_hex_road(hex: Vector3i) -> bool:
	return _hex_road_count(hex) >= 2


func _is_sub_hex_water(hex: Vector3i, sub_idx: int) -> bool:
	if sub_idx >= VERTEX_OFFSET:
		return _is_vertex_river(hex, sub_idx - VERTEX_OFFSET)
	if not _cell_exists(hex):
		return false
	var c: HexCellData = cells[hex]
	if _is_water_biome(c.biome):
		return true
	if river_cells.has(hex) and sub_idx in river_cells[hex]:
		return true
	return false


func _get_sub_hex_neighbors(parent_hex: Vector3i, sub_idx: int) -> Array:
	var result: Array = []
	if sub_idx == 0:
		for i in 6:
			result.append({"hex": parent_hex, "sub": i + 1})
	elif sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var ring_a: int = ((vi + 5) % 6) + 1
		var ring_b: int = (vi % 6) + 1
		result.append({"hex": parent_hex, "sub": ring_a})
		result.append({"hex": parent_hex, "sub": ring_b})
	else:
		result.append({"hex": parent_hex, "sub": 0})
		var prev_sub: int = ((sub_idx - 2) % 6) + 1
		var next_sub: int = (sub_idx % 6) + 1
		result.append({"hex": parent_hex, "sub": prev_sub})
		result.append({"hex": parent_hex, "sub": next_sub})
		var dir: int = (7 - sub_idx) % 6
		var opp_sub: int = ((sub_idx + 2) % 6) + 1
		var neighbor_hex: Vector3i = parent_hex + HexGridMath.cube_direction(dir)
		result.append({"hex": neighbor_hex, "sub": opp_sub})
		var vi_a: int = sub_idx - 1
		var vi_b: int = sub_idx % 6
		result.append({"hex": parent_hex, "sub": VERTEX_OFFSET + vi_a})
		result.append({"hex": parent_hex, "sub": VERTEX_OFFSET + vi_b})
	return result


func _count_sub_hex_water_neighbors(parent_hex: Vector3i, sub_idx: int) -> int:
	var count := 0
	for nb in _get_sub_hex_neighbors(parent_hex, sub_idx):
		if _is_sub_hex_water(nb["hex"], nb["sub"]):
			count += 1
	return count


func _can_place_river(hex: Vector3i, sub_idx: int) -> Array:
	if sub_idx >= VERTEX_OFFSET:
		return _can_place_river_vertex(hex, sub_idx - VERTEX_OFFSET)
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


func _can_place_river_vertex(hex: Vector3i, vi: int) -> Array:
	var key := _vertex_key(hex, vi)
	var vdata := _get_vertex_data(key)
	if vdata["river"]:
		return [true, ""]
	var ring_a: int = ((vi + 5) % 6) + 1
	var ring_b: int = (vi % 6) + 1
	var wn := 0
	if _is_sub_hex_water(hex, ring_a):
		wn += 1
	if _is_sub_hex_water(hex, ring_b):
		wn += 1
	if wn < 1:
		return [false, "No water nb (%d)" % wn]
	for ring_sub in [ring_a, ring_b]:
		if river_cells.has(hex) and ring_sub in river_cells[hex]:
			if _count_sub_hex_water_neighbors(hex, ring_sub) + 1 > 2:
				return [false, "Would overflow nb"]
	return [true, "OK"]


func _is_sub_hex_river(hex: Vector3i, sub_idx: int) -> bool:
	if sub_idx >= VERTEX_OFFSET:
		return _is_vertex_river(hex, sub_idx - VERTEX_OFFSET)
	return river_cells.has(hex) and sub_idx in river_cells[hex]


func _road_paint(hex: Vector3i, sub_idx: int) -> void:
	if _is_sub_hex_water(hex, sub_idx):
		return
	if sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var key := _vertex_key(hex, vi)
		if not vertex_subs.has(key):
			vertex_subs[key] = {"river": false, "road": false, "hex": hex, "vi": vi}
		vertex_subs[key]["road"] = true
		return
	if not road_cells.has(hex):
		road_cells[hex] = []
	if sub_idx not in road_cells[hex]:
		road_cells[hex].append(sub_idx)


func _place_road_at(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	var hex := _world_to_hex(world_pos)
	if not _cell_exists(hex):
		return

	if road_start == Vector3i(999999, 999999, -1999998):
		road_start = hex
		_invalidate_draw_cache()
		queue_redraw()
	else:
		if hex != road_start:
			var path := HexGridMath.cube_line(road_start, hex)
			for i in range(path.size() - 1):
				roads.append({"from": path[i], "to": path[i + 1]})
				var from_hex: Vector3i = path[i]
				var to_hex: Vector3i = path[i + 1]
				_road_paint(from_hex, 0)
				_road_paint(to_hex, 0)
				var diff := to_hex - from_hex
				for d in 6:
					if HexGridMath.cube_direction(d) == diff:
						var exit_sub: int = ((6 - d) % 6) + 1
						_road_paint(from_hex, exit_sub)
						var entry_dir: int = (d + 3) % 6
						var entry_sub: int = ((6 - entry_dir) % 6) + 1
						_road_paint(to_hex, entry_sub)
						break
		road_start = Vector3i(999999, 999999, -1999998)
		_invalidate_draw_cache()
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
	return null


func _elevation_to_biome(n: float) -> int:
	if n < -0.5:
		return BIOME_DEEP_WATER
	elif n < -0.3:
		return BIOME_WATER
	elif n < -0.15:
		return BIOME_BEACH
	elif n < 0.2:
		return BIOME_GRASS
	elif n < 0.4:
		return BIOME_DIRT
	else:
		return BIOME_STONE


func _elevation_to_color(e: float) -> Color:
	var t: float = clampf((e + 1.0) * 0.5, 0.0, 1.0)
	return Color(t, t, t, 0.4)


# ============================================================================
# CHUNK RIVER GENERATION
# ============================================================================
func _chunk_key(hex: Vector3i) -> Vector2i:
	return Vector2i(floori(float(hex.x) / CHUNK_SIZE), floori(float(hex.y) / CHUNK_SIZE))


func _ensure_chunk_rivers(chunk_origin: Vector2i) -> void:
	var key := chunk_origin
	if chunks_with_rivers.has(key):
		return
	chunks_with_rivers[key] = true

	if not chunk_manager._loaded_chunk_origins.has(chunk_origin):
		chunk_manager.generate_batch([chunk_origin])

	var cells_in_chunk: Array[Vector3i] = []
	for q in range(chunk_origin.x * CHUNK_SIZE, (chunk_origin.x + 1) * CHUNK_SIZE):
		for r in range(chunk_origin.y * CHUNK_SIZE, (chunk_origin.y + 1) * CHUNK_SIZE):
			var hex := Vector3i(q, r, -q - r)
			if _cell_exists(hex):
				cells_in_chunk.append(hex)

	if cells_in_chunk.is_empty():
		return

	var elevations: Array[float] = []
	for hex in cells_in_chunk:
		elevations.append(cells[hex].elevation)
	elevations.sort()
	var threshold_idx: int = int(elevations.size() * RIVER_SOURCE_PERCENTILE)
	if threshold_idx >= elevations.size():
		threshold_idx = elevations.size() - 1
	var threshold: float = elevations[threshold_idx]

	var candidates: Array[Vector3i] = []
	for hex in cells_in_chunk:
		var c: HexCellData = cells[hex]
		if c.elevation >= threshold and not _is_water_biome(c.biome):
			var adj_water: bool = false
			for nb in HexGridMath.cube_neighbors(hex):
				if _cell_exists(nb) and _is_water_biome(cells[nb].biome):
					adj_water = true
					break
			if not adj_water:
				candidates.append(hex)

	candidates.shuffle()
	var chunk_paths: Array[Array] = []
	var rivers_placed: int = 0
	for source in candidates:
		if rivers_placed >= MAX_RIVERS_PER_CHUNK:
			break
		var path := _flow_river(source)
		if path.size() >= 3:
			var end_cell: HexCellData = cells[path[-1]]
			var reached_water: bool = _is_water_biome(end_cell.biome)
			if not reached_water:
				var basin := _flood_fill_basin(path[-1])
				if basin.size() >= MIN_LAKE_SIZE:
					for whex in basin:
						var wc: HexCellData = cells[whex]
						wc.biome = BIOME_LAKE
						wc.color = BIOME_COLORS[BIOME_LAKE]
						_set_flat_water_heights(wc, LAKE_LEVEL)
						river_cells.erase(whex)
						road_cells.erase(whex)
						for vi in 6:
							var vkey := _vertex_key(whex, vi)
							if vertex_subs.has(vkey):
								vertex_subs[vkey]["river"] = false
								vertex_subs[vkey]["road"] = false
			_paint_river_path(path)
			chunk_paths.append(path)
			rivers_placed += 1

	_post_process_rivers(chunk_paths, cells_in_chunk)


func _is_water_biome(biome: int) -> bool:
	return biome == BIOME_WATER or biome == BIOME_DEEP_WATER or biome == BIOME_LAKE


func _set_flat_water_heights(cell: HexCellData, level: float) -> void:
	for i in TOTAL_SUBS:
		cell.sub_heights[i] = snappedf(level, 0.1)
	cell.elevation = snappedf(level, 0.1)


func _post_process_rivers(chunk_paths: Array[Array], cells_in_chunk: Array[Vector3i]) -> void:
	if chunk_paths.is_empty():
		return

	var total_len: int = 0
	for p in chunk_paths:
		total_len += p.size()
	var avg_len: float = float(total_len) / float(chunk_paths.size())

	for path in chunk_paths:
		var end_cell: HexCellData = cells[path[-1]]
		var reaches_water: bool = _is_water_biome(end_cell.biome)
		if not reaches_water or float(path.size()) <= avg_len:
			_undo_river_path(path)
		else:
			_convert_river_to_water(path)

	var changed := true
	while changed:
		changed = false
		var to_water: Array[Vector3i] = []
		for hex in cells_in_chunk:
			if not _cell_exists(hex):
				continue
			if _is_water_biome(cells[hex].biome):
				continue
			var wn := 0
			for nb in HexGridMath.cube_neighbors(hex):
				if _cell_exists(nb) and _is_water_biome(cells[nb].biome):
					wn += 1
			if wn >= 5:
				to_water.append(hex)
		for hex in to_water:
			var c: HexCellData = cells[hex]
			c.biome = BIOME_WATER
			c.color = BIOME_COLORS[BIOME_WATER]
			_set_flat_water_heights(c, WATER_LEVEL)
			river_cells.erase(hex)
			road_cells.erase(hex)
			for vi in 6:
				var vkey := _vertex_key(hex, vi)
				if vertex_subs.has(vkey):
					vertex_subs[vkey]["river"] = false
					vertex_subs[vkey]["road"] = false
		if to_water.size() > 0:
			changed = true

	var ocean_connected: Dictionary = {}
	var queue: Array[Vector3i] = []
	for hex in cells_in_chunk:
		if not _cell_exists(hex):
			continue
		if cells[hex].biome == BIOME_DEEP_WATER:
			ocean_connected[hex] = true
			queue.append(hex)
	for hex in cells_in_chunk:
		if not _cell_exists(hex):
			continue
		if cells[hex].biome == BIOME_WATER and not ocean_connected.has(hex):
			var adj_ocean: bool = false
			for nb in HexGridMath.cube_neighbors(hex):
				if _cell_exists(nb) and cells[nb].biome == BIOME_DEEP_WATER:
					adj_ocean = true
					break
			if adj_ocean:
				ocean_connected[hex] = true
				queue.append(hex)
	while queue.size() > 0:
		var h: Vector3i = queue.pop_back()
		for nb in HexGridMath.cube_neighbors(h):
			if ocean_connected.has(nb):
				continue
			if not _cell_exists(nb):
				continue
			if cells[nb].biome == BIOME_WATER:
				ocean_connected[nb] = true
				queue.append(nb)
	for hex in cells_in_chunk:
		if ocean_connected.has(hex):
			continue
		if not _cell_exists(hex):
			continue
		var c: HexCellData = cells[hex]
		if c.biome == BIOME_WATER:
			c.biome = BIOME_LAKE
			c.color = BIOME_COLORS[BIOME_LAKE]
			_set_flat_water_heights(c, LAKE_LEVEL)

	for hex in cells_in_chunk:
		if not _cell_exists(hex):
			continue
		if not _is_water_biome(cells[hex].biome):
			continue
		river_cells.erase(hex)
		for vi in 6:
			var vkey := _vertex_key(hex, vi)
			if vertex_subs.has(vkey):
				vertex_subs[vkey]["river"] = false


func _undo_river_path(path: Array[Vector3i]) -> void:
	for idx in path.size():
		var hex: Vector3i = path[idx]
		if not _cell_exists(hex):
			continue
		if _is_water_biome(cells[hex].biome):
			continue
		_river_erase(hex, 0)
		if idx < path.size() - 1:
			var diff: Vector3i = path[idx + 1] - hex
			for d in 6:
				if HexGridMath.cube_direction(d) == diff:
					_river_erase(hex, ((6 - d) % 6) + 1)
					break
		if idx > 0:
			var diff: Vector3i = hex - path[idx - 1]
			for d in 6:
				if HexGridMath.cube_direction(d) == diff:
					var entry_dir: int = (d + 3) % 6
					_river_erase(hex, ((6 - entry_dir) % 6) + 1)
					break


func _convert_river_to_water(path: Array[Vector3i]) -> void:
	for hex in path:
		if not _cell_exists(hex):
			continue
		if _is_water_biome(cells[hex].biome):
			continue
		var c: HexCellData = cells[hex]
		c.biome = BIOME_WATER
		c.color = BIOME_COLORS[BIOME_WATER]
		_set_flat_water_heights(c, WATER_LEVEL)


func _flood_fill_basin(start: Vector3i) -> Array[Vector3i]:
	var MAX_BASIN: int = MIN_LAKE_SIZE * 3
	var basin: Array[Vector3i] = []
	var queue: Array[Vector3i] = [start]
	var visited: Dictionary = {start: true}
	var max_elev: float = cells[start].elevation
	while queue.size() > 0:
		if basin.size() >= MAX_BASIN:
			break
		var h: Vector3i = queue.pop_back()
		basin.append(h)
		for nb in HexGridMath.cube_neighbors(h):
			if visited.has(nb):
				continue
			if not _cell_exists(nb):
				continue
			var nc: HexCellData = cells[nb]
			if _is_water_biome(nc.biome):
				continue
			if nc.elevation <= max_elev:
				visited[nb] = true
				queue.append(nb)
	return basin


func _flow_river(start: Vector3i) -> Array[Vector3i]:
	if _cell_exists(start) and _is_water_biome(cells[start].biome):
		return []

	var path: Array[Vector3i] = [start]
	var current := start
	var visited: Dictionary = {start: true}
	var UP_PENALTY: float = 8.0
	var MAX_STEPS: int = 150

	for _step in MAX_STEPS:
		var c: HexCellData = cells[current]

		if _is_water_biome(c.biome):
			return path

		var neighbors: Array = []
		for nb in HexGridMath.cube_neighbors(current):
			if _cell_exists(nb):
				neighbors.append(nb)
		if neighbors.is_empty():
			break
		neighbors.sort_custom(func(a, b): return cells[a].elevation < cells[b].elevation)

		var found_downhill: bool = false
		for nb in neighbors:
			if visited.has(nb):
				continue
			if cells[nb].elevation < c.elevation:
				visited[nb] = true
				path.append(nb)
				current = nb
				found_downhill = true
				break

		if found_downhill:
			continue

		var basin_path := _flow_escape_basin(current, visited, UP_PENALTY)
		if basin_path.size() > 1:
			for i in range(1, basin_path.size()):
				var nh: Vector3i = basin_path[i]
				visited[nh] = true
				path.append(nh)
				current = nh
				if _is_water_biome(cells[current].biome):
					return path
		else:
			break

	return path


func _flow_escape_basin(from: Vector3i, global_visited: Dictionary, up_penalty: float) -> Array[Vector3i]:
	var MAX_ESCAPE: int = 50
	var open: Array = []
	var g_cost: Dictionary = {from: 0.0}
	var came_from: Dictionary = {}
	var closed: Dictionary = {}
	var lowest_hex: Vector3i = from
	var lowest_elev: float = cells[from].elevation

	open.append([0.0, from])

	while open.size() > 0:
		var best_idx: int = 0
		for i in range(1, open.size()):
			if open[i][0] < open[best_idx][0]:
				best_idx = i
		var current: Vector3i = open[best_idx][1]
		open.remove_at(best_idx)

		if closed.has(current):
			continue
		closed[current] = true

		if global_visited.has(current) and current != from:
			continue

		var c_cell: HexCellData = cells[current]

		if _is_water_biome(c_cell.biome):
			var result: Array[Vector3i] = [current]
			var trace := current
			while came_from.has(trace):
				trace = came_from[trace]
				result.append(trace)
			result.reverse()
			return result

		if c_cell.elevation < lowest_elev:
			lowest_elev = c_cell.elevation
			lowest_hex = current

		if closed.size() >= MAX_ESCAPE:
			break

		for nb in HexGridMath.cube_neighbors(current):
			if closed.has(nb) or global_visited.has(nb):
				continue
			if not _cell_exists(nb):
				continue
			var nb_cell: HexCellData = cells[nb]
			var elev_diff: float = nb_cell.elevation - c_cell.elevation
			var move_cost: float = 1.0 + maxf(0.0, elev_diff) * up_penalty
			var new_g: float = g_cost[current] + move_cost
			if not g_cost.has(nb) or new_g < g_cost[nb]:
				g_cost[nb] = new_g
				came_from[nb] = current
				open.append([new_g, nb])

	if lowest_hex != from and came_from.has(lowest_hex):
		var result: Array[Vector3i] = [lowest_hex]
		var trace := lowest_hex
		while came_from.has(trace):
			trace = came_from[trace]
			result.append(trace)
		result.reverse()
		return result

	return []


func _paint_river_path(path: Array[Vector3i]) -> void:
	for idx in path.size():
		var hex: Vector3i = path[idx]
		if not _cell_exists(hex):
			continue
		var c: HexCellData = cells[hex]
		if _is_water_biome(c.biome):
			continue
		_river_paint(hex, 0)
		if idx < path.size() - 1:
			var next: Vector3i = path[idx + 1]
			var diff := next - hex
			for d in 6:
				if HexGridMath.cube_direction(d) == diff:
					var exit_sub: int = ((6 - d) % 6) + 1
					_river_paint(hex, exit_sub)
					break
		if idx > 0:
			var prev: Vector3i = path[idx - 1]
			var diff := hex - prev
			for d in 6:
				if HexGridMath.cube_direction(d) == diff:
					var entry_dir: int = (d + 3) % 6
					var entry_sub: int = ((6 - entry_dir) % 6) + 1
					_river_paint(hex, entry_sub)
					break


# ============================================================================
# SUB-HEX POSITIONS
# ============================================================================
func _get_sub_hex_world_pos(parent_hex: Vector3i, sub_idx: int) -> Vector2:
	var parent_world := HexGridMath.cube_to_world_flat_top(parent_hex, HEX_SIZE)
	var parent_2d := Vector2(parent_world.x, parent_world.z)
	if sub_idx == 0:
		return parent_2d
	elif sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var angle := deg_to_rad(60.0 * float(vi))
		return parent_2d + Vector2(cos(angle), sin(angle)) * HEX_SIZE
	else:
		var angle := deg_to_rad(30.0 + 60.0 * float(sub_idx - 1))
		return parent_2d + Vector2(cos(angle), sin(angle)) * SUB_HEX_DIST


func _get_sub_hex_screen_pos(parent_hex: Vector3i, sub_idx: int) -> Vector2:
	return _world_to_screen(_get_sub_hex_world_pos(parent_hex, sub_idx))


func _vertex_key(hex: Vector3i, vi: int) -> int:
	var dirs: Array = VERTEX_NEIGHBORS[vi]
	var h1 := hex
	var h2 := hex + HexGridMath.cube_direction(dirs[0])
	var h3 := hex + HexGridMath.cube_direction(dirs[1])
	var hx: int = mini(mini(h1.x, h2.x), h3.x)
	var hy: int = mini(mini(h1.y, h2.y), h3.y)
	var hz: int = mini(mini(h1.z, h2.z), h3.z)
	return hx * 1000003 + hy * 1009 + hz


func _get_vertex_data(key: int) -> Dictionary:
	if vertex_subs.has(key):
		return vertex_subs[key]
	return {"river": false, "road": false}


func _is_vertex_river(hex: Vector3i, vi: int) -> bool:
	return _get_vertex_data(_vertex_key(hex, vi))["river"]


func _is_vertex_road(hex: Vector3i, vi: int) -> bool:
	return _get_vertex_data(_vertex_key(hex, vi))["road"]


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

	var c00 := _world_to_hex(tl)
	var c10 := _world_to_hex(Vector2(br.x, tl.y))
	var c01 := _world_to_hex(Vector2(tl.x, br.y))
	var c11 := _world_to_hex(br)

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

	min_q -= 2
	max_q += 2
	min_r -= 2
	max_r += 2

	var result: Array[Vector3i] = []
	for q in range(min_q, max_q + 1):
		for r in range(min_r, max_r + 1):
			var s := -q - r
			var hex := Vector3i(q, r, s)
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
	_ensure_draw_cache()
	var visible_hexes := _cached_visible_hexes
	var visible_set := _cached_visible_set

	for hex in visible_hexes:
		if not _cell_exists(hex):
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var screen_pos := _world_to_screen(Vector2(hpos.x, hpos.z))
		var corners := _hex_corners(screen_pos, HEX_SIZE * camera_zoom)
		var draw_color := cell.color
		draw_colored_polygon(corners, draw_color)
		if show_elevation_shade:
			var elev_col := _elevation_to_color(cell.elevation)
			draw_colored_polygon(corners, elev_col)
		if show_grid:
			var grid_color := Color(0, 0, 0, 0.15)
			draw_polyline(corners + PackedVector2Array([corners[0]]), grid_color, 1.0)

	if show_height:
		for hex in visible_hexes:
			if not _cell_exists(hex):
				continue
			var cell: HexCellData = cells[hex]
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			var screen_pos := _world_to_screen(Vector2(hpos.x, hpos.z))
			var corners := _hex_corners(screen_pos, HEX_SIZE * camera_zoom)
			var brightness: float = lerpf(0.4, 1.6, (cell.elevation + 1.0) * 0.5)
			var col := Color(brightness, brightness, brightness, 0.35)
			draw_colored_polygon(corners, col)

	if show_overlay:
		for hex in visible_hexes:
			_draw_sub_hex_overlay(hex)

	for hex in _cached_visible_rivers:
		_draw_river_hex(hex)

	for key in _cached_visible_vertex_rivers:
		_draw_vertex_river(key)

	for road in roads:
		if visible_set.has(road["from"]) or visible_set.has(road["to"]):
			_draw_road_line(road["from"], road["to"])

	if tool_mode == 2 and road_start != Vector3i(999999, 999999, -1999998) and _cell_exists(road_start):
		var mouse_screen := get_viewport().get_mouse_position()
		var mouse_world := _screen_to_world(mouse_screen)
		var mouse_hex := _world_to_hex(mouse_world)
		if _cell_exists(mouse_hex):
			var path := HexGridMath.cube_line(road_start, mouse_hex)
			for i in range(path.size() - 1):
				_draw_road_line(path[i], path[i + 1], Color(1, 1, 0.5, 0.4))
		var start_screen := _world_to_screen(cells[road_start].get_world_position(HEX_SIZE))
		draw_circle(start_screen, 6.0, Color(1, 1, 0.2, 0.8))

	if tool_mode == 1:
		_draw_river_debug()


func _draw_river_debug() -> void:
	var mouse_screen := get_viewport().get_mouse_position()
	var mouse_world := _screen_to_world(mouse_screen)
	var hex := _world_to_hex(mouse_world)
	if not _cell_exists(hex):
		return
	var best_sub := 0
	var best_dist := INF
	for i in TOTAL_SUBS:
		var d := _get_sub_hex_world_pos(hex, i).distance_to(mouse_world)
		if d < best_dist:
			best_dist = d
			best_sub = i
	for i in TOTAL_SUBS:
		var result: Array = _can_place_river(hex, i)
		var ok: bool = result[0]
		var sub_screen := _get_sub_hex_screen_pos(hex, i)
		var sz := SUB_HEX_SIZE * camera_zoom
		var sub_corners := _hex_corners(sub_screen, sz)
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
	var can_place := _can_place_river(hex, best_sub)
	if not can_place[0]:
		var reason: String = can_place[1]
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
	for i in TOTAL_SUBS:
		var sub_screen := _get_sub_hex_screen_pos(hex, i)
		var sz := SUB_HEX_SIZE * camera_zoom
		var sub_corners := _hex_corners(sub_screen, sz)
		var fill := Color(1, 1, 1, 0.05)
		draw_colored_polygon(sub_corners, fill)
		draw_polyline(sub_corners + PackedVector2Array([sub_corners[0]]), Color(1, 1, 1, 0.2), 1.0)


func _draw_river_hex(hex: Vector3i) -> void:
	if not river_cells.has(hex) or not _cell_exists(hex):
		return
	for sub_idx in river_cells[hex]:
		var sub_screen := _get_sub_hex_screen_pos(hex, sub_idx)
		var sub_corners := _hex_corners(sub_screen, SUB_HEX_SIZE * camera_zoom)
		draw_colored_polygon(sub_corners, Color(0.2, 0.45, 0.75, 0.7))
		draw_polyline(sub_corners + PackedVector2Array([sub_corners[0]]), Color(0.15, 0.3, 0.6, 0.9), 1.5)


func _draw_vertex_river(key: int) -> void:
	var vdata: Dictionary = _get_vertex_data(key)
	if not vdata.has("hex") or not vdata.has("vi"):
		return
	var hex: Vector3i = vdata["hex"]
	var vi: int = vdata["vi"]
	var sub_screen := _get_sub_hex_screen_pos(hex, VERTEX_OFFSET + vi)
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

	if not _is_sub_hex_water(from_hex, 0):
		_draw_filled_sub(from_hex, 0, col)

	if dir >= 0:
		var exit_sub := ((6 - dir) % 6) + 1
		if not _is_sub_hex_water(from_hex, exit_sub):
			_draw_filled_sub(from_hex, exit_sub, col)
		var entry_dir := (dir + 3) % 6
		var entry_sub := ((6 - entry_dir) % 6) + 1
		if not _is_sub_hex_water(to_hex, entry_sub):
			_draw_filled_sub(to_hex, entry_sub, col)

	if not _is_sub_hex_water(to_hex, 0):
		_draw_filled_sub(to_hex, 0, col)


func _draw_filled_sub(hex: Vector3i, sub_idx: int, col: Color) -> void:
	var sub_screen := _get_sub_hex_screen_pos(hex, sub_idx)
	var sub_corners := _hex_corners(sub_screen, SUB_HEX_SIZE * camera_zoom)
	draw_colored_polygon(sub_corners, col)
