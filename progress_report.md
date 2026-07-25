# Progress Report — Gaze Avoidance & Material Optimisation

**Project:** Godot 4.7 — TheCreature AI navigation
**Date:** 25 July 2026
**Status:** Implemented, untested in-engine

---

## 1. Summary

Two workstreams this session:

1. **Material stripping for web builds** — removing normal and roughness maps from PBR materials to cut download size and per-pixel cost.
2. **Gaze avoidance for `TheCreature`** — keeping a `NavigationAgent3D` out of a conical region projected from the player's facing direction, as a hard constraint, without re-baking the navmesh at runtime.

Workstream 2 went through four design iterations before landing on something appropriately sized for the problem. The rejected approaches are documented below, because the reasons they fail are engine-level constraints likely to come up again.

---

## 2. Material stripping (web build)

### Approach

Normal and roughness maps removed from `StandardMaterial3D`, replaced with flat scalar roughness values.

- Per-material: uncheck **Normal Map > Enabled**, clear the **Roughness > Texture** slot, set a flat roughness value.
- Bulk: `EditorScript` walking `MeshInstance3D` nodes, setting `normal_enabled = false`, `normal_texture = null`, `roughness_texture = null`.

### Key detail

Setting `normal_texture = null` alone is not sufficient. With `normal_enabled` still true, Godot substitutes a default flat normal map and continues running the tangent-space shader path. Disabling `normal_enabled` is what actually removes the texture fetch and the per-pixel normal computation.

### Cost ranking on web (highest impact first)

| Cost | Notes |
|---|---|
| Texture memory / download size | Usually the dominant factor. Extra 1–4K maps per material inflate build size and load time. |
| Bandwidth from extra fetches | 2 extra fetches per fragment. Compounds badly with overdraw. |
| Tangent-space computation | Cheap in isolation, matters on integrated/mobile GPUs at high fill. |
| Compatibility renderer overhead | WebGL2 lacks Forward+ optimisations; trimming samples matters proportionally more. |

### Middle-ground options not taken

- Pack roughness into the alpha channel of the colour map (cuts texture count, keeps the data).
- Basis Universal / KTX2 compression if maps are retained.
- Strip maps on background geometry only, retain on hero assets.

---

## 3. Gaze avoidance — rejected approaches

### 3.1 `NavigationObstacle3D`

- **Re-bake mode:** re-baking `NavigationRegion3D` at runtime is far too expensive for a per-frame moving cone.
- **Avoidance mode:** RVO avoidance is a local steering suggestion, not a pathing constraint. Agents will enter and cross the region. Does not satisfy the hard-constraint requirement.

### 3.2 Cone as an overlay `NavigationRegion3D` with high `enter_cost`

Does not work, for two independent reasons:

- **Regions do not CSG against each other.** Godot stitches separate regions only along matching *edges* within `edge_connection_margin`. An overlay region leaves the floor region's polygons fully intact and interconnected underneath it. The agent walks straight across the base navmesh.
- **`enter_cost` is a boundary-crossing toll.** It is charged only when a path leaves one region and enters another via an edge connection. The cheap path never enters the cone region, so the cost is never paid. Any value, including absurd ones, changes nothing.

### 3.3 Pre-split navmesh into 1×1m tile regions

Mechanically feasible. Polygon clipping via `Geometry2D.clip_polygons` on the baked mesh generates tiles in milliseconds without a re-bake.

Genuinely attractive property: with fine tiles, `enter_cost` is charged roughly once per metre of penetration, so the penalty scales with how deep a path cuts into the cone. Coarse tiles lose this — an 8m tile charges the same toll for a 1m clip as for a full traversal.

**Rejected on region count.** A 100×100m level at 1m tiles is 10,000 regions and roughly 40,000 edge connections, all maintained by `NavigationServer3D` on every map sync whether or not the cone moved. Viable at 2–4m tiles; not at 1m.

Also unresolved: `enter_cost` remains soft, tile columns block bridges and the walkways beneath them together, and path funnelling can shave tile corners.

### 3.4 Per-vertex / per-polygon travel cost

**Does not exist in Godot.** `NavigationMesh` stores only vertices and polygon index arrays — no cost, weight, flag, or area-type field on either. The complete set of cost knobs is `enter_cost` and `travel_cost` on `NavigationRegion3D` and `NavigationLink3D`.

Worth recording for anyone arriving from Unity or another Detour-based engine: Recast/Detour has per-polygon area IDs with `dtQueryFilter::setAreaCost`, which is exactly the missing feature. Godot uses Recast for *baking* but implements its own pathfinding, and the area system was not carried over. Region cost is the substitute — which is why the tiling approach exists at all.

---

## 4. Gaze avoidance — implemented solution

### 4.1 Core insight

Path points cannot be moved. `get_current_navigation_path()` returns a copy, the server regenerates the path on every query, and a displaced point carries no guarantee of being on the navmesh or connected to its neighbours.

The workable substitute is **intermediate target injection**: detect that the route crosses the cone, choose a waypoint outside it, set that as `target_position`, and let the navigation server compute a real route. Restore the true goal on arrival. The server does all the pathing; we only choose where to aim it.

`NavigationServer3D.map_get_path()` makes this practical — it evaluates a candidate route without committing the agent, so detour candidates can be tested before selection.

### 4.2 Cone testing

The player's conical `Area3D` is queried directly via `PhysicsDirectSpaceState3D.intersect_point` with `collide_with_areas = true`. No cone mathematics is written anywhere. Whatever collision shape was authored is the shape that gets tested, vertical extent included. The query mask is read from `gaze_cone.collision_layer` at `_ready`, so there is no separate layer export to misconfigure.

**Critical detail:** testing the returned path points alone is insufficient. Navmesh paths contain long straight runs, and a cone parked mid-segment passes a point-only test cleanly. `_path_hits_cone` subdivides every segment at `sample_step` intervals. This value must stay comfortably under the cone's narrowest width.

### 4.3 Behaviour

| State | Trigger | Behaviour |
|---|---|---|
| `NORMAL` | default | Throttled re-plan. Direct route used when clear; detour waypoint injected when not. |
| `EVADING` | `gaze_cone.overlaps_body(self)` | Abandons the goal, moves to the nearest safe navmesh point at `evade_speed`. |

Detour selection: 12 candidates on a ring around the player at `cone_reach + ring_padding`, snapped to the navmesh, rejected if inside the cone, sorted by total detour length. The first candidate whose *both legs* test clear wins.

Escape point selection during evasion tries lateral sidesteps before radial retreat, since backing out along the cone axis means walking toward the player. Increasing distances are tried at each direction.

### 4.4 Hysteresis

`Area3D` overlap is binary with no margin, so boundary oscillation is handled temporally: the creature must be clear of the cone for `evade_clear_time` (default 0.3s) before returning to `NORMAL`. Without this it jitters whenever the player micro-adjusts aim.

### 4.5 Throttling

Re-planning runs at most every `replan_interval` (0.25s) and only when the player has moved more than 0.75m or turned more than 4°. A stationary player costs nothing.

Each re-plan is 1 to 25 `map_get_path` calls plus a physics point query per sample. With multiple creatures, stagger initial timer values so they do not all re-plan on the same frame.

---

## 5. Changes to existing `TheCreature` code

| Change | Reason |
|---|---|
| `select_new_target()` sets `final_goal` and calls `_replan()` instead of `set_movement_target()` directly | Everything must funnel through the detour check or it can be bypassed |
| Gaze logic moved above the `is_navigation_finished()` early return | Arriving at a detour waypoint is precisely when re-planning is needed |
| Null guards on `knowledge` and `pick_random()` | Both crash before `recieve_information` runs or on an empty lamp list |
| Zero-length guard on `Basis.looking_at` | Errors on a zero vector; reachable when the next path position lands on the creature. Detours create more waypoint transitions, so more opportunities |
| `OldTarget` now stores the goal position during evasion | Matches the apparent intent of the existing stub |

**Left unchanged:** the `gravity` variable remains unused. `_on_velocity_computed` overwrites `velocity` wholesale each frame, so `y` is always zero. Acceptable for a floating creature or flat floors; needs addressing for slopes.

---

## 6. Known limitations

- **Ring sampling can fail in enclosed geometry.** If all 12 candidates are unreachable without crossing the cone, the creature holds position until the player turns. The rejected AStar3D polygon-graph approach searched actual navmesh connectivity and did not have this failure mode. Open levels rarely hit it; corridor-heavy levels will.
- **`sample_step` is a correctness knob, not a performance knob.** Too coarse and the cone slips between samples undetected.
- **Vertical extent depends entirely on the authored `Area3D` shape.** Multi-storey levels need the collision shape to reflect that, or the cone will block walkways above and below the player.
- **Detour quality is unoptimised.** Candidates are sorted by straight-line distance sum, not actual path length. A candidate on the far side of a wall may sort well and then be rejected, wasting two path queries.

---

## 7. Next steps

1. Test in-engine. Verify `overlaps_body` fires — the cone's collision mask must include the creature's layer.
2. Tune `cone_reach` to match the authored shape; a mismatch puts detour candidates in the wrong place.
3. Add debug visualisation: draw the ring candidates, tint the selected detour, log `MovementState` transitions. Nearly every bug here is visually obvious and near-invisible in a printout.
4. Watch for the creature parking in place — that is `_find_detour` returning `INF`, usually because ring candidates are landing inside geometry. Raise `ring_padding` or `ring_samples`.
5. Profile with multiple creatures active before committing to the re-plan interval.
6. If enclosed-geometry failures prove common, revisit the AStar3D polygon graph. It solves the same problem properly at the cost of roughly three times the code.

---

## 8. Files

| File | Purpose |
|---|---|
| `the_creature.gd` | Integrated creature script — **current implementation** |
| `gaze_detour_agent.gd` | Standalone reference version of the same approach |
| `gaze_cone.gd` | Analytic cone maths (AStar3D approach, unused) |
| `nav_poly_graph.gd` | Polygon-graph builder (AStar3D approach, unused) |
| `gaze_avoidant_agent.gd` | Agent state machine (AStar3D approach, unused) |

The final three are retained as the fallback described in step 6.
