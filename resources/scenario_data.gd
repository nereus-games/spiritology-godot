## One exploration test scenario, as the selection screen shows it.
##
## Instances live in `data/scenarios/` and hold TEXT only — an id, a title, and what to
## watch for once inside. Building the dungeon stays code: `ScenarioCatalog` has one
## builder per scenario, and [member id] is what ties the two together.
##
## Split out so these can be edited without touching code, and because they are level
## design: they fall under the content licence, like everything in `data/`.
class_name ScenarioData
extends Resource

## Must match a case of [method ScenarioCatalog.build] — data_integrity_check and
## geometry_check both refuse an id with no builder.
@export var id: StringName

## Rank in the selection screen: scenarios run from simplest to most complete, whereas
## the directory reads alphabetically.
@export var order: int = 0

## The button label and the instructions are NOT fields here: they live in the .po files
## under the keys below, like every other displayed string in the project. What is left is
## the pair the code needs — which scenario, and where it sits in the list.


## Translation key of the button label: SCENARIO_<ID>_TITLE.
##
## Named `name_key` rather than `title_key` because that is the name every other resource
## uses, and data_integrity_check reaches for it by that name on all of them alike.
func name_key() -> String:
	return "SCENARIO_%s_TITLE" % GameEnums.key_token(id)


## Translation key of the instructions: SCENARIO_<ID>_DESC.
func desc_key() -> String:
	return "SCENARIO_%s_DESC" % GameEnums.key_token(id)
