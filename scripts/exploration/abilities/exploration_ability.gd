## Base of an exploration ability's effect.
##
## The exploration counterpart of [AbilityScript]: one subclass per exploration ability under
## `impl/<id>.gd`, overriding [method use] to apply the mechanic through [ExplorationContext]'s
## primitives. Resolved by `exploration_ability_catalog.gd`.
##
## No `class_name` (the CLI class-cache trap): `extends` and `preload` by path.
extends RefCounted


## Applies the ability's effect. Returns true when the ability was actually used, and so has to
## be marked spent for the visit. Does nothing by default.
func use(_ctx) -> bool:
	return false
