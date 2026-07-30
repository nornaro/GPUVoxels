# 2DO — Terrain System For Smooth Hex Based Tower Defense: State, Analysis & Plan

## 1. The Vision (from your description)

### Core Terrain — "The Fabric"
- A **single continuous mesh** (fabric/sheet) — **NOT per-hex geometry**
- Mesh vertices are the **shared corner points where 3 hexes meet** (not hex centers)
- Those vertices are displaced by heightmap noise
- The **hex grid is projected onto this fabric in the shader** — hex lines, centers, edges are all computed in the shader from world position
- The shader **colors the fabric** based on elevation + biome
- **Edges meld smoothly** into each other (natural interpolation)
- Subhexes (13 per hex) are **projected onto each hex cell via shader**, each with resource data derived from noise

### View & Streaming
- Hexes stream in/out based on camera view
- **20% buffer** outside camera frustum for pre-loading/pre-unloading
- Resources/subhexes filled on-demand via noise (or loaded from save)
- Binary save/load for fast GPU-loadable files

### UI & Overlays
- Mouse hover: **highlight the hex** with 75% transparent bright yellow layer
- **Hex grid lines projected via shader** (not geometry)
- **H key**: show subhex overlay, hide resource meshes, show resource colors + small random numbers (0-9)
- **Seamless dirt/grass/stone noise textures** with normal maps for 3D detail
- Seasonal tree colors: pines stay vibrant green with colored dots; deciduous go green→yellow→red→brown-white

### Terrain Editing
- Raise/lower terrain via UI sliders
- Flatten areas to target elevation
- Buildable objects placed on hexes, **deformed to fit the cell's curve**
- Buildables/units use hex **center points** for placement and navigation

### Units & Pathfinding
- Units spawn over random deep-water points
- They path toward center (radius 1-2), selecting lower-value cells
- Path computed at spawn time; **visually moved on 3D path by GPU**
- Paths updated only when a chunk changes; enemies whose route crosses the changed chunk get re-routed
- Registry of units → routes → chunks/cells for fast lookup

### Performance Targets
| Scenario | FPS Target |
|---|---|
| Empty terrain | 2000+ |
| 10,000 units | 240+ |
| 20,000 units | 120+ |
| 100,000 units | 30+ |
- Main thread never blocked
- CPU/GPU threaded; out-of-focus content stops rendering
- Minimal `_process` calls; use `_physics_process` where possible
- Heavy work batched to GPU; CPU/GPU communicate via large buffers

---

## 2. What Worked in the Past (from git history)

### Legacy Smooth Terrain (`6e58462`, July 20 — **REMOVED** `12bc46e`, July 29)
- Built a **continuous grid mesh** at 0.3× hex resolution from noise
- Sampled `chunk_manager.sample_height()` + `sample_biome()` per vertex
- Had **LOD**: grid step scaled 1×→5× with camera distance (326K→13K verts)
- Shore blending, wave shader, depth gradient
- **This was the closest to the "fabric" vision** — it's what should be resurrected

### Chunked Streaming (`30207c6`, July 23)
- 32-hex chunks with VIEW_CHUNKS=6 (visible radius ~192 hexes)
- 1 chunk/frame generation, sorted by camera distance
- Frustum culling on MultiMeshInstance3D nodes
- Radius slider 10–10000

### No-Rebuild-on-Pan (`c968be1`, July 21)
- MultiMesh covers full chunk range +1 border
- Dead-zone throttle (0.3 unit) to prevent micro-rebuilds
- Panning/zooming within generated terrain = zero mesh rebuilds

### Chunk Throttle + Overlay Caching (`05cd70d`, July 28)
- 2 chunks/frame, sorted by distance
- Per-frame cached mouse hex
- Overlay rebuild throttled 80ms

### Corner Averaging Formulas
- `VERTEX_NEIGHBORS` / `CORNER_NBORS` in both `hex_map.gd` and `approach_flat.gd` correctly map each hex corner to the 2 cube directions sharing it
- `_get_cell_elevation()` reads from `cells` dict (or creates on demand)

### GPU Compute for Noise & Pathfinding
- `compute_noise.glsl`: batch noise generation via RenderingDevice
- `pathfinding.glsl`: hex-grid pathfinding on GPU
- `enemy_compute.glsl`: enemy movement on GPU

### Binary Save/Load
- Format: magic `0x48564D50`, version 4
- Stores noise params, all cells (biome, elevation, 13 sub-heights), rivers, roads, objects, resources
- Auto-detects binary vs JSON

---

## 3. What Works NOW (current HEAD)

### Mesh Generation
- `approach_flat.gd`: single ArrayMesh, 6 triangle-fans per hex, **per-corner e_norm averaging** (just fixed), vertices at y=0 (shader displaces Y)
- `approach_prisms.gd`: per-chunk MultiMeshInstance3D, 1 hex face per instance, `CHUNKS_PER_FRAME=1`, sorted queue

### Shaders
- `hex_flat.gdshader`: CUSTOM0.r = e_norm, CUSTOM0.g = biome_norm/10, VERTEX.y = `height_scale * pow(height_step * e_norm, height_exp)`, biome colors via smoothstep blending, snow overlay at e>0.65
- `hex_prism.gdshader`: INSTANCE_CUSTOM for same, plus hex grid SDF lines
- Both have: noise_freq/seed/octaves/lacunarity/gain, height_step/exp/scale, grid_line_width

### Biome Classification (in `ChunkManager._classify_biome`)
| Threshold | Biome |
|---|---|
| e_norm < 0.25 | Water (0) |
| e_norm < 0.35 | Beach (1) |
| e_norm > 0.72 | Stone (4) |
| moisture < 0.25, else | Grass (2) |
| moisture < 0.55, else | Dirt (3) |
| else | Stone (4) |

### Terrain Editing
- Raise/Flatten/Level tools work (per-cell + area-select via Shift+click)
- After edit: `rebuild_chunk_for_hex()` → full `_rebuild_all()` on flat approach (expensive)
- Notifies `EnemyManager.notify_cell_changed()` for path recompute

### Enemies
- GPU compute: position buffer, per-frame dispatch, pathfinding compute shader
- Spawn at water biomes, path toward center
- 20000 max, 16 floats per enemy

### UI
- Left menu: Radius, Step, Curve, Height Scale, Grid Lines, Spawn Rate, Max Enemies, Spawn Batch
- Top toolbar: Nav/Raise/Flatten/Level/Place + Overlay/Resources/Values toggles
- Bottom palette: building/object placement

---

## 4. What's BROKEN or MISSING

### Critical Bugs

| Issue | File | Status |
|---|---|---|
| **Full mesh rebuild on every terrain edit** | `approach_flat.gd` | `rebuild_chunk_for_hex` calls full `_rebuild_all` — should rebuild only affected triangles |
| **Initial generation too slow** (25+ sec for radius 100) | `chunk_manager.gd` + `approach_flat.gd` | GPU batch with 500+ chunks overwhelms RenderingDevice; reduce batch size or defer per frame |
| **FPS 66 with full grid** (target: 2000+) | `approach_flat.gd` | 540K vertices for 30K hexes; should use fabric mesh with ~60K vertices instead |
| **MeshInstance3D has no chunks** | `approach_flat.gd` | Single mesh = no per-chunk visibility culling or streaming |

### Missing from Vision

| Feature | Priority | Notes |
|---|---|---|
| **Continuous fabric mesh** (not per-hex geometry) | HIGH | Replace triangle-fan-per-hex with triangulated corner-vertex mesh (like old smooth terrain). ~60K verts vs 540K. |
| **Hex grid projected via shader** | HIGH | Use hex SDF (exists in `hex_prism.gdshader`) to draw grid lines + hex centers on fabric. No hex geometry needed. |
| **Subhex resource projection** (shader-based) | HIGH | 13 sub-hexes per hex, resources assigned per sub-hex via noise, displayed as colored overlay (H key). |
| **20% frustum buffer streaming** | HIGH | Generate chunks 20% outside visible frustum; unload chunks 20% beyond that. |
| **Mouse hex highlight (yellow, 75%)** | MEDIUM | Shader overlay on hovered hex. Was in earlier commits, removed in flat-top rewrite. |
| **Seamless detail textures + normal maps** | MEDIUM | Dirt/grass/stone noise per biome area, normal maps for 3D detail. |
| **Seasonal tree colors** | MEDIUM | Was in `bd97f62`, removed. Pines: vibrant green + colored dots; deciduous: autumn gradient. |
| **Building deformation to cell curve** | LOW | Buildings tilt/curve to match cell surface normal. Quaternion tilt exists (`80e4297`) but no curve deformation. |
| **Unit spawn deep-water → center navigation** | MEDIUM | Basic GPU pathfinding exists; need spawn-point distribution and value-based cell selection. |
| **Route registry (unit ↔ chunk ↔ cell)** | MEDIUM | Fast lookup: "which units cross this cell?" for path update on terrain edit. |
| **GPU-only visual movement** | MEDIUM | Current: GPU positions computed each frame. Need to ensure path updates are minimal. |
| **Fabric-edge melding** | HIGH | Smooth interpolation between biome boundaries on the fabric (shader-based). Currently hard smoothstep thresholds. |
| **Out-of-focus render stop** | LOW | Detect viewport not visible → stop rendering. |
| **Binary save/load for fast GPU loading** | MEDIUM | Exists already, but needs to store/restore resource subhex data. |

---

## 5. Plan: Priority-Ordered Roadmap

### Phase 1 — "The Fabric" (Core Rearchitecture)

Goal: Replace per-hex geometry with a continuous fabric mesh + shader-projected hex grid.

1. **Kill `approach_flat.gd` triangle-fan approach.**
   - New approach: build a mesh where **vertices are hex corner points** (shared by 3 hexes).
   - Each corner has: world position (x,z), averaged e_norm, index of the 3 neighboring hexes (for biome interpolation).
   - Triangles connect these corner points — NOT center-to-corner fans.

2. **Hex grid shader.**
   - The `hex_prism.gdshader` already has `hex_sdf_flat_top()` and `find_hex_center()`.
   - Port these to `hex_flat.gdshader` or create new `hex_fabric.gdshader`.
   - Fabric vertices pass `CUSTOM0.rg` = (e_norm, biome). Fragment shader:
     - Uses `find_hex_center()` to determine which hex the pixel belongs to.
     - Uses SDF to draw grid lines.
     - Computes hex-center e_norm from the 3 surrounding corner values.
     - Colors by biome with smooth edge blending.

3. **Subhex projection shader.**
   - Each hex has 13 sub-hex slots (center + 6 inner + 6 outer).
   - Resource data stored per sub-hex in a texture or SSBO.
   - Fragment shader samples this data to draw resource overlays on H key.

**Expected wins:**
- Vertex count: 540K → ~60K (corner points only, ~2 per hex instead of 18)
- Draw calls: 1 (same as now, but cheaper)
- FPS: 66 → 2000+ (pure shader work instead of geometry)

### Phase 2 — Streaming & Chunking

Goal: Chunked fabric that streams in/out around camera.

4. **Divide fabric into chunks** (like `approach_prisms.gd` but with fabric mesh).
   - Each chunk = one `MeshInstance3D` with fabric geometry.
   - Chunk size: ~32 hexes = ~192 corner vertices.
   - Generate chunks on-demand, 2-4 per frame, sorted by distance.
   - **20% buffer**: generate chunks whose center is within 1.2× view radius; destroy chunks beyond 1.2×.

5. **Frustum culling** on chunk MeshInstance3Ds.
   - Godot's built-in `GeometryInstance3D.extra_cull_margin`.
   - Unload chunks outside frustum + buffer.

### Phase 3 — Overlay & Highlight

Goal: Mouse interaction, hex highlighting, resource overlay.

6. **Mouse hex highlight.**
   - In fragment shader: pass hex coordinate for hovered cell via uniform.
   - If current pixel's hex matches: ALBEDO = mix(ALBEDO, yellow(1,1,0), 0.75).
   - Uniform set from `hex_map.gd` mouse position → `world_to_cube`.

7. **H key: subhex resource overlay.**
   - Override fragment shader to show resource colors + small numbers.
   - Resource data per sub-hex in a 2D texture (width=grid_diameter×13, height=1) or SSBO.
   - Numbers: pseudo-random 0-9 based on sub-hex seed.

### Phase 4 — Resource/Decoration System Update

Goal: On-demand resource generation + seasonal colors.

8. **Sub-hex resource generation.**
   - On hex load: generate 13 sub-hex resource types from noise seeds.
   - Store in `HexCellData.sub_heights[]` (repurpose or extend).
   - Cache: resources persist while hex is in memory; discarded when unloaded.

9. **Seasonal tree colors.**
   - Port from `bd97f62`: uniform season_phase (0.0→1.0), noise-based per-tree color variation.
   - Pine = vibrant green + colored dots (same color per hex).
   - Deciduous = green→yellow→red→brown-white.

### Phase 5 — Unit System

Goal: Efficient unit spawning, pathing, movement.

10. **Spawn points: deep-water edges.**
    - Distribution: ring-based, weighted toward water hexes farther from center.
    - Value-based cell selection: lower `TileValuator` score = more likely path.

11. **Route registry.**
    - `Dictionary[Vector3i, Array[int]]` mapping cell → enemy slot indices.
    - On terrain edit: look up which enemies cross the changed cell, recompute their paths only.

12. **GPU path + movement.**
    - Already partially implemented in `enemy_manager.gd`.
    - Extend for large counts (100K): ensure position texture and storage buffers scale.

### Phase 6 — Polish & Performance

Goal: Hit all FPS targets, remove main-thread blocking.

13. **Background chunk generation.**
    - Use `call_deferred` + `_physics_process` for generation queue.
    - Never block main thread — yield every 1-2 chunks.

14. **Out-of-focus culling.**
    - `get_viewport().is_input_handled()` or `OS.is_window_focused()` → pause rendering.

15. **Binary save/load update.**
    - Add sub-hex resource data to binary format (version 5).
    - GPU-loadable: store as raw float buffer matching SSBO layout.

---

## 6. Key Architectural Decisions

### What to KEEP from current codebase:
- `ChunkManager` — cell generation, noise, save/load (add sub-hex resources)
- `HexCellData` — extend with sub-hex resources
- `hex_prism.gdshader` — hex SDF functions, grid line math (port to fabric shader)
- `EnemyManager` — GPU compute, pathfinding, position buffers
- `compute_noise.glsl` — batch noise on GPU
- `pathfinding.glsl` — hex pathfinding on GPU
- `HexGridMath` — coordinate math (proven correct)
- `hex_map.gd` _setup_ui, tools, camera, overlays — keep all UI

### What to REPLACE:
- `approach_flat.gd` — replace with fabric-mesh generator (`approach_fabric.gd`)
- `hex_flat.gdshader` — replace with fabric shader (`hex_fabric.gdshader`)

### What to REMOVE:
- `approach_prisms.gd` — obsolete once fabric approach handles all (or keep as fallback)
- `hex_prism.gdshader` — obsolete once fabric shader has SDF
- All per-hex triangle-fan geometry code

---

## 7. Remaining Questions

1. **Fabric resolution**: corner-only vertices (2 per hex) or finer grid (like old smooth terrain's 0.3× hex)?
   - Answer from vision: **corner points only** — the hex grid IS the mesh resolution. Shader handles all detail.
2. **Sub-hex data storage**: Texture array? SSBO? Per-chunk buffer?
3. **Chunk size**: 32 hexes (like prisms) or smaller for finer LOD?
4. **Binary format version**: Bump to version 5 for sub-hex resources, or add backward-compatible extension block?
