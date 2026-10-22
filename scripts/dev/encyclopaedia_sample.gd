## DEV: a deterministic spread of encyclopaedia progress, for looking at the grid and at pages
## without playing. Every icon state appears, and so do gaps between discovered species.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

## IFP handed out down the list of species (by identifier), repeating.
const PATTERN: Array[int] = [
	100,
	0,
	60,
	20,
	0,
	0,
	99,
	45,
	0,
	5,
	0,
	80,
	0,
	0,
	30,
	0,
	0,
	44,
	70,
	0,
	1,
	0,
	0,
	100,
]


## Replaces the session's encyclopaedia progress with the sample.
static func fill() -> void:
	GameSession.encyclopaedia_ifp.clear()
	var list: Array = GameData.all_species()
	list.sort_custom(func(a: SpeciesData, b: SpeciesData) -> bool: return str(a.id) < str(b.id))
	for i in list.size():
		var ifp: int = PATTERN[i % PATTERN.size()]
		if ifp > 0:
			GameSession.encyclopaedia_ifp[list[i].id] = ifp
