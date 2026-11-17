## What the dungeon editor opens on, handed over by the screen that opens it (the Dungeons tab of
## the dev picker): a dungeon to edit, or the name of a new one to create.
##
## A static, like `ScenarioCatalog.selected_dungeon`: the scene change forgets everything else.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

## The slug of the dungeon to edit or create.
static var slug: StringName = &""
## True when `slug` is a new dungeon: the editor starts empty instead of reading files.
static var create := false


static func edit(existing: StringName) -> void:
	slug = existing
	create = false


static func new_dungeon(new_slug: StringName) -> void:
	slug = new_slug
	create = true
