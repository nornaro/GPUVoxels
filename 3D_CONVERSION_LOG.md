# 3D Hex Conversion Log

## Session 1 - Full 2D→3D Conversion

### Files Changed
- `HexGrid/hex_map.tscn`: Node2D → Node3D
- `HexGrid/hex_map.gd`: Complete rewrite from Node2D to Node3D
- `HexGrid/hex_cell_data.gd`: Added get_world_position_3d()
- `project.godot`: Updated viewport stretch mode for 3D

### Architecture Changes
- Rendering: 2D ArrayMesh/CanvasItem draw → MultiMeshInstance3D + ImmediateMesh
- Camera: Manual pan/zoom → 3D orbit camera (yaw/pitch/distance/pivot)
- Input: 2D screen→world → 3D raycasting via Camera3D
- Lighting: Added DirectionalLight3D + WorldEnvironment
- Hex visualization: Flat 2D polygons → 3D hexagonal prisms extruded by elevation

### Key Constants
- HEIGHT_SCALE: 15.0 (elevation → Y height multiplier)
- WATER_HEIGHT: 0.3 (flat water slab height)

### Function Mapping (2D → 3D)
- `_draw()` → `_rebuild_hex_multimesh()` + `_rebuild_overlay_mesh()`
- `queue_redraw()` → `_needs_rebuild = true`
- `_screen_to_world()` → `_screen_to_world_3d()` (ray-ground intersection)
- `_world_to_screen()` → removed (not needed in 3D)
- `_build_hex_mesh()` → `_rebuild_hex_multimesh()` (MultiMesh)
- `_draw_river_hex()` → `_add_river_overlay()` (ImmediateMesh)
- `_draw_road_line()` → `_add_road_overlay()` (ImmediateMesh)
- `_draw_sub_hex_overlay()` → `_add_sub_hex_overlay()` (ImmediateMesh)
- `_draw_river_debug()` → `_add_river_debug_overlay()` (ImmediateMesh)
- `_draw_filled_sub()` → `_add_flat_hex()` (ImmediateMesh helper)
- `_hex_corners()` → `_hex_corners_3d()` (returns Vector3 array)

### Untouched Files
- `HexGrid/chunk_manager.gd`: No changes (data structures identical)
- `HexGrid/hex_grid_math.gd`: No changes (already returns Vector3)
- `shaders/compute_noise.glsl`: No changes (generates same data)

### Bug Fixes During Testing
- Removed `TONE_MAP_ACES` (not in Godot 4.7 API)
- Changed `Basis(Vector3)` → `Basis().scaled(Vector3)` (no such constructor)
- Changed `imm.set_color()`/`imm.add_vertex()` → `imm.surface_set_color()`/`imm.surface_add_vertex()` (ImmediateMesh API)
- Reordered MultiMesh properties: `transform_format`/`use_colors` set BEFORE `instance_count`
- Fixed camera Y: `sin(pitch)` → `-sin(pitch)` so negative pitch = camera above ground
- Added StandardMaterial3D with vertex_color_use_as_albedo to hex_multimesh_instance
- Fixed RMB pan: project camera basis onto XZ ground plane, use correct sign conventions
- Rewrote _get_visible_hex_range: use viewport corners + center projected to ground, auto-margin based on span

### Feature: Elevation Stepping (F key)
- F cycles through: Step 1.0m → Step 0.1m → Flat (0m)
- `_get_cell_height` snaps elevation to step before scaling
- Flash message shows current mode

### Test Results
- `godot --headless --quit-after 5` — only expected headless GPU error (no GPU for compute shader)
- Zero script parse errors
- Zero runtime errors
