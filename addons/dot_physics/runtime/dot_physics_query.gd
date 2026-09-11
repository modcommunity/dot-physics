class_name DotPhysicsQuery
extends RefCounted

## Casts written against layer names instead of bit arithmetic, in 2D and 3D.
##
## [b]Every one of these is four lines of Godot and the four lines are where the bugs
## are.[/b] A [PhysicsRayQueryParameters3D] built by hand forgets
## [code]collide_with_areas[/code] and misses every trigger, or leaves it on and stops
## every bullet on one; it forgets to exclude the shooter and every shot hits the person
## who fired it; and it takes a mask as a number, which is the thing this addon exists
## to stop people writing.
##
## The results are plain [Dictionary] values — Godot's own shape, plus a
## [code]surface[/code] entry when a [DotPhysicsSurfaceSet] was supplied — so nothing
## downstream has to import this class to read one.

const CHANNEL := "physics.query"

var layout: DotPhysicsLayout = null
var surfaces: DotPhysicsSurfaceSet = null


func _init(p_layout: DotPhysicsLayout = null, p_surfaces: DotPhysicsSurfaceSet = null) -> void:
	layout = p_layout
	surfaces = p_surfaces


# --- 3D ---------------------------------------------------------------------

## A ray from [param from] to [param to], hitting only the named layers.
##
## Empty dictionary for a miss, which is Godot's own convention and is why this does not
## return a [DotResult]: a ray that hits nothing is not a failure, it is an answer, and
## wrapping it would make every call site branch twice.
func ray_3d(
	world: World3D,
	from: Vector3,
	to: Vector3,
	layer_ids: Array[StringName],
	exclude: Array[RID] = [],
	hit_areas: bool = false
) -> Dictionary:
	if world == null:
		DotLog.warn(CHANNEL, "no world to cast in")
		return {}

	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = _mask(layer_ids)
	params.exclude = exclude
	params.collide_with_areas = hit_areas
	params.collide_with_bodies = true
	params.hit_from_inside = false

	var hit := world.direct_space_state.intersect_ray(params)
	return _decorate(hit)


## What a fired shot should use: everything solid, nothing query-only, not the shooter.
##
## Separate from [method ray_3d] because the mask is the part people get wrong, and
## because a shot that stops on its own hitbox is a bug this family has already shipped
## once in a different addon.
func shot_3d(
	world: World3D,
	from: Vector3,
	to: Vector3,
	shooter: Array[RID] = []
) -> Dictionary:
	if world == null:
		return {}

	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = layout.solid_mask() if layout != null else 0xFFFFFFFF
	params.exclude = shooter
	params.collide_with_areas = false

	return _decorate(world.direct_space_state.intersect_ray(params))


## Every body overlapping a sphere. What a grenade asks.
func sphere_3d(
	world: World3D,
	centre: Vector3,
	radius: float,
	layer_ids: Array[StringName],
	max_results: int = 32
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if world == null:
		return out

	var shape := SphereShape3D.new()
	shape.radius = maxf(0.001, radius)

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, centre)
	params.collision_mask = _mask(layer_ids)
	params.collide_with_areas = false
	params.collide_with_bodies = true

	for hit in world.direct_space_state.intersect_shape(params, max_results):
		out.append(_decorate(hit))

	return out


## Whether [param from] can see [param to] with nothing solid in between.
##
## The one-line version of the question every AI, every objective and every spawn
## selector asks, and the one people re-implement with a different mask each time.
func line_of_sight_3d(
	world: World3D,
	from: Vector3,
	to: Vector3,
	exclude: Array[RID] = []
) -> bool:
	if world == null:
		return false

	var blockers: Array[StringName] = [&"world"]

	if layout != null and layout.has_layer(&"prop"):
		blockers.append(&"prop")

	var hit := ray_3d(world, from, to, blockers, exclude, false)
	return hit.is_empty()


# --- 2D ---------------------------------------------------------------------

func ray_2d(
	world: World2D,
	from: Vector2,
	to: Vector2,
	layer_ids: Array[StringName],
	exclude: Array[RID] = [],
	hit_areas: bool = false
) -> Dictionary:
	if world == null:
		DotLog.warn(CHANNEL, "no world to cast in")
		return {}

	var params := PhysicsRayQueryParameters2D.create(from, to)
	params.collision_mask = _mask(layer_ids)
	params.exclude = exclude
	params.collide_with_areas = hit_areas
	params.collide_with_bodies = true

	return _decorate(world.direct_space_state.intersect_ray(params))


func circle_2d(
	world: World2D,
	centre: Vector2,
	radius: float,
	layer_ids: Array[StringName],
	max_results: int = 32
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if world == null:
		return out

	var shape := CircleShape2D.new()
	shape.radius = maxf(0.001, radius)

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, centre)
	params.collision_mask = _mask(layer_ids)
	params.collide_with_areas = false
	params.collide_with_bodies = true

	for hit in world.direct_space_state.intersect_shape(params, max_results):
		out.append(_decorate(hit))

	return out


# --- Internals --------------------------------------------------------------

## A mask from names, or everything when there is no layout.
##
## Everything rather than nothing: a query with no layout installed that hits nothing at
## all is a silent, total failure of whatever called it, and this addon being absent
## should degrade to "Godot's default behaviour" rather than to "no physics".
func _mask(layer_ids: Array[StringName]) -> int:
	if layout == null:
		return 0xFFFFFFFF

	return layout.mask_of(layer_ids)


func _decorate(hit: Dictionary) -> Dictionary:
	if hit.is_empty():
		return hit

	if surfaces != null:
		hit["surface"] = surfaces.for_collider(hit.get("collider", null))

	return hit
