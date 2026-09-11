@tool
class_name DotPhysicsSurface
extends Resource

## What one material is like to collide with: friction, bounce, density, and what it
## sounds like.
##
## [b]Distinct from dot-player-controller's [code]DotFpsSurface[/code], and the difference
## is worth stating because the two will otherwise be merged by somebody tidying up.[/b]
## That one is a set of [i]multipliers on player movement[/i] — ice makes you accelerate
## worse. This one is what the [i]solver[/i] is told about a rigid body: how much it
## slides, how much it bounces, and what it weighs per cubic metre. A game wants both,
## and they are read by different code at different times.
##
## The field list is the one that shipped-engine surface tables converged on, because
## each entry turns out to be needed:
##
## - [member friction] and [member restitution] go to the solver;
## - [member density] is what turns a shape's volume into a mass, so a wooden crate and
##   a steel one the same size are not the same weight;
## - [member thickness] is for sheet materials — glass, a fence — which have a volume
##   the solver would otherwise take literally;
## - [member impact_sound] and [member scrape_sound] are ids for dot-audio, kept here
##   because a table with the physics in one file and the sounds in another drifts.

## The name everything else refers to: [code]&"metal"[/code], [code]&"ice"[/code].
@export var id: StringName = &""

@export var display_name: String = ""

@export_group("Solver")

## Coulomb friction, roughly 0 (ice) to 1 (rubber).
@export_range(0.0, 2.0, 0.01) var friction: float = 0.6

## Coefficient of restitution: how much of the approach speed survives a bounce.
##
## Above about 0.9 a body gains energy from solver error and starts bouncing higher than
## it was dropped from, which looks exactly like a bug in the level.
@export_range(0.0, 1.0, 0.01) var restitution: float = 0.1

## Kilograms per cubic metre. Water is 1000, oak about 700, steel about 7800.
@export_range(1.0, 25000.0, 1.0) var density: float = 900.0

## For sheet materials: the real thickness in metres, or 0 for a solid.
##
## A pane of glass modelled as a box is a box; told it is 6 mm thick, its mass comes out
## as a pane of glass's rather than as a solid cube of it.
@export_range(0.0, 1.0, 0.001) var thickness: float = 0.0

## Extra velocity lost on contact, beyond friction. For mud, snow, sand.
@export_range(0.0, 10.0, 0.01) var dampening: float = 0.0

@export_group("Movement")

## Multiplier on a character's ground acceleration. 1.0 is normal ground.
##
## Here as well as in a controller's own surface table because a game that only uses
## dot-physics still wants ice to be slippery, and a game that uses both should be
## reading one number.
@export_range(0.0, 4.0, 0.01) var move_scale: float = 1.0

## Multiplier on a character's ground friction. Below 1 is ice.
@export_range(0.0, 4.0, 0.01) var traction: float = 1.0

## Whether a character takes falling damage landing on this.
@export var breaks_fall: bool = false

@export_group("Presentation")

## dot-audio id played on impact. Empty for silence.
@export var impact_sound: StringName = &""

## dot-audio id played while sliding along it.
@export var scrape_sound: StringName = &""

## dot-audio id played by a footstep on it.
@export var footstep_sound: StringName = &""

## dot-fx id for the puff a bullet makes.
@export var impact_effect: StringName = &""


static func make(
	p_id: StringName,
	p_friction: float,
	p_restitution: float,
	p_density: float
) -> DotPhysicsSurface:
	var s := DotPhysicsSurface.new()
	s.id = p_id
	s.display_name = String(p_id).capitalize()
	s.friction = p_friction
	s.restitution = p_restitution
	s.density = p_density
	return s


## The engine resource the solver actually reads.
##
## Built on demand rather than stored, because a [PhysicsMaterial] handed to two bodies
## is shared by them: editing it to tune one retunes the other, which is the same
## resource-aliasing trap dot-user-avatar's tinting had to avoid.
func to_physics_material() -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = friction
	m.bounce = restitution
	return m


## Mass of a shape of [param volume] cubic metres made of this.
##
## Thickness, when set, is taken as the material being a shell: the volume is treated as
## a surface times the thickness rather than as solid.
func mass_for_volume(volume: float, surface_area: float = 0.0) -> float:
	if thickness > 0.0 and surface_area > 0.0:
		return maxf(0.001, surface_area * thickness * density)

	return maxf(0.001, volume * density)


func describe() -> String:
	return "%s friction=%.2f bounce=%.2f density=%.0f" % [
		String(id), friction, restitution, density
	]


func _to_string() -> String:
	return "DotPhysicsSurface(%s)" % describe()
