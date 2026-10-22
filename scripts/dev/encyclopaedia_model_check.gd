## Headless check of the encyclopaedia model: fragments, the 99 % cap, the assembly, the
## ability thresholds, the starting duo, Forlorn pages and the save round trip.
##
## Run with: Godot --headless --path . res://scenes/dev/encyclopaedia_model_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Model := preload("res://scripts/encyclopaedia/encyclopaedia_model.gd")

## Two species with two encyclopaedia abilities and a Forlorn one apiece.
const Catalog := preload("res://scripts/exploration/abilities/exploration_ability_catalog.gd")

const A := &"ravbak"
const B := &"zuk"

var _fails: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	_run_all()


func _run_all() -> void:
	await get_tree().process_frame
	_check_fragments()
	_check_cap_and_assembly()
	_check_thresholds()
	_check_destruction()
	_check_starting_duo()
	_check_forlorn_page()
	_check_save_round_trip()
	_check_session()
	_check_catalogues()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	GameSession.reset()
	get_tree().quit(0 if _fails.is_empty() else 1)


## A model with a page at `ifp` and `arranged` fragments arranged.
func _model_at(ifp: int, arranged: int, forlorn: bool = false) -> Model:
	var m := Model.new()
	m.add_ifp(A, ifp, forlorn)
	m.set_arranged(A, forlorn, arranged)
	return m


func _check_fragments() -> void:
	print("fragments")
	var m := Model.new()
	_check(not m.knows(A), "an untouched species is unknown")
	m.add_ifp(A, 2)
	_check(m.knows(A) and m.ifp(A) == 2, "2 IFP make the species known")
	_check(m.true_fragments(A) == 0 and m.parasitic_fragments(A) == 0, "...but form no fragment")
	m.add_ifp(A, 1)
	_check(m.true_fragments(A) == 1, "the 3rd IFP forms a true fragment")
	_check(m.parasitic_fragments(A) == 1, "...and a parasitic one with it")
	m.add_ifp(A, 8)
	_check(m.true_fragments(A) == 3 and m.parasitic_fragments(A) == 3, "11 IFP: 3 and 3")
	_check(m.add_ifp(A, 0) == 0 and m.add_ifp(A, -4) == 0, "no IFP, or negative, adds nothing")
	m.add_ifp(B, 6)
	_check(m.ifp(A) == 11 and m.ifp(B) == 6, "pages are per species")


func _check_cap_and_assembly() -> void:
	print("the 99 % cap and the assembly")
	var m := Model.new()
	_check(m.add_ifp(A, 98) == 98, "98 IFP all go in")
	_check(m.add_ifp(A, 5) == 1, "only 1 more fits: the page stops at 99")
	_check(m.ifp(A) == 99 and m.true_fragments(A) == 33, "99 % is 33 true fragments")
	_check(m.parasitic_fragments(A) == 33, "...and 33 parasitic ones")
	_check(m.add_ifp(A, 3) == 0 and m.room(A) == 0, "a page at 99 takes nothing")
	_check(not m.is_complete(A), "99 % is not complete")
	_check(not m.mark_assembled(A), "no assembly is accepted with nothing arranged")
	m.set_arranged(A, false, 32)
	_check(not m.mark_assembled(A), "...nor with 32 fragments arranged")
	m.set_arranged(A, false, 33)
	_check(m.mark_assembled(A), "33 arranged at 99 %: the assembly is accepted")
	_check(m.ifp(A) == 100 and m.is_complete(A), "the last % is earned")
	_check(m.parasitic_fragments(A) == 0, "the parasitic fragments disappear")
	_check(m.completed_species().has(A), "the species counts as complete")
	_check(m.add_ifp(A, 3) == 0, "a complete page takes nothing")
	_check(not m.mark_assembled(A), "...and cannot be assembled twice")
	_check(m.destroy_fragments(A, false, 3) == 0, "...nor lose a fragment")
	var low := _model_at(60, 20)
	_check(not low.mark_assembled(A), "an unfinished page cannot be marked assembled")
	_check(not low.completed_species().has(A), "...and is not complete")


func _check_thresholds() -> void:
	print("ability thresholds")
	var sp: SpeciesData = GameData.species(A)
	_check(sp.encyclopaedia_abilities.size() == 2 and sp.forlorn_ability != &"", "fixture species")
	var m := Model.new()
	m.add_ifp(A, 99)
	_check(m.unlocked_abilities(sp).is_empty(), "99 IFP unlock nothing: fragments are not arranged")
	_check(m.set_arranged(A, false, 14) == 0 and m.unlocked_abilities(sp).is_empty(), "14: none")
	_check(m.set_arranged(A, false, 15) == 1, "15 reveals a tier")
	_check(m.unlocked_abilities(sp) == [sp.encyclopaedia_abilities[0]], "...the first ability")
	_check(m.set_arranged(A, false, 29) == 0, "29: nothing more")
	_check(m.set_arranged(A, false, 30) == 1, "30 reveals the next tier")
	var got := m.unlocked_abilities(sp)
	_check(got == [sp.encyclopaedia_abilities[0], sp.encyclopaedia_abilities[1]], "...the second")
	m.set_arranged(A, false, 0)
	_check(m.unlocked_abilities(sp).size() == 2, "arranged fragments falling to 0 take nothing back")
	_check(m.set_arranged(A, false, 100) == 0 and m.arranged_fragments(A) == 33, "clamped to 33")
	_check(
		m.set_arranged(A, true, 20) == 0 and m.unlocked_abilities(sp).size() == 2,
		"fragments cannot be arranged on a Forlorn page that has none"
	)
	var jumped := _model_at(99, 30)
	_check(jumped.unlocked_abilities(sp).size() == 2, "30 at once reveals both")
	_check(jumped.set_arranged(A, false, 30) == 0, "...and reporting it again reveals nothing new")
	_check(Model.new().unlocked_abilities(null).is_empty(), "no species, no ability")


func _check_destruction() -> void:
	print("destruction")
	var sp: SpeciesData = GameData.species(A)
	var m := _model_at(99, 30)
	_check(m.destroy_fragments(A, false, 2) == 2, "two fragments destroyed")
	_check(m.ifp(A) == 93 and m.true_fragments(A) == 31, "...the page loses 6 IFP")
	_check(m.arranged_fragments(A) == 30, "...the arranged count was untouched")
	m.destroy_fragments(A, false, 5)
	_check(m.true_fragments(A) == 26 and m.arranged_fragments(A) == 26, "arranged is capped to what is left")
	_check(m.unlocked_abilities(sp).size() == 2, "revealed abilities stay usable")
	_check(m.add_ifp(A, 15) == 15 and m.true_fragments(A) == 31, "the IFP can be earned back")
	_check(m.parasitic_fragments(A) == 33 + 5, "...and each re-formed fragment brings a parasitic one")
	_check(m.remove_parasitic(A, false, 4) == 4 and m.parasitic_fragments(A) == 34, "parasitic removed")
	_check(m.remove_parasitic(A, false, 99) == 34, "...never below none")
	var odd := Model.new()
	odd.add_ifp(A, 7)
	odd.destroy_fragments(A, false, 1)
	_check(odd.ifp(A) == 4 and odd.true_fragments(A) == 1, "the IFP that were not a fragment stay")
	_check(Model.new().destroy_fragments(A, false) == 0, "nothing to destroy on an untouched page")


func _check_starting_duo() -> void:
	print("the starting duo")
	var m := Model.new()
	m.grant_starting_duo(A, B)
	_check(m.arranged_fragments(A) == 15 and m.arranged_fragments(B) == 15, "15 each")
	_check(m.ifp(A) == 45 and m.true_fragments(A) == 15, "...which is 45 IFP")
	_check(m.unlocked_abilities(GameData.species(A)).size() == 1, "one ability each")
	_check(m.unlocked_abilities(GameData.species(B)).size() == 1, "...for both")
	_check(m.grant_starting_duo(A, B).is_empty(), "granting again changes nothing")
	var twins := Model.new()
	twins.grant_starting_duo(A, A)
	_check(twins.arranged_fragments(A) == 30 and twins.ifp(A) == 90, "the same species twice: 30")
	_check(twins.unlocked_abilities(GameData.species(A)).size() == 2, "...and both abilities")
	_check(twins.parasitic_fragments(A) == 0, "...with no parasitic fragment left over")
	var ahead := _model_at(99, 33)
	ahead.grant_starting_duo(A, B)
	_check(ahead.arranged_fragments(A) == 33 and ahead.ifp(A) == 99, "a page ahead is left alone")
	var done := _model_at(99, 33)
	done.mark_assembled(A)
	_check(done.grant_starting_duo(A, A).is_empty() and done.ifp(A) == 100, "...a complete one too")
	var none := Model.new()
	none.grant_starting_duo(&"", &"")
	_check(not none.knows(A), "no duo, no grant")


func _check_forlorn_page() -> void:
	print("the Forlorn page")
	var sp: SpeciesData = GameData.species(A)
	var m := Model.new()
	m.add_ifp(A, 40, true)
	_check(m.ifp(A, true) == 40 and m.ifp(A) == 0, "its percentage is its own")
	_check(not m.knows(A), "the main page does not know the species for it")
	m.set_arranged(A, true, 14)
	_check(m.unlocked_abilities(sp).is_empty(), "14 fragments of the Forlorn page reveal nothing")
	m.add_ifp(A, 8, true)
	m.set_arranged(A, true, 15)
	_check(m.unlocked_abilities(sp) == [sp.forlorn_ability], "15 reveal the Forlorn ability")
	_check(m.arranged_fragments(A) == 0, "...without touching the main page")
	m.set_arranged(A, true, 0)
	_check(m.unlocked_abilities(sp) == [sp.forlorn_ability], "...and it stays")
	m.add_ifp(A, 60, true)
	_check(m.ifp(A, true) == 99, "the Forlorn page stops at 99 as well")
	m.set_arranged(A, true, 33)
	_check(m.mark_assembled(A, true) and m.is_complete(A, true), "and is assembled on its own")
	_check(not m.is_complete(A), "the main page is not complete for it")
	_check(not m.completed_species().has(A), "...and the damage condition reads the main page")


func _check_save_round_trip() -> void:
	print("saving")
	var m := Model.new()
	m.grant_starting_duo(A, A)
	m.add_ifp(B, 31)
	m.add_ifp(B, 12, true)
	m.set_arranged(B, true, 4)
	m.page(B).puzzle_state = {"order": [3, 1, 2]}
	var text := JSON.stringify(m.to_dict())
	var back := Model.new()
	back.from_dict(JSON.parse_string(text))
	_check(back.ifp(A) == 90 and back.arranged_fragments(A) == 30, "pages come back")
	_check(back.unlocked_abilities(GameData.species(A)).size() == 2, "...with their abilities")
	_check(back.ifp(B) == 31 and back.parasitic_fragments(B) == 10, "...and their parasitic fragments")
	_check(back.ifp(B, true) == 12 and back.arranged_fragments(B, true) == 4, "...Forlorn pages too")
	_check(back.page(B).puzzle_state.has("order"), "...and the puzzle's own state")
	var legacy := Model.new()
	legacy.from_legacy_ifp({"zuk": 40.0, "ravbak": 100.0})
	_check(legacy.ifp(B) == 40 and legacy.true_fragments(B) == 13, "an old save's IFP become a page")
	_check(legacy.is_complete(A) and legacy.parasitic_fragments(A) == 0, "...a complete one stays so")


func _check_session() -> void:
	print("GameSession")
	GameSession.reset()
	var unlocked := []
	var formed := []
	var assembled := []
	var progress := []
	GameSession.encyclopaedia_ability_unlocked.connect(func(s, a): unlocked.append([s, a]))
	GameSession.encyclopaedia_fragments_formed.connect(func(s, f, n): formed.append([s, f, n]))
	GameSession.encyclopaedia_page_assembled.connect(func(s, f): assembled.append([s, f]))
	GameSession.encyclopaedia_progress.connect(func(s, i): progress.append([s, i]))

	GameSession.main_character = A
	GameSession.teammate = B
	_check(GameSession.knows_species(A) and GameSession.knows_species(B), "the duo's pages exist")
	_check(GameSession.unlocked_abilities(A).size() == 1, "the duo starts with one ability each")
	GameSession.teammate = A
	_check(GameSession.arranged_fragments(A) == 30, "two of one species: 30 fragments")

	var sp: SpeciesData = GameData.species(&"gelmi")
	var n := GameSession.award_ifp(&"gelmi", GameEnums.IfpAction.EXAMINE_RIVAL)
	_check(n > 0 and GameSession.page_ifp(&"gelmi") == n, "an Examine goes to the main page")
	_check(not formed.is_empty() or n < 3, "...and announces fragments when 3 IFP are crossed")
	_check(
		GameSession.award_ifp(&"gelmi", GameEnums.IfpAction.EXAMINE_RIVAL, true) > 0
		and GameSession.page_ifp(&"gelmi", true) == 0,
		"a Forlorn rival whose main page is incomplete pays into the main page"
	)
	# A species whose page the tests take to 99.
	GameSession.add_ifp(&"gelmi", 200)
	_check(GameSession.page_ifp(&"gelmi") == 99, "the session's pages stop at 99")
	_check(GameSession.award_ifp(&"gelmi", GameEnums.IfpAction.EXAMINE_RIVAL) == 0, "...and award 0")
	_check(
		GameSession.award_ifp(&"gelmi", GameEnums.IfpAction.EXAMINE_DECOR) == 0
		and GameSession.exploration_examine_ifp.get(&"gelmi", 0) <= GameSession.EXAMINE_DECOR_CAP,
		"a full page does not eat the decor allowance either"
	)
	_check(not GameSession.mark_page_assembled(&"gelmi"), "nothing arranged: not assembled")
	GameSession.set_arranged_fragments(&"gelmi", false, 15)
	_check(unlocked.has([&"gelmi", sp.encyclopaedia_abilities[0]]), "the unlock is announced")
	GameSession.set_arranged_fragments(&"gelmi", false, 33)
	_check(GameSession.mark_page_assembled(&"gelmi"), "33 arranged: assembled")
	_check(assembled == [[&"gelmi", false]], "...and announced")
	_check(GameSession.completed_species().has(&"gelmi"), "the damage condition sees the page")
	_check(GameSession.unlocked_abilities(&"gelmi").size() == 2, "a complete page reveals both")

	var before := GameSession.page_ifp(&"gelmi", true)
	var f := GameSession.award_ifp(&"gelmi", GameEnums.IfpAction.EXAMINE_RIVAL, true)
	_check(f > 0 and GameSession.page_ifp(&"gelmi", true) == before + f, "a Forlorn rival now pays into the Forlorn page")
	_check(GameSession.page_ifp(&"gelmi") == 100, "...leaving the main page alone")
	_check(progress.size() > 0, "encyclopaedia_progress still fires")

	# A real save and load, through the same JSON.
	var saved := JSON.stringify(GameSession.encyclopaedia.to_dict())
	GameSession.reset()
	_check(not GameSession.knows_species(&"gelmi"), "a new game forgets")
	GameSession.encyclopaedia.from_dict(JSON.parse_string(saved))
	_check(GameSession.is_page_complete(&"gelmi"), "a loaded page is still complete")
	GameSession.reset()


func _check_catalogues() -> void:
	print("the ability catalogues")
	GameSession.reset()
	var sp: SpeciesData = GameData.species(A)
	var first := sp.encyclopaedia_abilities[0]
	var second := sp.encyclopaedia_abilities[1]
	# The data lists a species' gated abilities among its origin ones, so the fixture must be one
	# where that holds for the check to mean anything.
	_check(first in sp.origin_abilities and second in sp.origin_abilities, "fixture: gated and native")
	# A player of a species whose pages have revealed nothing has none of the gated abilities.
	var plain := EncounterIndividual.new(sp, true)
	_check(not (first in plain.ability_ids), "a player with nothing arranged lacks the first")
	_check(not (sp.forlorn_ability in plain.ability_ids), "...and the Forlorn one")
	var rival := EncounterIndividual.new(sp, false)
	_check(first in rival.ability_ids and second in rival.ability_ids, "a rival keeps all of its own")
	GameSession.main_character = A
	var duo := EncounterIndividual.new(sp, true)
	_check(first in duo.ability_ids and not (second in duo.ability_ids), "the starting duo has the first")
	GameSession.teammate = A
	duo = EncounterIndividual.new(sp, true)
	_check(first in duo.ability_ids and second in duo.ability_ids, "two of a species have both")
	_check(not (sp.forlorn_ability in duo.ability_ids), "...but not the Forlorn one")
	GameSession.add_ifp(A, 99, true)
	GameSession.set_arranged_fragments(A, true, 15)
	_check(sp.forlorn_ability in EncounterIndividual.new(sp, true).ability_ids, "15 Forlorn fragments reveal it")
	var other := EncounterIndividual.new(GameData.species(B), true)
	_check(
		not (GameData.species(B).encyclopaedia_abilities[0] in other.ability_ids),
		"another species' abilities are not borrowed"
	)
	# Exploration reads the same list. No species carries an exploration ability in the data yet,
	# so give one a gated one for the length of the check.
	var saved_origin := sp.origin_abilities.duplicate()
	var saved_enc := sp.encyclopaedia_abilities.duplicate()
	sp.origin_abilities.append(&"fog_mantel")
	sp.encyclopaedia_abilities.assign([first, &"fog_mantel"])
	GameSession.reset()
	GameSession.main_character = A
	_check(not (&"fog_mantel" in Catalog.known_for_duo()), "exploration: a gated ability is not known")
	GameSession.teammate = A
	_check(&"fog_mantel" in Catalog.known_for_duo(), "exploration: ...until the 30th fragment")
	sp.origin_abilities.assign(saved_origin)
	sp.encyclopaedia_abilities.assign(saved_enc)
	GameSession.reset()
