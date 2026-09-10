## Base of a talent: a species' passive, hooked into the encounter loop.
##
## The counterpart of [AbilityScript], but EVENT-DRIVEN. An ability runs at one single
## point, when it is used. A talent REACTS to things scattered through the loop — the
## encounter starting or ending, a Talk resolving, a single-use ability being spent, the
## menu being built. Hence a set of HOOKS rather than one `execute`.
##
## Each talent overrides only the hooks that concern it; everything else stays no-op here.
## The manager is passed to every hook, since it holds both the state and the helpers.
##
## No `class_name`: a newly added one is absent from the global class cache, which only the
## editor regenerates, and this game is launched from the command line — it would fail with
## "Identifier not declared". Callers preload it, and the implementations extend it BY
## PATH.
extends RefCounted

## The talent's data. Set by [TalentCatalog].
var talent: TalentData
## Who carries it. Hooks that only concern the bearer compare against this.
var owner: EncounterFighter
## How many copies the bearer's side carries — above 1 only when the duo shares a species
## and the talent is meant to stack. Team-wide talents use it; per-character ones ignore
## it.
var stacks := 1

# --- Lifecycle ---


## Before the first round. Where set-up belongs — dungeon reveals and the like.
func on_encounter_start(_manager) -> void:
	pass


## The encounter is over.
func on_encounter_end(_manager, _result: StringName) -> void:
	pass


# --- Talk ---


## Adjusts how likely a Talk is to be effective. Called for every talent on the speaker's
## side, with the base chance — which is itself a proxy, see
## [method EncounterManager._resolve_talk]. Return the adjusted value.
func modify_talk_chance(_manager, _speaker, _target, base: float) -> float:
	return base


## After a Talk from the bearer's side has resolved. Serene Waves heals the teammate that
## was spoken to; Slick Merchant gives the rival the speaker's weakness.
func on_talk_resolved(_manager, _speaker, _target, _effective: bool) -> void:
	pass


## May the bearer Talk to its TEAMMATE, not only to rivals? Serene Waves (spodra) says yes,
## because talking to the teammate revitalises them. By default Talk only reaches rivals.
func allows_ally_talk(_manager) -> bool:
	return false


# --- Abilities ---


## A single-use ability of the bearer's was just spent. Return true to hand it back —
## Reuse does so half the time.
func wants_reuse(_manager, _user, _ability) -> bool:
	return false


# --- Weakness and Examine: gathering encyclopaedia information ---


## An exposed weakness was struck, by the bearer or against it. The reward is information,
## and gathering information mid-encounter is not built — so this only logs.
func on_weakness_touched(_manager, _attacker, _defender, _ability) -> void:
	pass


## Adjusts what the bearer's Examine yields (Recon Glide: +10 %). How much an Examine
## yields is not modelled, so this multiplies a number with no consequence yet.
func modify_examine_info(_manager, _target, base: float) -> float:
	return base


# --- Menu ---


## Mutates the actions offered to the bearer, in place. Run Away and Steal both arrive
## this way, each replacing Talk. An action a talent removes is ABSENT from the menu rather
## than greyed out: the talent replaces it, it does not forbid it.
func modify_menu(_manager, _kinds: Array) -> void:
	pass
