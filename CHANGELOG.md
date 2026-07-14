# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed
- **Complete 2D rewrite** — Stripped all 3D rendering (chunks, meshes, shaders, libraries). Kept only `HexGridMath` and simplified `HexCellData`.
- **2D hex map** — Flat 2D top-down hex map with Camera2D panning (WASD/MMB) and scroll zoom.
- **Noise-based terrain** — Infinite terrain generated on-demand from FastNoiseLite (Simplex Smooth, FBM 3 octaves). 6 biomes: deep water, water, beach, grass, dirt, stone.
- **Sub-hex overlay** — Every hex split into 7 sub-hexes (1 center + 6 ring). Transparent by default, toggle with H key.
- **River paint brush** — Free-draw rivers on sub-hexes. LMB paint, RMB erase. Toggle full/half brush with Shift.
- **Road line tool** — Point-to-point thick line drawing. Click first hex, click second hex to draw road. Roads rendered as thick lines with end caps.
- **Controls** — 1=Navigate, 2=River, 3=Road. G=grid lines. H=overlay. Esc=cancel.
