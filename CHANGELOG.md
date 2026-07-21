# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed
- **Larger landmasses** — Reduced base noise frequency from 0.03 to 0.0075 (4x) and detail frequency from 0.1 to 0.025 (4x), making continents and biomes scale ~4x larger. Randomized seed ranges adjusted accordingly.
- **Zoom-out stutter fix (LOD)** — Smooth terrain and water mesh grid step now scales with camera distance (1x at default zoom to 5x at max zoom), reducing vertex count from ~326K to ~13K at max zoom-out. Smooth rebuild timer also scales (0.15s to 0.6s debounce).
- **Grid lines skip at distance** — Grid lines are no longer rebuilt when camera distance exceeds 60 (invisible at that scale anyway), saving thousands of trig calls per frame.
- **Cull margins** — Added extra_cull_margin (20-50) on hex multimesh, smooth terrain, and water mesh instances to prevent frustum-edge popping during camera movement.

### Fixed
- **`_flow_river` short-circuit** — Split combined `_cell_exists(start) and _is_water_biome(...)` check so non-existent start returns `[]` without crashing.
- **`_level_at` re-validation** — Validates `_level_target` still exists before accessing cells dictionary.
- **`_pending_resource_recompute` loop** — Fixed broken GDScript `for` loop syntax.

### Previous (carried forward)
- **Complete 2D rewrite** — Stripped all 3D rendering. Kept `HexGridMath` and simplified `HexCellData`.
- **Noise-based terrain** — Infinite terrain from FastNoiseLite. 6 biomes: deep water, water, beach, grass, dirt, stone.
- **Sub-hex overlay** — 7 sub-hexes per hex. Toggle with H key.
- **River paint brush** — Free-draw rivers on sub-hexes. LMB paint, RMB erase.
- **Road line tool** — Point-to-point thick line drawing.
- **Controls** — 1=Navigate, 2=River, 3=Road. G=grid. H=overlay. Esc=cancel.
