# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- **GPU compute shader** — Wired up `compute_noise.glsl` via `RenderingDevice`. All terrain noise generation (base elevation + 12 detail sub-heights) now runs on GPU with automatic CPU fallback. Eliminates ~10M FastNoiseLite calls per generation.
- **Binary save format** — Maps saved as packed binary (magic `HVBM`, ~50KB per 785K cells) instead of JSON (~200MB). Auto-detects format on load. JSON maps still loadable for migration.
- **Ring-based progressive generation** — World generates in expanding rings (0→10→20→30→40→50 chunks radius). First ring shows terrain immediately. Each ring: chunks → rivers → resources → full rebuild → save → next ring.
- **Generation progress panel** — Centered on-screen panel with title, status, color-coded log during generation.
- **Index-based chunk/resource queues** — Eliminated O(n) `slice()` per frame for both chunk and resource queues.
- **Unlimited river processing** — During generation, all pending rivers processed per frame (no throttle).
- **Skip resource computation on load** — Loaded maps bypass resource recomputation entirely (not saved, not needed for display).

### Changed
- **Larger landmasses** — Reduced base noise frequency from 0.03 to 0.0075 (4x) and detail frequency from 0.1 to 0.025 (4x), making continents and biomes scale ~4x larger. Randomized seed ranges adjusted accordingly.
- **Zoom-out stutter fix (LOD)** — Smooth terrain and water mesh grid step now scales with camera distance (1x at default zoom to 5x at max zoom-out), reducing vertex count from ~326K to ~13K at max zoom-out. Smooth rebuild timer also scales (0.15s to 0.6s debounce).
- **Grid lines skip at distance** — Grid lines are no longer rebuilt when camera distance exceeds 60 (invisible at that scale anyway), saving thousands of trig calls per frame.
- **Cull margins** — Added extra_cull_margin (20-50) on hex multimesh, smooth terrain, and water mesh instances to prevent frustum-edge popping during camera movement.
- **No rebuild on camera movement** — Removed all mesh rebuild triggers from `_ensure_draw_cache()`. Water mesh, grid lines, multimesh, smooth terrain, and decorations now only rebuild when new chunk data is generated, not on every pan/zoom. Multimesh covers full chunk range +1 border so panning within generated terrain requires zero rebuilds.
- **Batch size during generation** — Immediately uses MAX_TERRAIN_PER_FRAME (128) instead of ramping from 16.
- **`_get_sub_hex_neighbors`** — Returns flat `Array` of `[Vector3i, int]` pairs instead of `Array` of `Dictionary` with string keys. Eliminates ~126M Dict heap allocations during resource computation.
- **`_count_sub_hex_water_neighbors`** — Fully inlined with zero allocations. Computes neighbor water checks directly without intermediate data structures.
- **`_flow_escape_basin` A\*** — Replaced linear scan min-finding with insertion-sorted `PackedFloat32Array` for O(log n) insertion instead of O(n) extraction.
- **`_rebuild_smooth_terrain`** — Uses `cells[nearest_hex].biome` directly instead of re-evaluating noise via `sample_biome()` per vertex.
- **GLSL compute shader** — Fixed biome classification thresholds and added elevation remapping to match CPU behavior. Input space now uses (q, r) coordinates matching CPU.

### Fixed
- **`_flow_river` short-circuit** — Split combined `_cell_exists(start) and _is_water_biome(...)` check so non-existent start returns `[]` without crashing.
- **`_level_at` re-validation** — Validates `_level_target` still exists before accessing cells dictionary.
- **`_pending_resource_recompute` loop** — Fixed broken GDScript `for` loop syntax.
- **Load path performance** — `_load_map_from` no longer routes through generation block. Sets `_generating = false` immediately and uses `_queue_post_load_rebuilds()` for fast ~1s loads.

### Previous (carried forward)
- **Complete 2D rewrite** — Stripped all 3D rendering. Kept `HexGridMath` and simplified `HexCellData`.
- **Noise-based terrain** — Infinite terrain from FastNoiseLite. 6 biomes: deep water, water, beach, grass, dirt, stone.
- **Sub-hex overlay** — 7 sub-hexes per hex. Toggle with H key.
- **River paint brush** — Free-draw rivers on sub-hexes. LMB paint, RMB erase.
- **Road line tool** — Point-to-point thick line drawing.
- **Controls** — 1=Navigate, 2=River, 3=Road. G=grid. H=overlay. Esc=cancel.
