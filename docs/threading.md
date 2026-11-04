# Physics space queries and threads

Godot's `physics/3d/run_on_separate_thread` makes `PhysicsDirectSpaceState` accessible only during the physics step, so every query has to run inside the `_physics_process` chain (or the engine's physics callbacks). Neither addon here owns a tick: no `_process`, no input handler, no deferred call or `await` in any file that queries. Whether a query runs in the step is decided by the caller. Design and measurements: `~/docs/server-threading.md` (nightly `server-physics-thread-1`).

## Callers in dot-physics and dot-combat

| File | Query | Who must call it inside a physics step |
| --- | --- | --- |
| `dot-physics/addons/dot_physics/runtime/dot_physics_query.gd` | `ray_3d`, `ray_2d`, `sphere_3d`, `circle_2d`, `line_of_sight_3d` through `direct_space_state` | Every caller; it takes the `World3D`/`World2D` and never schedules anything |
| `dot-combat/addons/dot_combat/trace/dot_trace_physics.gd` | `intersect_ray` for the world half of a `DotTrace` | `DotCombatManager.resolve_shot` and anything tracing: from the tick, never from `_process` or a signal that fires between ticks |
| `dot-combat/addons/dot_combat/core/dot_sentry.gd` | `find_spot` (static, the caller passes the space) | The placement handler; get the space from `get_world_3d().direct_space_state` inside the same step |

Everything else in dot-combat (`DotHitbox`, `DotHitboxSet`, lag-compensation rewind, `DotTrace`'s hitbox half) is analytic geometry on node transforms: no space state. Lag compensation moves bodies and then queries, on the main thread inside the tick, and must stay there.

`DotTracePhysics._world_ray` already warns when no space state exists instead of reporting a miss. With the threaded setting, an out-of-step access is an engine error and an empty result, so a wall would read as open: the warning is the signal.

## The check

`examples/physics_selftest.tscn` section "space-query audit" and dot-combat's `combat_selftest` section of the same name grep their own addon for space-query calls and fail when the file set differs from the table above, when a querying file gains a frame, input, deferred or awaited entry point, or (here only) when this page stops naming a file. Add a caller: add it to `QUERY_FILES` and to this table.

## Not covered here (held by other repos)

`DotTpsController._apply_intent` (`move_and_slide` from `_process`), `DotFpsController._apply_intent` callers, `DotVehicleRide.find_exit_position`, and the mg-prop-hunt and mg-wipeout weapon chains stay open on `server-physics-thread-1`.
