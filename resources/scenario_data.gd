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

## Button label.
@export var title: String = ""

## What to watch for once inside — the test's instructions.
@export_multiline var description: String = ""
