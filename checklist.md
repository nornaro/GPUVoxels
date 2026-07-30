# Checklist — Terrain System

## Legend
- ✅ = Working / Improved
- ⚠️ = Works but needs attention
- ❌ = Broken / Not implemented
- 📌 = Planned

---

## Performance

| Item | Status | Notes |
|------|--------|-------|
| Empty terrain FPS (current: ~66) | ⚠️ | Target 2000+. Main bottleneck: 540K vertices for 30K hexes (6 triangle-fans per hex). Fix: fabric mesh (~60K verts). |
| Initial generation time (current: ~25s) | ❌ | Too many chunks in one GPU batch. Fix: defer per frame, reduce batch size. |
| No MeshInstance3D for terrain | ❌ | Currently uses MeshInstance3D. Must use RenderingServer RIDs or equivalent. |
| No MeshInstance3D for resources | ❌ | Currently per-resource MultiMesh but still has MeshInstance3D overhead. Must preload to GPU via MultiMesh. |
| No MeshInstance3D for units | ⚠️ | Enemy manager already uses MultiMeshInstance3D + GPU compute. Extend to full pipeline. |
| GPU noise (replace CPU FastNoiseLite) | ❌ | CPU noise still called per-cell. Extend `compute_noise.glsl` to match FastNoiseLite output exactly. |
| Preload all meshes to GPU at startup | ❌ | Resources, units, terrain chunks all loaded lazily. Preload at init. |
| Frustum culling + 20% buffer streaming | ❌ | Single mesh = no culling. Needs chunked fabric. |
| Out-of-focus render stop | ❌ | Not implemented. |

---

## Terrain Mesh ("The Fabric")

| Item | Status | Notes |
|------|--------|-------|
| Continuous fabric (not per-hex geometry) | ❌ | Current: 6 triangle-fans per hex. Need: mesh with vertices only at shared corner points. |
| Corner-only vertices (~60K vs 540K) | ❌ | Currently 7 verts per hex (center + 6 corners) × 6 tris. Fabric needs ~2 verts per hex (shared corners). |
| Hex grid projected via shader SDF | ❌ | Port hex_sdf_flat_top + find_hex_center from hex_prism.gdshader to new fabric shader. |
| Shared corner heights averaged from 3 hexes | ✅ | Just implemented in approach_flat.gd _rebuild_all. |
| Biome color blending on fabric | ❌ | Currently per-hex colors with smoothstep. Needs per-pixel biome interpolation on fabric. |
| Subhex projection via shader | ❌ | 13 sub-hexes per hex, resource data from GPU buffer, drawn in fragment shader. |
| Chunked fabric (streaming + culling) | ❌ | Split fabric into chunks, each chunk as RID mesh, 2-4 chunks/frame generation. |

---

## Terrain Definition

| Item | Status | Notes |
|------|--------|-------|
| Height step = 1m base unit | ✅ | `height_step` slider (0.5–5.0) scales this. Default 3.0. |
| Hex = 1m wide, 1m tall (design resolution) | ✅ | HEX_SIZE = 1.1547 (corner-to-corner). Width side-to-side = 1.1547 × √3/2 × 2 = 2.0m. Actually need to verify — current hex is 2m wide, not 1m. May need to adjust or accept as-is. |

---

## Biomes

| Item | Status | Notes |
|------|--------|-------|
| Water (e_norm < 0.25) | ✅ | Working |
| Beach (e_norm < 0.35) | ✅ | Working |
| Grass (moisture < 0.25) | ✅ | Working |
| Forest/Dirt (moisture < 0.55) | ✅ | Working |
| Rocky (moisture ≥ 0.55 or e_norm > 0.72) | ✅ | Working |
| Snow overlay (e_norm > 0.65) | ✅ | Working in shader |
| Seamless detail textures + normal maps | ❌ | Not implemented |

---

## Resources & Decorations

| Item | Status | Notes |
|------|--------|-------|
| Trees (per biome) | ⚠️ | Works but uses individual MeshInstance3D · must move to MultiMesh. |
| Mountains / Rocks | ⚠️ | Same as trees. |
| Minerals (silver/gold/tungsten/titanium/copper) | ⚠️ | Same. |
| Oil resources | ⚠️ | Same. |
| MultiMesh preloaded to GPU | ❌ | Load all resource meshes at startup into MultiMesh. Transforms uploaded from CPU. |
| On-demand resource gen (20% buffer) | ❌ | Resources generated with chunks, loaded/unloaded with 20% frustum buffer. |
| Seasonal tree colors | ❌ | Was in commit bd97f62, removed. Re-implement via shader uniform. |
| H key: subhex resource overlay | ❌ | Show resource colors + random 0-9 numbers instead of resource meshes. |

---

## Terrain Editing

| Item | Status | Notes |
|------|--------|-------|
| Raise / Lower | ✅ | Working |
| Flatten to elevation | ✅ | Working |
| Area selection (Shift+click) | ✅ | Working |
| After-edit: rebuild terrain | ❌ | Currently full `_rebuild_all`. Must rebuild only affected chunk(s). |
| After-edit: update unit paths | ✅ | `notify_cell_changed` works. |
| UI sliders (radius, step, curve, scale) | ✅ | All working. |

---

## Objects / Buildings

| Item | Status | Notes |
|------|--------|-------|
| Place objects on hexes | ✅ | Working |
| Object tilt to terrain normal | ✅ | Working (commit 80e4297). |
| Wall connection system | ✅ | Working. |
| Object deformation to cell curve | ❌ | Objects are flat on hex, not deformed. |

---

## Units & Pathfinding

| Item | Status | Notes |
|------|--------|-------|
| GPU compute positions | ✅ | Working in enemy_manager. |
| GPU pathfinding (pathfinding.glsl) | ✅ | Working. |
| MultiMesh instance rendering | ⚠️ | Uses MultiMeshInstance3D already. Extend for 100K units. |
| Spawn at deep-water edges | ❌ | Not implemented (spawns at random water). |
| Value-based cell selection | ❌ | Not integrated (TileValuator exists but not wired). |
| Route registry (cell → unit lookup) | ❌ | Needed for path update on terrain edit. |
| Path update on chunk change | ⚠️ | `notify_cell_changed` works but path invalidation is O(n). Needs route registry. |

---

## Overlay / UI

| Item | Status | Notes |
|------|--------|-------|
| Mouse hex highlight (yellow, 75%) | ❌ | Uses a MeshInstance3D cursor. Must be shader-based overlay on fabric. |
| Hex grid lines via shader | ❌ | Currently in hex_prism.gdshader but not in flat approach. Port to fabric shader. |
| H key subhex overlay | ❌ | Not implemented. |
| Resource numbers on overlay | ❌ | Random 0-9 per sub-hex. |
| Toolbar / palette / left menu | ✅ | Working. |

---

## Save / Load

| Item | Status | Notes |
|------|--------|-------|
| Binary save (magic 0x48564D50, v4) | ✅ | Working. |
| JSON fallback | ✅ | Working. |
| Sub-hex resource data in save | ❌ | Not stored (not implemented yet). |
| GPU-buffer-layout save format | ❌ | Store raw float buffers matching SSBO layout for instant GPU load. |
| Auto-detect binary vs JSON | ✅ | Working. |

---

## Code Quality

| Item | Status | Notes |
|------|--------|-------|
| Unused variable warnings | ✅ | Fixed in hex_map.gd and approach_flat.gd. |
| Typed arrays (Array[Vector3i] etc.) | ⚠️ | Some arrays untyped (CORNER_NBORS, CUBE_DIRECTIONS). |
| Approach scripts decoupled from hex_map | ✅ | Good separation of concerns. |
| ChunkManager as RefCounted (not Node) | ✅ | Good design. |
| EnemyManager GPU pipeline | ✅ | Solid architecture. |
| No main-thread blocking | ⚠️ | `_rebuild_all` blocks for 1000ms+ on initial gen. |
| Minimal _process calls | ⚠️ | approach_flat._process runs every frame. Use _physics_process where possible. |
