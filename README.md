This is the **physics** asset for TMC's **Dot** collection. It turns the two dozen engine settings a project sets once and never finds again into something layered, named and reviewable — and turns collision layers from bit arithmetic into names.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## The problem

A Godot project has thirty-two collision bits and no memory of what any of them meant. So the arithmetic gets written out at the call sites — `1 << 3 | 1 << 7` in one script, `0x88` in another — and the day a layer moves, one of them is quietly wrong and the bug is reported as "bullets pass through the glass sometimes".

The same project has about twenty physics numbers living in `ProjectSettings` under names like `physics/3d/solver/default_contact_bias`. They are not reviewable, they are not layered, and changing one changes how every rigid body in the game behaves.

dot-physics is both of those made explicit: **a layout you pick, and a profile you can hand a dedicated server on the command line.**

## Install

Copy `addons/dot_physics/` and `addons/dot_core/` into your project and enable both in *Project → Project Settings → Plugins*.

Requires Godot 4.7 or newer.

## Use

```gdscript
var physics := DotPhysicsWorld.new()
physics.profile  = DotPhysicsProfile.arcade_shooter()   # 128 Hz, gravity 20, no interpolation
physics.layout   = DotPhysicsLayout.shooter_3d()        # sixteen named layers
physics.surfaces = DotPhysicsSurfaceSet.standard()      # eleven materials
add_child(physics)

var res := physics.setup()
if not res.ok:
    push_error(res.error.message)

physics.classify(player_body, &"player")                # layer and mask, by name
var hit := physics.query().shot_3d(world, muzzle, muzzle + dir * 100.0)
if not hit.is_empty():
    var surface: DotPhysicsSurface = hit["surface"]     # what it is made of
    audio.play(surface.impact_sound)
```

`DotPhysicsWorld` remembers every setting it overwrote and puts it back on the way out of the tree. That is not tidiness: a dedicated server that switches from a sandbox at 64 Hz to a timer server at 128 must not leave the second game running on the first one's gravity, and a settings write with no matching restore is exactly how that happens.

## Layouts

| | |
| --- | --- |
| `shooter_3d` | Sixteen layers, read off twenty-five years of shipped first-person shooters. Player and NPC clip volumes, debris that touches only the world, a query-only hitbox layer for lag-compensated hit registration. |
| `sandbox_3d` | The shooter's, plus `held_prop` and `frozen_prop`. A held prop deliberately does not push the player holding it. |
| `platformer_2d` | Side-on. One-way platforms are their own layer, so a projectile is not stopped by a surface the player walks through. |
| `top_down_2d` | No gravity, many bodies, players who pass through each other. |

`DotPhysicsLayout.custom()` is the fifth. Every layout declares its collision relation **once** — "debris collides with world" — and `build()` closes it symmetrically, because a table where both halves are written by hand is a table that drifts.

A name that does not exist is **refused at build time**, not ignored. A typo in a collision list contributes no bit, so the pair silently never collides, and nothing anywhere says why.

## Profiles

Named for how they feel, because that is the only thing about them anybody can reason about:

| | |
| --- | --- |
| `arcade_shooter` | 128 Hz, gravity 20 m/s², interpolation off, characters not pushed by bodies. |
| `grounded` | 64 Hz, gravity 12, sixteen solver iterations, interpolation on. |
| `sandbox` | Twenty-four iterations so a stack of crates holds, an aggressive sleep threshold so two hundred settled props cost nothing. |
| `floaty_platformer` | Long jumps, generous slopes. |
| `top_down` | No gravity at all. |

Every one of them is a `DotConfig`, so the family's layering applies: exported defaults < JSON file < environment < command line. `--physics-tick-rate 128` on a dedicated server, with no rebuild.

## Surfaces

`DotPhysicsSurfaceSet.standard()` is eleven materials with friction, restitution, density, sheet thickness, movement multipliers and dot-audio/dot-fx ids.

The hard half is not the table, it is the lookup: a ray hits a collider and nothing in Godot's result says it hit concrete. `for_collider()` tries node metadata, then groups, then the node's name — in that order, with the last one an honest guess rather than a design, because a level built by a mapper is the one case where nothing else is available.

## What it is not

It does not simulate anything. Godot does that. This addon decides what Godot is told, and makes those decisions something a person can read.

It is also **not** dot-player-controller's surface table. That one is multipliers on player movement; this one is what the solver is told about a rigid body. A game wants both, they are read by different code at different times, and merging them is a tidy-up that would break one of the two.

## Licence

MIT. See [LICENSE](LICENSE).
