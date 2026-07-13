# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed
- **Noise pattern repeating across chunks** — `_generate_chunk_tiles()` now offsets noise sampling by chunk world position instead of always sampling from (0,0).
- **Biomes too small/inconsistent** — Added fractal noise (3 octaves) with lower base frequency for larger, more natural biome regions.

### Added
- **Terrain deformation** — Flat tiles now have slight elevation jitter (±5% of hex width) for a more natural surface.
- **Road and River painters** — New exclusive painter system:
  - River overrides road (same tile cannot be both).
  - Roads draw straight connections between adjacent road tiles.
  - Rivers draw curvy connections with 45-degree bisectors at 90-degree turns.
  - Each painter draws a colored dot at the center and connecting strips to neighbors.
