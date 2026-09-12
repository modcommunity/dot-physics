# dot-physics

Physics as a choice a game makes, rather than as whatever the engine defaulted to.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first — no autoloads, `DotNodeRef` instead of scene paths, `DotResult` for anything fallible, `Dot`-prefixed class names, layered configuration, `describe()` on anything stateful. This file is only what is specific to physics.

## The one idea

**A collision layer has a name, and the name is the only thing anything downstream is allowed to say.**

Godot gives a project thirty-two bits and no memory of what any of them meant. Everything else in this addon follows from refusing to let that leak: `layer_mask(&"player")`, `mask_of([&"world", &"prop"])`, `classify(body, &"debris")`. There is no supported way to get a bit number out of this addon except by asking a layout for one, and the only place a number is written down is `DotPhysicsLayer.bit`, which the layout assigns.

The second idea is smaller and is about lifetime: **anything that writes to `ProjectSettings` must be able to put it back.** `DotPhysicsWorld` is a `Node` for exactly that reason — a dedicated server switching from one game to another switches physics with it, and a write with no matching restore leaves the next game running on the last one's gravity. That presents as "the new mode feels wrong", which is not a bug anybody finds.

## Layout

```
addons/dot_physics/
  core/
    dot_physics_layer.gd        one named layer, and what it touches
    dot_physics_layout.gd       the set, the matrix, and the four presets
    dot_physics_profile.gd      every engine number, as a layered DotConfig
    dot_physics_surface.gd      what one material is like to collide with
    dot_physics_surface_set.gd  the table, and how a collider maps to an entry
  runtime/
    dot_physics_world.gd        applies a profile and a layout, and puts them back
    dot_physics_query.gd        casts written against layer names
```

`core/` never touches the engine and never touches a node. That is what lets the whole decision half — which is where the bugs are — be tested with no world, no bodies and no renderer, and it is the first thing to break if a convenient `ProjectSettings.set_setting` is added to a `Resource`.

## Where the presets came from

The shooter layout is read off what shipped first-person shooters converge on, and three of its layers are the ones a project inventing this itself always forgets and always adds back after a bug:

- **A clip layer** the player collides with and nothing else does, so a mapper can fence off a ledge without the fence stopping bullets or trapping grenades.
- **Debris**, which touches the world and nothing else. A hundred shell casings colliding with each other is a hundred bodies in the solver and none of it is visible.
- **A query-only hitbox layer.** Lag-compensated hit registration rewinds and traces against shapes that were never part of the simulation, which is why a bullet's mask and a body's mask are different numbers.

`query_only` exists for the same reason in reverse: a shot that stops in mid-air on a capture zone reads as bad aim, not as a mask bug. `solid_mask()` is the answer and `shot_3d()` uses it without being asked.

The surface fields are the ones shipped engine surface tables converge on: friction and restitution go to the solver, density turns a shape's volume into a mass, and thickness exists because a pane of glass modelled as a box is otherwise a solid block of glass the size of a box.

## The collision relation is declared once

`DotPhysicsLayer.collides_with` is written one way — "debris collides with world" — and `DotPhysicsLayout.build()` closes it. Physics collision in the engine is mutually exclusive: A's mask must contain B's layer *and* the reverse, and a table where both halves are maintained by hand is a table that drifts within a month.

`build()` also **refuses a name that does not exist**, which is the single most valuable line in the file. A typo in a collision list contributes no bit, so the pair simply never collides and there is no error, no warning and no symptom except a report that says "sometimes bullets go through".

## Two hazards this file already stepped on

`DotPhysicsWorld._write_setting` is not called `_set`. `Object` already has a `_set` virtual — the one the engine calls for every property assignment — and GDScript would have taken the definition without a word. See the family's `docs/gdscript-hazards.md`: a method that shadows a native one is silently the native one, and this would have been the same collision pointed the other way.

`Engine.physics_ticks_per_second` is set as well as the project setting. The engine reads its tick rate from `Engine` once a project is running, so writing only `ProjectSettings` changes the number a *future* run uses. That is the exact shape of "the setting does nothing", which this family has shipped before.

## What this does not do

It does not simulate. It does not own bodies. It does not replace dot-player-controller's `DotFpsSurface`, which is a set of multipliers on player movement rather than a description of a rigid body — a game wants both and they are read by different code at different times.

It also does not decide collision layers for you at runtime. `classify()` is a call a game makes; nothing here walks a scene tree looking for things to reclassify, because a system that silently changes what a body collides with is a system nobody can debug.

## Naming a layer is half a layout; the other half is `classify`

`DotPhysicsWorld.setup` writes the layer names into ProjectSettings so a designer can read
them in the inspector. That is the half that is easy to reach and the half that changes
nothing: every body in all five games in this family stayed on Godot's default layer 1
masking layer 1 while the inspector showed a layout nothing followed.

Two of the consequences were live bugs rather than cosmetics. Two physics props dropped in
the same place **passed through each other** in both sandboxes, because layer 1 masks layer
1 and nothing else. And `DotFpsTunables.collision_mask` defaults to `1`, which no game had
ever set — so the moment anything moved off bit 0, a player would have walked through it
with nothing erroring, because a sweep that hits nothing is a sweep rather than an error.

**A failed `classify` must not be discarded.** It returns a `DotResult` and fails for a
layer the layout does not have; the body then keeps layer 1, which every preset here calls
`world`. A hazard that is a piece of floor is what that looks like, and
`var _put := classify(...)` is how it goes unnoticed.

**`top_down_2d` gained a `hazard` layer**, which `platformer_2d` has had since it was
written. Its absence was not a decision: a top-down arena has spikes and lava like any
other.

**A layout is not a local preference.** It is the numbers written into `collision_layer` on
nodes that both a server and its clients build, so a consumer that only builds the layout
where it also applies the *profile* ends up with two worlds whose collision matrices
differ — agreeing only for as long as nothing reads the layout. The profile is the server's
to decide; the layout is everybody's.
