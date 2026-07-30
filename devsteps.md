# Dev Steps — Development Rules

## File Governance

| File | Who Can Edit | Commit Policy |
|------|-------------|---------------|
| `2DO.md` | **Only the user.** AI must never modify `2DO.md`. It is a reference document. | Can be committed and pushed to git, but only after user explicitly confirms. |
| `checklist.md` | Both user and AI. AI updates task statuses as work progresses. | Commit at milestone boundaries. |
| `devsteps.md` (this file) | Both user and AI. AI may clarify rules here if needed. | Commit rarely, only when rules change. |
| All `.gd`, `.gdshader`, `.glsl` files | Both user and AI. | Standard workflow. |
| All `.tscn`, `.tres`, `.import` files | Both user and AI. | Standard workflow. |

## Task Status Rules (in checklist.md)

- `✅` = feature works correctly, no known issues
- `⚠️` = works but has known problems or doesn't meet target
- `❌` = broken or not yet implemented
- `📌` = planned, not started

**Update checklist.md immediately** when:
- A feature's status changes (e.g., ❌ → ✅)
- A new issue is discovered
- A target metric is met or missed

Keep exactly **one** active work item at a time. When starting new work, move previous item to completed.

## Testing Rules

### NEVER use headless mode
- Always run with graphics enabled (`--rendering-driver opengl3` or `--rendering-driver vulkan`)
- Headless mode cannot verify visual correctness (colors, shaders, biome blending, highlights, overlays)

### Screenshot-based verification
- Take **multiple screenshots** from different camera angles (overhead, oblique, close-up)
- Capture both wide views (full terrain) and detail views (hex transitions, biome edges)
- Compare screenshots before and after changes when fixing visual bugs

### Stress testing
- Move all generation sliders (radius, height step, curve, scale) to extremes and verify no crashes
- Mouse-scroll zoom from minimum to maximum distance
- Pan across the entire terrain grid
- Toggle all overlay/resource/display modes (H, J, Tab keys)
- Test terrain editing (raise, flatten, level) on single hexes and area selections
- For unit changes: test at 30, 10000, 20000, 100000 enemy counts

### Performance benchmarking
- Note FPS and frame time (`mspf`) from the "Project FPS" output
- Test with: empty terrain, terrain + full decorations, terrain + units (various counts)
- Test at different radii (10, 50, 100, 500, 1000) to verify scaling

## Workflow

1. **Plan**: Read `2DO.md` for context, `checklist.md` for current status
2. **Change**: Modify code in appropriate files
3. **Test**: Run game, take screenshots, check FPS, verify no errors in output
4. **Update**: Update `checklist.md` status items
5. **Refresh**: Refresh devsteps guidelines to keep in memory
6. **Repeat**: Move to next item

## Commit Rules

Use separate branches to work on separate tasks
Commit each step where some small change seems to work, to it's dev branch
Create screenshot cathalog of improvements, using 1080p png or webp
Use a dev branch for merging finished things
Only merge to master when **explicitly told** to merge. Never auto-merge to master.
