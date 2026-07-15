class_name ChunkManager
extends RefCounted

const CHUNK_SIZE: int = 10
const TOTAL_SUBS: int = 13
const CELLS_PER_CHUNK: int = CHUNK_SIZE * CHUNK_SIZE
const VALUES_PER_CELL: int = 15

const BIOME_COLORS: Array = [
	Color(0.18, 0.35, 0.65),
	Color(0.28, 0.52, 0.78),
	Color(0.82, 0.77, 0.55),
	Color(0.35, 0.55, 0.28),
	Color(0.55, 0.42, 0.28),
	Color(0.48, 0.48, 0.48),
	Color(0.32, 0.55, 0.82),
]

const NOISE_FREQ: float = 0.008
const NOISE_SEED: int = 42
const DETAIL_FREQ: float = 0.032
const DETAIL_SEED: int = 1042
const FRACTAL_OCTAVES: int = 5
const FRACTAL_LACUNARITY: float = 2.0
const FRACTAL_GAIN: float = 0.5
const DETAIL_OCTAVES: int = 3
const DETAIL_LACUNARITY: float = 2.0
const DETAIL_GAIN: float = 0.4

var cells: Dictionary
var _loaded_chunk_origins: Dictionary = {}
var _rd: RenderingDevice
var _shader_rid: RID
var _pipeline: RID


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


func cleanup() -> void:
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
	_generate_batch_gpu(batch)


func _generate_batch_gpu(batch: Array) -> void:
	var batch_size := batch.size()

	var params := PackedFloat32Array()
	params.push_back(float(CHUNK_SIZE))
	params.push_back(float(batch_size))
	params.push_back(NOISE_FREQ)
	params.push_back(float(NOISE_SEED))
	params.push_back(DETAIL_FREQ)
	params.push_back(float(DETAIL_SEED))
	params.push_back(float(FRACTAL_OCTAVES))
	params.push_back(FRACTAL_LACUNARITY)
	params.push_back(FRACTAL_GAIN)
	params.push_back(float(DETAIL_OCTAVES))
	params.push_back(DETAIL_LACUNARITY)
	params.push_back(DETAIL_GAIN)
	params.push_back(0.0)
	params.push_back(0.0)
	params.push_back(0.0)
	params.push_back(0.0)
	var params_bytes := params.to_byte_array()
	var params_buf := _rd.storage_buffer_create(params_bytes.size(), params_bytes)

	var origins := PackedInt32Array()
	for ck in batch:
		origins.push_back(ck.x)
		origins.push_back(ck.y)
	var origins_bytes := origins.to_byte_array()
	var origins_buf := _rd.storage_buffer_create(origins_bytes.size(), origins_bytes)

	var output_count := batch_size * CELLS_PER_CHUNK * VALUES_PER_CELL
	var output_size := output_count * 4
	var output_buf := _rd.storage_buffer_create(output_size)

	var u_params := RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_params.binding = 0
	u_params.add_id(params_buf)

	var u_origins := RDUniform.new()
	u_origins.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_origins.binding = 1
	u_origins.add_id(origins_buf)

	var u_output := RDUniform.new()
	u_output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_output.binding = 2
	u_output.add_id(output_buf)

	var uniform_set := _rd.uniform_set_create([u_params, u_origins, u_output], _shader_rid, 0)

	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	_rd.compute_list_dispatch(cl, 1, 1, batch_size)
	_rd.compute_list_end()

	_rd.submit()
	_rd.sync()

	var output_bytes := _rd.buffer_get_data(output_buf, 0, output_size)
	var floats := output_bytes.to_float32_array()

	for ci in batch_size:
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

	# Note: batch resources (bufs, uniform_set) are freed when local RD is freed.
	# Per-batch free_rid fails on local devices due to Godot RID tracking issue.
