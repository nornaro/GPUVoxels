class_name ChunkManager
extends RefCounted

const CHUNK_SIZE: int = 10
const TOTAL_SUBS: int = 13
const MAX_BATCH: int = 16384
const HEX_SIZE: float = 1.1547
const CELLS_PER_CHUNK: int = CHUNK_SIZE * CHUNK_SIZE
const FLOATS_PER_CELL: int = 15

const BIOME_DEEP_WATER := 0
const BIOME_WATER := 1
const BIOME_BEACH := 2
const BIOME_GRASS := 3
const BIOME_DIRT := 4
const BIOME_STONE := 5

const BIOME_COLORS: Array = [
	Color(0.35, 0.30, 0.30, 1.0),
	Color(0.70, 0.60, 0.60, 0.7),
	Color(0.82, 0.77, 0.55, 1.0),
	Color(0.35, 0.55, 0.28, 1.0),
	Color(0.55, 0.42, 0.28, 1.0),
	Color(0.48, 0.48, 0.48, 1.0),
	Color(0.32, 0.55, 0.82, 1.0),
]

const BINARY_MAGIC: int = 0x48564D50
const BINARY_VERSION: int = 4

var noise_freq: float = 0.0075
var noise_seed: int = 42
var detail_freq: float = 0.025
var detail_seed: int = 1042
var fractal_octaves: int = 3
var fractal_lacunarity: float = 2.0
var fractal_gain: float = 0.3
var detail_octaves: int = 3
var detail_lacunarity: float = 2.0
var detail_gain: float = 0.3
var warp_strength: float = 0.4
var moisture_freq: float = 0.005
var moisture_seed: int = 7777

var _noise: FastNoiseLite
var _detail_noise: FastNoiseLite

var _gpu_available: bool = false
var _gpu_shader: RID
var _gpu_pipeline: RID
var _params_buf: RID
var _origins_buf: RID
var _output_buf: RID
var _gpu_uniform_set: RID

var cells: Dictionary
var _loaded_chunk_origins: Dictionary = {}
var _last_batch_generated: bool = false


func randomize_seeds() -> void:
	noise_seed = randi()
	detail_seed = randi()
	moisture_seed = randi()
	noise_freq = randf_range(0.004, 0.015)
	detail_freq = randf_range(0.0125, 0.05)
	warp_strength = randf_range(0.2, 0.6)
	_init_noise()
	_compile_gpu_shader()


func _init(p_cells: Dictionary) -> void:
	cells = p_cells
	_init_noise()
	_compile_gpu_shader()


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
	print("ChunkManager: CPU noise init, freq=%.4f octaves=%d" % [noise_freq, fractal_octaves])


func _compile_gpu_shader() -> void:
	_gpu_available = false
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		print("ChunkManager: No RenderingDevice, CPU only")
		return
	var shader_file = load("res://shaders/compute_noise.glsl")
	if shader_file == null:
		print("ChunkManager: No compute shader file, CPU only")
		return
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	_gpu_shader = rd.shader_create_from_spirv(spirv)
	if _gpu_shader == RID():
		print("ChunkManager: Shader compile failed, CPU only")
		return
	_gpu_pipeline = rd.compute_pipeline_create(_gpu_shader)
	if not rd.compute_pipeline_is_valid(_gpu_pipeline):
		print("ChunkManager: Pipeline create failed, CPU only")
		rd.free_rid(_gpu_shader)
		_gpu_shader = RID()
		return
	_gpu_available = true
	print("ChunkManager: GPU compute ready")


func cleanup() -> void:
	if _gpu_available:
		var rd := RenderingServer.get_rendering_device()
		if rd != null:
			if _gpu_uniform_set != RID():
				rd.free_rid(_gpu_uniform_set)
			if _output_buf != RID():
				rd.free_rid(_output_buf)
			if _origins_buf != RID():
				rd.free_rid(_origins_buf)
			if _params_buf != RID():
				rd.free_rid(_params_buf)
			if _gpu_pipeline != RID():
				rd.free_rid(_gpu_pipeline)
			if _gpu_shader != RID():
				rd.free_rid(_gpu_shader)
		_gpu_available = false


func is_initialized() -> bool:
	return _noise != null


func get_or_create_cell(hex: Vector3i) -> HexCellData:
	if cells.has(hex):
		return cells[hex]
	if not is_initialized():
		return null
	var nval: float = _noise.get_noise_2d(float(hex.x), float(hex.y))
	var biome: int = _classify_biome(nval)
	var elevation: float = _remap_elevation(biome, nval)
	var cell := HexCellData.new(hex, biome, elevation)
	cell.color = BIOME_COLORS[clampi(biome, 0, BIOME_COLORS.size() - 1)]
	cell.sub_heights[0] = elevation
	const INNER_DIST: float = HEX_SIZE * 0.57735026919
	const OUTER_DIST: float = HEX_SIZE
	for i in 6:
		var angle: float = deg_to_rad(30.0 + 60.0 * float(i))
		var sub_q: float = float(hex.x) + cos(angle) * INNER_DIST
		var sub_r: float = float(hex.y) + sin(angle) * INNER_DIST
		var detail: float = _detail_noise.get_noise_2d(sub_q, sub_r) * 0.15
		cell.sub_heights[i + 1] = elevation + detail
	for i in 6:
		var angle: float = deg_to_rad(60.0 * float(i))
		var sub_q: float = float(hex.x) + cos(angle) * OUTER_DIST
		var sub_r: float = float(hex.y) + sin(angle) * OUTER_DIST
		var detail: float = _detail_noise.get_noise_2d(sub_q, sub_r) * 0.15
		cell.sub_heights[i + 7] = elevation + detail
	cells[hex] = cell
	return cell


func generate_batch(batch: Array) -> void:
	if batch.is_empty() or not is_initialized():
		return
	var bs := mini(batch.size(), MAX_BATCH)
	if _gpu_available:
		_generate_batch_gpu(batch, bs)
	else:
		_generate_batch_cpu(batch, bs)
	_last_batch_generated = true


func _generate_batch_gpu(batch: Array, bs: int) -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null or not _gpu_available:
		_generate_batch_cpu(batch, bs)
		return

	var params := PackedFloat32Array([
		float(CHUNK_SIZE), float(bs),
		noise_freq, float(noise_seed),
		detail_freq, float(detail_seed),
		float(fractal_octaves), fractal_lacunarity, fractal_gain,
		float(detail_octaves), detail_lacunarity, detail_gain,
		warp_strength, moisture_freq, float(moisture_seed), 0.0
	])
	_params_buf = rd.storage_buffer_create(params.size() * 4, params.to_byte_array())

	var origins := PackedInt32Array()
	for ci in bs:
		var ck: Vector2i = batch[ci]
		origins.append(ck.x)
		origins.append(ck.y)
	_origins_buf = rd.storage_buffer_create(origins.size() * 4, origins.to_byte_array())

	var out_size: int = bs * CELLS_PER_CHUNK * FLOATS_PER_CELL
	var out_bytes: int = out_size * 4
	_output_buf = rd.storage_buffer_create(out_bytes)

	var params_uniform := RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	params_uniform.binding = 0
	params_uniform.add_id(_params_buf)

	var origins_uniform := RDUniform.new()
	origins_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	origins_uniform.binding = 1
	origins_uniform.add_id(_origins_buf)

	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 2
	output_uniform.add_id(_output_buf)

	_gpu_uniform_set = rd.uniform_set_create([params_uniform, origins_uniform, output_uniform], _gpu_shader, 0)

	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _gpu_pipeline)
	rd.compute_list_bind_uniform_set(cl, _gpu_uniform_set, 0)
	var wg_x := ceili(float(CHUNK_SIZE) / 10.0)
	var wg_y := ceili(float(CHUNK_SIZE) / 10.0)
	rd.compute_list_dispatch(cl, wg_x, wg_y, bs)
	rd.compute_list_end()

	var raw: PackedByteArray = rd.buffer_get_data(_output_buf, 0, out_bytes)
	rd.free_rid(_params_buf)
	rd.free_rid(_origins_buf)
	rd.free_rid(_output_buf)
	rd.free_rid(_gpu_uniform_set)

	if raw.size() < out_bytes:
		_generate_batch_cpu(batch, bs)
		return

	var floats := raw.to_float32_array()
	for ci in bs:
		var ck: Vector2i = batch[ci]
		if _loaded_chunk_origins.has(ck):
			continue
		_loaded_chunk_origins[ck] = true
		var base_q: int = ck.x * CHUNK_SIZE
		var base_r: int = ck.y * CHUNK_SIZE
		for cx in CHUNK_SIZE:
			for cy in CHUNK_SIZE:
				var q: int = base_q + cx
				var r: int = base_r + cy
				var hex := Vector3i(q, r, -q - r)
				if cells.has(hex):
					continue
				var cell_idx: int = (ci * CELLS_PER_CHUNK + cx * CHUNK_SIZE + cy) * FLOATS_PER_CELL
				var elevation: float = floats[cell_idx]
				var biome: int = int(floats[cell_idx + 1])
				var cell := HexCellData.new(hex, biome, elevation)
				cell.color = BIOME_COLORS[clampi(biome, 0, BIOME_COLORS.size() - 1)]
				for si in TOTAL_SUBS:
					cell.sub_heights[si] = floats[cell_idx + 2 + si]
				cells[hex] = cell


func _generate_batch_cpu(batch: Array, bs: int) -> void:
	for ci in bs:
		var ck: Vector2i = batch[ci]
		if _loaded_chunk_origins.has(ck):
			continue
		_loaded_chunk_origins[ck] = true
		var base_q: int = ck.x * CHUNK_SIZE
		var base_r: int = ck.y * CHUNK_SIZE
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
			return remap(nval, -0.3, -0.1, 0.3, 0.5)
		BIOME_BEACH:
			return remap(nval, -0.1, 0.1, 0.5, 0.7)
		BIOME_GRASS:
			return remap(nval, 0.1, 0.4, 0.7, 1.8)
		BIOME_DIRT:
			return remap(nval, 0.4, 0.7, 1.8, 2.8)
		BIOME_STONE:
			return remap(nval, 0.7, 1.4, 2.8, 4.0)
		_:
			return remap(nval, -1.0, 1.0, 0.3, 3.0)


func sample_height(world_pos: Vector3) -> float:
	if not is_initialized():
		return HEX_SIZE
	var q: float = 0.66666666667 * world_pos.x / HEX_SIZE
	var r: float = (-0.33333333333 * world_pos.x + 0.57735026919 * world_pos.z) / HEX_SIZE
	var nval: float = _noise.get_noise_2d(q, r)
	var biome: int = _classify_biome(nval)
	if biome == BIOME_DEEP_WATER or biome == BIOME_WATER:
		return 0.3
	var elevation: float = _remap_elevation(biome, nval)
	var hex_width: float = HEX_SIZE * 1.73205080757
	return maxf(elevation, 0.0) * hex_width + HEX_SIZE


func sample_biome(world_pos: Vector3) -> int:
	if not is_initialized():
		return BIOME_GRASS
	var q: float = 0.66666666667 * world_pos.x / HEX_SIZE
	var r: float = (-0.33333333333 * world_pos.x + 0.57735026919 * world_pos.z) / HEX_SIZE
	var nval: float = _noise.get_noise_2d(q, r)
	return _classify_biome(nval)


# ============================================================================
# BINARY SAVE / LOAD
# ============================================================================
func save_map(path: String, p_river_cells: Dictionary = {}, p_road_cells: Dictionary = {}, p_vertex_subs: Dictionary = {}, p_chunks_with_rivers: Dictionary = {}, p_roads: Array = [], p_blocks: Dictionary = {}, p_objects: Dictionary = {}, p_resource_cache: Dictionary = {}) -> void:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_32(BINARY_MAGIC)
	buf.put_32(BINARY_VERSION)
	buf.put_float(noise_freq)
	buf.put_32(noise_seed)
	buf.put_float(detail_freq)
	buf.put_32(detail_seed)
	buf.put_32(fractal_octaves)
	buf.put_float(fractal_lacunarity)
	buf.put_float(fractal_gain)
	buf.put_32(detail_octaves)
	buf.put_float(detail_lacunarity)
	buf.put_float(detail_gain)
	buf.put_float(warp_strength)
	buf.put_float(moisture_freq)
	buf.put_32(moisture_seed)
	buf.put_32(cells.size())
	for key in cells:
		var c: HexCellData = cells[key]
		buf.put_32(key.x)
		buf.put_32(key.y)
		buf.put_8(c.biome)
		buf.put_float(c.elevation)
		for si in TOTAL_SUBS:
			buf.put_float(c.sub_heights[si])
	buf.put_32(p_river_cells.size())
	for hex_key in p_river_cells:
		var arr: Array = p_river_cells[hex_key]
		buf.put_32(hex_key.x)
		buf.put_32(hex_key.y)
		buf.put_32(arr.size())
		for s in arr:
			buf.put_32(s)
	buf.put_32(p_road_cells.size())
	for hex_key in p_road_cells:
		var arr: Array = p_road_cells[hex_key]
		buf.put_32(hex_key.x)
		buf.put_32(hex_key.y)
		buf.put_32(arr.size())
		for s in arr:
			buf.put_32(s)
	buf.put_32(p_roads.size())
	for road in p_roads:
		buf.put_32(road["from"].x)
		buf.put_32(road["from"].y)
		buf.put_32(road["from"].z)
		buf.put_32(road["to"].x)
		buf.put_32(road["to"].y)
		buf.put_32(road["to"].z)
	buf.put_32(p_vertex_subs.size())
	for vkey in p_vertex_subs:
		var vd: Dictionary = p_vertex_subs[vkey]
		buf.put_32(vkey)
		buf.put_8(1 if vd["river"] else 0)
		buf.put_8(1 if vd["road"] else 0)
		buf.put_32(vd["hex"].x)
		buf.put_32(vd["hex"].y)
		buf.put_32(vd["hex"].z)
		buf.put_32(vd["vi"])
	buf.put_32(p_chunks_with_rivers.size())
	for ck in p_chunks_with_rivers:
		buf.put_32(ck.x)
		buf.put_32(ck.y)
	buf.put_32(p_blocks.size())
	for b_hex in p_blocks:
		buf.put_32(b_hex.x)
		buf.put_32(b_hex.y)
		buf.put_32(b_hex.z)
	buf.put_32(p_objects.size())
	for o_hex in p_objects:
		var od: Dictionary = p_objects[o_hex]
		buf.put_32(o_hex.x)
		buf.put_32(o_hex.y)
		buf.put_32(o_hex.z)
		var path_str: String = od.get("path", "")
		buf.put_32(path_str.length())
		for ci2 in path_str.length():
			buf.put_8(path_str.unicode_at(ci2))
		buf.put_float(od.get("rotation", 0.0))
		buf.put_float(od.get("scale", 1.0))
	buf.put_32(p_resource_cache.size())
	for rc_hex in p_resource_cache:
		var res_arr: Array = p_resource_cache[rc_hex]
		buf.put_32(rc_hex.x)
		buf.put_32(rc_hex.y)
		buf.put_32(rc_hex.z)
		buf.put_32(res_arr.size())
		for res in res_arr:
			var sub_idx: int = res.get("sub_idx", 0)
			var res_type: String = res.get("type", "")
			var model: String = res.get("model", "")
			buf.put_32(sub_idx)
			buf.put_32(res_type.length())
			for ci2 in res_type.length():
				buf.put_8(res_type.unicode_at(ci2))
			buf.put_32(model.length())
			for ci3 in model.length():
				buf.put_8(model.unicode_at(ci3))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ChunkManager: Cannot write " + path)
		return
	f.store_buffer(buf.data_array)
	f.close()
	print("ChunkManager: Saved binary map (%d cells, %d resources, %.1f KB)" % [cells.size(), p_resource_cache.size(), buf.data_array.size() / 1024.0])


func load_map(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var file_data := f.get_buffer(f.get_length())
	f.close()
	if file_data.size() < 16:
		return {}
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = file_data
	var magic: int = buf.get_32()
	if magic == BINARY_MAGIC:
		return _load_map_binary(buf)
	else:
		return _load_map_json(file_data)


func _load_map_binary(buf: StreamPeerBuffer) -> Dictionary:
	var version: int = buf.get_32()
	noise_freq = buf.get_float()
	noise_seed = buf.get_32()
	detail_freq = buf.get_float()
	detail_seed = buf.get_32()
	fractal_octaves = buf.get_32()
	fractal_lacunarity = buf.get_float()
	fractal_gain = buf.get_float()
	detail_octaves = buf.get_32()
	detail_lacunarity = buf.get_float()
	detail_gain = buf.get_float()
	if version >= 4:
		warp_strength = buf.get_float()
		moisture_freq = buf.get_float()
		moisture_seed = buf.get_32()
	_init_noise()
	var num_cells: int = buf.get_32()
	cells.clear()
	_loaded_chunk_origins.clear()
	for _i in num_cells:
		var q: int = buf.get_32()
		var r: int = buf.get_32()
		var biome: int = buf.get_8()
		var elevation: float = buf.get_float()
		var hex := Vector3i(q, r, -q - r)
		var c := HexCellData.new(hex, biome, elevation)
		c.color = BIOME_COLORS[clampi(biome, 0, BIOME_COLORS.size() - 1)]
		for si in TOTAL_SUBS:
			c.sub_heights[si] = buf.get_float()
		cells[hex] = c
		var ck := Vector2i(floori(float(q) / CHUNK_SIZE), floori(float(r) / CHUNK_SIZE))
		_loaded_chunk_origins[ck] = true
	var result: Dictionary = {}
	var river_cells: Dictionary = {}
	var num_rivers: int = buf.get_32()
	for _i in num_rivers:
		var rq: int = buf.get_32()
		var rr: int = buf.get_32()
		var hex := Vector3i(rq, rr, -rq - rr)
		var count: int = buf.get_32()
		var subs: Array = []
		for _j in count:
			subs.append(buf.get_32())
		river_cells[hex] = subs
	result["river_cells"] = river_cells
	var road_cells: Dictionary = {}
	var num_roads_data: int = buf.get_32()
	for _i in num_roads_data:
		var rq: int = buf.get_32()
		var rr: int = buf.get_32()
		var hex := Vector3i(rq, rr, -rq - rr)
		var count: int = buf.get_32()
		var subs: Array = []
		for _j in count:
			subs.append(buf.get_32())
		road_cells[hex] = subs
	result["road_cells"] = road_cells
	var roads: Array = []
	var num_roads: int = buf.get_32()
	for _i in num_roads:
		var from_hex := Vector3i(buf.get_32(), buf.get_32(), buf.get_32())
		var to_hex := Vector3i(buf.get_32(), buf.get_32(), buf.get_32())
		roads.append({"from": from_hex, "to": to_hex})
	result["roads"] = roads
	var vertex_subs: Dictionary = {}
	var num_vs: int = buf.get_32()
	for _i in num_vs:
		var vkey: int = buf.get_32()
		var is_river: bool = buf.get_8() != 0
		var is_road: bool = buf.get_8() != 0
		var hex := Vector3i(buf.get_32(), buf.get_32(), buf.get_32())
		var vi: int = buf.get_32()
		vertex_subs[vkey] = {"river": is_river, "road": is_road, "hex": hex, "vi": vi}
	result["vertex_subs"] = vertex_subs
	var chunks_with_rivers: Dictionary = {}
	var num_cwr: int = buf.get_32()
	for _i in num_cwr:
		chunks_with_rivers[Vector2i(buf.get_32(), buf.get_32())] = true
	result["chunks_with_rivers"] = chunks_with_rivers
	var blocks: Dictionary = {}
	var num_blocks: int = buf.get_32()
	for _i in num_blocks:
		blocks[Vector3i(buf.get_32(), buf.get_32(), buf.get_32())] = true
	result["blocks"] = blocks
	var objects: Dictionary = {}
	var num_objects: int = buf.get_32()
	for _i in num_objects:
		var o_hex := Vector3i(buf.get_32(), buf.get_32(), buf.get_32())
		var path_len: int = buf.get_32()
		var path_str := ""
		for _j in path_len:
			path_str += char(buf.get_8())
		objects[o_hex] = {"path": path_str, "rotation": buf.get_float(), "scale": buf.get_float()}
	result["objects"] = objects
	var resource_cache: Dictionary = {}
	if version >= 3 and buf.get_available_bytes() >= 4:
		var num_resources: int = buf.get_32()
		if num_resources > 0 and num_resources < 10000000:
			for _i in num_resources:
				if buf.get_available_bytes() < 16:
					break
				var rc_hex := Vector3i(buf.get_32(), buf.get_32(), buf.get_32())
				var res_count: int = buf.get_32()
				var res_arr: Array = []
				if res_count > 0 and res_count < 1000:
					for _j in res_count:
						if buf.get_available_bytes() < 8:
							break
						var sub_idx: int = buf.get_32()
						var type_len: int = buf.get_32()
						var res_type := ""
						if type_len > 0 and type_len < 256:
							if buf.get_available_bytes() >= type_len:
								for _k in type_len:
									res_type += char(buf.get_8())
						var model_len: int = buf.get_32()
						var model_path := ""
						if model_len > 0 and model_len < 512:
							if buf.get_available_bytes() >= model_len:
								for _k in model_len:
									model_path += char(buf.get_8())
						res_arr.append({"sub_idx": sub_idx, "type": res_type, "model": model_path})
				resource_cache[rc_hex] = res_arr
	result["resource_cache"] = resource_cache
	print("ChunkManager: Loaded binary map (%d cells)" % cells.size())
	return result


func _load_map_json(file_data: PackedByteArray) -> Dictionary:
	var text := file_data.get_string_from_utf8()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("ChunkManager: JSON parse error")
		return {}
	var root: Dictionary = json.data
	if not root is Dictionary:
		return {}
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
		warp_strength = n.get("warp_strength", warp_strength)
		moisture_freq = n.get("moisture_freq", moisture_freq)
		moisture_seed = n.get("moisture_seed", moisture_seed)
		_init_noise()
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
	var resource_cache: Dictionary = {}
	for key_str in root.get("resource_cache", {}):
		var key_string: String = str(key_str)
		var stripped: String = key_string.strip_edges().replace("(", "").replace(")", "")
		var parts: PackedStringArray = stripped.split(",")
		if parts.size() >= 3:
			var hex := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
			var res_arr: Array = []
			for res_entry in root["resource_cache"][key_str]:
				res_arr.append({"sub_idx": res_entry.get("sub_idx", 0), "type": res_entry.get("type", ""), "model": res_entry.get("model", "")})
			resource_cache[hex] = res_arr
	result["resource_cache"] = resource_cache
	return result
