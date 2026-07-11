class_name HexGpuTerrainGenerator
extends RefCounted

const MAX_TILES := 256 * 256  # Max chunk size
const FLOATS_PER_TILE := 3   # elevation, type_index, noise_val
const INTS_PER_TILE := 3     # q, r, s
const PARAM_FLOATS := 4      # noise_seed, noise_freq, tile_count, _pad

var _rd: RenderingDevice
var _shader_rid: RID
var _pipeline_rid: RID

# Triple-buffered: params, input, output per slot
var _params_buf: Array[RID] = []
var _input_buf: Array[RID] = []
var _output_buf: Array[RID] = []
var _uniform_set: Array[RID] = []

var _frame_counter: int = 0
var _initialized: bool = false


func _init() -> void:
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		push_error("HexGpuTerrainGenerator: failed to create local RenderingDevice")
		return
	_init_shader()
	if _initialized:
		_init_buffers()


func _init_shader() -> void:
	var shader_file := load("res://HexGrid/hex_terrain_gen.glsl")
	if shader_file == null:
		push_error("HexGpuTerrainGenerator: failed to load compute shader")
		return
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	_shader_rid = _rd.shader_create_from_spirv(shader_spirv)
	if not _shader_rid.is_valid():
		push_error("HexGpuTerrainGenerator: failed to create shader from SPIR-V")
		return
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)
	if not _pipeline_rid.is_valid():
		push_error("HexGpuTerrainGenerator: failed to create compute pipeline")
		return
	_initialized = true


func _init_buffers() -> void:
	var params_size := PARAM_FLOATS * 4  # 16 bytes
	var input_size := MAX_TILES * INTS_PER_TILE * 4   # int3 per tile
	var output_size := MAX_TILES * FLOATS_PER_TILE * 4 # float3 per tile

	for i in 3:
		var empty := PackedByteArray()
		empty.resize(params_size)
		_params_buf.append(_rd.storage_buffer_create(params_size, empty))

		empty.resize(input_size)
		_input_buf.append(_rd.storage_buffer_create(input_size, empty))

		empty.resize(output_size)
		_output_buf.append(_rd.storage_buffer_create(output_size, empty))

		# Uniform set: binding 0=params, 1=input, 2=output
		var u0 := RDUniform.new()
		u0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u0.binding = 0
		u0.add_id(_params_buf[i])

		var u1 := RDUniform.new()
		u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u1.binding = 1
		u1.add_id(_input_buf[i])

		var u2 := RDUniform.new()
		u2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u2.binding = 2
		u2.add_id(_output_buf[i])

		_uniform_set.append(_rd.uniform_set_create([u0, u1, u2], _shader_rid, 0))


func generate_terrain(cells: Array[Vector3i], noise_seed: float, noise_freq: float) -> Array[Dictionary]:
	if not _initialized or cells.is_empty():
		return []

	var tile_count := cells.size()
	var slot := _frame_counter % 3
	_frame_counter += 1

	# Pack params: [noise_seed(int), noise_freq(float), tile_count(int), _pad(int)]
	var params := PackedFloat32Array()
	params.append(float(int(noise_seed)))
	params.append(noise_freq)
	params.append(float(tile_count))
	params.append(0.0)
	_rd.buffer_update(_params_buf[slot], 0, params.to_byte_array().size(), params.to_byte_array())

	# Pack input coords: [q0, r0, s0, q1, r1, s1, ...]
	var input_data := PackedInt32Array()
	input_data.resize(tile_count * INTS_PER_TILE)
	for i in tile_count:
		input_data[i * 3 + 0] = cells[i].x
		input_data[i * 3 + 1] = cells[i].y
		input_data[i * 3 + 2] = cells[i].z
	_rd.buffer_update(_input_buf[slot], 0, input_data.to_byte_array().size(), input_data.to_byte_array())

	# Dispatch: 64 threads per workgroup, ceil(tile_count / 64) groups
	var groups_x := ceili(float(tile_count) / 64.0)
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(cl, _uniform_set[slot], 0)
	_rd.compute_list_dispatch(cl, groups_x, 1, 1)
	_rd.compute_list_end()

	_rd.submit()
	_rd.sync()

	# Read back results
	var out_bytes := _rd.buffer_get_data(_output_buf[slot], 0, tile_count * FLOATS_PER_TILE * 4)
	var out_floats := out_bytes.to_float32_array()

	var results: Array[Dictionary] = []
	results.resize(tile_count)
	for i in tile_count:
		var elevation: float = out_floats[i * 3 + 0]
		var type_idx: int = int(out_floats[i * 3 + 1])
		var nval: float = out_floats[i * 3 + 2]
		results[i] = {
			"coords": cells[i],
			"elevation": elevation,
			"type_index": type_idx,
			"noise_val": nval,
			"detail": 0.0,
		}
	return results


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _rd == null:
			return
		for i in 3:
			if _params_buf.size() > i and _params_buf[i].is_valid():
				_rd.free_rid(_params_buf[i])
			if _input_buf.size() > i and _input_buf[i].is_valid():
				_rd.free_rid(_input_buf[i])
			if _output_buf.size() > i and _output_buf[i].is_valid():
				_rd.free_rid(_output_buf[i])
			if _uniform_set.size() > i and _uniform_set[i].is_valid():
				_rd.free_rid(_uniform_set[i])
		if _pipeline_rid.is_valid():
			_rd.free_rid(_pipeline_rid)
		if _shader_rid.is_valid():
			_rd.free_rid(_shader_rid)
		_rd.free()
