@tool
class_name DotPhysicsLayout
extends Resource

## A named set of collision layers, and the matrix of what touches what.
##
## [b]A game picks a layout; it does not invent one.[/b] The four here are the four that
## keep being needed — a shooter, a physics sandbox, a side-on 2D game and a top-down 2D
## game — and each is a table somebody would otherwise rediscover one bug at a time.
## [method custom] exists for the fifth.
##
## [codeblock]
## var layout := DotPhysicsLayout.shooter_3d()
## body.collision_layer = layout.layer_mask(&"player")
## body.collision_mask  = layout.collision_mask(&"player")
## var world_only := layout.mask_of([&"world", &"static_prop"])
## [/codeblock]
##
## Nothing here touches the engine. [DotPhysicsWorld] is what applies a layout to a
## running project; this is the description, and it is a [Resource] so a game can save
## one, edit it in the inspector and hand it around.

const CHANNEL := "physics.layout"

## What this layout is called, for logs and for a settings screen.
@export var id: StringName = &""

@export var description: String = ""

## The layers, in bit order. Index is the bit after [method build].
@export var layers: Array[DotPhysicsLayer] = []

var _by_id: Dictionary = {}
var _built: bool = false


# --- Construction -----------------------------------------------------------

## Assigns bits, makes the collision relation symmetric, and indexes by id.
##
## Idempotent, and called automatically by every accessor, so a layout loaded from disk
## or assembled by hand behaves the same as one from a preset. Returns a failure rather
## than half-building: a layout with two layers claiming one name is a layout where
## [method collision_mask] answers about whichever one was loaded second, which is not a
## thing to discover at runtime.
func build() -> DotResult:
	_by_id.clear()

	if layers.size() > 32:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A layout has at most 32 layers; this one has %d." % layers.size(),
			"Godot gives a body 32 collision bits and there is no 33rd."
		)

	for i in range(layers.size()):
		var layer := layers[i]

		if layer == null:
			return DotResult.fail(
				DotError.CODE_INVALID, "Layer %d is null." % i
			)

		if layer.id == &"":
			return DotResult.fail(
				DotError.CODE_INVALID, "Layer %d has no id." % i
			)

		if _by_id.has(layer.id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Two layers are called '%s'." % String(layer.id),
				"Every lookup would answer about the second one, silently."
			)

		layer.bit = i
		_by_id[layer.id] = layer

	# Names first, bits second: a typo in a collision list is the most likely mistake
	# in this whole file and the one with the least visible symptom, so it is refused
	# here rather than quietly contributing nothing to a mask.
	for layer in layers:
		for other_id in layer.collides_with:
			if not _by_id.has(other_id):
				return DotResult.fail(
					DotError.CODE_INVALID,
					"Layer '%s' collides with '%s', which does not exist."
					% [String(layer.id), String(other_id)],
					"A name that resolves to nothing contributes no bit, so the pair "
					+ "simply never collides and nothing says why."
				)

	# The relation is declared once and closed here. See DotPhysicsLayer.collides_with.
	for layer in layers:
		for other_id in layer.collides_with.duplicate():
			var other: DotPhysicsLayer = _by_id[other_id]
			if not other.collides_with.has(layer.id):
				other.collides_with.append(layer.id)

	_built = true
	return DotResult.success(null)


func _ensure_built() -> void:
	if not _built or _by_id.size() != layers.size():
		var res := build()
		if not res.ok:
			DotLog.error(CHANNEL, "layout is not usable", {"why": res.error.message})


# --- Lookup -----------------------------------------------------------------

func has_layer(layer_id: StringName) -> bool:
	_ensure_built()
	return _by_id.has(layer_id)


func layer(layer_id: StringName) -> DotPhysicsLayer:
	_ensure_built()
	return _by_id.get(layer_id, null)


## The single bit a body on [param layer_id] sits on, as a mask. 0 if unknown.
##
## Zero rather than an error because this is called from `_ready` on hundreds of nodes,
## and a body with `collision_layer = 0` is invisible to every query — which is a loud,
## findable symptom. The warning names the layer.
func layer_mask(layer_id: StringName) -> int:
	_ensure_built()
	var l: DotPhysicsLayer = _by_id.get(layer_id, null)

	if l == null:
		DotLog.warn(CHANNEL, "no such layer", {"layer": String(layer_id), "layout": String(id)})
		return 0

	return l.mask()


## Everything a body on [param layer_id] should have in its `collision_mask`.
func collision_mask(layer_id: StringName) -> int:
	_ensure_built()
	var l: DotPhysicsLayer = _by_id.get(layer_id, null)

	if l == null:
		DotLog.warn(CHANNEL, "no such layer", {"layer": String(layer_id), "layout": String(id)})
		return 0

	var mask := 0
	for other_id in l.collides_with:
		var other: DotPhysicsLayer = _by_id.get(other_id, null)
		if other != null:
			mask |= other.mask()

	return mask


## An arbitrary mask, by name. What a raycast wants.
func mask_of(ids: Array[StringName]) -> int:
	_ensure_built()
	var mask := 0

	for layer_id in ids:
		var l: DotPhysicsLayer = _by_id.get(layer_id, null)
		if l == null:
			DotLog.warn(CHANNEL, "no such layer", {"layer": String(layer_id)})
			continue
		mask |= l.mask()

	return mask


## Everything except the named layers. What "shoot through nothing but smoke" wants.
func mask_excluding(ids: Array[StringName]) -> int:
	_ensure_built()
	return all_mask() & ~mask_of(ids)


func all_mask() -> int:
	_ensure_built()
	var mask := 0
	for l in layers:
		mask |= l.mask()
	return mask


## The layers a bullet trace should never stop on.
##
## Worth its own accessor because forgetting it produces a bug that looks like bad aim:
## shots stopping in mid-air wherever a trigger volume happens to be.
func query_only_mask() -> int:
	_ensure_built()
	var mask := 0
	for l in layers:
		if l.query_only:
			mask |= l.mask()
	return mask


## What a shot should hit: everything solid, minus the volumes nothing rests on.
func solid_mask() -> int:
	_ensure_built()
	return all_mask() & ~query_only_mask()


func layer_ids() -> Array[StringName]:
	_ensure_built()
	var out: Array[StringName] = []
	for l in layers:
		out.append(l.id)
	return out


## Whether two layers collide. The matrix, as a question.
func collides(a: StringName, b: StringName) -> bool:
	_ensure_built()
	var la: DotPhysicsLayer = _by_id.get(a, null)
	if la == null:
		return false
	return la.collides_with.has(b)


# --- Applying ---------------------------------------------------------------

## Sets `collision_layer` and `collision_mask` on any 2D or 3D collision object.
##
## Typed as [Node] rather than as [CollisionObject3D] deliberately: 2D and 3D have no
## common base below [Node], and a layout is used by both. The property names are
## identical on each, which is why this works at all.
func apply_to(node: Node, layer_id: StringName) -> DotResult:
	if node == null:
		return DotResult.fail(DotError.CODE_INVALID, "No node to apply a layout to.")

	if not (node is CollisionObject2D or node is CollisionObject3D):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"%s is not a collision object." % node.name,
			"Only a CollisionObject2D or CollisionObject3D has collision_layer."
		)

	if not has_layer(layer_id):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"This layout has no layer called '%s'." % String(layer_id)
		)

	node.set("collision_layer", layer_mask(layer_id))
	node.set("collision_mask", collision_mask(layer_id))
	return DotResult.success(null)


## The project-settings names Godot shows in the editor's layer dropdowns.
##
## A layout that a designer cannot read in the inspector is a layout a designer will
## work around, so [method DotPhysicsWorld.setup] writes these. Returns the pairs rather
## than writing them, because a [Resource] that edits ProjectSettings is a surprise.
func project_setting_names(kind: String = "3d") -> Dictionary:
	_ensure_built()
	var out: Dictionary = {}

	for l in layers:
		out["layer_names/%s_physics/layer_%d" % [kind, l.bit + 1]] = String(l.id)

	return out


func describe_lines() -> PackedStringArray:
	_ensure_built()
	var out := PackedStringArray()
	out.append("layout %s — %s" % [String(id), description])
	out.append("  %d layers" % layers.size())

	for l in layers:
		out.append("  %2d  %s" % [l.bit, l.describe()])

	return out


func describe() -> String:
	return "DotPhysicsLayout(%s, %d layers)" % [String(id), layers.size()]


func _to_string() -> String:
	return describe()


# --- Presets ----------------------------------------------------------------

## A blank layout with the names given, each colliding with everything.
##
## The starting point for a game whose shape is none of the four below. Everything
## colliding with everything is the honest default: it is what a project with no layout
## at all already does, so adopting this changes nothing until an exclusion is written.
static func custom(p_id: StringName, ids: Array[StringName]) -> DotPhysicsLayout:
	var layout := DotPhysicsLayout.new()
	layout.id = p_id
	layout.description = "A custom layout."

	for layer_id in ids:
		layout.layers.append(DotPhysicsLayer.make(layer_id, ids.duplicate()))

	var _res := layout.build()
	return layout


## The competitive-shooter layout.
##
## Read off twenty-five years of shipped first-person shooters, where the same dozen
## categories keep appearing under different names. The three that are always forgotten
## by a project inventing this itself, and always added back after a bug:
##
## - [b]a clip layer[/b] the player collides with and nothing else does, so a mapper can
##   fence a ledge off without the fence stopping bullets or trapping grenades;
## - [b]debris[/b], which touches the world and nothing else, because a hundred shell
##   casings that collide with each other is a hundred bodies the solver has to care
##   about and none of it is visible;
## - [b]a separate hitbox layer[/b], query-only, so lag-compensated hit registration can
##   rewind and trace against shapes that were never part of the simulation.
static func shooter_3d() -> DotPhysicsLayout:
	var layout := DotPhysicsLayout.new()
	layout.id = &"shooter_3d"
	layout.description = "Competitive first- and third-person shooters."

	layout.layers = [
		DotPhysicsLayer.make(
			&"world",
			[&"player", &"npc", &"prop", &"debris", &"projectile", &"vehicle", &"ragdoll"],
			"Level geometry. Static, and everything that can move collides with it."
		),
		DotPhysicsLayer.make(
			&"player",
			[&"world", &"npc", &"prop", &"projectile", &"vehicle", &"player_clip", &"ladder"],
			"A live player's collision hull. Not other players — see the note on "
			+ "player-vs-player in the layout's documentation."
		),
		DotPhysicsLayer.make(
			&"npc",
			[&"world", &"player", &"npc", &"prop", &"projectile", &"vehicle", &"npc_clip"],
			"Anything the game drives. Collides with its own kind, which players do not."
		),
		DotPhysicsLayer.make(
			&"prop",
			[&"world", &"player", &"npc", &"prop", &"projectile", &"vehicle"],
			"A simulated object a player can push, shoot or pick up."
		),
		DotPhysicsLayer.make(
			&"debris",
			[&"world"],
			"Shells, gibs, glass. Touches the level and nothing else, on purpose."
		),
		DotPhysicsLayer.make(
			&"projectile",
			[&"world", &"player", &"npc", &"prop", &"vehicle"],
			"A rocket or a grenade in flight. Never a clip brush, never another "
			+ "projectile."
		),
		DotPhysicsLayer.make(
			&"vehicle",
			[&"world", &"player", &"npc", &"prop", &"projectile", &"vehicle_clip"],
			"A driven body, with its own clip layer for the routes it may not take."
		),
		DotPhysicsLayer.make(
			&"ragdoll",
			[&"world"],
			"A corpse. Solid against the level so it settles, and against nothing else "
			+ "so it cannot block a doorway or be used as a step."
		),
		DotPhysicsLayer.make(
			&"player_clip",
			[&"player"],
			"An invisible wall only players collide with.",
			true
		),
		DotPhysicsLayer.make(
			&"npc_clip",
			[&"npc"],
			"An invisible wall only the game's own characters collide with.",
			true
		),
		DotPhysicsLayer.make(
			&"vehicle_clip",
			[&"vehicle"],
			"An invisible wall only vehicles collide with.",
			true
		),
		DotPhysicsLayer.make(
			&"ladder",
			[&"player"],
			"A volume that changes how movement works rather than stopping it.",
			true
		),
		DotPhysicsLayer.make(
			&"water",
			[],
			"A volume that changes how movement works rather than stopping it.",
			true
		),
		DotPhysicsLayer.make(
			&"trigger",
			[],
			"Anything that fires when entered: a capture zone, a timer gate, a hurt "
			+ "volume. Nothing ever rests on one.",
			true
		),
		DotPhysicsLayer.make(
			&"hitbox",
			[],
			"Per-limb shapes a shot traces against, including rewound ones. Never "
			+ "simulated, which is why a bullet's mask and a body's mask are different "
			+ "numbers.",
			true
		),
		DotPhysicsLayer.make(
			&"pickup",
			[],
			"A weapon or an item lying in the world, found by a query rather than by "
			+ "being walked into.",
			true
		),
	]

	var _res := layout.build()
	return layout


## The sandbox layout: the shooter's, plus what a physics gun needs.
##
## Two additions, and both exist because holding an object is not the same as the object
## being solid. A prop on the end of a physics beam must not push the player holding it
## — that is a feedback loop that launches both — and a frozen prop must stay a surface
## a player can stand on while no longer being something the solver integrates.
static func sandbox_3d() -> DotPhysicsLayout:
	var layout := shooter_3d()
	layout.id = &"sandbox_3d"
	layout.description = "A physics sandbox: everything the shooter has, plus held and "
	layout.description += "frozen props."

	layout.layers.append(DotPhysicsLayer.make(
		&"held_prop",
		[&"world", &"prop", &"npc"],
		"A prop on the end of a physics beam. Deliberately NOT the player holding it: "
		+ "a held object that pushes its holder pushes the beam, which pushes the "
		+ "object, and both leave the map."
	))
	layout.layers.append(DotPhysicsLayer.make(
		&"frozen_prop",
		[&"world", &"player", &"npc", &"prop", &"projectile"],
		"A prop the player has frozen. Still a surface to stand on and still shootable; "
		+ "no longer integrated."
	))

	var _res := layout.build()
	return layout


## The side-on 2D layout.
##
## The one-way platform is the reason this is not just the top-down table with different
## names: it is a layer whose collision depends on which direction the body is moving,
## which is a property of the collision shape in Godot and of the [i]layout[/i] in every
## project that forgets to separate it.
static func platformer_2d() -> DotPhysicsLayout:
	var layout := DotPhysicsLayout.new()
	layout.id = &"platformer_2d"
	layout.description = "Side-on 2D: solid ground, one-way platforms, hazards."

	layout.layers = [
		DotPhysicsLayer.make(
			&"world", [&"player", &"enemy", &"prop", &"projectile"], "Solid ground."
		),
		DotPhysicsLayer.make(
			&"one_way",
			[&"player", &"enemy", &"prop"],
			"A platform you pass up through and land on. Its own layer so a projectile "
			+ "is not silently stopped by a surface the player can walk through."
		),
		DotPhysicsLayer.make(
			&"player", [&"world", &"one_way", &"enemy", &"prop", &"hazard"], "The player."
		),
		DotPhysicsLayer.make(
			&"enemy", [&"world", &"one_way", &"player", &"prop", &"projectile"], "Enemies."
		),
		DotPhysicsLayer.make(
			&"prop", [&"world", &"one_way", &"player", &"enemy", &"projectile"], "Pushables."
		),
		DotPhysicsLayer.make(
			&"projectile", [&"world", &"player", &"enemy", &"prop"], "Shots and thrown things."
		),
		DotPhysicsLayer.make(
			&"hazard", [&"player"], "Spikes, lava, a crusher.", true
		),
		DotPhysicsLayer.make(
			&"pickup", [], "Coins and power-ups, found by a query.", true
		),
		DotPhysicsLayer.make(
			&"ladder", [], "Climbable volumes.", true
		),
		DotPhysicsLayer.make(
			&"trigger", [], "Anything that fires when entered.", true
		),
	]

	var _res := layout.build()
	return layout


## The top-down 2D layout. No gravity, no one-way anything, and a lot of bodies.
##
## [b]Note what is missing:[/b] there is no separate debris layer, because in a top-down
## arena the thing that costs is the [i]count[/i] of mutually colliding bodies and the
## answer is a spatial hash rather than a layer. See dot-2d.
static func top_down_2d() -> DotPhysicsLayout:
	var layout := DotPhysicsLayout.new()
	layout.id = &"top_down_2d"
	layout.description = "Top-down 2D arenas: no gravity, many bodies."

	layout.layers = [
		DotPhysicsLayer.make(
			&"world", [&"player", &"enemy", &"prop", &"projectile"], "Walls."
		),
		DotPhysicsLayer.make(
			&"player", [&"world", &"enemy", &"prop"], "Players. Not each other."
		),
		DotPhysicsLayer.make(
			&"enemy", [&"world", &"player", &"enemy", &"prop", &"projectile"], "Enemies."
		),
		DotPhysicsLayer.make(
			&"prop", [&"world", &"player", &"enemy", &"projectile"], "Pushables."
		),
		DotPhysicsLayer.make(
			&"projectile", [&"world", &"enemy", &"prop"], "Shots."
		),
		DotPhysicsLayer.make(&"pickup", [], "Found by a query.", true),
		DotPhysicsLayer.make(&"trigger", [], "Fires when entered.", true),
	]

	var _res := layout.build()
	return layout


## Every preset, by id. What a settings screen or a console command lists.
static func presets() -> Dictionary:
	return {
		&"shooter_3d": Callable(DotPhysicsLayout, "shooter_3d"),
		&"sandbox_3d": Callable(DotPhysicsLayout, "sandbox_3d"),
		&"platformer_2d": Callable(DotPhysicsLayout, "platformer_2d"),
		&"top_down_2d": Callable(DotPhysicsLayout, "top_down_2d"),
	}


## Builds a preset by name. Null for a name that is not one.
static func preset(p_id: StringName) -> DotPhysicsLayout:
	var table := presets()

	if not table.has(p_id):
		return null

	var fn: Callable = table[p_id]
	return fn.call() as DotPhysicsLayout
