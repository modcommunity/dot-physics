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

## Callers in dot-vehicle and mg-prop-hunt

| File and function | Query | Who calls it |
| --- | --- | --- |
| `dot-vehicle/addons/dot_vehicle/runtime/dot_vehicle_hover.gd` `_drive` | one `intersect_ray` per mount | `DotVehicleSpawner.tick` through `DotVehicleChassis.drive`: caller-driven, in the step |
| `dot-vehicle/addons/dot_vehicle/runtime/dot_vehicle_ride.gd` `find_exit_position` | `intersect_shape` per exit candidate | `exit`, reached from `DotVehicleSpawner.set_command` (an exit request), `destroy` and `remove` (`_evacuate`). Request handlers run between ticks: the game must deliver them from its tick, or the threaded setting reads every exit as free |
| `mg-prop-hunt/game/ph_game.gd` `_clear_between`, `_look`, `_make_room` | ray and shape | `_step` (decoy checks, bots) and the request handlers `request_disguise` and `reveal`, called from the net bridge between ticks: the same hazard as exit requests |
| `mg-prop-hunt/game/ph_client.gd` `_process` | one ray for the ambient roof probe | Client only, every frame. Not fixed: the threaded option is a server setting and a client never sets it |

Both suites grep their own code for this (`vehicle_selftest` and `headless_config` section "space-query audit"). The two request-handler paths are open on `server-physics-thread-1`: queue the request and act on it in the next tick before the option can ship.

## The check

`examples/physics_selftest.tscn` section "space-query audit" and dot-combat's `combat_selftest` section of the same name grep their own addon for space-query calls and fail when the file set differs from the table above, when a querying file gains a frame, input, deferred or awaited entry point, or (here only) when this page stops naming a file. Add a caller: add it to `QUERY_FILES` and to this table.

## Not covered here (held by other repos)

`DotTpsController._apply_intent` (`move_and_slide` from `_process`), `DotFpsController._apply_intent` callers and the mg-wipeout weapon chains stay open on `server-physics-thread-1`.
