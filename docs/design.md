# dot-physics design

Why the addon is shaped the way it is, and why the obvious alternative is wrong at each point. The rules are one line each in [CLAUDE.md](../CLAUDE.md).

## A collision layer has a name

The name is the only thing anything downstream is allowed to say. Godot gives a project thirty-two bits and no memory of what any of them meant. Everything else in this addon follows from refusing to let that leak: `layer_mask(&"player")`, `mask_of([&"world", &"prop"])`, `classify(body, &"debris")`. There is no supported way to get a bit number out of this addon except by asking a layout for one, and the only place a number is written down is `DotPhysicsLayer.bit`, which the layout assigns.

## Anything that writes to `ProjectSettings` puts it back

`DotPhysicsWorld` is a `Node` for exactly that reason: a dedicated server switching from one game to another switches physics with it, and a write with no matching restore leaves the next game running on the last one's gravity. That presents as "the new mode feels wrong", which is not a bug anybody finds.

`core/` never touches the engine and never touches a node. That is what lets the whole decision half, which is where the bugs are, be tested with no world, no bodies and no renderer, and it is the first thing to break if a convenient `ProjectSettings.set_setting` is added to a `Resource`.

`Engine.physics_ticks_per_second` is set as well as the project setting. The engine reads its tick rate from `Engine` once a project is running, so writing only `ProjectSettings` changes the number a future run uses: the exact shape of "the setting does nothing".

`DotPhysicsWorld._write_setting` is not called `_set`: `Object` already has a `_set` virtual, the one the engine calls for every property assignment, and GDScript would have taken the definition without a word ([gdscript-hazards](../../../docs/gdscript-hazards.md)).

## Where the presets came from

`DotPhysicsLayout` has four presets (`shooter_3d`, `sandbox_3d`, `platformer_2d`, `top_down_2d`) and `custom`. The shooter layout is read off what shipped first-person shooters converge on, and three of its layers are the ones a project inventing this itself always forgets and always adds back after a bug:

- **A clip layer** the player collides with and nothing else does, so a mapper can fence off a ledge without the fence stopping bullets or trapping grenades.
- **Debris**, which touches the world and nothing else. A hundred shell casings colliding with each other is a hundred bodies in the solver and none of it is visible.
- **A query-only hitbox layer.** Lag-compensated hit registration rewinds and traces against shapes that were never part of the simulation, which is why a bullet's mask and a body's mask are different numbers.

`query_only` exists for the same reason in reverse: a shot that stops in mid-air on a capture zone reads as bad aim, not as a mask bug. `solid_mask()` is the answer and `DotPhysicsQuery.shot_3d()` uses it without being asked.

Both 2D presets have a `hazard` layer: a top-down arena has spikes and lava like any other.

## The collision relation is declared once

`DotPhysicsLayer.collides_with` is written one way ("debris collides with world") and `DotPhysicsLayout.build()` closes it. Physics collision in the engine is mutual: A's mask must contain B's layer and the reverse, and a table where both halves are maintained by hand is a table that drifts within a month.

`build()` also refuses a name that does not exist, which is the single most valuable line in the file. A typo in a collision list contributes no bit, so the pair simply never collides and there is no error, no warning and no symptom except a report that says "sometimes bullets go through".

## Naming a layer is half a layout; the other half is `classify`

`DotPhysicsWorld.setup` writes the layer names into ProjectSettings so a designer can read them in the inspector. That is the half that is easy to reach and the half that changes nothing: a body nobody classified stays on Godot's default layer 1 masking layer 1, while the inspector shows a layout nothing follows ([history](history.md#every-body-stayed-on-layer-1)). A game classifies every body it creates.

A failed `classify` must not be discarded. It returns a `DotResult` and fails for a layer the layout does not have; the body then keeps layer 1, which every preset here calls `world`. A hazard that is a piece of floor is what that looks like, and `var _put := classify(...)` is how it goes unnoticed.

A player controller's sweep mask is the same problem from the other side: `DotFpsTunables.collision_mask` defaults to `1`, so a game that moves anything off bit 0 sets the controller's mask from the layout too, or the player walks through it with nothing erroring.

A layout is not a local preference. It is the numbers written into `collision_layer` on nodes that both a server and its clients build, so a consumer that only builds the layout where it also applies the profile ends up with two worlds whose collision matrices differ, agreeing only for as long as nothing reads the layout. The profile is the server's to decide; the layout is everybody's.

## Surfaces are numbers, not behaviour

`DotPhysicsSurface` holds what one material is like to collide with. Friction and restitution go to the solver, density turns a shape's volume into a mass, and thickness exists because a pane of glass modelled as a box is otherwise a solid block of glass the size of a box. `liquid` (a volume something is in, not a floor), `break_health` (damage a sheet takes before it breaks, 0 never), `hazard_damage` (per second, touching or inside), `jump_scale` and `solid` (false: drawn, walked through) extend it.

`DotPhysicsSurfaceSet.standard()` has eighteen: concrete, dirt, flesh, foliage, glass, grass, ice, lava, metal, mud, rock, rubber, sand, slime, snow, thin_ice, water, wood. Water, lava and slime are liquids; glass breaks at 25 and thin ice at 8; lava burns at 60 a second and slime at 15; rubber jumps 1.8x with restitution held at 0.8, under the threshold where a bounce gains energy.

The addon simulates none of it. A game decides what a liquid does to a body, what breaking looks like, and whose damage system a hazard goes through.

## What this does not do

It does not simulate and it does not own bodies. It does not replace dot-player-controller's `DotFpsSurface`, which is a set of multipliers on player movement rather than a description of a rigid body: a game wants both, and they are read by different code at different times.

It does not decide collision layers at runtime. `classify()` is a call a game makes; nothing here walks a scene tree looking for things to reclassify, because a system that silently changes what a body collides with is a system nobody can debug.
