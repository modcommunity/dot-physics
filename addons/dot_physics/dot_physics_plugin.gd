@tool
extends EditorPlugin

## Editor entry point for dot-physics. Registers inspector types only.
##
## No autoloads: a client and a server in one process each want their own
## [DotPhysicsWorld], and the second one is exactly the case an autoload forbids.

const _ICON := "res://addons/dot_physics/icon_placeholder.svg"

const _TYPES := [
	[
		"DotPhysicsWorld",
		"Node",
		"res://addons/dot_physics/runtime/dot_physics_world.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
