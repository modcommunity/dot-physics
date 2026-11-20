# Physics space queries and threads

Godot's `physics/3d/run_on_separate_thread` makes `PhysicsDirectSpaceState` accessible only during the physics step, so every query has to run inside the `_physics_process` chain (or the engine's physics callbacks). Neither addon here owns a tick: no `_process`, no input handler, no deferred call or `await` in any file that queries. Whether a query runs in the step is decided by the caller. Design and measurements: `~/docs/server-threading.md` (nightly `server-physics-thread-1`).

## Callers in GameSpice Physics and GameSpice Combat

| File | Query | Who must call it inside a physics step |
| --- | --- | --- |
| `dot-physics/addons/dot_physics/runtime/dot_physics_query.gd` | `ray_3d`, `ray_2d`, `sphere_3d`, `circle_2d`, `line_of_sight_3d` through `direct_space_state` | Every caller; it takes the `World3D`/`World2D` and never schedules anything |
| `dot-combat/addons/dot_combat/trace/dot_trace_physics.gd` | `intersect_ray` for the world half of a `DotTrace` | `DotCombatManager.resolve_shot` and anything tracing: from the tick, never from `_process` or a signal that fires between ticks |
| `dot-combat/addons/dot_combat/core/dot_sentry.gd` | `find_spot` (static, the caller passes the space) | The placement handler; get the space from `get_world_3d().direct_space_state` inside the same step |

Everything else in GameSpice Combat (`DotHitbox`, `DotHitboxSet`, lag-compensation rewind, `DotTrace`'s hitbox half) is analytic geometry on node transforms: no space state. Lag compensation moves bodies and then queries, on the main thread inside the tick, and must stay there.

`DotTracePhysics._world_ray` already warns when no space state exists instead of reporting a miss. With the threaded setting, an out-of-step access is an engine error and an empty result, so a wall would read as open: the warning is the signal.

## Callers in GameSpice Vehicle and mg-prop-hunt

| File and function | Query | Who calls it |
| --- | --- | --- |
| `dot-vehicle/addons/dot_vehicle/runtime/dot_vehicle_hover.gd` `_drive` | one `intersect_ray` per mount | `DotVehicleSpawner.tick` through `DotVehicleChassis.drive`: caller-driven, in the step |
| `dot-vehicle/addons/dot_vehicle/runtime/dot_vehicle_ride.gd` `find_exit_position` | `intersect_shape` per exit candidate | `exit`, reached from `DotVehicleSpawner.set_command` (an exit request), `destroy` and `remove` (`_evacuate`). `set_command` queues the exit and `destroy`/`remove` of an occupied vehicle queue too; `DotVehicleSpawner.tick` performs them first thing, so the sweep runs in the step. |
| `mg-prop-hunt/game/ph_game.gd` `_clear_between`, `_look`, `_make_room` | ray and shape | `_step` only: decoy checks, bots, and the queued requests. The net bridge and the offline client call `queue_disguise`/`queue_reveal`, which `_step` drains first thing (`request_disguise` and `reveal` are the in-tick implementations). |
| `mg-prop-hunt/game/ph_client.gd` `_process` | one ray for the ambient roof probe | Client only, every frame. The threaded option is a server setting and a client never sets it, so this stays out of the step |

Both suites grep their own code for this (`vehicle_selftest` and `headless_config` section "space-query audit"). Both request-handler paths queue the request and run it in the next tick; the replies are the `refused` signals as before.

## Handlers that arrive between ticks: DotTickGate

Console and chat commands, admin tools, map votes and network requests run in the idle frame, not in the step. A game whose handler reaches a query (a map change that rebuilds nav and drops objects with rays, a spawn that snaps to the floor) routes it through one `DotTickGate` (`runtime/dot_tick_gate.gd`, no space access itself):

- The server sets `armed = true` when it starts and calls `disarm()` when it stops; solo, clients and bare suites leave it unarmed and every call runs at once.
- The server's tick calls `open()` first thing: queued calls run in arrival order, then coroutines waiting in `reached()` resume, still inside the step.
- A handler wraps its work in `gate.run(fn)` (or `await gate.reached()` before it). Inside the step, or unarmed, it runs immediately, so the same code serves the tick and the console.
- A call queued while `open()` runs waits for the next tick; a call whose object was freed is skipped; `disarm()` drops the queue and releases waiters.

The selftest section "tick gate" covers this with a stand-in for `Engine.is_in_physics_frame()` (`in_step`).

## The check

`examples/physics_selftest.tscn` section "space-query audit" and GameSpice Combat's `combat_selftest` section of the same name grep their own addon for space-query calls and fail when the file set differs from the table above, when a querying file gains a frame, input, deferred or awaited entry point, or (here only) when this page stops naming a file. Add a caller: add it to `QUERY_FILES` and to this table.

## Other addons and the games (audit 2026-11-16)

Found by running every suite with the setting on and tracing each "Space state is inaccessible" back to its root caller. Server paths all query inside the tick; what remains off-step is client presentation or a test harness.

| Where | Query | Runs |
| --- | --- | --- |
| GameSpice Player Controller `DotFpsPhysicsBodyNative.bind` | `direct_space_state` | Off-step on a join. On a threaded server it leaves the space unbound and the first query in the step binds it through `revalidate` (`fps_controller_selftest` section "threaded bind"). |
| GameSpice Player Controller motor, hull, surf, ladders | rays and shape casts | `simulate_tick` from the game tick: in the step |
| GameSpice Player Controller `DotCameraBoom`, `DotCameraProbe`, `DotTpsController` camera | camera rays | Client only |
| GameSpice NPC senses, GameSpice Bot nav (`_step_stitches`, `_buried`, `_clear_fall`, `_drop_landing`), GameSpice 2D `body_physics`, GameSpice Core `DotSpaceQuery` | rays and shapes | Caller-driven: from the game tick or bot think |
| dot-npc-ai annotator, dot-npc-ai-director `_is_visible_to_any_player`, dot-weapon drops, dot-props `toy_box` | rays | Stepped from the game tick |
| GameSpice Props toy `_sleep_at_start` | ray | After `await physics_frame` |
| GameSpice Spectate `_killer_hidden` | ray | Server delivery, inside `DotNetManager._physics_process` |
| GameSpice Player Char ragdoll `crossing`, `_hold_walls` | rays | `_physics_process` |
| GameSpice Player Char `DotHumanoidLegs.floor_lift`, ragdolls `_covered`; GameSpice Audio, GameSpice FX, GameSpice Mobile, GameSpice Voice | rays | Client only (`_process`) |
| GameSpice Map glass sight, use, world | rays | The caller passes the space |
| GameSpice Core `collision_sweep` | sweeps | Editor and tools |
| GameSpice Core `DotCameraFade`, Zombie Zone zee-weapons view (`ZeeWorldModel._probe_wall`) | rays and shapes | Client only (`_process`) |
| Zombie Zone `ZzMap.clear_spot` (spawns, players placed at the start and on a join) | `intersect_shape` | The start and a join run off-step (module load, signon). There `clear_spot` returns the unchecked spot (`ZzMap.space_open()`), and `ZzGame.seat_on_start` re-clears the seat through the `DotTickGate` in the next step (`dedicated` section "a start point waits for the tick"). |
| Fatal Contact server: `game.tick`, spawn scoring (`_can_see_site`), bot think, nav warm-up from `_keep_bots` | rays | In the step |
| Fatal Contact map and mode changes (`FcMapSession.change_to_map` after a delivered pack mounts, `fc_mode`, restarts, admin respawns): `settle_spawns`, the spawn sight | shape and ray | Already wait on `game.tick_gate` (armed by `FcModule`), so they run first thing in the next tick |
| Fatal Contact client: `fc_client._present_roof`, `fc_player._behind_world`, `fc_player_build._under_cursor`, fc-weapons view (`aw_view_model_wall`, `aw_wall_slam`, `aw_world_model._probe_wall`, `aw_shot_fx`) | rays | Client only (`_process`) |

Suites that drive `game.tick` or `world.is_route_pending()` from `await process_frame` (Fatal Contact `headless_botthreads`, `bot_map_base`, `headless_arena16`, `headless_ride_pilot`, `headless_imported`, `headless_cp_orange`, `headless_net`'s stepped server, `headless_delivered`'s unarmed game, and the view suites) are off-step by construction. With the setting forced on they log the error and fail; that is the harness, not the server. The setting is a dedicated-server option (`sv_physics_thread` in GameSpice Server Deploy, default 0, unchanged), and a client never sets it. Measured: the thread gives no gain on a headless server, so the default stays off.
