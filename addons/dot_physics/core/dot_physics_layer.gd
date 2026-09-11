@tool
class_name DotPhysicsLayer
extends Resource

## One named collision layer, and what it is allowed to touch.
##
## [b]The name is the point.[/b] Godot gives a project thirty-two collision bits and no
## memory of what any of them meant, so the arithmetic ends up written out at every call
## site — [code]1 << 3 | 1 << 7[/code] in one script and [code]0x88[/code] in another,
## and the day a layer moves, one of them is quietly wrong and the bug is "bullets pass
## through the glass sometimes".
##
## So a layer is declared once, with a [member id], and everything downstream asks for it
## by that id. [member bit] is an implementation detail that a [DotPhysicsLayout] assigns
## and nothing else needs to read.

## The name used everywhere else: [code]&"player"[/code], [code]&"debris"[/code].
@export var id: StringName = &""

## Which bit this occupies, 0-31. Assigned by the layout; -1 until then.
##
## Not exported as a number for the designer to choose, because two layers with the same
## number is a bug with no symptom until two unrelated things start colliding.
@export_range(-1, 31, 1) var bit: int = -1

## What this layer collides with, by id.
##
## [b]Declared one way and made symmetric by the layout.[/b] Physics collision is
## mutually exclusive in the engine — A's mask must contain B's layer [i]and[/i] the
## reverse for a pair to report a contact — and a table where "debris collides with
## world" is written in one place and "world collides with debris" in another is a table
## that drifts. [method DotPhysicsLayout.build] closes the relation instead.
@export var collides_with: Array[StringName] = []

## Human-readable, for the editor and for [method DotPhysicsLayout.describe_lines].
@export var description: String = ""

## Whether this layer describes something that is queried but never simulated.
##
## Triggers, clip brushes and hitboxes are all this: an [Area3D] or a shape a raycast is
## meant to find, which no rigid body should ever rest on. Kept as a flag rather than a
## convention because [method DotPhysicsLayout.query_only_mask] is what a bullet trace
## needs in order to skip them, and a game that gets it wrong sees shots stopping in
## mid-air on a trigger volume.
@export var query_only: bool = false


static func make(
	p_id: StringName,
	p_collides_with: Array[StringName] = [],
	p_description: String = "",
	p_query_only: bool = false
) -> DotPhysicsLayer:
	var l := DotPhysicsLayer.new()
	l.id = p_id
	l.collides_with = p_collides_with.duplicate()
	l.description = p_description
	l.query_only = p_query_only
	return l


## The single-bit mask for this layer, or 0 while it is unassigned.
func mask() -> int:
	return 0 if bit < 0 else (1 << bit)


func describe() -> String:
	return "%s bit=%d collides_with=[%s]%s" % [
		String(id),
		bit,
		", ".join(_names()),
		" (query only)" if query_only else "",
	]


func _names() -> PackedStringArray:
	var out := PackedStringArray()
	for n in collides_with:
		out.append(String(n))
	return out


func _to_string() -> String:
	return "DotPhysicsLayer(%s)" % describe()
