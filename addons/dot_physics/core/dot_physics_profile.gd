@tool
class_name DotPhysicsProfile
extends DotConfig

## Every engine-level physics number, layered, with presets named after how they feel.
##
## [b]These are the settings a project sets once, in the editor, and then cannot find
## again.[/b] They live in ProjectSettings under names like
## [code]physics/3d/solver/default_contact_bias[/code], they are not in version control
## in any reviewable form, and changing one changes how every rigid body in the game
## behaves. So they are a [DotConfig] here instead: layered the family's way — exported
## defaults, then a JSON file, then the environment, then the command line — which is
## what lets a dedicated server be told to run at 128 Hz without a rebuild.
##
## The presets are deliberately named for the [i]feel[/i] rather than for a title.
## "Arcade shooter" is a real, describable set of choices — high gravity, a short jump,
## props that settle fast — and naming it that way is the difference between a table
## somebody can reason about and a table somebody copies.

@export_group("Time")

## Simulation ticks per second.
##
## [b]The single most consequential number in this file.[/b] It sets the granularity of
## every collision test, so a fast projectile at 30 Hz passes through a wall that it
## catches at 128; and it is the rate a networked game's commands are counted in, so
## changing it changes what a recorded run means. dot-net, dot-match and dot-timer all
## count in ticks and all have to be told the same number — which is why this is one
## value in one place rather than three.
@export_range(10, 1000, 1) var tick_rate: int = 60

## How many physics steps one rendered frame may run before the engine gives up.
##
## The clamp that stops a stalled frame — a level load, a breakpoint, a laptop lid —
## from becoming a spiral of ever-longer catch-up. Raising it does not help a slow
## machine; it makes the stall longer.
@export_range(1, 64, 1) var max_steps_per_frame: int = 8

@export_group("Gravity")

## Metres per second squared, downward, in 3D.
##
## Godot's default is 9.8, which is correct and feels wrong: a player falling at true
## Earth gravity at a human scale reads as floating, and every shooter since the
## mid-nineties has used roughly twice it. 20.0 is what dot-player-controller's own
## tunables use, and the two agreeing matters — a controller simulating its own gravity
## against a world using a different one produces props and players that fall at
## visibly different rates.
@export_range(0.0, 200.0, 0.1) var gravity_3d: float = 20.0

## Pixels per second squared, downward, in 2D.
@export_range(0.0, 20000.0, 1.0) var gravity_2d: float = 980.0

## Whether 2D has gravity at all. Off for a top-down game.
@export var gravity_2d_enabled: bool = true

@export_group("Damping")

## Velocity a body loses per second to nothing in particular.
##
## The engine's stand-in for air. Zero is vacuum and is what a shooter wants for a
## projectile; a small value is what stops a sandbox prop drifting forever after a nudge.
@export_range(0.0, 100.0, 0.001, "or_greater") var linear_damp_3d: float = 0.1

@export_range(0.0, 100.0, 0.001, "or_greater") var angular_damp_3d: float = 0.1

@export_range(0.0, 100.0, 0.001, "or_greater") var linear_damp_2d: float = 0.1

@export_range(0.0, 100.0, 0.001, "or_greater") var angular_damp_2d: float = 1.0

@export_group("Sleeping")

## Below this speed for [member time_before_sleep] seconds, a body stops being simulated.
##
## [b]The setting that decides whether a sandbox is playable.[/b] Two hundred props that
## never sleep is two hundred bodies in the solver every tick forever; the same two
## hundred asleep cost nothing. Too high and a prop freezes visibly while still moving,
## which reads as the game stuttering.
@export_range(0.0, 10.0, 0.01) var sleep_threshold_linear: float = 0.1

@export_range(0.0, 20.0, 0.01) var sleep_threshold_angular: float = 0.139626

@export_range(0.0, 60.0, 0.01) var time_before_sleep: float = 0.5

@export_group("Solver")

## Constraint solver iterations per step.
##
## More is stiffer and slower. Eight is Godot's default and is right for a game whose
## physics is decoration; a stack of crates a player is meant to climb wants more, and a
## ragdoll wants more still. This is the knob to turn when things sink into each other.
@export_range(1, 64, 1) var solver_iterations: int = 8

## How hard the solver pushes overlapping bodies apart, per step, as a fraction.
##
## Low is soft and stable, high is rigid and jittery. The default is Godot's.
@export_range(0.0, 1.0, 0.001) var contact_bias: float = 0.8

## Overlap the solver tolerates before it corrects at all, in metres.
##
## Not zero, on purpose: a solver asked to resolve every micron spends its whole budget
## fighting floating-point noise, and the symptom is a resting stack that hums.
@export_range(0.0, 1.0, 0.0001) var max_allowed_penetration: float = 0.01

@export_range(0.0, 1.0, 0.0001) var contact_max_separation: float = 0.05

@export_range(0.0, 1.0, 0.0001) var contact_recycle_radius: float = 0.01

@export_group("Characters")

## Steepest floor a character may stand on, in degrees.
##
## [b]Also the definition of a surf ramp.[/b] A face steeper than this does not ground
## the player, so they keep air acceleration and slide along it — which is not a feature
## anybody implemented, it is what a collide-and-slide movement model does when the
## ground test fails. Lowering this number makes more of a map surfable.
@export_range(0.0, 89.0, 0.5) var max_slope_angle: float = 46.0

## Tallest lip a character walks up without jumping, in metres.
##
## The number that decides whether stairs feel like stairs or like a wall. Must stay
## below the crouched height or a crouched player steps into somewhere they cannot fit.
@export_range(0.0, 2.0, 0.01) var step_height: float = 0.4

## Whether characters are pushed by, and push, simulated bodies.
##
## Off for a competitive shooter: a player who can be shoved by a prop can be shoved off
## a ledge by a team-mate with a crate, and server-authoritative rigid bodies are not
## reproducible across machines anyway.
@export var characters_push_bodies: bool = false

@export_group("Interpolation")

## Whether the engine interpolates transforms between physics ticks for rendering.
##
## What lets a 30 Hz simulation render at 144 Hz without looking like it. Costs a frame
## of latency by construction, which is why a competitive shooter at a high tick rate
## turns it off and a sandbox leaves it on.
@export var physics_interpolation: bool = false


func env_prefix() -> String:
	return "DOT_PHYSICS_"


func cli_prefix() -> String:
	return "physics-"


func validate() -> DotResult:
	if step_height >= 1.0 and max_slope_angle < 1.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A step height of %.2f m with a maximum slope of %.1f° means a character "
			% [step_height, max_slope_angle]
			+ "steps up things it may not stand on, and then falls off them."
		)

	if contact_max_separation < max_allowed_penetration:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"contact_max_separation (%.4f) is below max_allowed_penetration "
				+ "(%.4f). The solver would discard the contacts it is meant to be "
				+ "correcting, and bodies sink through each other under load."
			) % [contact_max_separation, max_allowed_penetration]
		)

	if max_steps_per_frame < 1:
		return DotResult.fail(
			DotError.CODE_INVALID, "max_steps_per_frame must be at least 1."
		)

	return DotResult.success(null)


## Seconds in one simulated tick.
func tick_delta() -> float:
	return 1.0 / float(maxi(1, tick_rate))


func max_slope_radians() -> float:
	return deg_to_rad(max_slope_angle)


## Jump launch speed for a given apex height, under this profile's gravity.
##
## Here rather than in a controller so that a game changing gravity does not silently
## change how high everything jumps.
func jump_speed_for(height: float) -> float:
	return sqrt(2.0 * maxf(0.0001, gravity_3d) * maxf(0.0, height))


func gravity_vector_3d() -> Vector3:
	return Vector3.DOWN * gravity_3d


func gravity_vector_2d() -> Vector2:
	return Vector2.DOWN * (gravity_2d if gravity_2d_enabled else 0.0)


# --- Presets ----------------------------------------------------------------

## Fast, high-gravity, low-friction-feeling movement, and props that settle quickly.
##
## The arcade first-person shooter: air control matters, jumps are short and snappy, and
## the physics exists to be shot at rather than to be simulated accurately. 128 Hz
## because hit registration at speed is the whole game.
static func arcade_shooter() -> DotPhysicsProfile:
	var p := DotPhysicsProfile.new()
	p.tick_rate = 128
	p.gravity_3d = 20.0
	p.linear_damp_3d = 0.05
	p.angular_damp_3d = 0.1
	p.solver_iterations = 8
	p.max_slope_angle = 46.0
	p.step_height = 0.4
	p.characters_push_bodies = false
	p.physics_interpolation = false
	p.sleep_threshold_linear = 0.2
	p.time_before_sleep = 0.3
	return p


## Earth-ish gravity, a deliberate step, stiffer contacts, interpolation on.
##
## The grounded shooter and the co-operative shooter: movement is weighty, stacks of
## crates hold, ragdolls settle rather than twitch. 64 Hz, because the simulation is
## doing more per tick and nothing in it is decided by a shot fired mid-strafe.
static func grounded() -> DotPhysicsProfile:
	var p := DotPhysicsProfile.new()
	p.tick_rate = 64
	p.gravity_3d = 12.0
	p.linear_damp_3d = 0.15
	p.angular_damp_3d = 0.2
	p.solver_iterations = 16
	p.contact_bias = 0.9
	p.max_slope_angle = 40.0
	p.step_height = 0.35
	p.characters_push_bodies = true
	p.physics_interpolation = true
	return p


## Everything stays where it is put, and two hundred props cost nothing.
##
## The sandbox: high solver iterations so a stack holds, an aggressive sleep threshold
## so a map full of settled props is free, and characters that push bodies because
## shoving things about is the point.
static func sandbox() -> DotPhysicsProfile:
	var p := DotPhysicsProfile.new()
	p.tick_rate = 64
	p.gravity_3d = 16.0
	p.linear_damp_3d = 0.12
	p.angular_damp_3d = 0.3
	p.solver_iterations = 24
	p.contact_bias = 0.9
	p.sleep_threshold_linear = 0.08
	p.sleep_threshold_angular = 0.1
	p.time_before_sleep = 0.4
	p.characters_push_bodies = true
	p.physics_interpolation = true
	return p


## Long jumps, slow falls, generous slopes.
##
## The side-on platformer, where gravity is a design parameter rather than a physical
## constant and the arc of a jump is the whole feel of the game.
static func floaty_platformer() -> DotPhysicsProfile:
	var p := DotPhysicsProfile.new()
	p.tick_rate = 60
	p.gravity_2d = 1400.0
	p.gravity_3d = 9.0
	p.linear_damp_2d = 0.0
	p.angular_damp_2d = 0.0
	p.max_slope_angle = 55.0
	p.step_height = 0.5
	p.physics_interpolation = true
	return p


## No gravity, no damping, and a lot of bodies.
##
## The top-down arena. Everything that moves is driven rather than falling, so the only
## numbers that matter are the solver's and the sleep threshold's.
static func top_down() -> DotPhysicsProfile:
	var p := DotPhysicsProfile.new()
	p.tick_rate = 60
	p.gravity_2d_enabled = false
	p.gravity_2d = 0.0
	p.gravity_3d = 0.0
	p.linear_damp_2d = 1.0
	p.angular_damp_2d = 2.0
	p.solver_iterations = 6
	p.physics_interpolation = true
	return p


## The values this project already has, read out of ProjectSettings.
##
## [b]For a game whose rigid bodies are content.[/b] A preset is a set of decisions, and
## applying one to a project whose props and vehicles were tuned by hand against
## whatever was already there retunes every one of them at once. The symptom is never
## "physics feels different" — it is a car that will not pull away, or a crate that
## rises out of a stack, because traction and contact resolution were balanced against
## the old numbers.
##
## So: adopt what is there, change the one thing you meant to change, apply that.
##
## [codeblock]
## var profile := DotPhysicsProfile.from_project()
## profile.tick_rate = game.tick_rate      # the only thing this game decides
## world.profile = profile
## [/codeblock]
##
## The character fields — [member max_slope_angle], [member step_height],
## [member characters_push_bodies] — have no ProjectSettings counterpart and keep this
## class's defaults. Nothing in the engine reads them; a controller does.
static func from_project() -> DotPhysicsProfile:
	var p := DotPhysicsProfile.new()

	p.tick_rate = int(_setting("physics/common/physics_ticks_per_second", p.tick_rate))
	p.max_steps_per_frame = int(
		_setting("physics/common/max_physics_steps_per_frame", p.max_steps_per_frame)
	)
	p.physics_interpolation = bool(
		_setting("physics/common/physics_interpolation", p.physics_interpolation)
	)

	p.gravity_3d = float(_setting("physics/3d/default_gravity", p.gravity_3d))
	p.linear_damp_3d = float(_setting("physics/3d/default_linear_damp", p.linear_damp_3d))
	p.angular_damp_3d = float(_setting("physics/3d/default_angular_damp", p.angular_damp_3d))
	p.sleep_threshold_linear = float(
		_setting("physics/3d/sleep_threshold_linear", p.sleep_threshold_linear)
	)
	p.sleep_threshold_angular = float(
		_setting("physics/3d/sleep_threshold_angular", p.sleep_threshold_angular)
	)
	p.time_before_sleep = float(_setting("physics/3d/time_before_sleep", p.time_before_sleep))
	p.solver_iterations = int(
		_setting("physics/3d/solver/solver_iterations", p.solver_iterations)
	)
	p.contact_bias = float(
		_setting("physics/3d/solver/default_contact_bias", p.contact_bias)
	)
	p.max_allowed_penetration = float(
		_setting("physics/3d/solver/contact_max_allowed_penetration", p.max_allowed_penetration)
	)
	p.contact_max_separation = float(
		_setting("physics/3d/solver/contact_max_separation", p.contact_max_separation)
	)
	p.contact_recycle_radius = float(
		_setting("physics/3d/solver/contact_recycle_radius", p.contact_recycle_radius)
	)

	p.gravity_2d = float(_setting("physics/2d/default_gravity", p.gravity_2d))
	p.gravity_2d_enabled = p.gravity_2d > 0.0
	p.linear_damp_2d = float(_setting("physics/2d/default_linear_damp", p.linear_damp_2d))
	p.angular_damp_2d = float(_setting("physics/2d/default_angular_damp", p.angular_damp_2d))

	return p


## A project setting, or the fallback.
##
## [b]`has_setting` first, on purpose.[/b] `ProjectSettings.get_setting(name, default)`
## returns the default for an absent key — but several of these keys are absent only in
## an exported build, where the engine bakes in the ones that differ from its own
## defaults and drops the rest. Reading them without the guard is still correct; the
## guard is here so the intent survives somebody "simplifying" the fallbacks away.
static func _setting(name: String, fallback: Variant) -> Variant:
	if not ProjectSettings.has_setting(name):
		return fallback

	var value: Variant = ProjectSettings.get_setting(name)
	return value if value != null else fallback


static func presets() -> Dictionary:
	return {
		&"arcade_shooter": Callable(DotPhysicsProfile, "arcade_shooter"),
		&"grounded": Callable(DotPhysicsProfile, "grounded"),
		&"sandbox": Callable(DotPhysicsProfile, "sandbox"),
		&"floaty_platformer": Callable(DotPhysicsProfile, "floaty_platformer"),
		&"top_down": Callable(DotPhysicsProfile, "top_down"),
	}


static func preset(p_id: StringName) -> DotPhysicsProfile:
	var table := presets()

	if not table.has(p_id):
		return null

	var fn: Callable = table[p_id]
	return fn.call() as DotPhysicsProfile
