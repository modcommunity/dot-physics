# dot-physics history

Kept because the bug could come back. The live rules are in [design.md](design.md).

## Every body stayed on layer 1

`DotPhysicsWorld.setup` named the layers in ProjectSettings and every game in the family looked set up, but no game called `classify`, so every body stayed on Godot's default layer 1 masking layer 1. Two consequences were live bugs rather than cosmetics: two physics props dropped in the same place passed through each other in both sandboxes, and `DotFpsTunables.collision_mask` defaulted to `1` and no game set it, so the moment anything moved off bit 0 a player would have walked through it with nothing erroring. game-arena, game-g2gfast, game-hungario, game-playground and mg-smash-copter call `classify` now, and game-arena and game-g2gfast set the controller's mask from the layout.

`top_down_2d` had no `hazard` layer at the time, though `platformer_2d` had one from the start. Its absence was not a decision.
