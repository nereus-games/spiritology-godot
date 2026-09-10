## Shared enumerations.
##
## The closed types referenced by the data resources (species, abilities) and by the
## encounter logic. Used as a static namespace: `GameEnums.Energy.HEAT`.
## Source: design doc, Game Design / Abilities + Talents.
class_name GameEnums
extends RefCounted

## Spiricosm of origin. Feeds the damage modifiers: sharing one with the target counts
## as a condition. French names: Gloom/Terne, Fiery/Ardent, Wonderful/Merveilleux.
enum Spiricosm {
	GLOOM,
	FIERY,
	WONDERFUL,
}

## The five energies, plus two modes for abilities whose energy changes every turn —
## the same energy for everyone using one during that turn.
enum Energy {
	HEAT,
	FLUID,
	CRYSTAL,
	ARCANE,
	TOXIC,
	RANDOM,  ## drawn afresh each round
	VARIABLE,  ## decided by an effect of the ability itself
	NONE,  ## no energy at all: talents, exploration, some encounter abilities
}

## Ability kind (see [AbilityData]).
enum AbilityType {
	TALENT,  ## passive, one per species, neither learnable nor unlockable
	EXPLORATION,  ## once per dungeon visit, unless a refresh crystal restores it
	ENCOUNTER,  ## available to players and rivals; may reorder the turn or disturb the UI
}

## ETH cost tier of an encounter ability. The doc names the tiers but gives no figures;
## those live in `data/balance.tres` ([BalanceData]).
enum Cost {
	NONE,
	MINI,
	NORMAL,
	MEDIUM,
	A_LOT,
}

## Position in the turn order, which decides WHICH of a species' three weaknesses is
## currently exposed. The order is drawn at the start of an encounter and changes only
## through abilities — which is what makes reordering the turn an attack.
enum TurnPosition {
	FIRST,
	MIDDLE,
	LAST,
}

## An action that earns encyclopaedia info points (IFP).
## Source: design doc, Game Design / Encyclopaedia, "Obtaining Info Points".
##
## Whether a rival is Forlorn is a separate boolean rather than an entry here: the Forlorn
## bonus only applies once the ordinary page is already complete.
enum IfpAction {
	EXAMINE_DECOR,  ## examining decor or ground while exploring (capped at 15 per species)
	EXAMINE_RIVAL,
	TALK_RIVAL,  ## only earns anything if the dialogue is effective
	DISSOLVE_RIVAL,
}

## What an inventory object DOES — not how much of it, which is parametric on
## [ObjectData]. Every object is consumable and stackable.
## Source: design doc, Game Design / Objects + Inventory.
## ## TODO: the gameplay these feed — fleeing, poison, disguise, crumbly ground, pursuit —
## is largely unbuilt. See docs/roadmap.md.
enum ObjectEffect {
	NONE,  ## no mechanical effect; exists to be given away (Notice)
	HEAL_DEN,  ## Rune stone
	FLEE_ENCOUNTER,  ## Smoke bomb
	CURE_POISON,  ## Tea drop
	DISGUISE,  ## Costume: take on a species' appearance
	DIG,  ## Spade, on crumbly ground
	AVOID_PURSUIT,  ## Torment veil: rivals neither pursue nor start encounters
}


## Turns a slug into a translation-key token: uppercase, accents folded to ASCII.
##
## Slugs are ASCII today, but species are common nouns and the accented form survives as
## the displayed name — so the folding stays, and an accented id would still resolve.
## Every `name_key()` / `desc_key()` goes through here: the shape of a key is decided in
## this one place and nowhere else.
static func key_token(raw) -> String:
	var s := str(raw).to_upper()
	var map := {
		"É": "E",
		"È": "E",
		"Ê": "E",
		"À": "A",
		"Â": "A",
		"Î": "I",
		"Ï": "I",
		"Ô": "O",
		"Û": "U",
		"Ù": "U",
		"Ç": "C"
	}
	for k in map:
		s = s.replace(k, map[k])
	return s
