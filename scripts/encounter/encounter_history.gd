## What has happened in an encounter, round by round: who did what to whom, what hurt whom, who
## helped whom, and how often each ability was used.
##
## Kept by [EncounterManager], which records each turn as it resolves, and written to by
## [EncounterContext] for the two things it applies itself — damage and recoveries. Abilities
## read it through [member EncounterContext.history], never the manager.
##
## [b]"Turn" means the round.[/b] The doc's *tour* is both, and every unit here is the round: an
## individual acts once per round, so "its last turn" is its action in an earlier round, and
## "this turn or the previous one" is [constant RECENT_ROUNDS] rounds.
##
## It holds individuals, but none of them holds it, so no reference cycle forms; it dies with
## the manager that owns it.
##
## No `class_name` (the CLI class-cache trap): preloaded.
extends RefCounted

## "Recently", in rounds: the current one and the one before. The doc says "this turn or the
## previous one" for damage and just "recently" for aid; the aid follows the damage.
const RECENT_ROUNDS := 2

## What a recovery or a gift was made of.
enum AidKind { ETH, DEN, OBJECT }

## The round being played; 0 before the first.
var round_number := 0

var _turns: Array = []
var _hurts: Array = []
var _aids: Array = []


## One individual's turn: what it did, to whom, how much damage that dealt, and the weakness it
## was exposing as the turn began.
class Turn:
	extends RefCounted
	var round_number := 0
	var actor: EncounterIndividual = null
	var kind := EncounterAction.Kind.PASS
	## The ability's id for [constant EncounterAction.Kind.ABILITY], otherwise &"".
	var ability_id := &""
	var targets: Array = []
	var damage_dealt := 0
	var weakness := GameEnums.Energy.NONE

	## The same kind of action, and the same ability if it was one. Passing is not an action: it
	## is the doc's "…", what an individual does when it does nothing.
	func same_action_as(other: Turn) -> bool:
		return (
			kind != EncounterAction.Kind.PASS
			and kind == other.kind
			and (ability_id == other.ability_id)
		)


## DEN lost: `victim` was hurt by `actor` (null when nobody is to blame).
class Hurt:
	extends RefCounted
	var round_number := 0
	var victim: EncounterIndividual = null
	var actor: EncounterIndividual = null
	var amount := 0

	## Dealt by someone on the victim's own side, the victim itself excepted.
	func by_teammate() -> bool:
		return actor != null and actor != victim and actor.is_player == victim.is_player


## `helper` gave `recipient` ETH, DEN or an object.
class Aid:
	extends RefCounted
	var round_number := 0
	var helper: EncounterIndividual = null
	var recipient: EncounterIndividual = null
	var kind := AidKind.ETH
	var amount := 0


# --- Recording ---


func begin_round(number: int) -> void:
	round_number = number


## Records a resolved turn. An object handed to someone else is an aid as well.
func record_turn(
	actor: EncounterIndividual,
	action: EncounterAction,
	damage_dealt: int,
	weakness: GameEnums.Energy
) -> void:
	var t := Turn.new()
	t.round_number = round_number
	t.actor = actor
	t.kind = action.kind
	t.ability_id = action.ability.id if action.ability != null else &""
	t.targets = action.targets.duplicate()
	t.damage_dealt = damage_dealt
	t.weakness = weakness
	_turns.append(t)
	if action.kind == EncounterAction.Kind.USE_OBJECT and not action.targets.is_empty():
		record_aid(actor, action.targets[0], AidKind.OBJECT, 0)


func record_hurt(victim, actor, amount: int) -> void:
	if not (victim is EncounterIndividual) or amount <= 0:
		return
	var h := Hurt.new()
	h.round_number = round_number
	h.victim = victim
	h.actor = actor if actor is EncounterIndividual else null
	h.amount = amount
	_hurts.append(h)


## Only a recovery by someone else counts as help: an individual recovering by itself is not
## helping anybody. `amount` is what was actually gained (0 for an object).
func record_aid(helper, recipient, kind: AidKind, amount: int) -> void:
	if not (helper is EncounterIndividual) or not (recipient is EncounterIndividual):
		return
	if helper == recipient or (kind != AidKind.OBJECT and amount <= 0):
		return
	var a := Aid.new()
	a.round_number = round_number
	a.helper = helper
	a.recipient = recipient
	a.kind = kind
	a.amount = amount
	_aids.append(a)


# --- Turns and abilities ---


## How many times `who` used the ability, in the encounter so far.
func times_used(who, ability_id: StringName) -> int:
	var n := 0
	for t in _turns:
		if t.actor == who and t.kind == EncounterAction.Kind.ABILITY and t.ability_id == ability_id:
			n += 1
	return n


## How many abilities `who` used, whichever they were.
func abilities_used(who) -> int:
	var n := 0
	for t in _turns:
		if t.actor == who and t.kind == EncounterAction.Kind.ABILITY:
			n += 1
	return n


## `who`'s most recent use of the ability, or null.
func last_use(who, ability_id: StringName) -> Turn:
	for i in range(_turns.size() - 1, -1, -1):
		var t: Turn = _turns[i]
		if t.actor == who and t.kind == EncounterAction.Kind.ABILITY and t.ability_id == ability_id:
			return t
	return null


## `who`'s turn in the round being played, or null if it has not acted yet.
func turn_this_round(who) -> Turn:
	for i in range(_turns.size() - 1, -1, -1):
		var t: Turn = _turns[i]
		if t.round_number < round_number:
			return null
		if t.actor == who:
			return t
	return null


## `who`'s latest turn from a round before this one, or null.
func previous_turn(who) -> Turn:
	for i in range(_turns.size() - 1, -1, -1):
		var t: Turn = _turns[i]
		if t.actor == who and t.round_number < round_number:
			return t
	return null


## Whether `who` exposes, now, the weakness it exposed on its previous turn. Having none is not
## having a weakness, so it never counts.
func repeated_weakness(who, weakness_now: GameEnums.Energy) -> bool:
	var before := previous_turn(who)
	return (
		before != null and weakness_now != GameEnums.Energy.NONE and before.weakness == weakness_now
	)


## Whether `who` took the same action this round as on its previous turn. One that has not acted
## yet this round has no action to compare, and does not repeat.
func repeated_action(who) -> bool:
	var now := turn_this_round(who)
	var before := previous_turn(who)
	return now != null and before != null and now.same_action_as(before)


## Whether `who`'s last two recorded turns were the same action (Deflection's condition). The turn
## being decided is not recorded yet, so these are the two it has already taken, whatever rounds
## they fell in.
func repeated_twice(who) -> bool:
	var last: Turn = null
	for i in range(_turns.size() - 1, -1, -1):
		var t: Turn = _turns[i]
		if t.actor != who:
			continue
		if last == null:
			last = t
		else:
			return last.same_action_as(t)
	return false


# --- Damage ---


## Whether `who` lost DEN this round or the one before.
func hurt_recently(who) -> bool:
	for h in _hurts:
		if h.victim == who and _is_recent(h.round_number):
			return true
	return false


## Whether `who` lost DEN to its own side in that time — a teammate's doing, not its own.
func hurt_recently_by_teammate(who) -> bool:
	for h in _hurts:
		if h.victim == who and _is_recent(h.round_number) and h.by_teammate():
			return true
	return false


# --- Help ---


## Whether someone helped a member of the side — a player side when `players` — recently:
## recovering ETH or DEN thanks to another individual, or being given an object.
func side_helped_recently(players: bool) -> bool:
	for a in _aids:
		if a.recipient.is_player == players and _is_recent(a.round_number):
			return true
	return false


func _is_recent(round_of: int) -> bool:
	return round_of > round_number - RECENT_ROUNDS
