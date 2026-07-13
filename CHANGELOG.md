# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed
- **Noise pattern repeating across chunks** — `_generate_chunk_tiles()` now uses `get_noise_2d()` with world-positioned coordinates instead of `get_image()` which always sampled from (0,0).
- **Biomes too small/inconsistent** — Added fractal noise (FBM, 3 octaves) with lower base frequency (0.008) for larger, more natural biome regions.
- **Terrain modes** — Default view shows smooth terrain (flat hexes at varying heights). F key switches to voxel view with 1m-stepped hex columns.
- **Painter UX** — LMB places, RMB removes. Escape cancels all modes. Strip meshes now reach neighbor centers (sqrt(3) * HEX_SIZE).

### Added
- **Terrain deformation** — Voxel mode has deterministic height jitter for natural variation between steps.
- **Road and River painters** — Exclusive painter system:
  - River overrides road (same tile cannot be both).
  - Roads draw straight connections, rivers draw curvy sinusoidal connections.
  - 90-degree turns get bisecting dot connectors.
  - Drag-painting with both LMB (place) and RMB (remove).
