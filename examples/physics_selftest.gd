extends Node

## Exercises dot-physics with no bodies, no level and no renderer.
##
## Which is nearly all of it, because nearly all of it is a decision rather than a
## simulation: which bit a layer got, what a mask comes out as, whether a table refuses
## a name that does not exist, and whether a settings write can be put back. The half a
## headless run genuinely cannot see is whether the numbers feel right, and no assertion
## anywhere reaches that.
##
## [codeblock]
## godot --headless --path . res://examples/physics_selftest.tscn
## [/codeblock]

const SECTIONS := 8
const CHECKS := 124

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-physics self-test")
	_line("")

	_test_layers()
	_test_layout_presets()
	_test_layout_refusals()
	_test_masks()
	_test_profiles()
	_test_surfaces()
	_test_world()
	# Awaited: this section needs physics frames to pass before a cast can hit
	# anything, and an un-awaited coroutine would let the tally below print first.
	await _test_queries()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


# --- Layers -----------------------------------------------------------------

func _test_layers() -> void:
	_section("a layer")

	var l := DotPhysicsLayer.make(&"player", [&"world"], "the player")
	_check(l.id == &"player", "has the name everything else uses")
	_check(l.bit == -1, "and no bit until a layout gives it one")
	_check(l.mask() == 0, "so its mask is zero, not bit zero")

	l.bit = 3
	_check(l.mask() == 8, "and once assigned, the mask is that one bit")
	_check(not l.query_only, "a layer is simulated unless it says otherwise")
	_check(l.describe().contains("player"), "and it describes itself")


# --- Presets ----------------------------------------------------------------

func _test_layout_presets() -> void:
	_section("the presets")

	var shooter := DotPhysicsLayout.shooter_3d()
	_check(shooter.build().ok, "the shooter layout builds")
	_check(shooter.layers.size() == 16, "with sixteen layers")
	_check(shooter.has_layer(&"player_clip"), "including a clip layer only players hit")
	_check(
		shooter.layer(&"debris").collides_with.has(&"world"),
		"debris touches the world"
	)
	_check(
		not shooter.collides(&"debris", &"player"),
		"and nothing else — a hundred shell casings colliding with each other is a "
		+ "hundred bodies in the solver that nobody can see"
	)
	_check(
		shooter.layer(&"hitbox").query_only,
		"hitboxes are query-only, so a bullet's mask and a body's mask are different "
		+ "numbers on purpose"
	)

	var sandbox := DotPhysicsLayout.sandbox_3d()
	_check(sandbox.build().ok, "the sandbox layout builds")
	_check(sandbox.layers.size() == 18, "and is the shooter's plus two")
	_check(
		not sandbox.collides(&"held_prop", &"player"),
		"a held prop does not push the player holding it, which would push the beam, "
		+ "which would push the prop"
	)
	_check(
		sandbox.collides(&"frozen_prop", &"player"),
		"a frozen one is still something to stand on"
	)

	var platformer := DotPhysicsLayout.platformer_2d()
	_check(platformer.build().ok, "the platformer layout builds")
	_check(
		platformer.collides(&"one_way", &"player")
		and not platformer.collides(&"one_way", &"projectile"),
		"a one-way platform catches the player and not their shots"
	)

	var top_down := DotPhysicsLayout.top_down_2d()
	_check(top_down.build().ok, "the top-down layout builds")
	_check(
		not top_down.collides(&"player", &"player"),
		"and players walk through each other, because in a top-down arena they must"
	)

	_check(DotPhysicsLayout.preset(&"shooter_3d") != null, "presets resolve by name")
	_check(
		DotPhysicsLayout.preset(&"nonexistent") == null,
		"and a name that is not one resolves to nothing rather than to a default"
	)
	_check(DotPhysicsLayout.presets().size() == 4, "there are four of them")


func _test_layout_refusals() -> void:
	_section("what a layout refuses")

	var dup := DotPhysicsLayout.new()
	dup.id = &"dup"
	dup.layers = [
		DotPhysicsLayer.make(&"world"),
		DotPhysicsLayer.make(&"world"),
	]
	_check(
		not dup.build().ok,
		"two layers with one name are refused: every lookup would answer about the "
		+ "second one and nothing would say so"
	)

	var typo := DotPhysicsLayout.new()
	typo.id = &"typo"
	typo.layers = [
		DotPhysicsLayer.make(&"world", [&"playr"]),
		DotPhysicsLayer.make(&"player", []),
	]
	var res := typo.build()
	_check(
		not res.ok,
		"a collision list naming something that does not exist is refused — a name "
		+ "that resolves to nothing contributes no bit, so the pair silently never "
		+ "collides"
	)
	_check(res.code() == DotError.CODE_INVALID, "with an invalid code")
	_check(res.error.message.contains("playr"), "that names the typo")

	var empty := DotPhysicsLayout.new()
	empty.layers = [DotPhysicsLayer.make(&""), ]
	_check(not empty.build().ok, "so is a layer with no name")

	var too_many := DotPhysicsLayout.new()
	for i in range(33):
		too_many.layers.append(DotPhysicsLayer.make(StringName("l%d" % i)))
	_check(
		not too_many.build().ok,
		"and thirty-three layers, because a body has thirty-two bits and there is no "
		+ "thirty-third"
	)

	var symmetric := DotPhysicsLayout.new()
	symmetric.layers = [
		DotPhysicsLayer.make(&"a", [&"b"]),
		DotPhysicsLayer.make(&"b", []),
	]
	_check(symmetric.build().ok, "a one-sided declaration builds")
	_check(
		symmetric.collides(&"b", &"a"),
		"and is made symmetric, because the engine needs both halves and a table with "
		+ "the halves written in two places drifts"
	)


func _test_masks() -> void:
	_section("masks")

	var layout := DotPhysicsLayout.shooter_3d()

	_check(layout.layer_mask(&"world") == 1, "the first layer is bit zero")
	_check(
		layout.layer_mask(&"nope") == 0,
		"an unknown layer masks nothing rather than everything — a body invisible to "
		+ "every query is a loud symptom, and a body in every query is a quiet one"
	)

	var player_mask := layout.collision_mask(&"player")
	_check(
		player_mask & layout.layer_mask(&"world") != 0,
		"a player collides with the world"
	)
	_check(
		player_mask & layout.layer_mask(&"debris") == 0,
		"and not with debris"
	)

	var two := layout.mask_of([&"world", &"prop"])
	_check(
		two == layout.layer_mask(&"world") | layout.layer_mask(&"prop"),
		"mask_of is the union of the named layers"
	)

	_check(
		layout.query_only_mask() & layout.layer_mask(&"trigger") != 0,
		"triggers are in the query-only mask"
	)
	_check(
		layout.solid_mask() & layout.layer_mask(&"trigger") == 0,
		"and out of the solid one, so a shot does not stop in mid-air on a capture zone"
	)
	_check(
		layout.solid_mask() & layout.layer_mask(&"world") != 0,
		"which still contains the world"
	)
	_check(
		layout.mask_excluding([&"world"]) & layout.layer_mask(&"world") == 0,
		"mask_excluding drops what it is given"
	)
	_check(
		layout.all_mask() == (1 << layout.layers.size()) - 1,
		"and all_mask is every assigned bit"
	)
	_check(layout.layer_ids().size() == 16, "the ids come back in bit order")

	# Applying to a real body, which is the only part of a layout that touches a node.
	var body := StaticBody3D.new()
	add_child(body)
	_check(layout.apply_to(body, &"world").ok, "a layout sets a body's layer and mask")
	_check(body.collision_layer == layout.layer_mask(&"world"), "to the right bit")
	_check(body.collision_mask == layout.collision_mask(&"world"), "and the right mask")
	_check(
		not layout.apply_to(body, &"nope").ok,
		"and refuses a layer it does not have rather than leaving the body at zero"
	)

	var node := Node.new()
	add_child(node)
	_check(
		not layout.apply_to(node, &"world").ok,
		"a plain Node has no collision_layer, and is refused rather than silently set"
	)
	_check(not layout.apply_to(null, &"world").ok, "so is nothing at all")

	_check(
		layout.project_setting_names("3d").has("layer_names/3d_physics/layer_1"),
		"a layout can name itself in the editor's layer dropdowns, which is what stops "
		+ "the next person writing bits again"
	)

	body.queue_free()
	node.queue_free()


# --- Profiles ---------------------------------------------------------------

func _test_profiles() -> void:
	_section("profiles")

	var p := DotPhysicsProfile.new()
	_check(p.validate().ok, "the defaults validate")
	_check(
		is_equal_approx(p.gravity_3d, 20.0),
		"with gravity at 20 rather than 9.8 — true Earth gravity at a human scale "
		+ "reads as floating, and dot-player-controller's own tunables already say 20"
	)
	_check(is_equal_approx(p.tick_delta(), 1.0 / 60.0), "and a tick is 1/60 s")

	var arcade := DotPhysicsProfile.arcade_shooter()
	_check(arcade.tick_rate == 128, "the arcade shooter runs at 128 Hz")
	_check(
		not arcade.physics_interpolation,
		"with interpolation off, because it costs a frame of latency by construction"
	)
	_check(
		not arcade.characters_push_bodies,
		"and characters that cannot be shoved off a ledge by a team-mate with a crate"
	)

	var grounded := DotPhysicsProfile.grounded()
	_check(grounded.solver_iterations > arcade.solver_iterations, "grounded solves harder")
	_check(grounded.gravity_3d < arcade.gravity_3d, "and falls slower")

	var sandbox := DotPhysicsProfile.sandbox()
	_check(sandbox.characters_push_bodies, "the sandbox lets players shove things")
	_check(sandbox.solver_iterations >= 24, "and solves hard enough for a stack to hold")

	var top_down := DotPhysicsProfile.top_down()
	_check(not top_down.gravity_2d_enabled, "the top-down profile has no gravity")
	_check(top_down.gravity_vector_2d() == Vector2.ZERO, "and its gravity vector is zero")

	var floaty := DotPhysicsProfile.floaty_platformer()
	_check(floaty.max_slope_angle > grounded.max_slope_angle, "the platformer is forgiving")

	_check(DotPhysicsProfile.presets().size() == 5, "there are five profile presets")
	_check(DotPhysicsProfile.preset(&"sandbox") != null, "and they resolve by name")
	_check(DotPhysicsProfile.preset(&"nope") == null, "an unknown one resolves to nothing")

	# The jump-height conversion, which is the reason gravity lives here at all.
	var slow := DotPhysicsProfile.new()
	slow.gravity_3d = 5.0
	var fast := DotPhysicsProfile.new()
	fast.gravity_3d = 20.0
	_check(
		slow.jump_speed_for(1.0) < fast.jump_speed_for(1.0),
		"reaching the same height under lower gravity takes less launch speed, which "
		+ "is what keeps a jump honest when gravity is retuned"
	)

	var bad := DotPhysicsProfile.new()
	bad.contact_max_separation = 0.001
	bad.max_allowed_penetration = 0.01
	_check(
		not bad.validate().ok,
		"a separation below the allowed penetration is refused: the solver would "
		+ "discard the contacts it is meant to be correcting"
	)

	var layered := DotPhysicsProfile.new()
	var applied := layered.apply_dictionary({"tick_rate": 128, "gravity_3d": 15.5})
	_check(applied.size() == 2, "a profile takes a dictionary the family's way")
	_check(layered.tick_rate == 128, "and the tick rate came through")
	_check(is_equal_approx(layered.gravity_3d, 15.5), "and so did gravity")
	_check(layered.env_prefix() == "DOT_PHYSICS_", "with its own environment prefix")


# --- Surfaces ---------------------------------------------------------------

func _test_surfaces() -> void:
	_section("surfaces")

	var set := DotPhysicsSurfaceSet.standard()
	_check(set.build().ok, "the standard table builds")
	_check(set.ids().size() == 11, "with eleven surfaces")
	_check(set.get_surface(&"ice").traction < 0.5, "ice has almost no traction")
	_check(set.get_surface(&"metal").density > 7000.0, "and metal is heavy")
	_check(
		set.get_surface(&"glass").thickness > 0.0,
		"glass is a sheet, so its mass is a pane's rather than a solid block's"
	)

	var pane := set.get_surface(&"glass")
	_check(
		pane.mass_for_volume(1.0, 2.0) < pane.mass_for_volume(1.0),
		"and a sheet weighs less than the same volume taken literally"
	)

	_check(
		set.get_surface(&"not_a_surface") == set.fallback(),
		"an unknown surface falls back rather than returning null into a caller that "
		+ "is halfway through playing a sound"
	)

	var broken := DotPhysicsSurfaceSet.new()
	broken.surfaces = [DotPhysicsSurface.make(&"a", 1.0, 0.0, 1.0)]
	broken.fallback_id = &"missing"
	_check(
		not broken.build().ok,
		"a fallback that is not in the table is refused, or every unmatched collider "
		+ "resolves to null and each caller crashes somewhere else"
	)

	_check(not DotPhysicsSurfaceSet.new().build().ok, "an empty table is refused")

	# The lookup, which is the hard half.
	var tagged := StaticBody3D.new()
	tagged.name = "SomeWall"
	DotPhysicsSurfaceSet.tag(tagged, &"metal")
	add_child(tagged)
	_check(set.for_collider(tagged).id == &"metal", "metadata is checked first")

	var grouped := StaticBody3D.new()
	grouped.name = "SomeOtherWall"
	grouped.add_to_group(&"surface_wood")
	add_child(grouped)
	_check(set.for_collider(grouped).id == &"wood", "then groups, with the prefix stripped")

	var named := StaticBody3D.new()
	named.name = "walkway_metal_03"
	add_child(named)
	_check(
		set.for_collider(named).id == &"metal",
		"then the node name, which is a guess and is the only thing a level built by a "
		+ "mapper offers"
	)

	var anonymous := StaticBody3D.new()
	anonymous.name = "Thing"
	add_child(anonymous)
	_check(set.for_collider(anonymous) == set.fallback(), "and otherwise the fallback")
	_check(set.for_collider(null) == set.fallback(), "including for nothing at all")

	var mat := set.get_surface(&"ice").to_physics_material()
	_check(mat != null and mat.friction < 0.2, "a surface hands the solver a material")
	_check(
		mat != set.get_surface(&"ice").to_physics_material(),
		"a fresh one each time, because a PhysicsMaterial handed to two bodies is "
		+ "shared by them and tuning one retunes the other"
	)

	tagged.queue_free()
	grouped.queue_free()
	named.queue_free()
	anonymous.queue_free()


# --- The world --------------------------------------------------------------

func _test_world() -> void:
	_section("applying and putting back")

	var before_rate := int(ProjectSettings.get_setting(
		"physics/common/physics_ticks_per_second", 60
	))
	var before_gravity: Variant = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

	var world := DotPhysicsWorld.new()
	world.register_service = false
	world.profile = DotPhysicsProfile.arcade_shooter()
	world.layout = DotPhysicsLayout.shooter_3d()
	world.surfaces = DotPhysicsSurfaceSet.standard()
	add_child(world)

	var res := world.setup()
	_check(res.ok, "a world applies")
	_check(world.is_applied(), "and says so")
	_check(
		int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0)) == 128,
		"the tick rate reached ProjectSettings"
	)
	_check(
		Engine.physics_ticks_per_second == 128,
		"and Engine, which is the one the running process actually reads — a setting "
		+ "that only changes the next run is the shape of 'the setting does nothing'"
	)
	_check(
		ProjectSettings.has_setting("layer_names/3d_physics/layer_1"),
		"and the layer names are in the editor's dropdowns"
	)

	var q := world.query()
	_check(q != null and q.layout == world.layout, "a world hands out a bound query")

	var body := CharacterBody3D.new()
	add_child(body)
	_check(world.classify(body, &"player").ok, "and classifies a body by name")
	_check(body.collision_layer == world.layout.layer_mask(&"player"), "correctly")

	_check(world.describe_lines().size() > 5, "it describes itself")
	_check(world.use_layout_preset(&"sandbox_3d").ok, "a layout can be switched at runtime")
	_check(world.layout.layers.size() == 18, "to the new one")
	_check(
		not world.use_layout_preset(&"nope").ok,
		"and an unknown preset is refused rather than leaving no layout at all"
	)
	_check(world.use_profile_preset(&"grounded").ok, "so can a profile")
	_check(Engine.physics_ticks_per_second == 64, "which re-applies immediately")

	_check(world.restore().ok, "and it all goes back")
	_check(not world.is_applied(), "with the node saying so")
	_check(
		int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0))
		== before_rate,
		"the tick rate is what it was — a server switching games must not leave the "
		+ "next one running on the last one's physics"
	)
	_check(
		DotValue.same(ProjectSettings.get_setting("physics/3d/default_gravity", null),
			before_gravity),
		"and so is gravity"
	)
	_check(Engine.physics_ticks_per_second == before_rate, "including on Engine")

	var invalid := DotPhysicsWorld.new()
	invalid.register_service = false
	invalid.profile = DotPhysicsProfile.new()
	invalid.profile.contact_max_separation = 0.0001
	invalid.profile.max_allowed_penetration = 0.5
	add_child(invalid)
	_check(
		not invalid.setup().ok,
		"a profile that does not validate is refused before anything is written — half "
		+ "an applied physics configuration is worse than the one it replaced"
	)
	_check(not invalid.is_applied(), "and the world stays unapplied")

	body.queue_free()
	world.queue_free()
	invalid.queue_free()


# --- Queries ----------------------------------------------------------------

func _test_queries() -> void:
	_section("queries")

	var layout := DotPhysicsLayout.shooter_3d()
	var surfaces := DotPhysicsSurfaceSet.standard()
	var q := DotPhysicsQuery.new(layout, surfaces)

	_check(q.layout == layout, "a query carries its layout")
	_check(
		q.ray_3d(null, Vector3.ZERO, Vector3.ONE, [&"world"]).is_empty(),
		"a cast with no world answers nothing rather than crashing"
	)
	_check(
		q.ray_2d(null, Vector2.ZERO, Vector2.ONE, [&"world"]).is_empty(),
		"in 2D as well"
	)
	_check(q.sphere_3d(null, Vector3.ZERO, 1.0, [&"prop"]).is_empty(), "and a sphere")
	_check(q.circle_2d(null, Vector2.ZERO, 1.0, [&"prop"]).is_empty(), "and a circle")
	_check(not q.line_of_sight_3d(null, Vector3.ZERO, Vector3.ONE), "and sight is refused")

	var bare := DotPhysicsQuery.new()
	_check(
		bare.layout == null,
		"a query with no layout is allowed, because this addon being absent should "
		+ "degrade to Godot's own behaviour rather than to no physics at all"
	)

	# The real cast, against a body that is actually in a world.
	var space := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.5)
	shape.shape = box
	space.add_child(shape)
	space.position = Vector3(0, 0, -5)
	DotPhysicsSurfaceSet.tag(space, &"metal")
	var _applied := layout.apply_to(space, &"world")
	add_child(space)

	# One physics frame, or the body is not in the space yet and every cast misses.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var hit := q.ray_3d(
		space.get_world_3d(), Vector3.ZERO, Vector3(0, 0, -20), [&"world"]
	)
	_check(not hit.is_empty(), "a ray finds a wall on the layer it was told about")
	_check(hit.get("collider", null) == space, "and reports which one")
	_check(
		(hit.get("surface", null) as DotPhysicsSurface).id == &"metal",
		"with the surface attached, which is the thing Godot's own result never says"
	)

	var wrong_layer := q.ray_3d(
		space.get_world_3d(), Vector3.ZERO, Vector3(0, 0, -20), [&"player"]
	)
	_check(wrong_layer.is_empty(), "and misses it entirely on a layer it is not on")

	var shot := q.shot_3d(space.get_world_3d(), Vector3.ZERO, Vector3(0, 0, -20))
	_check(not shot.is_empty(), "a shot uses the solid mask and finds the same wall")

	_check(
		not q.line_of_sight_3d(space.get_world_3d(), Vector3.ZERO, Vector3(0, 0, -20)),
		"and line of sight through it is blocked"
	)
	_check(
		q.line_of_sight_3d(space.get_world_3d(), Vector3.ZERO, Vector3(0, 0, 20)),
		"while the other way is clear"
	)

	var overlaps := q.sphere_3d(space.get_world_3d(), Vector3(0, 0, -5), 1.0, [&"world"])
	_check(overlaps.size() == 1, "a sphere finds it too")
	_check(
		(overlaps[0].get("surface", null) as DotPhysicsSurface).id == &"metal",
		"and decorates that as well"
	)

	space.queue_free()


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
