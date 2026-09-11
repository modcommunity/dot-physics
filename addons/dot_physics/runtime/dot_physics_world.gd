class_name DotPhysicsWorld
extends Node

## Applies a profile and a layout to the running project, and can put them back.
##
## [b]This is the only thing in the addon that writes to ProjectSettings, and it is a
## [Node] so that the writing has a lifetime.[/b] A dedicated server that switches from
## one game to another switches physics with it — a sandbox at 64 Hz to a timer server
## at 128 — and a settings write with no matching restore is how the second game ends up
## running with the first one's gravity, which presents as "the new mode feels wrong"
## rather than as anything findable.
##
## So [method setup] records what it overwrote and [method restore] puts it back, and
## the node does the restore on the way out of the tree whether or not anybody
## remembered to.
##
## [codeblock]
## var physics := DotPhysicsWorld.new()
## physics.profile = DotPhysicsProfile.arcade_shooter()
## physics.layout = DotPhysicsLayout.shooter_3d()
## physics.surfaces = DotPhysicsSurfaceSet.standard()
## add_child(physics)
## var res := physics.setup()
## [/codeblock]

const CHANNEL := "physics"

## Registry name, so anything can find the one in the scene without a path.
const SERVICE := &"dot_physics_world"

## The two halves of Godot's layer-name settings. Declared rather than written as a
## literal in the loop: an untyped array literal makes its loop variable a [Variant],
## which is a parse error the moment anything infers a type from it.
const KINDS: Array[String] = ["3d", "2d"]

## Fired after [method setup] succeeds, so a controller can re-read gravity.
signal applied(profile: DotPhysicsProfile, layout: DotPhysicsLayout)

## Fired after [method restore].
signal reverted()

## The numbers. Never null after [method setup] — a default is built if none was set.
@export var profile: DotPhysicsProfile = null

## The collision table. Optional: without one, layer names resolve to nothing and
## [DotPhysicsQuery] falls back to Godot's own "collide with everything".
@export var layout: DotPhysicsLayout = null

## The material table. Optional.
@export var surfaces: DotPhysicsSurfaceSet = null

## Whether to write the layer [i]names[/i] into ProjectSettings as well as the numbers.
##
## On by default because a layout a designer cannot see in the inspector's layer
## dropdown is a layout a designer will work around by typing bits again. Off for a
## dedicated server, where nobody is looking at an inspector and the write is pure cost.
@export var write_layer_names: bool = true

## Whether to register in [DotRegistry] under [constant SERVICE].
@export var register_service: bool = true

var _saved: Dictionary = {}
var _applied: bool = false


func _ready() -> void:
	if register_service:
		DotRegistry.register(SERVICE, self)


func _exit_tree() -> void:
	# Unconditional: see the class documentation. A restore nobody called is exactly the
	# case this is for.
	if _applied:
		var _res := restore()


## Writes the profile and the layout into the engine.
##
## Returns a failure without having written anything when the profile does not validate,
## because a half-applied physics configuration is worse than the one it replaced: the
## tick rate changed and the gravity did not, and the game is now in a state no preset
## describes.
func setup() -> DotResult:
	if profile == null:
		profile = DotPhysicsProfile.new()

	var valid := profile.validate()

	if not valid.ok:
		return valid.wrap("This physics profile was not applied")

	if layout != null:
		var built := layout.build()
		if not built.ok:
			return built.wrap("This collision layout was not applied")

	if _applied:
		var _res := restore()

	_write_setting("physics/common/physics_ticks_per_second", profile.tick_rate)
	_write_setting("physics/common/max_physics_steps_per_frame", profile.max_steps_per_frame)
	_write_setting("physics/common/physics_interpolation", profile.physics_interpolation)

	_write_setting("physics/3d/default_gravity", profile.gravity_3d)
	_write_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	_write_setting("physics/3d/default_linear_damp", profile.linear_damp_3d)
	_write_setting("physics/3d/default_angular_damp", profile.angular_damp_3d)
	_write_setting("physics/3d/sleep_threshold_linear", profile.sleep_threshold_linear)
	_write_setting("physics/3d/sleep_threshold_angular", profile.sleep_threshold_angular)
	_write_setting("physics/3d/time_before_sleep", profile.time_before_sleep)
	_write_setting("physics/3d/solver/solver_iterations", profile.solver_iterations)
	_write_setting("physics/3d/solver/default_contact_bias", profile.contact_bias)
	_write_setting(
		"physics/3d/solver/contact_max_allowed_penetration",
		profile.max_allowed_penetration
	)
	_write_setting("physics/3d/solver/contact_max_separation", profile.contact_max_separation)
	_write_setting("physics/3d/solver/contact_recycle_radius", profile.contact_recycle_radius)

	_write_setting(
		"physics/2d/default_gravity",
		profile.gravity_2d if profile.gravity_2d_enabled else 0.0
	)
	_write_setting("physics/2d/default_gravity_vector", Vector2.DOWN)
	_write_setting("physics/2d/default_linear_damp", profile.linear_damp_2d)
	_write_setting("physics/2d/default_angular_damp", profile.angular_damp_2d)
	_write_setting("physics/2d/sleep_threshold_linear", profile.sleep_threshold_linear * 100.0)
	_write_setting("physics/2d/sleep_threshold_angular", profile.sleep_threshold_angular)
	_write_setting("physics/2d/time_before_sleep", profile.time_before_sleep)
	_write_setting("physics/2d/solver/solver_iterations", profile.solver_iterations)
	_write_setting("physics/2d/solver/default_contact_bias", profile.contact_bias)

	# The engine reads its tick rate from Engine, not from ProjectSettings, once the
	# project is running. Setting only the project setting changes the number a future
	# run uses and not this one, which is exactly the kind of "the setting does nothing"
	# bug this family has shipped before.
	Engine.physics_ticks_per_second = profile.tick_rate
	Engine.max_physics_steps_per_frame = profile.max_steps_per_frame

	if layout != null and write_layer_names:
		for kind in KINDS:
			var names := layout.project_setting_names(kind)
			for key: Variant in names.keys():
				_write_setting(String(key), names[key])

	_applied = true

	DotLog.info(CHANNEL, "physics applied", {
		"tick_rate": profile.tick_rate,
		"gravity_3d": profile.gravity_3d,
		"layout": String(layout.id) if layout != null else "<none>",
		"layers": layout.layers.size() if layout != null else 0,
	})

	applied.emit(profile, layout)
	return DotResult.success(null)


## Puts every setting this node overwrote back.
func restore() -> DotResult:
	if not _applied:
		return DotResult.success(null)

	for key: Variant in _saved.keys():
		ProjectSettings.set_setting(String(key), _saved[key])

	if _saved.has("physics/common/physics_ticks_per_second"):
		Engine.physics_ticks_per_second = int(
			_saved["physics/common/physics_ticks_per_second"]
		)

	if _saved.has("physics/common/max_physics_steps_per_frame"):
		Engine.max_physics_steps_per_frame = int(
			_saved["physics/common/max_physics_steps_per_frame"]
		)

	_saved.clear()
	_applied = false

	DotLog.debug(CHANNEL, "physics restored")
	reverted.emit()
	return DotResult.success(null)


## Switches to a named profile preset, keeping the layout.
func use_profile_preset(preset_id: StringName) -> DotResult:
	var p := DotPhysicsProfile.preset(preset_id)

	if p == null:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"No physics profile preset called '%s'." % String(preset_id),
			"Known: %s" % ", ".join(_preset_names(DotPhysicsProfile.presets()))
		)

	profile = p
	return setup()


## Switches to a named layout preset, keeping the profile.
func use_layout_preset(preset_id: StringName) -> DotResult:
	var l := DotPhysicsLayout.preset(preset_id)

	if l == null:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"No collision layout preset called '%s'." % String(preset_id),
			"Known: %s" % ", ".join(_preset_names(DotPhysicsLayout.presets()))
		)

	layout = l
	return setup()


## A query object bound to this world's layout and surfaces.
func query() -> DotPhysicsQuery:
	return DotPhysicsQuery.new(layout, surfaces)


## Sets a collision object's layer and mask from the layout, by name.
func classify(node: Node, layer_id: StringName) -> DotResult:
	if layout == null:
		return DotResult.fail(
			DotError.CODE_STATE,
			"No collision layout is installed, so '%s' means nothing." % String(layer_id)
		)

	return layout.apply_to(node, layer_id)


func is_applied() -> bool:
	return _applied


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("dot-physics %s" % ("applied" if _applied else "not applied"))

	if profile != null:
		out.append("  tick rate        %d Hz (%.4f s)" % [
			profile.tick_rate, profile.tick_delta()
		])
		out.append("  gravity          %.2f m/s² 3D, %.0f px/s² 2D" % [
			profile.gravity_3d, profile.gravity_2d
		])
		out.append("  solver           %d iterations, bias %.2f" % [
			profile.solver_iterations, profile.contact_bias
		])
		out.append("  characters       slope %.1f°, step %.2f m" % [
			profile.max_slope_angle, profile.step_height
		])
		out.append("  interpolation    %s" % (
			"on" if profile.physics_interpolation else "off"
		))

	if layout != null:
		out.append_array(layout.describe_lines())

	if surfaces != null:
		out.append_array(surfaces.describe_lines())

	out.append("  %d settings saved for restore" % _saved.size())
	return out


func describe() -> String:
	return "DotPhysicsWorld(%s, %d Hz)" % [
		"applied" if _applied else "idle",
		profile.tick_rate if profile != null else 0,
	]


## Writes one setting, remembering the old value exactly once.
##
## Exactly once matters: a second [method setup] without a restore would otherwise
## record its own value as the thing to go back to, and the original would be gone.
##
## [b]Not called [code]_set[/code].[/b] [Object] already has a [code]_set[/code] virtual
## — the one the engine calls for every property assignment on this node — and GDScript
## would take this definition without a word. See the family's gdscript-hazards notes:
## a method that shadows a native one is silently the native one, and here it would be
## the reverse and worse.
func _write_setting(key: String, value: Variant) -> void:
	if not _saved.has(key):
		_saved[key] = ProjectSettings.get_setting(key, null)

	ProjectSettings.set_setting(key, value)


func _preset_names(table: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for k: Variant in table.keys():
		out.append(String(k))
	out.sort()
	return out
