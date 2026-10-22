## Remembers which species the encyclopaedia last gained information on, because the grid's
## selector starts there and [GameSession] does not keep it.
##
## SEAM: if the session ever stores it (and saves it), delete this and read it from there.
## [method watch] is called once, from the boot scene.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

static var last_species: StringName = &""
static var _watching := false


## Starts following [signal GameSession.encyclopaedia_progress]. Safe to call twice.
static func watch() -> void:
	if _watching:
		return
	_watching = true
	GameSession.encyclopaedia_progress.connect(_on_progress)


static func _on_progress(species_id: StringName, _ifp: int) -> void:
	last_species = species_id
