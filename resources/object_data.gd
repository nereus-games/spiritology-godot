## An inventory object: consumable, stackable.
##
## Instances live in `data/objects/`, hand-maintained like the other resources.
## Source: design doc, Game Design / Objects + Inventory. "There is no necessary object in
## this game" — every one is consumed on use, every one stacks.
##
## Objects are NOT a database in the design doc the way species and abilities are; they are
## a bullet list inside one page. Their effects are therefore mapped BY SLUG rather than
## inferred from the prose — the table is in docs/data-model.md. The same slugs appear as
## species loot.
##
## "costume" is deliberately absent. The doc says the costume name indicates which
## spirimonster ("e.g. fopin costume"), so there is one per species, and the species it
## avoids is "specified in object description" — which nothing enumerates. Guessing would
## be worse than the gap.
class_name ObjectData
extends Resource

## Slug. Doubles as the inventory key ([member GameSession.inventory]) and as the base of
## the translation keys. A costume's slug carries its species: "fopin_costume".
@export var id: StringName

## Which of the parametric fields below matter.
@export var effect: GameEnums.ObjectEffect = GameEnums.ObjectEffect.NONE

## How much, read according to [member effect]: DEN granted for HEAL_DEN, increased
## encounter probability for DISGUISE.
## ## TODO: the doc writes these as "X %" and "Y DEN" — placeholders, not figures. 0 means
## "not stated", and consumers fall back to `data/balance.tres`.
@export var magnitude: int = 0

## How long a lasting effect lasts, counted in player moves. 0 means instantaneous.
## The doc states 15 for the Costume and the Torment veil, and nothing for the rest.
@export var duration_moves: int = 0

## The species an effect targets. For a costume, the one whose appearance is taken.
@export var species_id: StringName

## A second species, where the effect needs one. For a costume, the species that wearing
## it avoids entirely.
@export var secondary_species_id: StringName


## Translation key of the displayed name: OBJECT_<ID>_NAME.
func name_key() -> String:
	return "OBJECT_%s_NAME" % GameEnums.key_token(id)


## Translation key of the description: OBJECT_<ID>_DESC.
func description_key() -> String:
	return "OBJECT_%s_DESC" % GameEnums.key_token(id)
