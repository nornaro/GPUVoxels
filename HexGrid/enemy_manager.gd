extends Node3D

const HEX_SIZE: float = 1.1547
const MAX_PATH_STEPS: int = 120
const SPAWN_DISTANCE_MIN: int = 3
const SEARCH_RADIUS: int = 2
const TARGET_RADIUS: int = 2
const BIOME_WATER: int = 0
const SUB_STEPS: int = 4

const MAX_ENEMIES: int = 20000
const ENEMY_STRIDE: int = 16
const TEX_WIDTH: int = 256
const TEX_HEIGHT: int = 79

var cells: Dictionary
var chunk_manager: ChunkManager

var _spawn_timer: float = 0.0
var spawn_interval: float = 2.0
var max_enemies: int = 30
var spawn_batch_size: int = 1
var _spawn_queue: int = 0
const _SPAWNS_PER_FRAME: int = 3

var _water_spawns: PackedVector3Array
var _water_hexes: Array[Vector3i]
var _water_spawns_dirty: bool = true
var _water_count: int = 0
var _last_cell_count: int = 0
var _rebuild_timer: float = 0.0
var _spawn_ring_index: int = 0
var _spawn_ring_buckets: Array[Array] = []
var _spawn_distribution: Array[int] = []

var _active_count: int = 0
var _slot_alive: PackedByteArray
var _next_slot: int = 0
var _free_slots: Array[int] = []

var _gpu_enemy_data: PackedFloat32Array
var _gpu_path_data: PackedFloat32Array

var _rd: RenderingDevice
var _enemy_shader: RID
var _enemy_pipeline: RID
var _enemy_buf: RID
var _path_buf: RID
var _pos_tex_rid: RID
var _uniform_set: RID
var _render_tex: Texture2DRD
var _gpu_initialized: bool = false
var _path_rng := RandomNumberGenerator.new()

var _multimesh: MultiMesh
var _multimesh_instance: MultiMeshInstance3D

var _readback_timer: float = 0.0

var _enemy_path_hexes: Array[Dictionary] = []

var _pending_slots: Array[int] = []
var _pending_spawn_pos: Dictionary = {}

var _pf_shader: RID
var _pf_pipeline: RID
var _pf_params_buf: RID
var _pf_request_buf: RID
var _pf_result_buf: RID
var _pf_uniform_set: RID
var _pf_initialized: bool = false


func _ready() -> void:
	_slot_alive.resize(MAX_ENEMIES)
	_slot_alive.fill(0)
	_gpu_enemy_data.resize(MAX_ENEMIES * ENEMY_STRIDE)
	_gpu_enemy_data.fill(0.0)
	_gpu_path_data.resize(MAX_ENEMIES * MAX_PATH_STEPS * 3)
	_gpu_path_data.fill(0.0)

	_multimesh = MultiMesh.new()
	_multimesh.mesh = BoxMesh.new()
	_multimesh.mesh.size = Vector3(1.0, 1.5, 1.0)
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = false
	_multimesh.instance_count = max_enemies

	for i in max_enemies:
		_multimesh.set_instance_transform(i, Transform3D.IDENTITY)

	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = _multimesh
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_multimesh_instance.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 200, 1000))

	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://shaders/enemy_cubes.gdshader")
	shader_mat.set_shader_parameter("tex_width", TEX_WIDTH)
	_multimesh_instance.material_override = shader_mat
	add_child(_multimesh_instance)

	_init_gpu()

	_enemy_path_hexes.resize(MAX_ENEMIES)
	for i in MAX_ENEMIES:
		_enemy_path_hexes[i] = {}


var _height_step: float = 3.0
var _height_exp: float = 1.0


func setup(p_cells: Dictionary, p_chunk_manager: ChunkManager) -> void:
	cells = p_cells
	chunk_manager = p_chunk_manager


func set_max_enemies(n: int) -> void:
	max_enemies = n
	if _multimesh:
		_multimesh.instance_count = max_enemies
		for i in max_enemies:
			_multimesh.set_instance_transform(i, Transform3D.IDENTITY)


func set_height_params(step: float, exp_val: float) -> void:
	_height_step = step
	_height_exp = exp_val


func _init_gpu() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		push_warning("EnemyManager: No RenderingDevice available")
		return

	var spirv: RDShaderSPIRV = load("res://shaders/enemy_compute.glsl").get_spirv()
	_enemy_shader = _rd.shader_create_from_spirv(spirv)
	if _enemy_shader == RID():
		push_warning("EnemyManager: Compute shader compile failed")
		return

	_enemy_pipeline = _rd.compute_pipeline_create(_enemy_shader)
	if not _rd.compute_pipeline_is_valid(_enemy_pipeline):
		push_warning("EnemyManager: Compute pipeline invalid")
		_rd.free_rid(_enemy_shader)
		_enemy_shader = RID()
		return

	var enemy_buf_size: int = MAX_ENEMIES * ENEMY_STRIDE * 4
	_enemy_buf = _rd.storage_buffer_create(enemy_buf_size)

	var path_buf_size: int = MAX_ENEMIES * MAX_PATH_STEPS * 3 * 4
	_path_buf = _rd.storage_buffer_create(path_buf_size)

	var tex_fmt := RDTextureFormat.new()
	tex_fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tex_fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tex_fmt.width = TEX_WIDTH
	tex_fmt.height = TEX_HEIGHT
	tex_fmt.depth = 1
	tex_fmt.array_layers = 1
	tex_fmt.mipmaps = 1
	tex_fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var tex_view := RDTextureView.new()
	var total_pixels := TEX_WIDTH * TEX_HEIGHT
	var dead_floats := PackedFloat32Array()
	dead_floats.resize(total_pixels * 4)
	for i in total_pixels:
		dead_floats[i * 4 + 0] = 0.0
		dead_floats[i * 4 + 1] = -999.0
		dead_floats[i * 4 + 2] = 0.0
		dead_floats[i * 4 + 3] = 0.0
	_pos_tex_rid = _rd.texture_create(tex_fmt, tex_view, [dead_floats.to_byte_array()])

	_render_tex = Texture2DRD.new()
	_render_tex.texture_rd_rid = _pos_tex_rid
	var mat: ShaderMaterial = _multimesh_instance.material_override
	mat.set_shader_parameter("pos_texture", _render_tex)

	_uniform_set = _build_uniform_set()
	if _uniform_set == RID():
		push_warning("EnemyManager: Uniform set creation failed")
		return

	_gpu_initialized = true
	print("EnemyManager: GPU compute pipeline ready (max=%d)" % MAX_ENEMIES)
	_init_pathfinding_gpu()
	if _pf_initialized:
		print("EnemyManager: GPU pathfinding ready")


func _build_uniform_set() -> RID:
	var uniforms: Array[RDUniform] = []

	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u0.binding = 0
	u0.add_id(_enemy_buf)
	uniforms.append(u0)

	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(_path_buf)
	uniforms.append(u1)

	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u2.binding = 2
	u2.add_id(_pos_tex_rid)
	uniforms.append(u2)

	return _rd.uniform_set_create(uniforms, _enemy_shader, 0)


func _init_pathfinding_gpu() -> void:
	var spirv: RDShaderSPIRV = load("res://shaders/pathfinding.glsl").get_spirv()
	_pf_shader = _rd.shader_create_from_spirv(spirv)
	if _pf_shader == RID():
		push_warning("Pathfinding: shader compile failed")
		return
	_pf_pipeline = _rd.compute_pipeline_create(_pf_shader)
	if not _rd.compute_pipeline_is_valid(_pf_pipeline):
		push_warning("Pathfinding: pipeline invalid")
		_rd.free_rid(_pf_shader)
		_pf_shader = RID()
		return

	var params_size: int = 16 * 4
	_pf_params_buf = _rd.storage_buffer_create(params_size)
	var req_size: int = 4 * 4
	_pf_request_buf = _rd.storage_buffer_create(req_size)
	var result_size: int = 361 * 4
	_pf_result_buf = _rd.storage_buffer_create(result_size)

	var req_init := PackedInt32Array([0, 0, 0, 0])
	_rd.buffer_update(_pf_request_buf, 0, req_size, req_init.to_byte_array())

	var uniforms: Array[RDUniform] = []

	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u0.binding = 0
	u0.add_id(_pf_params_buf)
	uniforms.append(u0)

	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(_pf_request_buf)
	uniforms.append(u1)

	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u2.binding = 2
	u2.add_id(_pf_result_buf)
	uniforms.append(u2)

	_pf_uniform_set = _rd.uniform_set_create(uniforms, _pf_shader, 0)
	if _pf_uniform_set == RID():
		push_warning("Pathfinding: uniform set failed")
		_rd.free_rid(_pf_shader)
		_rd.free_rid(_pf_pipeline)
		_rd.free_rid(_pf_params_buf)
		_rd.free_rid(_pf_request_buf)
		_rd.free_rid(_pf_result_buf)
		_pf_shader = RID()
		return

	_pf_initialized = true


func _update_pf_params() -> void:
	if not _pf_initialized or not chunk_manager:
		return
	var cm := chunk_manager
	var params := PackedFloat32Array([
		cm.noise_freq, float(cm.noise_seed),
		cm.detail_freq, float(cm.detail_seed),
		float(cm.fractal_octaves), cm.fractal_lacunarity, cm.fractal_gain,
		float(cm.detail_octaves), cm.detail_lacunarity, cm.detail_gain,
		cm.warp_strength, cm.moisture_freq, float(cm.moisture_seed),
		_height_step, _height_exp, float(chunk_manager.cells.size())
	])
	var size := params.size() * 4
	_rd.buffer_update(_pf_params_buf, 0, size, params.to_byte_array())


func _request_gpu_path(spawn_hex: Vector3i, slot: int) -> void:
	if not _pf_initialized:
		return
	_update_pf_params()
	var req := PackedInt32Array([spawn_hex.x, spawn_hex.y, slot, 1])
	_rd.buffer_update(_pf_request_buf, 0, 16, req.to_byte_array())
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pf_pipeline)
	_rd.compute_list_bind_uniform_set(cl, _pf_uniform_set, 0)
	_rd.compute_list_dispatch(cl, 1, 1, 1)
	_rd.compute_list_end()


func _poll_gpu_path() -> Array[Vector3i]:
	if not _pf_initialized:
		return []
	var raw: PackedByteArray = _rd.buffer_get_data(_pf_request_buf, 12, 4)
	if raw.size() < 4:
		return []
	var status := raw.decode_s32(0)
	if status != 2:
		return []
	var slot_raw: PackedByteArray = _rd.buffer_get_data(_pf_request_buf, 8, 4)
	if slot_raw.size() < 4:
		return []
	var gpu_slot := slot_raw.decode_s32(0)
	var raw_result: PackedByteArray = _rd.buffer_get_data(_pf_result_buf, 0, 4)
	if raw_result.size() < 4:
		return []
	var path_len := raw_result.decode_s32(0)
	if path_len <= 0 or path_len > MAX_PATH_STEPS:
		_rd.buffer_update(_pf_request_buf, 12, 4, PackedInt32Array([0]).to_byte_array())
		return []
	var result_data: PackedByteArray = _rd.buffer_get_data(_pf_result_buf, 0, (1 + path_len * 3) * 4)
	if result_data.size() < (1 + path_len * 3) * 4:
		_rd.buffer_update(_pf_request_buf, 12, 4, PackedInt32Array([0]).to_byte_array())
		return []
	var result_arr := result_data.to_int32_array()
	var result: Array[Vector3i] = [Vector3i(gpu_slot, 0, 0)]
	for i in path_len:
		var qi := result_arr[1 + i * 3 + 0]
		var ri := result_arr[1 + i * 3 + 1]
		var si := result_arr[1 + i * 3 + 2]
		result.append(Vector3i(qi, ri, si))
	_rd.buffer_update(_pf_request_buf, 12, 4, PackedInt32Array([0]).to_byte_array())
	return result


func _cleanup_pathfinding() -> void:
	if _pf_uniform_set != RID():
		_rd.free_rid(_pf_uniform_set)
	if _pf_result_buf != RID():
		_rd.free_rid(_pf_result_buf)
	if _pf_request_buf != RID():
		_rd.free_rid(_pf_request_buf)
	if _pf_params_buf != RID():
		_rd.free_rid(_pf_params_buf)
	if _pf_pipeline != RID():
		_rd.free_rid(_pf_pipeline)
	if _pf_shader != RID():
		_rd.free_rid(_pf_shader)
	_pf_initialized = false


func _exit_tree() -> void:
	if _rd == null:
		return
	_cleanup_pathfinding()
	if _uniform_set != RID():
		_rd.free_rid(_uniform_set)
	if _pos_tex_rid != RID():
		_rd.free_rid(_pos_tex_rid)
	if _path_buf != RID():
		_rd.free_rid(_path_buf)
	if _enemy_buf != RID():
		_rd.free_rid(_enemy_buf)
	if _enemy_pipeline != RID():
		_rd.free_rid(_enemy_pipeline)
	if _enemy_shader != RID():
		_rd.free_rid(_enemy_shader)


func invalidate_water_spawns() -> void:
	_water_spawns_dirty = true


func _rebuild_water_spawns() -> void:
	_water_spawns.clear()
	_water_hexes.clear()
	_water_count = 0
	_water_spawns_dirty = false

	var 	ring_max := SPAWN_DISTANCE_MIN
	for hex in cells:
		var cell: HexCellData = cells[hex]
		if cell.biome != BIOME_WATER:
			continue
		var dist: int = maxi(maxi(absi(hex.x), absi(hex.y)), absi(hex.z))
		if dist >= SPAWN_DISTANCE_MIN:
			ring_max = maxi(ring_max, dist)

	var rings_per_spawn := 8
	var ring_step := maxi(int(ring_max / float(rings_per_spawn)), 1)
	_spawn_ring_buckets.clear()
	_spawn_ring_buckets.resize(rings_per_spawn)
	_spawn_distribution.resize(rings_per_spawn)
	_spawn_distribution.fill(0)

	for hex in cells:
		var cell: HexCellData = cells[hex]
		if cell.biome != BIOME_WATER:
			continue
		var dist: int = maxi(maxi(absi(hex.x), absi(hex.y)), absi(hex.z))
		if dist >= SPAWN_DISTANCE_MIN:
			var ring_bucket := mini(int(float(dist - SPAWN_DISTANCE_MIN) / float(ring_step)), rings_per_spawn - 1)
			var pos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			var h := _get_height_from_cell(cell)
			_spawn_ring_buckets[ring_bucket].append({
				"pos": Vector3(pos.x, h, pos.z),
				"hex": hex
			})
			_spawn_distribution[ring_bucket] += 1

	_water_count = 0
	for bucket in _spawn_ring_buckets:
		_water_count += bucket.size()

	_spawn_ring_index = 0


func _process(delta: float) -> void:
	_rebuild_timer -= delta
	if cells.size() != _last_cell_count:
		_last_cell_count = cells.size()
		if _rebuild_timer <= 0.0:
			_water_spawns_dirty = true
			_rebuild_timer = 5.0

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		_spawn_queue += spawn_batch_size

	var spawned := 0
	while _spawn_queue > 0 and _active_count < max_enemies and spawned < _SPAWNS_PER_FRAME:
		_spawn_queue -= 1
		spawned += 1
		_try_spawn_one()
	if _active_count >= max_enemies:
		_spawn_queue = 0

	if _pf_initialized and _pending_slots.size() > 0:
		_process_pending_paths()

	_readback_timer -= delta
	if _readback_timer <= 0.0 and _gpu_initialized and _active_count > 0:
		_readback_timer = 0.5
		_reclaim_dead_slots()

	if _gpu_initialized:
		_dispatch_compute(delta)


func _dispatch_compute(delta: float) -> void:
	if _active_count == 0:
		return

	var push_data := PackedFloat32Array([delta, float(_active_count), float(TEX_WIDTH), 0.0])
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _enemy_pipeline)
	_rd.compute_list_bind_uniform_set(cl, _uniform_set, 0)
	_rd.compute_list_set_push_constant(cl, push_data.to_byte_array(), 16)
	var groups := ceili(float(_active_count) / 256.0)
	_rd.compute_list_dispatch(cl, groups, 1, 1)
	_rd.compute_list_end()


func _reclaim_dead_slots() -> void:
	if _enemy_buf == RID():
		return
	var buf_size: int = MAX_ENEMIES * ENEMY_STRIDE * 4
	var raw: PackedByteArray = _rd.buffer_get_data(_enemy_buf, 0, buf_size)
	if raw.size() < buf_size:
		return
	var floats := raw.to_float32_array()
	var freed := 0
	for i in _active_count:
		if _slot_alive[i] != 0:
			var dead_val: float = floats[i * ENEMY_STRIDE + 5]
			if dead_val > 0.5:
				_slot_alive[i] = 0
				_free_slots.append(i)
				_enemy_path_hexes[i].clear()
				freed += 1
	if freed > 0:
		print("EnemyManager: reclaimed %d dead slots" % freed)


func _try_spawn_one() -> void:
	if not _gpu_initialized:
		return
	if cells.is_empty():
		return
	if _water_count == 0 or _water_spawns_dirty:
		_rebuild_water_spawns()
	if _water_count == 0:
		return

	var attempts := 0
	var spawn_pos: Vector3
	var spawn_hex: Vector3i
	var found := false
	while attempts < _spawn_ring_buckets.size() and not found:
		if _spawn_ring_buckets[_spawn_ring_index].is_empty():
			_spawn_ring_index = (_spawn_ring_index + 1) % _spawn_ring_buckets.size()
			attempts += 1
			continue
		var bucket := _spawn_ring_buckets[_spawn_ring_index]
		var ridx: int = randi() % bucket.size()
		spawn_pos = bucket[ridx]["pos"]
		spawn_hex = bucket[ridx]["hex"]
		found = true
		_spawn_ring_index = (_spawn_ring_index + 1) % _spawn_ring_buckets.size()

	if not found:
		return

	if _pf_initialized:
		if not _pending_slots.is_empty():
			return
		var gpu_slot := _alloc_slot_gpu()
		if gpu_slot < 0:
			return
		_pending_slots.append(gpu_slot)
		_pending_spawn_pos[gpu_slot] = {"pos": spawn_pos, "hex": spawn_hex}
		_request_gpu_path(spawn_hex, gpu_slot)
		return

	var hex_path := _compute_path_cpu(spawn_hex)
	if hex_path.is_empty():
		return
	var slot := _alloc_slot()
	if slot < 0:
		return
	_upload_enemy(slot, spawn_hex, spawn_pos, hex_path)


func _process_pending_paths() -> void:
	while _pending_slots.size() > 0:
		var result := _poll_gpu_path()
		if result.is_empty():
			break
		var slot: int = result[0].x
		var path: Array[Vector3i] = result.slice(1)
		if path.is_empty():
			_pending_slots.erase(slot)
			_pending_spawn_pos.erase(slot)
			_free_slots.append(slot)
			continue
		var spawn_data: Dictionary = _pending_spawn_pos.get(slot, {})
		var spawn_pos: Vector3 = spawn_data.get("pos", Vector3.ZERO)
		var spawn_hex: Vector3i = spawn_data.get("hex", Vector3i.ZERO)
		_pending_spawn_pos.erase(slot)
		_pending_slots.erase(slot)
		_upload_enemy(slot, spawn_hex, spawn_pos, path)


func _alloc_slot_gpu() -> int:
	if _free_slots.size() > 0:
		var s: int = _free_slots.pop_back()
		if _slot_alive[s] == 0:
			_enemy_path_hexes[s].clear()
			return s
	if _next_slot < MAX_ENEMIES:
		var s: int = _next_slot
		_next_slot += 1
		_enemy_path_hexes[s].clear()
		return s
	return -1


func _alloc_slot() -> int:
	if _free_slots.size() > 0:
		var s: int = _free_slots.pop_back()
		if _slot_alive[s] == 0:
			_slot_alive[s] = 1
			_active_count = maxi(_active_count, s + 1)
			_enemy_path_hexes[s].clear()
			return s
	if _next_slot < MAX_ENEMIES:
		var s: int = _next_slot
		_next_slot += 1
		_slot_alive[s] = 1
		_active_count = maxi(_active_count, s + 1)
		_enemy_path_hexes[s].clear()
		return s
	return -1


func _hex_path_to_positions(hex_path: Array[Vector3i]) -> PackedVector3Array:
	var positions := PackedVector3Array()
	if hex_path.is_empty():
		return positions

	for i in range(hex_path.size()):
		var h := hex_path[i]
		var center := HexGridMath.cube_to_world_flat_top(h, HEX_SIZE)
		var height := _get_height(h)
		positions.append(Vector3(center.x, height, center.z))

		if i < hex_path.size() - 1:
			var next_h := hex_path[i + 1]
			var next_center := HexGridMath.cube_to_world_flat_top(next_h, HEX_SIZE)
			for j in range(1, SUB_STEPS):
				var t := float(j) / float(SUB_STEPS)
				var wx := lerpf(center.x, next_center.x, t)
				var wz := lerpf(center.z, next_center.z, t)
				var sub_hex := HexGridMath.world_to_cube_flat_top(Vector3(wx, 0, wz), HEX_SIZE)
				var sub_height := _get_height(sub_hex)
				positions.append(Vector3(wx, sub_height, wz))

	return positions


func _upload_enemy(slot: int, _spawn_hex: Vector3i, _world_pos: Vector3, hex_path: Array[Vector3i]) -> void:
	if not _gpu_initialized:
		return
	if _slot_alive[slot] == 0:
		_slot_alive[slot] = 1
		_active_count = maxi(_active_count, slot + 1)

	var positions := _hex_path_to_positions(hex_path)
	if positions.size() < 2:
		return

	var base: int = slot * ENEMY_STRIDE
	_gpu_enemy_data[base + 0] = 0.0
	_gpu_enemy_data[base + 1] = 0.1
	_gpu_enemy_data[base + 2] = 0.0
	var poff: int = slot * MAX_PATH_STEPS

	_gpu_enemy_data[base + 3] = float(poff)
	_gpu_enemy_data[base + 4] = float(positions.size())
	_gpu_enemy_data[base + 5] = 0.0
	_gpu_enemy_data[base + 6] = 0.0
	_gpu_enemy_data[base + 7] = 0.0
	_gpu_enemy_data[base + 8] = positions[0].x
	_gpu_enemy_data[base + 9] = positions[0].y
	_gpu_enemy_data[base + 10] = positions[0].z
	_gpu_enemy_data[base + 11] = 0.0
	_gpu_enemy_data[base + 12] = positions[1].x
	_gpu_enemy_data[base + 13] = positions[1].y
	_gpu_enemy_data[base + 14] = positions[1].z
	_gpu_enemy_data[base + 15] = float(randi() % 4)

	var plen: int = positions.size()

	for j in plen:
		var p := positions[j]
		_gpu_path_data[(poff + j) * 3 + 0] = p.x
		_gpu_path_data[(poff + j) * 3 + 1] = p.y
		_gpu_path_data[(poff + j) * 3 + 2] = p.z

	_enemy_path_hexes[slot].clear()
	for h in hex_path:
		_enemy_path_hexes[slot][h] = true
	for j in plen:
		var p := positions[j]
		var sub_hex := HexGridMath.world_to_cube_flat_top(Vector3(p.x, 0, p.z), HEX_SIZE)
		_enemy_path_hexes[slot][sub_hex] = true

	_rd.buffer_update(_enemy_buf, slot * ENEMY_STRIDE * 4, ENEMY_STRIDE * 4,
		_gpu_enemy_data.slice(base, base + ENEMY_STRIDE).to_byte_array())
	_rd.buffer_update(_path_buf, poff * 3 * 4, plen * 3 * 4,
		_gpu_path_data.slice(poff * 3, poff * 3 + plen * 3).to_byte_array())


func _compute_path_cpu(start: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	var current := start
	var on_land := false
	_path_rng.seed = hash(current)
	for _step in MAX_PATH_STEPS:
		var cd: int = maxi(maxi(absi(current.x), absi(current.y)), absi(current.z))
		if cd <= TARGET_RADIUS:
			path.append(Vector3i.ZERO)
			break
		var candidates: Array[Vector3i] = []
		var best_dist := cd
		for dq in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			for dr in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
				var ds: int = -dq - dr
				if maxi(maxi(absi(dq), absi(dr)), absi(ds)) > SEARCH_RADIUS:
					continue
				if dq == 0 and dr == 0:
					continue
				var candidate := current + Vector3i(dq, dr, ds)
				var c_dist: int = maxi(maxi(absi(candidate.x), absi(candidate.y)), absi(candidate.z))
				if c_dist > best_dist:
					continue
				if not cells.has(candidate):
					if chunk_manager:
						var cc: HexCellData = chunk_manager.get_or_create_cell(candidate)
						if not cc:
							continue
					else:
						continue
				var c_cell: HexCellData = cells[candidate]
				if on_land and c_cell.biome == BIOME_WATER:
					continue
				if c_dist < best_dist:
					candidates.clear()
					best_dist = c_dist
				candidates.append(candidate)

		if candidates.is_empty():
			break

		var pick: Vector3i = candidates[_path_rng.randi() % candidates.size()]

		if not on_land and cells.has(pick):
			var bc: HexCellData = cells[pick]
			if bc.biome != BIOME_WATER:
				on_land = true
		current = pick
		path.append(current)
	return path


func notify_cell_changed(hex: Vector3i) -> void:
	var slots_to_recompute: Array[int] = []
	for slot in range(_active_count):
		if _slot_alive[slot] != 0 and _enemy_path_hexes[slot].has(hex):
			slots_to_recompute.append(slot)
	for slot in slots_to_recompute:
		_recompute_enemy_path(slot)


func _recompute_enemy_path(slot: int) -> void:
	if not _gpu_initialized:
		return
	var base: int = slot * ENEMY_STRIDE
	var px := _gpu_enemy_data[base + 8]
	var pz := _gpu_enemy_data[base + 10]
	var current_hex := HexGridMath.world_to_cube_flat_top(Vector3(px, 0, pz), HEX_SIZE)
	if _pf_initialized and _pending_slots.is_empty():
		_pending_slots.append(slot)
		_pending_spawn_pos[slot] = {"pos": Vector3(px, 0, pz), "hex": current_hex}
		_request_gpu_path(current_hex, slot)
		return
	var hex_path := _compute_path_cpu(current_hex)
	if hex_path.is_empty():
		return
	var positions := _hex_path_to_positions(hex_path)
	if positions.size() < 2:
		return

	var old_plen := int(_gpu_enemy_data[base + 4])
	var poff := int(_gpu_enemy_data[base + 3])
	var plen := positions.size()

	if plen > old_plen:
		plen = old_plen
		positions = positions.slice(0, plen)

	_gpu_enemy_data[base + 0] = 0.0
	_gpu_enemy_data[base + 1] = 0.1
	_gpu_enemy_data[base + 2] = 0.0
	_gpu_enemy_data[base + 4] = float(plen)
	_gpu_enemy_data[base + 5] = 0.0
	_gpu_enemy_data[base + 8] = positions[0].x
	_gpu_enemy_data[base + 9] = positions[0].y
	_gpu_enemy_data[base + 10] = positions[0].z
	_gpu_enemy_data[base + 11] = 0.0
	_gpu_enemy_data[base + 12] = positions[1].x
	_gpu_enemy_data[base + 13] = positions[1].y
	_gpu_enemy_data[base + 14] = positions[1].z

	for j in plen:
		var p := positions[j]
		_gpu_path_data[(poff + j) * 3 + 0] = p.x
		_gpu_path_data[(poff + j) * 3 + 1] = p.y
		_gpu_path_data[(poff + j) * 3 + 2] = p.z

	_enemy_path_hexes[slot].clear()
	for h in hex_path:
		_enemy_path_hexes[slot][h] = true
	for j in plen:
		var p := positions[j]
		var sub_hex := HexGridMath.world_to_cube_flat_top(Vector3(p.x, 0, p.z), HEX_SIZE)
		_enemy_path_hexes[slot][sub_hex] = true

	_rd.buffer_update(_enemy_buf, slot * ENEMY_STRIDE * 4, ENEMY_STRIDE * 4,
		_gpu_enemy_data.slice(base, base + ENEMY_STRIDE).to_byte_array())
	_rd.buffer_update(_path_buf, poff * 3 * 4, plen * 3 * 4,
		_gpu_path_data.slice(poff * 3, poff * 3 + plen * 3).to_byte_array())


func _get_height_from_cell(cell: HexCellData) -> float:
	var e_norm := clampf(cell.elevation, 0.0, 1.0)
	return pow(maxf(_height_step * e_norm, 0.001), _height_exp)


func _get_height(hex: Vector3i) -> float:
	if not cells.has(hex):
		return 0.0
	return _get_height_from_cell(cells[hex])


func invalidate_all_paths() -> void:
	for slot in range(_active_count):
		if _slot_alive[slot] != 0:
			_recompute_enemy_path(slot)


func get_enemy_count() -> int:
	return _active_count
