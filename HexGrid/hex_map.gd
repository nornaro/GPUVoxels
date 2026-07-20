extends Node3D

const HEX_SIZE: float = 1.1547
const SUB_HEX_SIZE: float = HEX_SIZE / 3.0
const SUB_HEX_DIST: float = HEX_SIZE * 0.57735026919
const WATER_HEIGHT: float = 0.3
const FORCE_REGENERATE: bool = false

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

const ELEVATION_STEPS: Array[float] = [1.0, 0.1, 0.01, 0.0]
const ELEVATION_STEP_NAMES: Array[String] = ["Step 1.0", "Step 0.1", "Step 0.01", "Flat"]
var elevation_step_idx: int = 0

var cells: Dictionary = {}
var chunk_manager: ChunkManager

var river_cells: Dictionary = {}
var road_cells: Dictionary = {}
var vertex_subs: Dictionary = {}

## Toggle sub-hex overlay (H key). Shows the 13 sub-hex grid on each hex for river/road painting.
@export var show_overlay: bool = false

## Toggle grid lines (G key). Shows a wireframe grid on the terrain.
@export var show_grid: bool = false

## Toggle height labels (V key). Shows elevation height text on each hex.
@export var show_height: bool = false

## Toggle elevation shading (Insert key). Colors hexes by elevation value.
@export var show_elevation_shade: bool = false

## Hex render mode: 0=per-pixel shaded, 1=per-vertex simple 3D, 2=unshaded flat.
var hex_render_mode: int = 0
const HEX_RENDER_MODE_NAMES := ["Shaded", "Simple 3D", "Flat"]

## Current tool: 0=Navigate, 1=River, 2=Road, 3=Place, 4=Raise, 5=Flatten, 6=Level, 7=WaterFlow. Keys 1-8.
@export_range(0, 7) var tool_mode: int = 0:
	set(v):
		tool_mode = v
		if is_inside_tree():
			_update_ui()

## Elevation step precision (F key). 1.0=integer, 0.1=tenth, 0.0=flat/raw.
@export var elevation_step: float = 1.0:
	set(v):
		elevation_step = v
		if ELEVATION_STEPS.has(v):
			elevation_step_idx = ELEVATION_STEPS.find(v)

var roads: Array[Dictionary] = []
const TOOL_NAMES := ["Navigate", "River", "Road", "Place", "Raise", "Flatten", "Level", "WaterFlow"]

var painting: bool = false
var erasing: bool = false

var road_start: Vector3i = Vector3i(999999, 999999, -1999998)
var placed_blocks: Dictionary = {}
var placed_objects: Dictionary = {}
var _placed_object_instances: Dictionary = {}
var _objects_container: Node3D
var selected_model_path: String = ""
var _placement_rotation: float = 0.0
var _placement_scale: float = 1.0
var _default_scale: float = 1.0
var _ghost_instance: Node3D = null
var _ghost_model_path: String = ""
var _level_target: Vector3i = Vector3i(999999, 999999, -1999998)
var _flatten_target: float = 0.0
var _flatten_captured: bool = false

var info_label: Label
var tool_label: Label

var panning: bool = false
var pan_start: Vector2 = Vector2.ZERO
var orbiting: bool = false
var orbit_start: Vector2 = Vector2.ZERO

var chunks_with_rivers: Dictionary = {}
const CHUNK_SIZE: int = 10
const RIVER_SOURCE_PERCENTILE: float = 0.97
const MAX_RIVERS_PER_CHUNK: int = 1
const MIN_LAKE_SIZE: int = 10

var _pending_chunks: Array[Vector2i] = []
var _pending_rivers: Array[Vector2i] = []
const MAX_TERRAIN_PER_FRAME: int = 32
const MAX_RIVERS_PER_FRAME: int = 8
const MAX_NEW_CHUNKS_QUEUED_PER_FRAME: int = 64
@export var max_chunk_radius: int = 50

var _cached_visible_hexes: Array[Vector3i] = []
var _cached_visible_set: Dictionary = {}
var _cached_visible_rivers: Array = []
var _cached_visible_vertex_rivers: Array = []
var _needs_save: bool = false
var _tool_flash_timer: float = 0.0
var _last_hover_hex: Vector3i = Vector3i(999999, 999999, -1999998)
var _last_debug_hover_hex: Vector3i = Vector3i(999999, 999999, -1999998)
var _cached_chunk_min: Vector2i = Vector2i.ZERO
var _cached_chunk_max: Vector2i = Vector2i.ZERO

var camera: Camera3D
var hex_multimesh_instance: MultiMeshInstance3D
var _hex_mat: StandardMaterial3D
var _hex_render_mode_btn: Button
var overlay_mesh_instance: MeshInstance3D
var grid_lines_mesh_instance: MeshInstance3D

var camera_yaw: float = 45.0
var camera_pitch: float = -55.0
var camera_distance: float = 25.0
var camera_pivot: Vector3 = Vector3.ZERO

var _hex_prism_mesh: ArrayMesh = null
var _hex_grass_mesh: ArrayMesh = preload("res://assets/kaykit_medieval_hexagon_pack/tiles/base/hex_grass.mesh")
var _blocks_container: Node3D
var _block_instances: Dictionary = {}
var _needs_rebuild: bool = true
var _needs_decoration_rebuild: bool = false
var _needs_overlay_rebuild: bool = true

var _cached_camera_yaw: float = NAN
var _cached_camera_pitch: float = NAN
var _cached_camera_distance: float = NAN
var _cached_camera_pivot: Vector3 = Vector3(NAN, NAN, NAN)

## Resource heatmap
@export var show_resources: bool = false
var resource_cache: Dictionary = {}
var _decoration_multimeshes: Dictionary = {}
var _decoration_mesh_cache: Dictionary = {}
var _tree_materials: Dictionary = {}

const RESOURCE_TREE_MODELS := [
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/trees_A_large.tscn",
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/trees_B_large.tscn",
]
const RESOURCE_MOUNTAIN_MODELS := [
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/mountain_A.tscn",
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/mountain_B.tscn",
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/mountain_C.tscn",
]
const RESOURCE_ROCK_MODELS := [
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/rock_single_A.tscn",
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/rock_single_B.tscn",
	"res://assets/kaykit_medieval_hexagon_pack/decoration/nature/rock_single_C.tscn",
]
const RESOURCE_TREE_COLOR := Color(0.2, 0.7, 0.2, 0.5)
const RESOURCE_MOUNTAIN_COLOR := Color(0.6, 0.5, 0.5, 0.5)
const RESOURCE_ROCK_COLOR := Color(0.5, 0.5, 0.4, 0.5)

const SEASON_NAMES := ["Spring", "Summer", "Autumn", "Winter"]
var current_season: int = 1  # Summer default


func _ready() -> void:
	chunk_manager = ChunkManager.new(cells)
	_setup_3d()
	_setup_ui()
	var save_path := "res://map_save.json"
	if FileAccess.file_exists(save_path) and not FORCE_REGENERATE:
		if _load_map_from(save_path):
			return
	_needs_rebuild = true


func _exit_tree() -> void:
	if chunk_manager:
		chunk_manager.cleanup()


func _setup_3d() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 60.0
	camera.near = 0.01
	camera.far = 500.0
	add_child(camera)
	_update_camera_transform()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(30, 150, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.8, 0.85, 1.0)
	add_child(fill)

	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.4)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	hex_multimesh_instance = MultiMeshInstance3D.new()
	_hex_mat = StandardMaterial3D.new()
	_hex_mat.vertex_color_use_as_albedo = true
	_apply_hex_render_mode()
	hex_multimesh_instance.material_override = _hex_mat
	add_child(hex_multimesh_instance)

	overlay_mesh_instance = MeshInstance3D.new()
	var overlay_mat := StandardMaterial3D.new()
	overlay_mat.vertex_color_use_as_albedo = true
	overlay_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay_mesh_instance.material_override = overlay_mat
	add_child(overlay_mesh_instance)

	grid_lines_mesh_instance = MeshInstance3D.new()
	var grid_mat := StandardMaterial3D.new()
	grid_mat.vertex_color_use_as_albedo = true
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_lines_mesh_instance.material_override = grid_mat
	add_child(grid_lines_mesh_instance)

	_blocks_container = Node3D.new()
	add_child(_blocks_container)

	_objects_container = Node3D.new()
	add_child(_objects_container)

	_hex_prism_mesh = _create_hex_prism_mesh()


func _update_camera_transform() -> void:
	var yaw_rad := deg_to_rad(camera_yaw)
	var pitch_rad := deg_to_rad(camera_pitch)
	var offset := Vector3(
		cos(pitch_rad) * sin(yaw_rad),
		-sin(pitch_rad),
		cos(pitch_rad) * cos(yaw_rad)
	) * camera_distance
	camera.global_position = camera_pivot + offset
	camera.look_at(camera_pivot, Vector3.UP)


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

	_setup_top_toolbar(canvas)
	_setup_bottom_palette(canvas)
	_update_ui()


var _top_toolbar: HBoxContainer
var _bottom_palette: PanelContainer
var _palette_tabs: TabContainer
var _palette_grids: Dictionary = {}
var _tool_buttons: Array[Button] = []


func _setup_top_toolbar(canvas: CanvasLayer) -> void:
	var screen_size := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.position = Vector2(200, 0)
	panel.size = Vector2(screen_size.x - 210, 32)
	var toolbar_style := StyleBoxFlat.new()
	toolbar_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	toolbar_style.corner_radius_bottom_left = 4
	toolbar_style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", toolbar_style)
	canvas.add_child(panel)

	_top_toolbar = HBoxContainer.new()
	_top_toolbar.add_theme_constant_override("separation", 4)
	panel.add_child(_top_toolbar)

	var tool_defs := [
		["Nav", 0, "1"],
		["River", 1, "2"],
		["Road", 2, "3"],
		["Place", 3, "4"],
		["Raise", 4, "5"],
		["Flatten", 5, "6"],
		["Level", 6, "7"],
	]
	for td in tool_defs:
		var btn := Button.new()
		btn.text = "%s [%s]" % [td[0], td[2]]
		btn.toggle_mode = true
		btn.pressed.connect(_on_tool_button.bind(td[1]))
		btn.custom_minimum_size = Vector2(80, 26)
		_top_toolbar.add_child(btn)
		_tool_buttons.append(btn)

	var sep := VSeparator.new()
	_top_toolbar.add_child(sep)
	var hex_mode_btn := Button.new()
	hex_mode_btn.text = "Hex [T]"
	hex_mode_btn.custom_minimum_size = Vector2(80, 26)
	hex_mode_btn.pressed.connect(_cycle_hex_render_mode)
	_top_toolbar.add_child(hex_mode_btn)
	_hex_render_mode_btn = hex_mode_btn


func _on_tool_button(mode: int) -> void:
	_set_tool(mode)


func _update_tool_buttons() -> void:
	for i in _tool_buttons.size():
		_tool_buttons[i].button_pressed = (i == tool_mode)


func _cycle_hex_render_mode() -> void:
	hex_render_mode = (hex_render_mode + 1) % HEX_RENDER_MODE_NAMES.size()
	_apply_hex_render_mode()
	_tool_flash("Hex: " + HEX_RENDER_MODE_NAMES[hex_render_mode])


func _apply_hex_render_mode() -> void:
	match hex_render_mode:
		0:
			_hex_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_hex_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		1:
			_hex_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_hex_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		2:
			_hex_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_hex_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _setup_bottom_palette(canvas: CanvasLayer) -> void:
	var screen_size := get_viewport().get_visible_rect().size

	var panel := PanelContainer.new()
	panel.position = Vector2(4, screen_size.y - 134)
	panel.size = Vector2(screen_size.x - 8, 130)
	canvas.add_child(panel)
	_bottom_palette = panel

	_palette_tabs = TabContainer.new()
	_palette_tabs.size = Vector2(screen_size.x - 8, 130)
	_palette_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tab_style := StyleBoxFlat.new()
	tab_style.bg_color = Color(0.15, 0.15, 0.15, 0.85)
	tab_style.corner_radius_top_left = 4
	tab_style.corner_radius_top_right = 4
	tab_style.content_margin_left = 4
	tab_style.content_margin_right = 4
	tab_style.content_margin_top = 2
	tab_style.content_margin_bottom = 2
	_palette_tabs.add_theme_stylebox_override("panel", tab_style)
	_palette_tabs.add_theme_stylebox_override("tab_selected", tab_style)
	var tab_unsel := tab_style.duplicate()
	tab_unsel.bg_color = Color(0.25, 0.25, 0.25, 0.7)
	_palette_tabs.add_theme_stylebox_override("tab_unselected", tab_unsel)
	_palette_tabs.add_theme_font_size_override("font_size", 12)
	panel.add_child(_palette_tabs)

	_add_palette_tab("neutral", "res://assets/kaykit_medieval_hexagon_pack/buildings/neutral/")
	_add_palette_tab("nature", "res://assets/kaykit_medieval_hexagon_pack/decoration/nature/")
	_add_palette_tab("props", "res://assets/kaykit_medieval_hexagon_pack/decoration/props/")


func _add_palette_tab(tab_name: String, dir_path: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette_tabs.add_child(scroll)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	scroll.add_child(grid)
	_palette_grids[tab_name] = grid

	var cancel_btn := Button.new()
	cancel_btn.text = "X"
	cancel_btn.custom_minimum_size = Vector2(12, 12)
	cancel_btn.tooltip_text = "Cancel placement"
	var cancel_style := StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.5, 0.15, 0.15, 0.7)
	cancel_style.corner_radius_top_left = 3
	cancel_style.corner_radius_top_right = 3
	cancel_style.corner_radius_bottom_left = 3
	cancel_style.corner_radius_bottom_right = 3
	cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	var cancel_hover := cancel_style.duplicate()
	cancel_hover.bg_color = Color(0.7, 0.2, 0.2, 0.9)
	cancel_btn.add_theme_stylebox_override("hover", cancel_hover)
	cancel_btn.pressed.connect(_cancel_placement)
	grid.add_child(cancel_btn)

	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	var items: Array[String] = []
	while fname != "":
		if fname.ends_with(".tscn") and not fname.begins_with("."):
			items.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	items.sort()

	for tscn_name in items:
		var base_name := tscn_name.get_basename()
		var icon_path := dir_path + base_name + ".webp"
		var scene_path := dir_path + tscn_name

		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(72, 72)
		btn.size = Vector2(72, 72)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.2, 0.2, 0.2, 0.6)
		btn_style.corner_radius_top_left = 2
		btn_style.corner_radius_top_right = 2
		btn_style.corner_radius_bottom_left = 2
		btn_style.corner_radius_bottom_right = 2
		btn_style.content_margin_left = 1
		btn_style.content_margin_right = 1
		btn_style.content_margin_top = 1
		btn_style.content_margin_bottom = 1
		btn.add_theme_stylebox_override("normal", btn_style)
		var btn_hover := btn_style.duplicate()
		btn_hover.bg_color = Color(0.35, 0.35, 0.4, 0.8)
		btn.add_theme_stylebox_override("hover", btn_hover)
		var btn_pressed := btn_style.duplicate()
		btn_pressed.bg_color = Color(0.2, 0.4, 0.6, 0.9)
		btn.add_theme_stylebox_override("pressed", btn_pressed)

		if ResourceLoader.exists(icon_path):
			var tex := load(icon_path) as Texture2D
			if tex:
				btn.texture_normal = tex

		btn.pressed.connect(_on_palette_item_selected.bind(scene_path))
		btn.tooltip_text = base_name
		grid.add_child(btn)


func _on_palette_item_selected(path: String) -> void:
	selected_model_path = path
	_placement_scale = _default_scale
	_placement_rotation = 0.0
	tool_mode = 3
	_update_tool_buttons()
	_create_ghost(path)
	_tool_flash("Select: " + path.get_file().get_basename())


func _create_ghost(model_path: String) -> void:
	_remove_ghost()
	if not ResourceLoader.exists(model_path):
		return
	var scene: PackedScene = load(model_path)
	if not scene:
		return
	_ghost_instance = scene.instantiate()
	_objects_container.add_child(_ghost_instance)
	_ghost_model_path = model_path
	_set_node_transparency(_ghost_instance, 0.5)


func _set_node_transparency(node: Node, alpha: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			for i in mi.get_surface_override_material_count():
				var mat = mi.get_surface_override_material(i)
				if mat == null and mi.mesh != null:
					mat = mi.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					var new_mat: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
					new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					var col := new_mat.albedo_color
					col.a = alpha
					new_mat.albedo_color = col
					mi.set_surface_override_material(i, new_mat)
		_set_node_transparency(child, alpha)


func _update_ghost_position() -> void:
	if _ghost_instance == null:
		return
	var world_pos := _screen_to_world_3d(get_viewport().get_mouse_position())
	if world_pos.x == INF:
		_ghost_instance.visible = false
		return
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		_ghost_instance.visible = false
		return
	_ghost_instance.visible = true
	var cell: HexCellData = cells[hex]
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cell)
	_ghost_instance.position = Vector3(hpos.x, height, hpos.z)
	_ghost_instance.rotation_degrees.y = _placement_rotation
	_ghost_instance.scale = Vector3(_placement_scale, _placement_scale, _placement_scale)


func _remove_ghost() -> void:
	if _ghost_instance and is_instance_valid(_ghost_instance):
		_ghost_instance.queue_free()
	_ghost_instance = null
	_ghost_model_path = ""


func _cancel_placement() -> void:
	_remove_ghost()
	selected_model_path = ""
	_placement_rotation = 0.0
	_placement_scale = _default_scale
	_set_tool(0)


func _update_ui() -> void:
	var tool_name: String = TOOL_NAMES[tool_mode] if tool_mode < TOOL_NAMES.size() else "?"
	tool_label.text = "Tool: %s" % tool_name
	if tool_mode == 3:
		info_label.text = "Place: LMB | Cancel: RMB/Esc | Rotate: Z/X | Scale: KP+/KP- | Default: KP Enter | Rot: %.0f° | Scale: %.0f%%" % [_placement_rotation, _placement_scale * 100]
	else:
		info_label.text = "Orbit: MMB | Pan: WASD/RMB | Zoom: Scroll | Rot: Q/E | Grid: G | Overlay: H | ElevStep: F | Season: N | Regen: R | QSave: F6 | QLoad: F7 | Save: F8 | Load: F9 | Esc: Cancel"


# ============================================================================
# FRAME PROCESSING
# ============================================================================
func _process(delta: float) -> void:
	_discover_visible_chunks()
	_process_pending_batch()
	_process_pending_rivers()
	if _tool_flash_timer > 0.0:
		_tool_flash_timer -= delta
		if _tool_flash_timer <= 0.0:
			_update_ui()
	if not _pending_chunks.is_empty() or not _pending_rivers.is_empty():
		if chunk_manager._last_batch_generated:
			_needs_rebuild = true
			chunk_manager._last_batch_generated = false
	else:
		if _needs_save and not FORCE_REGENERATE:
			_save_map()
			_needs_save = false
		_update_hover_info()

	if _needs_rebuild:
		_rebuild_hex_multimesh()
		_rebuild_overlay_mesh()
		_rebuild_grid_lines()
		_update_block_instances()
		_update_object_instances()
		_needs_rebuild = false
		_needs_overlay_rebuild = false
	elif _needs_overlay_rebuild:
		_rebuild_overlay_mesh()
		_needs_overlay_rebuild = false

	if _needs_decoration_rebuild:
		_rebuild_decorations()
		_needs_decoration_rebuild = false

	if tool_mode == 1:
		var hover := _get_mouse_hex()
		if hover != _last_debug_hover_hex:
			_last_debug_hover_hex = hover
			_needs_overlay_rebuild = true

	if tool_mode == 3:
		_update_ghost_position()


func _update_hover_info() -> void:
	if tool_mode == 3:
		return
	var hex := _get_mouse_hex()
	if hex == _last_hover_hex:
		return
	_last_hover_hex = hex
	if _cell_exists(hex):
		var cell: HexCellData = cells[hex]
		var biome_name: String = BIOME_NAMES[cell.biome]
		var world_pos := _screen_to_world_3d(get_viewport().get_mouse_position())
		var hex_world := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var local := world_pos - hex_world
		var best_sub := 0
		var best_dist := INF
		for i in TOTAL_SUBS:
			var sub_pos := _get_sub_hex_local_pos(hex, i)
			var d := Vector2(local.x, local.z).distance_to(sub_pos)
			if d < best_dist:
				best_dist = d
				best_sub = i
		var wn := _count_sub_hex_water_neighbors(hex, best_sub)
		var sub_type := "Sub"
		if best_sub >= VERTEX_OFFSET:
			sub_type = "Vertex"
		var display_h: float = _get_cell_height(cell)
		var labels := ""
		if _is_hex_river(hex):
			labels += "  |  RIVER(%d)" % _hex_river_count(hex)
		if _is_hex_road(hex):
			labels += "  |  ROAD(%d)" % _hex_road_count(hex)
		if placed_objects.has(hex):
			var obj_data: Variant = placed_objects[hex]
			if obj_data is Dictionary:
				labels += "  |  OBJ rot:%.0f° scale:%.0f%%" % [obj_data.get("rotation", 0.0), obj_data.get("scale", 1.0) * 100]
			elif obj_data is String:
				labels += "  |  OBJ"
		if show_resources:
			var counts := _get_resource_counts(hex)
			if not counts.is_empty():
				var parts: PackedStringArray = []
				for rtype in counts:
					var display_name: String = rtype.capitalize()
					parts.append("%dx %s" % [counts[rtype], display_name])
				labels += "  |  Resources: " + ", ".join(parts)
		info_label.text = "Hex: (%d,%d,%d)  |  %s  |  %s %d  |  Elev: %.2f  |  Height: %.1f  |  Water nb: %d%s  |  Q:%d R:%d" % [
			hex.x, hex.y, hex.z, biome_name, sub_type, best_sub, cell.elevation, display_h, wn, labels,
			_pending_chunks.size(), _pending_rivers.size()
		]
	else:
		info_label.text = "Hex: none  |  Q:%d R:%d" % [_pending_chunks.size(), _pending_rivers.size()]


func _discover_visible_chunks() -> void:
	_ensure_draw_cache()
	for cq in range(_cached_chunk_min.x, _cached_chunk_max.x + 1):
		for cr in range(_cached_chunk_min.y, _cached_chunk_max.y + 1):
			var ck := Vector2i(cq, cr)
			if cq * cq + cr * cr > max_chunk_radius * max_chunk_radius:
				continue
			if not chunk_manager._loaded_chunk_origins.has(ck):
				if not _pending_chunks.has(ck) and _pending_chunks.size() < MAX_NEW_CHUNKS_QUEUED_PER_FRAME:
					_pending_chunks.append(ck)


func _process_pending_batch() -> void:
	if _pending_chunks.is_empty():
		return
	var count := mini(_pending_chunks.size(), MAX_TERRAIN_PER_FRAME)
	var batch: Array[Vector2i] = _pending_chunks.slice(0, count)
	_pending_chunks = _pending_chunks.slice(count)
	chunk_manager.generate_batch(batch)
	for ck in batch:
		_compute_chunk_resources(ck)
		if _chunk_has_cells(ck) and not chunks_with_rivers.has(ck):
			_pending_rivers.append(ck)
	if _pending_chunks.is_empty():
		_needs_save = true
		_needs_decoration_rebuild = true


func _process_pending_rivers() -> void:
	var processed := 0
	var remaining: Array[Vector2i] = []
	for ck in _pending_rivers:
		if chunks_with_rivers.has(ck):
			continue
		if processed < MAX_RIVERS_PER_FRAME and _chunk_all_neighbors_loaded(ck):
			_ensure_chunk_rivers(ck)
			processed += 1
		else:
			remaining.append(ck)
	_pending_rivers = remaining
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


# ============================================================================
# DRAW CACHE
# ============================================================================
func _invalidate_draw_cache() -> void:
	_cached_camera_yaw = NAN
	_cached_camera_pitch = NAN
	_cached_camera_distance = NAN
	_cached_camera_pivot = Vector3(NAN, NAN, NAN)


func _ensure_draw_cache() -> void:
	if _cached_camera_yaw == camera_yaw and _cached_camera_pitch == camera_pitch and \
	   _cached_camera_distance == camera_distance and _cached_camera_pivot == camera_pivot:
		return
	_cached_camera_yaw = camera_yaw
	_cached_camera_pitch = camera_pitch
	_cached_camera_distance = camera_distance
	_cached_camera_pivot = camera_pivot
	_cached_visible_hexes = _get_visible_hex_range()
	_cached_visible_set.clear()
	for hex in _cached_visible_hexes:
		_cached_visible_set[hex] = true
	if not _cached_visible_hexes.is_empty():
		_cached_chunk_min = _chunk_key(_cached_visible_hexes[0])
		_cached_chunk_max = _cached_chunk_min
		for hex in _cached_visible_hexes:
			var ck := _chunk_key(hex)
			_cached_chunk_min.x = mini(_cached_chunk_min.x, ck.x)
			_cached_chunk_max.x = maxi(_cached_chunk_max.x, ck.x)
			_cached_chunk_min.y = mini(_cached_chunk_min.y, ck.y)
			_cached_chunk_max.y = maxi(_cached_chunk_max.y, ck.y)
	_cached_visible_rivers.clear()
	for hex in river_cells:
		if _cached_visible_set.has(hex):
			_cached_visible_rivers.append(hex)
	_cached_visible_vertex_rivers.clear()
	for key in vertex_subs:
		var vdata: Dictionary = vertex_subs[key]
		if vdata["river"] and vdata.has("hex") and _cached_visible_set.has(vdata["hex"]):
			_cached_visible_vertex_rivers.append(key)
	_needs_rebuild = true


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
		camera_distance = clampf(camera_distance * 0.85, 2.0, 100.0)
		_update_camera_transform()
		_invalidate_draw_cache()
		return
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_distance = clampf(camera_distance * 1.15, 2.0, 100.0)
		_update_camera_transform()
		_invalidate_draw_cache()
		return

	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			orbiting = true
			orbit_start = event.position
		else:
			orbiting = false
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		if tool_mode == 1 and event.pressed:
			erasing = true
			_paint_river_at(event.position, true)
		elif not event.pressed:
			erasing = false
		if tool_mode == 3 and event.pressed:
			_cancel_placement()
			return
		if tool_mode in [0, 2, 4, 5, 6, 7]:
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
			3:
				_place_object_at(event.position)
			4:
				painting = true
				_raise_at(event.position)
			5:
				painting = true
				_flatten_at(event.position)
			6:
				painting = true
				_level_at(event.position)
			7:
				painting = true
				_water_flow_at(event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if orbiting:
		var delta := event.position - orbit_start
		camera_yaw += delta.x * 0.3
		camera_pitch = clampf(camera_pitch + delta.y * 0.3, -85.0, -10.0)
		orbit_start = event.position
		_update_camera_transform()
		_invalidate_draw_cache()
		return

	if panning:
		var delta := event.position - pan_start
		var forward := -camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		var pan_speed := camera_distance * 0.004
		camera_pivot += (right * delta.x + forward * -delta.y) * pan_speed
		pan_start = event.position
		_update_camera_transform()
		_invalidate_draw_cache()
		return

	if painting and tool_mode == 1:
		_paint_river_at(event.position, false)
		return
	elif erasing and tool_mode == 1:
		_paint_river_at(event.position, true)
		return
	elif painting and tool_mode == 4:
		_raise_at(event.position)
		return
	elif painting and tool_mode == 5:
		_flatten_at(event.position)
		return
	elif painting and tool_mode == 6:
		_level_at(event.position)
		return
	elif painting and tool_mode == 7:
		_water_flow_at(event.position)
		return


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	match event.keycode:
		KEY_1, KEY_KP_1:
			_set_tool(0)
		KEY_2, KEY_KP_2:
			_set_tool(1)
		KEY_3, KEY_KP_3:
			_set_tool(2)
		KEY_4, KEY_KP_4:
			_set_tool(3)
		KEY_5, KEY_KP_5:
			_set_tool(4)
		KEY_6, KEY_KP_6:
			_set_tool(5)
		KEY_7, KEY_KP_7:
			_set_tool(6)
		KEY_8, KEY_KP_8:
			_set_tool(7)
		KEY_H:
			show_overlay = not show_overlay
			_needs_overlay_rebuild = true
		KEY_G:
			show_grid = not show_grid
			_needs_overlay_rebuild = true
		KEY_J:
			show_resources = not show_resources
			_needs_overlay_rebuild = true
		KEY_V:
			show_height = not show_height
			_needs_rebuild = true
		KEY_INSERT:
			show_elevation_shade = not show_elevation_shade
			_needs_rebuild = true
		KEY_ESCAPE:
			if tool_mode == 3:
				_cancel_placement()
			else:
				_set_tool(0)
			road_start = Vector3i(999999, 999999, -1999998)
			painting = false
			erasing = false
			_last_debug_hover_hex = Vector3i(999999, 999999, -1999998)
			_needs_overlay_rebuild = true
		KEY_Q:
			camera_yaw -= 15.0
			_update_camera_transform()
			_invalidate_draw_cache()
		KEY_E:
			camera_yaw += 15.0
			_update_camera_transform()
			_invalidate_draw_cache()
		KEY_R:
			_regenerate_map()
		KEY_F:
			elevation_step_idx = (elevation_step_idx + 1) % ELEVATION_STEPS.size()
			elevation_step = ELEVATION_STEPS[elevation_step_idx]
			_needs_rebuild = true
			_needs_decoration_rebuild = true
			_tool_flash("Elevation: " + ELEVATION_STEP_NAMES[elevation_step_idx])
		KEY_N:
			current_season = (current_season + 1) % SEASON_NAMES.size()
			_update_tree_materials()
			_tool_flash("Season: " + SEASON_NAMES[current_season])
		KEY_T:
			_cycle_hex_render_mode()
		KEY_F6:
			_quick_save()
		KEY_F7:
			_quick_load()
		KEY_F8:
			_save()
		KEY_F9:
			_load()
		KEY_KP_ADD:
			if tool_mode == 3:
				_placement_scale = clampf(_placement_scale + 0.05, 0.75, 1.25)
				_tool_flash("Scale: %.0f%%" % (_placement_scale * 100))
		KEY_KP_SUBTRACT:
			if tool_mode == 3:
				_placement_scale = clampf(_placement_scale - 0.05, 0.75, 1.25)
				_tool_flash("Scale: %.0f%%" % (_placement_scale * 100))
		KEY_KP_ENTER:
			if tool_mode == 3:
				_default_scale = _placement_scale
				_tool_flash("Default scale: %.0f%%" % (_default_scale * 100))
		KEY_Z:
			if tool_mode == 3:
				_placement_rotation = wrapf(_placement_rotation - 60.0, 0.0, 360.0)
				_tool_flash("Rotation: %.0f°" % _placement_rotation)
		KEY_X:
			if tool_mode == 3:
				_placement_rotation = wrapf(_placement_rotation + 60.0, 0.0, 360.0)
				_tool_flash("Rotation: %.0f°" % _placement_rotation)


func _set_tool(mode: int) -> void:
	if tool_mode == 3 and mode != 3:
		_remove_ghost()
	tool_mode = mode
	_level_target = Vector3i(999999, 999999, -1999998)
	_flatten_captured = false
	painting = false
	erasing = false
	_last_debug_hover_hex = Vector3i(999999, 999999, -1999998)
	_needs_overlay_rebuild = true
	_update_tool_buttons()
	_update_ui()


func _regenerate_map() -> void:
	_remove_ghost()
	cells.clear()
	chunk_manager.cells = cells
	chunk_manager._loaded_chunk_origins.clear()
	chunk_manager.randomize_seeds()
	chunks_with_rivers.clear()
	river_cells.clear()
	road_cells.clear()
	vertex_subs.clear()
	roads.clear()
	placed_blocks.clear()
	_free_all_block_instances()
	placed_objects.clear()
	_free_all_object_instances()
	resource_cache.clear()
	_free_all_decorations()
	_pending_chunks.clear()
	_pending_rivers.clear()
	_needs_save = false
	_invalidate_draw_cache()
	_needs_rebuild = true


# ============================================================================
# SAVE / LOAD
# ============================================================================
func _save_map() -> void:
	var save_path := "res://map_save.json"
	chunk_manager.save_map(save_path, river_cells, road_cells, vertex_subs, chunks_with_rivers, roads, placed_blocks, placed_objects)


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
	placed_blocks = loaded.get("blocks", {})
	_rebuild_block_instances()
	placed_objects = loaded.get("objects", {})
	_rebuild_object_instances()
	_recompute_all_resources()
	_invalidate_draw_cache()
	_needs_rebuild = true
	_needs_decoration_rebuild = true
	return true


func _quick_save() -> void:
	_save_map()
	_tool_flash("Quick Saved")


func _quick_load() -> void:
	if _load_map_from("res://map_save.json"):
		_tool_flash("Quick Loaded")


func _save() -> void:
	chunk_manager.save_map("res://map_save_slot.json", river_cells, road_cells, vertex_subs, chunks_with_rivers, roads, placed_blocks, placed_objects)
	_tool_flash("Saved")


func _load() -> void:
	if _load_map_from("res://map_save_slot.json"):
		_tool_flash("Loaded")


func _tool_flash(msg: String) -> void:
	tool_label.text = msg
	_tool_flash_timer = 1.5


# ============================================================================
# COORDINATE CONVERSION
# ============================================================================
func _screen_to_world_3d(screen_pos: Vector2) -> Vector3:
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	if absf(ray_dir.y) < 0.0001:
		return Vector3(INF, INF, INF)
	var t := -ray_origin.y / ray_dir.y
	if t < 0:
		return Vector3(INF, INF, INF)
	return ray_origin + ray_dir * t


func _get_mouse_hex() -> Vector3i:
	var world_pos := _screen_to_world_3d(get_viewport().get_mouse_position())
	if world_pos.x == INF:
		return Vector3i(999999, 999999, -1999998)
	return HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)


func _cell_exists(hex: Vector3i) -> bool:
	return cells.has(hex)


func _elevation_to_color(e: float) -> Color:
	var t: float = clampf((e + 1.0) * 0.5, 0.0, 1.0)
	return Color(t, t, t, 0.4)


func _get_cell_height(cell: HexCellData) -> float:
	var step: float = ELEVATION_STEPS[elevation_step_idx]
	if _is_water_biome(cell.biome):
		return WATER_HEIGHT
	var hex_width: float = HEX_SIZE * HexGridMath.SQRT3
	if step <= 0.0:
		return HEX_SIZE
	var e := maxf(cell.elevation, 0.0)
	var height := e * hex_width + HEX_SIZE
	return snappedf(height, step)


# ============================================================================
# RIVER PAINTING
# ============================================================================
func _paint_river_at(screen_pos: Vector2, erase: bool) -> void:
	var world_pos := _screen_to_world_3d(screen_pos)
	if world_pos.x == INF:
		return
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if erase:
		if _cell_exists(hex):
			var best_sub := _find_closest_sub_hex(hex, world_pos)
			_river_erase(hex, best_sub)
	else:
		if not _cell_exists(hex):
			_needs_overlay_rebuild = true
			return
		var best_sub := _find_closest_sub_hex(hex, world_pos)
		var wn := _count_sub_hex_water_neighbors(hex, best_sub)
		if wn < 1 or wn > 2:
			_needs_overlay_rebuild = true
			return
		for nb in _get_sub_hex_neighbors(hex, best_sub):
			if river_cells.has(nb["hex"]) and nb["sub"] in river_cells[nb["hex"]]:
				if _count_sub_hex_water_neighbors(nb["hex"], nb["sub"]) + 1 > 2:
					_needs_overlay_rebuild = true
					return
		_river_paint(hex, best_sub)
	_needs_overlay_rebuild = true


func _find_closest_sub_hex(hex: Vector3i, world_pos: Vector3) -> int:
	var hex_world := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var local := Vector2(world_pos.x - hex_world.x, world_pos.z - hex_world.z)
	var best_sub := 0
	var best_dist := INF
	for i in TOTAL_SUBS:
		var sub_pos := _get_sub_hex_local_pos(hex, i)
		var d := local.distance_to(sub_pos)
		if d < best_dist:
			best_dist = d
			best_sub = i
	return best_sub


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


# ============================================================================
# ROAD PAINTING
# ============================================================================
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
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		return

	if road_start == Vector3i(999999, 999999, -1999998):
		road_start = hex
		_needs_overlay_rebuild = true
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
		_needs_overlay_rebuild = true


func _place_object_at(screen_pos: Vector2) -> void:
	if selected_model_path.is_empty():
		_tool_flash("No model selected")
		return
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		return
	_place_object_on_hex(hex, selected_model_path, _placement_rotation, _placement_scale)
	_needs_overlay_rebuild = true


func _place_object_on_hex(hex: Vector3i, model_path: String, rot: float = 0.0, scl: float = 1.0) -> void:
	_remove_object_at(hex)
	placed_objects[hex] = {"path": model_path, "rotation": rot, "scale": scl}
	if not ResourceLoader.exists(model_path):
		return
	var scene: PackedScene = load(model_path)
	if not scene:
		return
	var instance: Node3D = scene.instantiate()
	_objects_container.add_child(instance)
	var cell: HexCellData = cells[hex]
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cell)
	instance.position = Vector3(hpos.x, height, hpos.z)
	instance.rotation_degrees.y = rot
	instance.scale = Vector3(scl, scl, scl)
	_placed_object_instances[hex] = instance


func _remove_object_at(hex: Vector3i) -> void:
	placed_objects.erase(hex)
	if _placed_object_instances.has(hex):
		var inst: Node3D = _placed_object_instances[hex]
		_placed_object_instances.erase(hex)
		if is_instance_valid(inst):
			inst.queue_free()


func _free_all_object_instances() -> void:
	for hex in _placed_object_instances:
		var inst: Node3D = _placed_object_instances[hex]
		if is_instance_valid(inst):
			inst.queue_free()
	_placed_object_instances.clear()


func _rebuild_object_instances() -> void:
	_free_all_object_instances()
	for hex in placed_objects.keys():
		var obj_data: Variant = placed_objects[hex]
		if obj_data is String:
			_place_object_on_hex(hex, obj_data)
		elif obj_data is Dictionary:
			_place_object_on_hex(hex, obj_data["path"], obj_data.get("rotation", 0.0), obj_data.get("scale", 1.0))


func _update_object_instances() -> void:
	for hex in placed_objects.keys():
		var obj_data: Variant = placed_objects[hex]
		var model_path: String
		var rot: float = 0.0
		var scl: float = 1.0
		if obj_data is String:
			model_path = obj_data
		elif obj_data is Dictionary:
			model_path = obj_data["path"]
			rot = obj_data.get("rotation", 0.0)
			scl = obj_data.get("scale", 1.0)
		else:
			continue
		if not _placed_object_instances.has(hex):
			_place_object_on_hex(hex, model_path, rot, scl)
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell)
		var inst: Node3D = _placed_object_instances[hex]
		inst.position = Vector3(hpos.x, height, hpos.z)
		inst.rotation_degrees.y = rot
		inst.scale = Vector3(scl, scl, scl)


# ============================================================================
# RESOURCE HEATMAP & AUTO-DECORATIONS
# ============================================================================
func _resource_noise(hash_val: float) -> float:
	var x := sin(hash_val * 127.1 + hash_val * 311.7) * 43758.5453
	return x - floor(x)


func _resource_noise2(hash_val: float) -> float:
	var x := sin(hash_val * 419.2 + hash_val * 371.9) * 21458.3134
	return x - floor(x)


func _compute_resources_for_hex(hex: Vector3i) -> Array[Dictionary]:
	var resources: Array[Dictionary] = []
	if not _cell_exists(hex):
		return resources
	var cell: HexCellData = cells[hex]
	if cell.biome == BIOME_DEEP_WATER or cell.biome == BIOME_WATER or cell.biome == BIOME_BEACH or cell.biome == BIOME_LAKE:
		return resources
	var hex_h := float(hex.x) * 0.7 + float(hex.y) * 1.3
	var cluster := _resource_noise(hex_h)
	var in_tree_cluster := cluster < 0.10
	var in_mountain_cluster := cluster > 0.88 and cluster < 0.95
	var in_rock_cluster := cluster > 0.62 and cluster < 0.67
	for sub_idx in 7:
		if _is_sub_hex_water(hex, sub_idx) or _count_sub_hex_water_neighbors(hex, sub_idx) > 0:
			continue
		if river_cells.has(hex) and sub_idx in river_cells[hex]:
			continue
		var h := float(hex.x) * 12.9898 + float(hex.y) * 78.233 + float(sub_idx) * 45.164
		var density := _resource_noise(h)
		var density2 := _resource_noise2(h)
		var density3 := _resource_noise(h + 999.0)
		var resource_type := ""
		var model_path := ""
		if (cell.biome == BIOME_GRASS or cell.biome == BIOME_DIRT) and ((in_tree_cluster and density > 0.40) or (not in_tree_cluster and density > 0.93)):
			resource_type = "tree"
			model_path = RESOURCE_TREE_MODELS[int(h * 3.0) % RESOURCE_TREE_MODELS.size()]
		elif (cell.biome == BIOME_STONE or cell.biome == BIOME_DIRT) and ((in_mountain_cluster and density2 > 0.35) or (not in_mountain_cluster and density2 > 0.92)):
			resource_type = "mountain"
			model_path = RESOURCE_MOUNTAIN_MODELS[int(h * 7.0) % RESOURCE_MOUNTAIN_MODELS.size()]
		elif (cell.biome == BIOME_DIRT or cell.biome == BIOME_GRASS or cell.biome == BIOME_STONE) and ((in_rock_cluster and density3 > 0.45) or (not in_rock_cluster and density3 > 0.94)):
			resource_type = "rock"
			model_path = RESOURCE_ROCK_MODELS[int(h * 5.0) % RESOURCE_ROCK_MODELS.size()]
		if not resource_type.is_empty():
			resources.append({"sub_idx": sub_idx, "type": resource_type, "model": model_path})
	return resources


func _recompute_all_resources() -> void:
	resource_cache.clear()
	for hex in cells:
		var res := _compute_resources_for_hex(hex)
		if not res.is_empty():
			resource_cache[hex] = res


func _compute_chunk_resources(ck: Vector2i) -> void:
	for q in range(ck.x * CHUNK_SIZE, (ck.x + 1) * CHUNK_SIZE):
		for r in range(ck.y * CHUNK_SIZE, (ck.y + 1) * CHUNK_SIZE):
			var hex := Vector3i(q, r, -q - r)
			if _cell_exists(hex) and not resource_cache.has(hex):
				var res := _compute_resources_for_hex(hex)
				if not res.is_empty():
					resource_cache[hex] = res


func _load_decoration_mesh(model_path: String) -> Mesh:
	if _decoration_mesh_cache.has(model_path):
		return _decoration_mesh_cache[model_path]
	if not ResourceLoader.exists(model_path):
		return null
	var scene: PackedScene = load(model_path)
	if not scene:
		return null
	var root := scene.instantiate()
	var mesh: Mesh = _extract_mesh_from_node(root)
	_free_scene_children(root)
	if mesh:
		if _is_tree_model(model_path):
			var albedo_tex: Texture2D = null
			if mesh.get_surface_count() > 0:
				var orig_mat: Material = mesh.surface_get_material(0)
				if orig_mat is StandardMaterial3D:
					albedo_tex = (orig_mat as StandardMaterial3D).albedo_texture
				elif orig_mat is ShaderMaterial:
					albedo_tex = (orig_mat as ShaderMaterial).get_shader_parameter("albedo_texture")
			var tint_mat := _get_tree_material(model_path, albedo_tex)
			if tint_mat:
				mesh.surface_set_material(0, tint_mat)
		_decoration_mesh_cache[model_path] = mesh
	return mesh


func _is_tree_model(model_path: String) -> bool:
	return model_path.contains("tree")


func _is_evergreen(model_path: String) -> bool:
	return model_path.contains("trees_A") or model_path.contains("tree_single_A")


func _get_tree_material(model_path: String, albedo_tex: Texture2D = null) -> ShaderMaterial:
	var evergreen := _is_evergreen(model_path)
	var key := "evergreen" if evergreen else "deciduous"
	if _tree_materials.has(key):
		return _tree_materials[key]
	var shader := load("res://shaders/tree_tint.gdshader") as Shader
	if not shader:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("is_evergreen", evergreen)
	mat.set_shader_parameter("season", current_season)
	if albedo_tex:
		mat.set_shader_parameter("albedo_texture", albedo_tex)
	_tree_materials[key] = mat
	return mat


func _update_tree_materials() -> void:
	for key in _tree_materials:
		var mat: ShaderMaterial = _tree_materials[key]
		mat.set_shader_parameter("season", current_season)


func _extract_mesh_from_node(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for child in node.get_children():
		var m := _extract_mesh_from_node(child)
		if m:
			return m
	return null


func _free_scene_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _rebuild_decorations() -> void:
	_free_all_decorations()
	_ensure_draw_cache()
	var model_data: Dictionary = {}
	for hex in _cached_visible_hexes:
		if not resource_cache.has(hex) or not _cell_exists(hex):
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell)
		for res in resource_cache[hex]:
			var model_path: String = res["model"]
			var sub_idx: int = res["sub_idx"]
			if not model_data.has(model_path):
				model_data[model_path] = []
			var local := _get_sub_hex_local_pos(hex, sub_idx)
			var h1 := _resource_noise(float(hex.x) * 99.1 + float(hex.y) * 67.3 + float(sub_idx) * 23.7)
			var h3 := _resource_noise(float(hex.x) * 31.7 + float(hex.y) * 59.3 + float(sub_idx) * 87.1)
			var h4 := _resource_noise2(float(hex.x) * 11.3 + float(hex.y) * 93.7 + float(sub_idx) * 51.5)
			var rot_step := 60.0 if h1 > 0.5 else -60.0
			var mesh := _load_decoration_mesh(model_path)
			if not mesh:
				continue
			var aabb: AABB = mesh.get_aabb()
			var center := aabb.position + aabb.size * 0.5
			var max_horiz := maxf(aabb.size.x, aabb.size.z)
			var base_scl: float = SUB_HEX_SIZE * 0.925 / maxf(max_horiz, 0.01)
			var width_scl: float = base_scl * lerpf(1.0, 2.0, h3)
			var height_scl: float = base_scl * lerpf(1.0, 2.0, h4)
			var basis: Basis = Basis()
			basis = basis.rotated(Vector3.UP, deg_to_rad(rot_step))
			basis = basis.scaled(Vector3(width_scl, height_scl, width_scl))
			var center_xz := Vector3(center.x, 0.0, center.z)
			var rotated_center := basis * center_xz
			var origin := Vector3(
				hpos.x + local.x - rotated_center.x,
				height - height_scl * aabb.position.y,
				hpos.z + local.y - rotated_center.z
			)
			model_data[model_path].append(Transform3D(basis, origin))
	for model_path in model_data:
		var mesh := _load_decoration_mesh(model_path)
		if not mesh:
			continue
		var transforms: Array = model_data[model_path]
		var mm := MultiMesh.new()
		mm.mesh = mesh
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		add_child(mi)
		_decoration_multimeshes[model_path] = mi


func _free_all_decorations() -> void:
	for model_path in _decoration_multimeshes:
		var mi: MultiMeshInstance3D = _decoration_multimeshes[model_path]
		if is_instance_valid(mi):
			mi.queue_free()
	_decoration_multimeshes.clear()


func _get_resource_counts(hex: Vector3i) -> Dictionary:
	var counts := {}
	if resource_cache.has(hex):
		for res in resource_cache[hex]:
			var rtype: String = res["type"]
			counts[rtype] = counts.get(rtype, 0) + 1
	return counts


func _get_resource_color(rtype: String) -> Color:
	match rtype:
		"tree": return RESOURCE_TREE_COLOR
		"mountain": return RESOURCE_MOUNTAIN_COLOR
		"rock": return RESOURCE_ROCK_COLOR
	return Color.WHITE


# ============================================================================
# TERRAIN EDITING TOOLS
# ============================================================================
func _raise_at(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		return
	var cell: HexCellData = cells[hex]
	var old_elev := cell.elevation
	var hex_width: float = HEX_SIZE * HexGridMath.SQRT3
	var step := elevation_step if elevation_step > 0.0 else 0.1
	var delta := step / hex_width
	if Input.is_key_pressed(KEY_SHIFT):
		cell.elevation -= delta
	else:
		cell.elevation += delta
	cell.elevation = clampf(cell.elevation, -1.0, 2.0)
	if cell.elevation < old_elev - 0.01:
		_apply_water_flow_on_lower(hex)
	_needs_rebuild = true
	_needs_decoration_rebuild = true
	_invalidate_draw_cache()


func _flatten_at(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		return
	var cell: HexCellData = cells[hex]
	if not _flatten_captured:
		_flatten_target = cell.elevation
		_flatten_captured = true
	_flatten_single(hex)


func _flatten_single(hex: Vector3i) -> void:
	var cell: HexCellData = cells[hex]
	var old_elev := cell.elevation
	cell.elevation = _flatten_target
	if cell.elevation < old_elev - 0.01:
		_apply_water_flow_on_lower(hex)
	_needs_rebuild = true
	_needs_decoration_rebuild = true
	_invalidate_draw_cache()


func _level_at(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		return
	if _level_target == Vector3i(999999, 999999, -1999998):
		_level_target = hex
		_tool_flash("Level target set: (%d,%d,%d)" % [hex.x, hex.y, hex.z])
		return
	if hex == _level_target:
		return
	var target_cell: HexCellData = cells[_level_target]
	var cell: HexCellData = cells[hex]
	var old_elev := cell.elevation
	cell.elevation = target_cell.elevation
	if cell.elevation < old_elev - 0.01:
		_apply_water_flow_on_lower(hex)
	_needs_rebuild = true
	_needs_decoration_rebuild = true
	_invalidate_draw_cache()


# ============================================================================
# WATER FLOW MECHANICS
# ============================================================================
func _water_flow_at(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world_3d(screen_pos)
	var hex := HexGridMath.world_to_cube_flat_top(world_pos, HEX_SIZE)
	if not _cell_exists(hex):
		return
	_propagate_water(hex)
	_needs_rebuild = true
	_needs_decoration_rebuild = true
	_invalidate_draw_cache()


func _propagate_water(hex: Vector3i) -> void:
	var cell: HexCellData = cells[hex]
	if _is_water_biome(cell.biome):
		return
	var neighbors := HexGridMath.cube_neighbors(hex)
	var water_neighbors: Array[Vector3i] = []
	for nb in neighbors:
		if _cell_exists(nb) and _is_water_biome(cells[nb].biome):
			water_neighbors.append(nb)
	if water_neighbors.is_empty():
		return
	var has_flowing_water := false
	for wn in water_neighbors:
		if cells[wn].elevation <= cell.elevation + 0.01:
			has_flowing_water = true
			break
	if not has_flowing_water:
		return
	var roll := randf()
	if roll < 0.4:
		return
	var picked: Vector3i = water_neighbors[randi() % water_neighbors.size()]
	cell.biome = cells[picked].biome
	cell.color = cells[picked].color
	_rebuild_block_instances()
	_rebuild_object_instances()


func _apply_water_flow_on_lower(hex: Vector3i) -> void:
	var cell: HexCellData = cells[hex]
	if _is_water_biome(cell.biome):
		return
	var neighbors := HexGridMath.cube_neighbors(hex)
	var water_neighbors: Array[Vector3i] = []
	var all_neighbors: Array[Vector3i] = []
	for nb in neighbors:
		if _cell_exists(nb):
			all_neighbors.append(nb)
			if _is_water_biome(cells[nb].biome) and cells[nb].elevation <= cell.elevation + 0.01:
				water_neighbors.append(nb)
	var target_biome: int = -1
	var target_color: Color = Color.WHITE
	if not water_neighbors.is_empty():
		var wn := water_neighbors[randi() % water_neighbors.size()]
		target_biome = cells[wn].biome
		target_color = cells[wn].color
	elif not all_neighbors.is_empty():
		var roll := randf()
		if roll >= 0.4:
			var nb := all_neighbors[randi() % all_neighbors.size()]
			target_biome = cells[nb].biome
			target_color = cells[nb].color
	if target_biome >= 0:
		cell.biome = target_biome
		cell.color = target_color
		_rebuild_block_instances()
		_rebuild_object_instances()


func _create_block_instance(hex: Vector3i) -> void:
	if _block_instances.has(hex):
		return
	var cell: HexCellData = cells[hex]
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cell)
	var mi := MeshInstance3D.new()
	mi.mesh = _hex_grass_mesh
	mi.rotation_degrees.y = 30.0
	mi.position = Vector3(hpos.x, height, hpos.z)
	mi.scale.y = maxf(height, 0.05)
	_blocks_container.add_child(mi)
	_block_instances[hex] = mi


func _free_block_instance(hex: Vector3i) -> void:
	if _block_instances.has(hex):
		var mi: MeshInstance3D = _block_instances[hex]
		_block_instances.erase(hex)
		if is_instance_valid(mi):
			mi.queue_free()


func _free_all_block_instances() -> void:
	for hex in _block_instances:
		var mi: MeshInstance3D = _block_instances[hex]
		if is_instance_valid(mi):
			mi.queue_free()
	_block_instances.clear()


func _rebuild_block_instances() -> void:
	_free_all_block_instances()
	for hex in placed_blocks:
		_create_block_instance(hex)


func _update_block_instances() -> void:
	for hex in placed_blocks:
		if not _block_instances.has(hex):
			_create_block_instance(hex)
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell)
		var mi: MeshInstance3D = _block_instances[hex]
		mi.position = Vector3(hpos.x, height, hpos.z)
		mi.scale.y = maxf(height, 0.05)


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
			var next_hex: Vector3i = path[idx + 1]
			var diff := next_hex - hex
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
func _get_sub_hex_local_pos(_parent_hex: Vector3i, sub_idx: int) -> Vector2:
	if sub_idx == 0:
		return Vector2.ZERO
	elif sub_idx >= VERTEX_OFFSET:
		var vi: int = sub_idx - VERTEX_OFFSET
		var angle := deg_to_rad(60.0 * float(vi))
		return Vector2(cos(angle), sin(angle)) * HEX_SIZE
	else:
		var angle := deg_to_rad(30.0 + 60.0 * float(sub_idx - 1))
		return Vector2(cos(angle), sin(angle)) * SUB_HEX_DIST


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


# ============================================================================
# VISIBLE HEX RANGE
# ============================================================================
func _get_visible_hex_range() -> Array[Vector3i]:
	var viewport_size := get_viewport().get_visible_rect().size

	var corners := [
		Vector2(0, 0),
		Vector2(viewport_size.x, 0),
		Vector2(0, viewport_size.y),
		Vector2(viewport_size.x, viewport_size.y),
		Vector2(viewport_size.x * 0.5, viewport_size.y * 0.5),
	]
	var ground_points: Array[Vector3] = []
	for corner in corners:
		var gp := _screen_to_world_3d(corner)
		if gp.x != INF:
			ground_points.append(gp)

	if ground_points.is_empty():
		var center_hex := HexGridMath.world_to_cube_flat_top(camera_pivot, HEX_SIZE)
		return _spiral_range(center_hex, 5)

	var min_x := ground_points[0].x
	var max_x := ground_points[0].x
	var min_z := ground_points[0].z
	var max_z := ground_points[0].z
	for p in ground_points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)

	var span := maxf(max_x - min_x, max_z - min_z)
	var margin := maxf(HEX_SIZE * 3.0, span * 0.3)
	min_x -= margin
	max_x += margin
	min_z -= margin
	max_z += margin

	var h00 := HexGridMath.world_to_cube_flat_top(Vector3(min_x, 0, min_z), HEX_SIZE)
	var h01 := HexGridMath.world_to_cube_flat_top(Vector3(min_x, 0, max_z), HEX_SIZE)
	var h10 := HexGridMath.world_to_cube_flat_top(Vector3(max_x, 0, min_z), HEX_SIZE)
	var h11 := HexGridMath.world_to_cube_flat_top(Vector3(max_x, 0, max_z), HEX_SIZE)
	var range_min_q := mini(mini(h00.x, h01.x), mini(h10.x, h11.x)) - 2
	var range_max_q := maxi(maxi(h00.x, h01.x), maxi(h10.x, h11.x)) + 2
	var range_min_r := mini(mini(h00.y, h01.y), mini(h10.y, h11.y)) - 2
	var range_max_r := maxi(maxi(h00.y, h01.y), maxi(h10.y, h11.y)) + 2

	var result: Array[Vector3i] = []
	for q in range(range_min_q, range_max_q + 1):
		for r in range(range_min_r, range_max_r + 1):
			var hex := Vector3i(q, r, -q - r)
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			if hpos.x >= min_x - HEX_SIZE and hpos.x <= max_x + HEX_SIZE and \
			   hpos.z >= min_z - HEX_SIZE and hpos.z <= max_z + HEX_SIZE:
				result.append(hex)
	return result


func _spiral_range(center: Vector3i, radius: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = [center]
	for r in range(1, radius + 1):
		result.append_array(HexGridMath.cube_ring(center, r))
	return result


# ============================================================================
# 3D MESH: HEX PRISM TEMPLATE
# ============================================================================
func _create_hex_prism_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var top_verts: PackedVector3Array = PackedVector3Array()
	var bot_verts: PackedVector3Array = PackedVector3Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i))
		var x := cos(angle)
		var z := sin(angle)
		top_verts.append(Vector3(x, 1.0, z))
		bot_verts.append(Vector3(x, 0.0, z))

	var top_center := Vector3(0.0, 1.0, 0.0)
	for i in 6:
		var next_i := (i + 1) % 6
		st.add_vertex(top_center)
		st.add_vertex(top_verts[i])
		st.add_vertex(top_verts[next_i])

	var bot_center := Vector3(0.0, 0.0, 0.0)
	for i in 6:
		var next_i := (i + 1) % 6
		st.add_vertex(bot_center)
		st.add_vertex(bot_verts[next_i])
		st.add_vertex(bot_verts[i])

	for i in 6:
		var next_i := (i + 1) % 6
		st.add_vertex(bot_verts[i])
		st.add_vertex(top_verts[i])
		st.add_vertex(top_verts[next_i])
		st.add_vertex(bot_verts[i])
		st.add_vertex(top_verts[next_i])
		st.add_vertex(bot_verts[next_i])

	st.generate_normals()
	return st.commit()


# ============================================================================
# 3D MESH: REBUILD MULTIMESH
# ============================================================================
func _rebuild_hex_multimesh() -> void:
	var visible_hexes := _cached_visible_hexes
	var hex_count := 0
	for hex in visible_hexes:
		if _cell_exists(hex):
			hex_count += 1
	if hex_count == 0:
		hex_multimesh_instance.multimesh = null
		return

	var mm := MultiMesh.new()
	mm.mesh = _hex_prism_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = hex_count

	var idx := 0
	for hex in visible_hexes:
		if not _cell_exists(hex):
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell)
		var draw_color := cell.color
		if show_elevation_shade:
			var elev_col := _elevation_to_color(cell.elevation)
			draw_color = draw_color.lerp(elev_col, 0.4)
		if show_height:
			var brightness: float = lerpf(0.4, 1.6, (cell.elevation + 1.0) * 0.5)
			var height_col := Color(brightness, brightness, brightness, 0.35)
			draw_color = draw_color.lerp(height_col, 0.35)

		var t := Transform3D(Basis().scaled(Vector3(HEX_SIZE, height, HEX_SIZE)), Vector3(hpos.x, 0.0, hpos.z))
		mm.set_instance_transform(idx, t)
		mm.set_instance_color(idx, draw_color)
		idx += 1

	hex_multimesh_instance.multimesh = mm


# ============================================================================
# 3D MESH: REBUILD OVERLAY (rivers, roads, debug)
# ============================================================================
func _rebuild_overlay_mesh() -> void:
	var imm := ImmediateMesh.new()
	imm.clear_surfaces()
	var has_content := false

	# Rivers
	for hex in _cached_visible_rivers:
		if not river_cells.has(hex) or not _cell_exists(hex):
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell) + 0.05
		for sub_idx in river_cells[hex]:
			var local := _get_sub_hex_local_pos(hex, sub_idx)
			var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
			if not has_content:
				imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				has_content = true
			_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, Color(0.2, 0.45, 0.75, 0.75))

	# Vertex rivers
	for key in _cached_visible_vertex_rivers:
		var vdata: Dictionary = _get_vertex_data(key)
		if not vdata.has("hex") or not vdata.has("vi"):
			continue
		var hex: Vector3i = vdata["hex"]
		var vi: int = vdata["vi"]
		if not _cell_exists(hex):
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell) + 0.05
		var local := _get_sub_hex_local_pos(hex, VERTEX_OFFSET + vi)
		var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
		if not has_content:
			imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			has_content = true
		_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, Color(0.2, 0.45, 0.75, 0.75))

	# Roads
	for road in roads:
		var from_hex: Vector3i = road["from"]
		var to_hex: Vector3i = road["to"]
		if not _cell_exists(from_hex) or not _cell_exists(to_hex):
			continue
		if not has_content:
			imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			has_content = true
		_add_road_overlay_tris(imm, from_hex, to_hex, Color(0.6, 0.35, 0.15, 0.9))

	# Sub-hex overlay
	if show_overlay:
		for hex in _cached_visible_hexes:
			if not _cell_exists(hex):
				continue
			var cell: HexCellData = cells[hex]
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			var height := _get_cell_height(cell) + 0.03
			for i in TOTAL_SUBS:
				var local := _get_sub_hex_local_pos(hex, i)
				var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
				if not has_content:
					imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
					has_content = true
				_add_flat_hex_wireframe(imm, center, SUB_HEX_SIZE, Color(1, 1, 1, 0.25))

	# River tool debug
	if tool_mode == 1:
		if not has_content:
			imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			has_content = true
		_add_river_debug_overlay_tris(imm)

	# Resource heatmap
	if show_resources:
		for hex in _cached_visible_hexes:
			if not resource_cache.has(hex) or not _cell_exists(hex):
				continue
			var cell: HexCellData = cells[hex]
			var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
			var height := _get_cell_height(cell) + 0.04
			for res in resource_cache[hex]:
				var local := _get_sub_hex_local_pos(hex, res["sub_idx"])
				var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
				if not has_content:
					imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
					has_content = true
				_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, _get_resource_color(res["type"]))

	if has_content:
		imm.surface_end()
		overlay_mesh_instance.mesh = imm
	else:
		overlay_mesh_instance.mesh = null


func _add_flat_hex_tris(imm: ImmediateMesh, center: Vector3, size: float, col: Color) -> void:
	for i in 6:
		var angle1 := deg_to_rad(60.0 * float(i))
		var angle2 := deg_to_rad(60.0 * float((i + 1) % 6))
		var v1 := center + Vector3(cos(angle1), 0.0, sin(angle1)) * size
		var v2 := center + Vector3(cos(angle2), 0.0, sin(angle2)) * size
		imm.surface_set_color(col)
		imm.surface_add_vertex(center)
		imm.surface_set_color(col)
		imm.surface_add_vertex(v1)
		imm.surface_set_color(col)
		imm.surface_add_vertex(v2)


func _add_flat_hex_wireframe(imm: ImmediateMesh, center: Vector3, size: float, col: Color) -> void:
	var up := Vector3.UP * 0.02
	var thin := 0.015
	for i in 6:
		var angle1 := deg_to_rad(60.0 * float(i))
		var angle2 := deg_to_rad(60.0 * float((i + 1) % 6))
		var v1 := center + Vector3(cos(angle1), 0.0, sin(angle1)) * size
		var v2 := center + Vector3(cos(angle2), 0.0, sin(angle2)) * size
		var edge := v2 - v1
		var perp := Vector3(-edge.z, 0.0, edge.x).normalized() * thin
		var a := v1 + perp + up
		var b := v1 - perp + up
		var c := v2 - perp + up
		var d := v2 + perp + up
		imm.surface_set_color(col)
		imm.surface_add_vertex(a)
		imm.surface_set_color(col)
		imm.surface_add_vertex(b)
		imm.surface_set_color(col)
		imm.surface_add_vertex(c)
		imm.surface_set_color(col)
		imm.surface_add_vertex(a)
		imm.surface_set_color(col)
		imm.surface_add_vertex(c)
		imm.surface_set_color(col)
		imm.surface_add_vertex(d)


func _add_road_overlay_tris(imm: ImmediateMesh, from_hex: Vector3i, to_hex: Vector3i, col: Color) -> void:
	var diff := to_hex - from_hex
	var dir := -1
	for d in 6:
		if HexGridMath.cube_direction(d) == diff:
			dir = d
			break

	if not _is_sub_hex_water(from_hex, 0):
		_add_sub_hex_fill_tris(imm, from_hex, 0, col)
	if dir >= 0:
		var exit_sub := ((6 - dir) % 6) + 1
		if not _is_sub_hex_water(from_hex, exit_sub):
			_add_sub_hex_fill_tris(imm, from_hex, exit_sub, col)
		var entry_dir := (dir + 3) % 6
		var entry_sub := ((6 - entry_dir) % 6) + 1
		if not _is_sub_hex_water(to_hex, entry_sub):
			_add_sub_hex_fill_tris(imm, to_hex, entry_sub, col)
	if not _is_sub_hex_water(to_hex, 0):
		_add_sub_hex_fill_tris(imm, to_hex, 0, col)


func _add_sub_hex_fill_tris(imm: ImmediateMesh, hex: Vector3i, sub_idx: int, col: Color) -> void:
	if not _cell_exists(hex):
		return
	var cell: HexCellData = cells[hex]
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cell) + 0.06
	var local := _get_sub_hex_local_pos(hex, sub_idx)
	var center := Vector3(hpos.x + local.x, height, hpos.z + local.y)
	_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, col)


func _add_river_debug_overlay_tris(imm: ImmediateMesh) -> void:
	var hex := _get_mouse_hex()
	if not _cell_exists(hex):
		return
	var cell: HexCellData = cells[hex]
	var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
	var height := _get_cell_height(cell) + 0.08

	var world_pos := _screen_to_world_3d(get_viewport().get_mouse_position())
	var local := Vector2(world_pos.x - hpos.x, world_pos.z - hpos.z)
	var best_sub := 0
	var best_dist := INF
	for i in TOTAL_SUBS:
		var sub_pos := _get_sub_hex_local_pos(hex, i)
		var d := local.distance_to(sub_pos)
		if d < best_dist:
			best_dist = d
			best_sub = i

	for i in TOTAL_SUBS:
		var result: Array = _can_place_river(hex, i)
		var ok: bool = result[0]
		var sub_pos := _get_sub_hex_local_pos(hex, i)
		var center := Vector3(hpos.x + sub_pos.x, height, hpos.z + sub_pos.y)
		if ok:
			var fill_col := Color(0.2, 0.8, 0.2, 0.3)
			if i == best_sub:
				fill_col = Color(0.2, 0.9, 0.2, 0.5)
			_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, fill_col)
		else:
			var fill_col := Color(0.8, 0.2, 0.2, 0.3)
			if i == best_sub:
				fill_col = Color(0.9, 0.2, 0.2, 0.5)
			_add_flat_hex_tris(imm, center, SUB_HEX_SIZE, fill_col)


# ============================================================================
# 3D MESH: GRID LINES
# ============================================================================
func _rebuild_grid_lines() -> void:
	if not show_grid:
		grid_lines_mesh_instance.mesh = null
		return

	var imm := ImmediateMesh.new()
	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_LINES)

	var grid_col := Color(0, 0, 0, 0.2)
	for hex in _cached_visible_hexes:
		if not _cell_exists(hex):
			continue
		var cell: HexCellData = cells[hex]
		var hpos := HexGridMath.cube_to_world_flat_top(hex, HEX_SIZE)
		var height := _get_cell_height(cell) + 0.02
		var cos_arr: PackedFloat32Array = PackedFloat32Array()
		var sin_arr: PackedFloat32Array = PackedFloat32Array()
		for i in 6:
			var angle := deg_to_rad(60.0 * float(i))
			cos_arr.append(cos(angle))
			sin_arr.append(sin(angle))
		for i in 6:
			var next_i := (i + 1) % 6
			var x1 := hpos.x + cos_arr[i] * HEX_SIZE
			var z1 := hpos.z + sin_arr[i] * HEX_SIZE
			var x2 := hpos.x + cos_arr[next_i] * HEX_SIZE
			var z2 := hpos.z + sin_arr[next_i] * HEX_SIZE
			imm.surface_set_color(grid_col)
			imm.surface_add_vertex(Vector3(x1, height, z1))
			imm.surface_set_color(grid_col)
			imm.surface_add_vertex(Vector3(x2, height, z2))

	imm.surface_end()
	grid_lines_mesh_instance.mesh = imm
