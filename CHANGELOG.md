# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed
- **Noise pattern repeating across chunks** — `_generate_chunk_tiles()` now uses `get_noise_2d()` with world-positioned coordinates instead of `get_image()` which always sampled from (0,0).
- **Biomes too small/inconsistent** — Added fractal noise (FBM, 3 octaves) with lower base frequency (0.008) for larger, more natural biome regions.
- **Terrain deformation invisible in flat mode** — Moved jitter from `_generate_chunk_tiles` to `_make_transform` so it applies after flat mode scaling. Updated outline, overlay, and ghost positions to match.
- **Painter unresponsive / spots appear and disappear** — Removed double-click gate that made single clicks do nothing. Painter events now bypass the `not event.pressed` guard so mouse release fires correctly. Added drag-painting support.

### Added
- **Terrain deformation** — Tiles have deterministic elevation jitter (±50% of hex width for testing, ±10% for release) applied in both flat and 3D modes.
- **Road and River painters** — Exclusive painter system with single-click and drag-painting:
  - River overrides road (same tile cannot be both).
  - Roads draw straight connections between adjacent road tiles.
  - Rivers draw curvy sinusoidal connections with 45-degree bisectors at 90-degree turns.
  - Each painter draws a colored dot at the center and connecting strips to neighbors.
