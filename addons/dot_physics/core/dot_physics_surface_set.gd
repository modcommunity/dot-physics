@tool
class_name DotPhysicsSurfaceSet
extends Resource

## The surface table, and how a collider maps to an entry in it.
##
## [b]The lookup is the hard half, not the table.[/b] A ray hits a collider and the game
## needs to know it hit concrete; nothing in Godot's collision result says so. The three
## answers, in the order they are tried, are the three that every engine ends up with:
## a per-node metadata entry, then the node's groups, then the name of the collider —
## and the last one is a fallback rather than a design, because a level built by a
## mapper is the one case where nothing else is available.
##
## [codeblock]
## var set := DotPhysicsSurfaceSet.standard()
## var surface := set.for_collider(hit.collider)
## audio.play(surface.footstep_sound)
## [/codeblock]

const CHANNEL := "physics.surfaces"

## The node metadata key checked first. A mapper sets this on a [StaticBody3D].
const META_KEY := "dot_surface"

@export var surfaces: Array[DotPhysicsSurface] = []

## Used when nothing matches. Never null after [method build].
@export var fallback_id: StringName = &"concrete"

var _by_id: Dictionary = {}
var _built: bool = false


func build() -> DotResult:
	_by_id.clear()

	for s in surfaces:
		if s == null or s.id == &"":
			continue
		_by_id[s.id] = s

	if _by_id.is_empty():
		return DotResult.fail(
			DotError.CODE_INVALID, "A surface set with no surfaces answers nothing."
		)

	if not _by_id.has(fallback_id):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The fallback surface '%s' is not in the table." % String(fallback_id),
			"Every unmatched collider would resolve to null, and the callers that "
			+ "expect a surface would each crash somewhere else."
		)

	_built = true
	return DotResult.success(null)


func _ensure_built() -> void:
	if not _built or _by_id.size() == 0:
		var res := build()
		if not res.ok:
			DotLog.error(CHANNEL, "surface set unusable", {"why": res.error.message})


func has(surface_id: StringName) -> bool:
	_ensure_built()
	return _by_id.has(surface_id)


## The surface with this id, or the fallback. Never null once [method build] has passed.
func get_surface(surface_id: StringName) -> DotPhysicsSurface:
	_ensure_built()

	if _by_id.has(surface_id):
		return _by_id[surface_id]

	return _by_id.get(fallback_id, null)


func fallback() -> DotPhysicsSurface:
	_ensure_built()
	return _by_id.get(fallback_id, null)


## Which surface a collider is made of.
##
## Metadata, then groups, then the node name — see the class documentation for why that
## order. Returns the fallback rather than null, because every caller of this is in the
## middle of playing a sound or spawning a decal and none of them has a sensible thing
## to do with nothing.
func for_collider(collider: Object) -> DotPhysicsSurface:
	_ensure_built()

	if collider == null:
		return fallback()

	if collider is Node:
		var node := collider as Node

		if node.has_meta(META_KEY):
			var from_meta: Variant = node.get_meta(META_KEY)
			var meta_id := StringName(str(from_meta))
			if _by_id.has(meta_id):
				return _by_id[meta_id]

		for group in node.get_groups():
			var group_id := StringName(String(group).trim_prefix("surface_"))
			if _by_id.has(group_id):
				return _by_id[group_id]

		# The fallback of the fallbacks: a mapper's node called "metal_walkway_03".
		# Substring rather than equality because names in a level are never exactly a
		# surface id, and this is the one place where guessing beats nothing.
		var lowered := node.name.to_lower()
		for surface_id: Variant in _by_id.keys():
			if lowered.contains(String(surface_id)):
				return _by_id[surface_id]

	return fallback()


## Tags a node so [method for_collider] finds it in one step.
static func tag(node: Node, surface_id: StringName) -> void:
	if node != null:
		node.set_meta(META_KEY, String(surface_id))


func ids() -> Array[StringName]:
	_ensure_built()
	var out: Array[StringName] = []
	for s in surfaces:
		if s != null:
			out.append(s.id)
	return out


func describe_lines() -> PackedStringArray:
	_ensure_built()
	var out := PackedStringArray()
	out.append("%d surfaces, fallback '%s'" % [surfaces.size(), String(fallback_id)])

	for s in surfaces:
		if s != null:
			out.append("  " + s.describe())

	return out


func describe() -> String:
	return "DotPhysicsSurfaceSet(%d surfaces)" % surfaces.size()


func _to_string() -> String:
	return describe()


# --- Presets ----------------------------------------------------------------

## The eighteen surfaces a level is actually built out of: what buildings are made of, what
## the ground outdoors is, and the two liquids.
##
## Numbers are ordinary physical ones where the material is real — steel is 7800 kg/m³
## because it is — and chosen by feel where it is not. Ice at 0.05 friction is not what
## ice measures at; it is what ice has to be for a player to notice it.
static func standard() -> DotPhysicsSurfaceSet:
	var set := DotPhysicsSurfaceSet.new()

	var concrete := DotPhysicsSurface.make(&"concrete", 0.8, 0.05, 2400.0)
	concrete.footstep_sound = &"step_concrete"
	concrete.impact_effect = &"impact_concrete"
	concrete.impact_sound = &"impact_concrete"

	var metal := DotPhysicsSurface.make(&"metal", 0.5, 0.2, 7800.0)
	metal.footstep_sound = &"step_metal"
	metal.impact_effect = &"impact_metal"
	metal.impact_sound = &"impact_metal"
	metal.scrape_sound = &"scrape_metal"

	var wood := DotPhysicsSurface.make(&"wood", 0.6, 0.1, 700.0)
	wood.footstep_sound = &"step_wood"
	wood.impact_effect = &"impact_wood"
	wood.impact_sound = &"impact_wood"

	var glass := DotPhysicsSurface.make(&"glass", 0.4, 0.15, 2500.0)
	glass.thickness = 0.006
	# A pane takes a pistol magazine or one good hit from a thrown crate. Low on purpose:
	# glass in a level is there to be broken.
	glass.break_health = 25.0
	glass.footstep_sound = &"step_glass"
	glass.impact_effect = &"impact_glass"
	glass.impact_sound = &"impact_glass"

	var dirt := DotPhysicsSurface.make(&"dirt", 0.85, 0.0, 1600.0)
	dirt.dampening = 0.4
	dirt.footstep_sound = &"step_dirt"
	dirt.impact_effect = &"impact_dirt"

	var grass := DotPhysicsSurface.make(&"grass", 0.8, 0.0, 1200.0)
	grass.dampening = 0.3
	grass.footstep_sound = &"step_grass"
	grass.impact_effect = &"impact_dirt"

	var sand := DotPhysicsSurface.make(&"sand", 0.9, 0.0, 1500.0)
	sand.dampening = 1.2
	sand.move_scale = 0.8
	sand.breaks_fall = true
	sand.footstep_sound = &"step_sand"

	var snow := DotPhysicsSurface.make(&"snow", 0.5, 0.0, 400.0)
	snow.dampening = 0.8
	snow.move_scale = 0.9
	snow.breaks_fall = true
	snow.footstep_sound = &"step_snow"

	var ice := DotPhysicsSurface.make(&"ice", 0.05, 0.05, 917.0)
	ice.traction = 0.1
	ice.move_scale = 0.7
	ice.footstep_sound = &"step_ice"

	var flesh := DotPhysicsSurface.make(&"flesh", 0.9, 0.0, 1050.0)
	flesh.dampening = 2.0
	flesh.breaks_fall = true
	flesh.impact_effect = &"impact_flesh"
	flesh.impact_sound = &"impact_flesh"

	var water := DotPhysicsSurface.make(&"water", 0.1, 0.0, 1000.0)
	water.dampening = 3.0
	water.move_scale = 0.5
	water.breaks_fall = true
	water.footstep_sound = &"step_water"
	water.impact_effect = &"impact_water"
	water.liquid = true

	var rock := DotPhysicsSurface.make(&"rock", 0.8, 0.05, 2600.0)
	rock.footstep_sound = &"step_rock"
	rock.impact_effect = &"impact_concrete"
	rock.impact_sound = &"impact_concrete"

	# Deeper and stickier than dirt: slow to cross, and a jump out of it is a short one.
	var mud := DotPhysicsSurface.make(&"mud", 0.95, 0.0, 1700.0)
	mud.dampening = 2.5
	mud.move_scale = 0.6
	mud.traction = 1.2
	mud.jump_scale = 0.8
	mud.breaks_fall = true
	mud.footstep_sound = &"step_mud"
	mud.impact_effect = &"impact_dirt"

	# A trampoline. Restitution at 0.8 rather than at 1: past about 0.9 solver error adds
	# energy and a body bounces higher than it was dropped from (see [member restitution]).
	var rubber := DotPhysicsSurface.make(&"rubber", 1.0, 0.8, 1100.0)
	rubber.jump_scale = 1.8
	rubber.breaks_fall = true
	rubber.footstep_sound = &"step_rubber"
	rubber.impact_sound = &"impact_rubber"

	# Molten rock: a liquid that burns. Dense enough that wood floats on it and a person
	# wades rather than swims.
	var lava := DotPhysicsSurface.make(&"lava", 0.9, 0.0, 3100.0)
	lava.liquid = true
	lava.dampening = 6.0
	lava.move_scale = 0.3
	lava.hazard_damage = 60.0
	lava.impact_effect = &"impact_lava"

	# Ice thin enough to break: a hard landing or a few shots and it goes, and whatever is
	# under it (a frozen pond) is what the player meets next.
	var thin_ice := DotPhysicsSurface.make(&"thin_ice", 0.05, 0.05, 917.0)
	thin_ice.traction = 0.1
	thin_ice.move_scale = 0.7
	thin_ice.thickness = 0.05
	thin_ice.break_health = 8.0
	thin_ice.footstep_sound = &"step_ice"
	thin_ice.impact_sound = &"impact_glass"

	# Toxic: a liquid a person can swim in (barely denser than water) that hurts while they do.
	var slime := DotPhysicsSurface.make(&"slime", 0.3, 0.0, 1100.0)
	slime.liquid = true
	slime.dampening = 4.0
	slime.move_scale = 0.5
	slime.hazard_damage = 15.0
	slime.impact_effect = &"impact_water"

	# Leaves: drawn, walked through, hidden in. Not solid and not a liquid.
	var foliage := DotPhysicsSurface.make(&"foliage", 0.0, 0.0, 200.0)
	foliage.solid = false
	foliage.footstep_sound = &"step_grass"

	set.surfaces = [
		concrete, metal, wood, glass, dirt, grass, sand, snow, ice, flesh, water,
		rock, mud, rubber, lava, thin_ice, slime, foliage,
	]
	set.fallback_id = &"concrete"

	var _res := set.build()
	return set
