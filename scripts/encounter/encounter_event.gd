## Something that happened in an encounter, as the abilities that watch for it are told.
##
## There are two kinds. An ACTION is an individual's turn having been resolved — what it did, who
## it was aimed at, how much damage it dealt. DAMAGE is one individual having been hurt by an
## ability's damage, which can happen several times within a single action.
##
## An ability that reacts ([method AbilityScript.react]) is handed one of these, and decides for
## itself whether it concerns it; the questions below are what it asks.
##
## Built, handed over and dropped within one resolution: it holds individuals, so it must never
## be kept.
##
## No `class_name` (the CLI class-cache trap): preloaded.
extends RefCounted

enum Type { ACTION, DAMAGE }

var type := Type.ACTION

## ACTION: who acted. DAMAGE: who dealt the damage.
var actor: EncounterIndividual = null
## ACTION only.
var action: EncounterAction = null
## ACTION only: the damage that action dealt, whoever took it; 0 for any action that is not an
## ability.
var damage_dealt := 0
## DAMAGE only: who was hurt, and by how much after every modifier.
var victim: EncounterIndividual = null
var amount := 0


static func acted(
	p_actor: EncounterIndividual, p_action: EncounterAction, p_damage_dealt: int
) -> RefCounted:
	var e = new()
	e.type = Type.ACTION
	e.actor = p_actor
	e.action = p_action
	e.damage_dealt = p_damage_dealt
	return e


static func damaged(
	p_victim: EncounterIndividual, p_actor: EncounterIndividual, p_amount: int
) -> RefCounted:
	var e = new()
	e.type = Type.DAMAGE
	e.victim = p_victim
	e.actor = p_actor
	e.amount = p_amount
	return e


## An action was resolved, whatever it was.
func is_action() -> bool:
	return type == Type.ACTION


## An action of this kind was resolved — a Talk, a Meditate, an ability.
func is_action_of(kind: EncounterAction.Kind) -> bool:
	return type == Type.ACTION and action != null and action.kind == kind


## An action was resolved that was aimed at `who`.
func targeted(who: EncounterIndividual) -> bool:
	return type == Type.ACTION and action != null and action.targets.has(who)


## `who` was hurt by an ability's damage.
func hurt(who: EncounterIndividual) -> bool:
	return type == Type.DAMAGE and victim == who and amount > 0
