class_name ChunkManager
extends RefCounted

const CHUNK_SIZE: int = 10
const TOTAL_SUBS: int = 13
const CELLS_PER_CHUNK: int = CHUNK_SIZE * CHUNK_SIZE
const VALUES_PER_CELL: int = 15
const MAX_BATCH: int = 256

const BIOME_COLORS: Array = [
	Color(0.18, 0.35, 0.65),
	Color(0.28, 0.52, 0.78),
	Color(0.82, 0.77, 0.55),
	Color(0.35, 0.55, 0.28),
	Color(0.55, 0.42, 0.28),
	Color(0.48, 0.48, 0.48),
	Color(0.32, 0.55, 0.82),
]

var noise_freq: float = 0.008
var noise_seed: int = 42
var detail_freq: float = 0.032
var detail_seed: int = 1042
var fractal_octaves: int = 5
var fractal_lacunarity: float = 2.0
var fractal_gain: float = 0.5
var detail_octaves: int = 3
var detail_lacunarity: float = 2.0
var detail_gain: float = 0.4


func randomize_seeds() -> void:
	noise_seed = randi()
	detail_seed = randi()
	noise_freq = randf_range(0.004, 0.015)
	detail_freq = randf_range(0.02, 0.06)

var cells: Dictionary
var _loaded_chunk_origins: Dictionary = {}
var _rd: RenderingDevice
var _shader_rid: RID
var _pipeline: RID
var _params_buf: RID
var _origins_buf: RID
var _output_buf: RID
var _uniform_set: RID
var _last_batch_generated: bool = false


func _init(p_cells: Dictionary) -> void:
	cells = p_cells
	_rd = RenderingServer.create_local_rendering_device()
	_init_compute()


func _init_compute() -> void:
	var f = FileAccess.open("res://shaders/compute_noise.spv", FileAccess.READ)
	if f == null:
		push_error("ChunkManager: Cannot open compute_noise.spv")
		return
	var raw_bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()

	var spirv = RDShaderSPIRV.new()
	spirv.set_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE, raw_bytes)

	_shader_rid = _rd.shader_create_from_spirv(spirv)
	if not _shader_rid.is_valid():
		push_error("ChunkManager: Failed to create shader RID from SPIR-V")
		return
	_pipeline = _rd.compute_pipeline_create(_shader_rid)
	if not _pipeline.is_valid():
		push_error("ChunkManager: Failed to create compute pipeline")
		return

	_params_buf = _rd.storage_buffer_create(64)
	_origins_buf = _rd.storage_buffer_create(MAX_BATCH * 2 * 4)
	_output_buf = _rd.storage_buffer_create(MAX_BATCH * CELLS_PER_CHUNK * VALUES_PER_CELL * 4)
	_rebuild_uniform_set()


func _rebuild_uniform_set() -> void:
	var u_params := RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_params.binding = 0
	u_params.add_id(_params_buf)
	var u_origins := RDUniform.new()
	u_origins.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_origins.binding = 1
	u_origins.add_id(_origins_buf)
	var u_output := RDUniform.new()
	u_output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_output.binding = 2
	u_output.add_id(_output_buf)
	_uniform_set = _rd.uniform_set_create([u_params, u_origins, u_output], _shader_rid, 0)


func cleanup() -> void:
	if _uniform_set.is_valid():
		_rd.free_rid(_uniform_set)
		_uniform_set = RID()
	if _output_buf.is_valid():
		_rd.free_rid(_output_buf)
		_output_buf = RID()
	if _origins_buf.is_valid():
		_rd.free_rid(_origins_buf)
		_origins_buf = RID()
	if _params_buf.is_valid():
		_rd.free_rid(_params_buf)
		_params_buf = RID()
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
		_pipeline = RID()
	if _shader_rid.is_valid():
		_rd.free_rid(_shader_rid)
		_shader_rid = RID()


func is_initialized() -> bool:
	return _pipeline.is_valid() and _shader_rid.is_valid()


func generate_batch(batch: Array) -> void:
	if batch.is_empty() or not is_initialized():
		return
	var bs := mini(batch.size(), MAX_BATCH)
	_generate_batch_gpu(batch, bs)
	_last_batch_generated = true


func save_map(path: String, p_river_cells: Dictionary = {}, p_road_cells: Dictionary = {}, p_vertex_subs: Dictionary = {}, p_chunks_with_rivers: Dictionary = {}, p_roads: Array = []) -> void:
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
	return result


func _generate_batch_gpu(batch: Array, bs: int) -> void:
	var params := PackedFloat32Array()
	params.push_back(float(CHUNK_SIZE))
	params.push_back(float(bs))
	params.push_back(noise_freq)
	params.push_back(float(noise_seed))
	params.push_back(detail_freq)
	params.push_back(float(detail_seed))
	params.push_back(float(fractal_octaves))
	params.push_back(fractal_lacunarity)
	params.push_back(fractal_gain)
	params.push_back(float(detail_octaves))
	params.push_back(detail_lacunarity)
	params.push_back(detail_gain)
	params.push_back(0.0)
	params.push_back(0.0)
	params.push_back(0.0)
	params.push_back(0.0)
	_rd.buffer_update(_params_buf, 0, 64, params.to_byte_array())

	var origins := PackedInt32Array()
	for i in bs:
		origins.push_back(batch[i].x)
		origins.push_back(batch[i].y)
	_rd.buffer_update(_origins_buf, 0, origins.size() * 4, origins.to_byte_array())

	var output_count := bs * CELLS_PER_CHUNK * VALUES_PER_CELL
	var output_size := output_count * 4

	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, _uniform_set, 0)
	_rd.compute_list_dispatch(cl, 1, 1, bs)
	_rd.compute_list_end()

	_rd.submit()
	_rd.sync()

	var output_bytes := _rd.buffer_get_data(_output_buf, 0, output_size)
	var floats := output_bytes.to_float32_array()

	for ci in bs:
		var ck: Vector2i = batch[ci]
		if _loaded_chunk_origins.has(ck):
			continue
		_loaded_chunk_origins[ck] = true
		var base_q: int = ck.x * CHUNK_SIZE
		var base_r: int = ck.y * CHUNK_SIZE
		for cx in CHUNK_SIZE:
			for cy in CHUNK_SIZE:
				var idx: int = (ci * CELLS_PER_CHUNK + cx * CHUNK_SIZE + cy) * VALUES_PER_CELL
				var elevation: float = floats[idx]
				var biome: int = int(floats[idx + 1])
				var q: int = base_q + cx
				var r: int = base_r + cy
				var hex := Vector3i(q, r, -q - r)
				if cells.has(hex):
					continue
				var cell := HexCellData.new(hex, biome, elevation)
				cell.color = BIOME_COLORS[clampi(biome, 0, BIOME_COLORS.size() - 1)]
				for s in TOTAL_SUBS:
					cell.sub_heights[s] = floats[idx + 2 + s]
				cells[hex] = cell
