class_name ChunkManager
extends RefCounted

const CHUNK_SIZE: int = 10
const TOTAL_SUBS: int = 13
const MAX_BATCH: int = 256
const HEX_SIZE: float = 1.1547

const BIOME_DEEP_WATER := 0
const BIOME_WATER := 1
const BIOME_BEACH := 2
const BIOME_GRASS := 3
const BIOME_DIRT := 4
const BIOME_STONE := 5

const BIOME_COLORS: Array = [
	Color(0.18, 0.35, 0.65),
	Color(0.28, 0.52, 0.78),
	Color(0.82, 0.77, 0.55),
	Color(0.35, 0.55, 0.28),
	Color(0.55, 0.42, 0.28),
	Color(0.48, 0.48, 0.48),
	Color(0.32, 0.55, 0.82),
]

var noise_freq: float = 0.03
var noise_seed: int = 42
var detail_freq: float = 0.1
var detail_seed: int = 1042
var fractal_octaves: int = 3
var fractal_lacunarity: float = 2.0
var fractal_gain: float = 0.3
var detail_octaves: int = 3
var detail_lacunarity: float = 2.0
var detail_gain: float = 0.3

var _noise: FastNoiseLite
var _detail_noise: FastNoiseLite


func randomize_seeds() -> void:
	noise_seed = randi()
	detail_seed = randi()
	noise_freq = randf_range(0.015, 0.06)
	detail_freq = randf_range(0.05, 0.2)
	_init_noise()

var cells: Dictionary
var _loaded_chunk_origins: Dictionary = {}
var _last_batch_generated: bool = false


func _init(p_cells: Dictionary) -> void:
	cells = p_cells
	_init_noise()


func _init_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = noise_seed
	_noise.frequency = noise_freq
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = fractal_octaves
	_noise.fractal_lacunarity = fractal_lacunarity
	_noise.fractal_gain = fractal_gain
	_detail_noise = FastNoiseLite.new()
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.seed = detail_seed
	_detail_noise.frequency = detail_freq
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail_noise.fractal_octaves = detail_octaves
	_detail_noise.fractal_lacunarity = detail_lacunarity
	_detail_noise.fractal_gain = detail_gain
	print("ChunkManager: CPU FastNoiseLite initialized, freq=%.4f octaves=%d gain=%.2f" % [noise_freq, fractal_octaves, fractal_gain])


func cleanup() -> void:
	pass


func is_initialized() -> bool:
	return _noise != null


func generate_batch(batch: Array) -> void:
	if batch.is_empty() or not is_initialized():
		return
	var bs := mini(batch.size(), MAX_BATCH)
	_generate_batch_cpu(batch, bs)
	_last_batch_generated = true


func save_map(path: String, p_river_cells: Dictionary = {}, p_road_cells: Dictionary = {}, p_vertex_subs: Dictionary = {}, p_chunks_with_rivers: Dictionary = {}, p_roads: Array = [], p_blocks: Dictionary = {}, p_objects: Dictionary = {}) -> void:
	var data: Dictionary = {
		"noise": {
			"freq": noise_freq,
			"seed": noise_seed,
			"detail_freq": detail_freq,
			"detail_seed": detail_seed,
			"octaves": fractal_octaves,
			"lacunarity": fractal_lacunarity,
			"gain": fractal_gain,
			"detail_octaves": detail_octaves,
			"detail_lacunarity": detail_lacunarity,
			"detail_gain": detail_gain,
		},
		"cells": {},
		"rivers": {},
		"roads": {},
		"road_list": [],
		"vertex_subs": {},
		"chunks_with_rivers": [],
		"blocks": [],
		"objects": {},
	}
	for key in cells:
		var c: HexCellData = cells[key]
		var sh_rounded: Array = []
		for h in c.sub_heights:
			sh_rounded.push_back(snappedf(h, 0.01))
		data["cells"][str(key)] = {
			"q": key.x, "r": key.y, "s": key.z,
			"biome": c.biome,
			"elevation": snappedf(c.elevation, 0.01),
			"color": [snappedf(c.color.r, 0.01), snappedf(c.color.g, 0.01), snappedf(c.color.b, 0.01)],
			"sub_heights": sh_rounded,
		}
	for hex_key in p_river_cells:
		data["rivers"][str(hex_key)] = p_river_cells[hex_key]
	for hex_key in p_road_cells:
		data["roads"][str(hex_key)] = p_road_cells[hex_key]
	for road in p_roads:
		data["road_list"].append({"from": [road["from"].x, road["from"].y, road["from"].z], "to": [road["to"].x, road["to"].y, road["to"].z]})
	for vkey in p_vertex_subs:
		var vd: Dictionary = p_vertex_subs[vkey]
		data["vertex_subs"][str(vkey)] = {"river": vd["river"], "road": vd["road"], "hex": [vd["hex"].x, vd["hex"].y, vd["hex"].z], "vi": vd["vi"]}
	for ck in p_chunks_with_rivers:
		data["chunks_with_rivers"].append([ck.x, ck.y])
	for b_hex in p_blocks:
		data["blocks"].append([b_hex.x, b_hex.y, b_hex.z])
	for o_hex in p_objects:
		data["objects"][str(o_hex)] = p_objects[o_hex]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ChunkManager: Cannot write to " + path)
		return
	f.store_string(JSON.stringify(data))
	f.close()


func load_map(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	f.close()
	if err != OK:
		push_error("ChunkManager: JSON parse error in " + path)
		return {}
	var root: Dictionary = json.data
	if not root is Dictionary:
		return {}
	# Restore noise params
	if root.has("noise"):
		var n: Dictionary = root["noise"]
		noise_freq = n.get("freq", noise_freq)
		noise_seed = n.get("seed", noise_seed)
		detail_freq = n.get("detail_freq", detail_freq)
		detail_seed = n.get("detail_seed", detail_seed)
		fractal_octaves = n.get("octaves", fractal_octaves)
		fractal_lacunarity = n.get("lacunarity", fractal_lacunarity)
		fractal_gain = n.get("gain", fractal_gain)
		detail_octaves = n.get("detail_octaves", detail_octaves)
		detail_lacunarity = n.get("detail_lacunarity", detail_lacunarity)
		detail_gain = n.get("detail_gain", detail_gain)
		_init_noise()
	# Handle both old format (flat dict of cells) and new format (dict with "cells" key)
	var cells_data: Dictionary
	if root.has("cells"):
		cells_data = root["cells"]
	else:
		cells_data = root
	cells.clear()
	_loaded_chunk_origins.clear()
	for key_str in cells_data:
		var d: Dictionary = cells_data[key_str]
		var q: int = d["q"]
		var r: int = d["r"]
		var s: int = d["s"]
		var hex := Vector3i(q, r, s)
		var c := HexCellData.new(hex, d["biome"], d["elevation"])
		var col: Array = d["color"]
		c.color = Color(col[0], col[1], col[2])
		var sh: Array = d["sub_heights"]
		for i in TOTAL_SUBS:
			c.sub_heights[i] = sh[i]
		cells[hex] = c
		var ck := Vector2i(floori(float(q) / CHUNK_SIZE), floori(float(r) / CHUNK_SIZE))
		_loaded_chunk_origins[ck] = true
	# Restore river/road data
	var result: Dictionary = {}
	var river_cells: Dictionary = {}
	var rivers_data: Dictionary = root.get("rivers", {}) as Dictionary
	for key_str in rivers_data:
		var key_string: String = str(key_str)
		var stripped: String = key_string.strip_edges().replace("(", "").replace(")", "")
		var parts: PackedStringArray = stripped.split(",")
		if parts.size() >= 3:
			var hex := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
			river_cells[hex] = rivers_data[key_str]
	result["river_cells"] = river_cells
	var road_cells: Dictionary = {}
	var roads_data: Dictionary = root.get("roads", {}) as Dictionary
	for key_str in roads_data:
		var key_string: String = str(key_str)
		var stripped: String = key_string.strip_edges().replace("(", "").replace(")", "")
		var parts: PackedStringArray = stripped.split(",")
		if parts.size() >= 3:
			var hex := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
			road_cells[hex] = roads_data[key_str]
	result["road_cells"] = road_cells
	var vertex_subs: Dictionary = {}
	for key_str in root.get("vertex_subs", {}):
		var vd: Dictionary = root["vertex_subs"][key_str]
		var hx: Array = vd["hex"]
		var hex := Vector3i(hx[0], hx[1], hx[2])
		var vkey_int: int = int(key_str)
		vertex_subs[vkey_int] = {"river": vd["river"], "road": vd["road"], "hex": hex, "vi": vd["vi"]}
	result["vertex_subs"] = vertex_subs
	var chunks_with_rivers: Dictionary = {}
	for ck_arr in root.get("chunks_with_rivers", []):
		chunks_with_rivers[Vector2i(ck_arr[0], ck_arr[1])] = true
	result["chunks_with_rivers"] = chunks_with_rivers
	var roads: Array = []
	for road_entry in root.get("road_list", []):
		var f_arr: Array = road_entry["from"]
		var t_arr: Array = road_entry["to"]
		roads.append({"from": Vector3i(f_arr[0], f_arr[1], f_arr[2]), "to": Vector3i(t_arr[0], t_arr[1], t_arr[2])})
	result["roads"] = roads
	var blocks: Dictionary = {}
	for b_arr in root.get("blocks", []):
		blocks[Vector3i(b_arr[0], b_arr[1], b_arr[2])] = true
	result["blocks"] = blocks
	var objects: Dictionary = {}
	for key_str in root.get("objects", {}):
		var key_string: String = str(key_str)
		var stripped: String = key_string.strip_edges().replace("(", "").replace(")", "")
		var parts: PackedStringArray = stripped.split(",")
		if parts.size() >= 3:
			var hex := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
			objects[hex] = root["objects"][key_str]
	result["objects"] = objects
	return result


func _generate_batch_cpu(batch: Array, bs: int) -> void:
	for ci in bs:
		var ck: Vector2i = batch[ci]
		if _loaded_chunk_origins.has(ck):
			continue
		_loaded_chunk_origins[ck] = true
		var base_q: int = ck.x * CHUNK_SIZE
		var base_r: int = ck.y * CHUNK_SIZE
		var min_elev := 999.0
		var max_elev := -999.0
		var biome_counts := {}
		for cx in CHUNK_SIZE:
			for cy in CHUNK_SIZE:
				var q: int = base_q + cx
				var r: int = base_r + cy
				var hex := Vector3i(q, r, -q - r)
				if cells.has(hex):
					continue
				var nval: float = _noise.get_noise_2d(float(q), float(r))
				var biome: int = _classify_biome(nval)
				var elevation: float = _remap_elevation(biome, nval)
				var cell := HexCellData.new(hex, biome, elevation)
				cell.color = BIOME_COLORS[clampi(biome, 0, BIOME_COLORS.size() - 1)]
				cell.sub_heights[0] = elevation
				const INNER_DIST: float = HEX_SIZE * 0.57735026919
				const OUTER_DIST: float = HEX_SIZE
				for i in 6:
					var angle: float = deg_to_rad(30.0 + 60.0 * float(i))
					var sub_q: float = float(q) + cos(angle) * INNER_DIST
					var sub_r: float = float(r) + sin(angle) * INNER_DIST
					var detail: float = _detail_noise.get_noise_2d(sub_q, sub_r) * 0.15
					cell.sub_heights[i + 1] = elevation + detail
				for i in 6:
					var angle: float = deg_to_rad(60.0 * float(i))
					var sub_q: float = float(q) + cos(angle) * OUTER_DIST
					var sub_r: float = float(r) + sin(angle) * OUTER_DIST
					var detail: float = _detail_noise.get_noise_2d(sub_q, sub_r) * 0.15
					cell.sub_heights[i + 7] = elevation + detail
				cells[hex] = cell
				if elevation < min_elev: min_elev = elevation
				if elevation > max_elev: max_elev = elevation
				biome_counts[biome] = biome_counts.get(biome, 0) + 1
		print("ChunkManager: batch elev=[%.3f, %.3f] biomes=%s freq=%.4f" % [min_elev, max_elev, biome_counts, noise_freq])


func _classify_biome(nval: float) -> int:
	if nval < -0.3:
		return BIOME_DEEP_WATER
	elif nval < -0.1:
		return BIOME_WATER
	elif nval < 0.1:
		return BIOME_BEACH
	elif nval < 0.4:
		return BIOME_GRASS
	elif nval < 0.7:
		return BIOME_DIRT
	else:
		return BIOME_STONE


func _remap_elevation(biome: int, nval: float) -> float:
	match biome:
		BIOME_DEEP_WATER:
			return remap(nval, -1.0, -0.3, 0.1, 0.3)
		BIOME_WATER:
			return remap(nval, -0.3, -0.1, 0.15, 0.5)
		BIOME_BEACH:
			return remap(nval, -0.1, 0.1, 0.4, 0.7)
		BIOME_GRASS:
			return remap(nval, 0.1, 0.4, 0.7, 1.8)
		BIOME_DIRT:
			return remap(nval, 0.4, 0.7, 1.4, 2.8)
		BIOME_STONE:
			return remap(nval, 0.7, 1.4, 2.2, 4.0)
		_:
			return remap(nval, -1.0, 1.0, 0.3, 3.0)
