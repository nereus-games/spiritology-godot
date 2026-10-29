## Headless check on the Forlorn individual: the roll at spawn, the variant's bonuses on the map
## and in the encounter, the IFP it yields, Static Camouflage's weighting of the groups it shows,
## and the encyclopaedia's Forlorn tab.
##
## Run with: Godot --headless --path . res://scenes/dev/forlorn_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const RivalMember := preload("res://scripts/exploration/rival_member.gd")
const RivalSpawner := preload("res://scripts/exploration/rival_spawner.gd")
const Scouting := preload("res://scripts/exploration/scouting.gd")
const Source := preload("res://scripts/ui/encyclopaedia_page_source.gd")
const PageView := preload("res://scripts/ui/encyclopaedia_page_view.gd")

const SPECIES := &"matzal"
const SEED := 20261029

var _fails: Array[String] = []


## A stand-in for a rival group on the map: all the watch reads of one is its members.
class FakeGroup:
	extends Node
	var members: Array = []


class FakeDungeon:
	extends RefCounted

	func post_message(_text: String) -> void:
		pass


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
	var balance := BalanceData.current()
	_check_member(balance)
	_check_roll(balance)
	_check_individual(balance)
	_check_ifp()
	_check_camouflage(balance)
	_check_tab()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	GameSession.reset()
	get_tree().quit(0 if _fails.is_empty() else 1)


func _check_member(balance: BalanceData) -> void:
	print("a Forlorn member on the map")
	var plain := RivalMember.new(SPECIES, 100, 40)
	_check(not plain.forlorn and not plain.encounter_state().has("forlorn"), "ordinary by default")
	var m := RivalMember.new(SPECIES, 100, 40)
	m.make_forlorn()
	_check(m.forlorn and m.encounter_state().get("forlorn", false), "the flag rides into the state")
	_check(
		m.max_den == roundi(100 * balance.forlorn_den_factor) and m.den == m.max_den,
		"its DEN grows by the Forlorn factor"
	)
	_check(
		m.max_eth == roundi(40 * balance.forlorn_eth_factor) and m.eth == m.max_eth,
		"...and its ETH"
	)
	var den := m.max_den
	m.make_forlorn()
	_check(m.max_den == den, "turning Forlorn twice does not stack")


func _check_roll(balance: BalanceData) -> void:
	print("the roll at spawn")
	_check(is_equal_approx(balance.forlorn_chance, 0.01), "the shipped chance is 1 %")
	var spawner := RivalSpawner.new(DungeonConfig.new(), null, SEED)
	var shipped := balance.forlorn_chance
	balance.forlorn_chance = 1.0
	var members: Array = [RivalMember.new(SPECIES, 50, 50), RivalMember.new(SPECIES, 50, 50)]
	_check(spawner.roll_forlorn(members) == 2, "at 100 % every member is Forlorn")
	balance.forlorn_chance = 0.0
	members = [RivalMember.new(SPECIES, 50, 50), RivalMember.new(SPECIES, 50, 50)]
	_check(spawner.roll_forlorn(members) == 0 and not members[0].forlorn, "at 0 % none is")

	# About 1 %: over 20000 rolls the standard deviation is 14, so 120 to 280 is over five.
	balance.forlorn_chance = shipped
	var forlorn := 0
	for i in 20000:
		var one: Array = [RivalMember.new(SPECIES, 50, 50)]
		forlorn += spawner.roll_forlorn(one)
	_check(
		forlorn >= 120 and forlorn <= 280,
		"about 1 %% of rivals are Forlorn (%d / 20000)" % forlorn
	)

	# Through a whole composition, drawn at random.
	var config := DungeonConfig.new()
	config.possible_species = [SPECIES]
	config.group_size_min = 3
	config.group_size_max = 3
	config.member_max_den_min = 60
	config.member_max_den_max = 60
	config.member_max_eth_min = 40
	config.member_max_eth_max = 40
	config.random_composition_chance = 1.0
	balance.forlorn_chance = 1.0
	var drawn := RivalSpawner.new(config, null, SEED).roll_composition()
	var all_forlorn := drawn.size() == 3
	for m in drawn:
		all_forlorn = all_forlorn and m.forlorn
		all_forlorn = all_forlorn and m.max_den == roundi(60 * balance.forlorn_den_factor)
	_check(all_forlorn, "a composed group is rolled, with the bonus applied")
	balance.forlorn_chance = shipped


func _check_individual(balance: BalanceData) -> void:
	print("a Forlorn individual in the encounter")
	GameSession.reset()
	var sp: SpeciesData = GameData.species(SPECIES)
	var plain := EncounterIndividual.new(sp, false)
	var forlorn := EncounterIndividual.new(sp, false, true)
	_check(not plain.is_forlorn and forlorn.is_forlorn, "the flag is set")
	_check(forlorn.max_den == roundi(balance.base_den * balance.forlorn_den_factor), "more DEN")
	_check(forlorn.max_eth == roundi(balance.base_eth * balance.forlorn_eth_factor), "more ETH")
	_check(forlorn.den == forlorn.max_den and forlorn.eth == forlorn.max_eth, "...and full")
	_check(sp.forlorn_ability in forlorn.ability_ids, "it has the Forlorn ability")
	_check(not (sp.forlorn_ability in plain.ability_ids), "an ordinary rival does not")
	var kept := true
	for aid in sp.origin_abilities:
		if aid != sp.forlorn_ability and not (aid in plain.ability_ids):
			kept = false
	_check(kept, "...and keeps its other abilities")
	_check(not EncounterIndividual.new(sp, true, true).is_forlorn, "a player character never is")
	var made := EncounterManager.make_individual(SPECIES, false, true)
	_check(made != null and made.is_forlorn, "make_individual passes it on")
	_check(not EncounterManager.make_individual(SPECIES, false).is_forlorn, "...and defaults to no")

	var manager := EncounterManager.new()
	_check(manager._is_forlorn(forlorn) and not manager._is_forlorn(plain), "the manager reads it")
	manager.setup([EncounterIndividual.new(sp, true)], [forlorn], 1, {})
	var report := manager.rival_report()
	_check(report.size() == 1 and report[0].get("forlorn", false), "the report says so")
	manager.free()


func _check_ifp() -> void:
	print("the IFP a Forlorn rival yields")
	GameSession.reset()
	var ordinary := GameSession.ifp_amount(GameEnums.IfpAction.EXAMINE_RIVAL, false)
	_check(
		GameSession.ifp_amount(GameEnums.IfpAction.EXAMINE_RIVAL, true, false) == ordinary,
		"before the ordinary page is complete, Forlorn pays the ordinary rate"
	)
	_check(
		GameSession.ifp_amount(GameEnums.IfpAction.EXAMINE_RIVAL, true, true) > ordinary,
		"once it is, Forlorn pays more"
	)
	# What the encounter announces for a Forlorn rival dissolved by the duo.
	var manager := EncounterManager.new()
	var sp: SpeciesData = GameData.species(SPECIES)
	var seen: Array = []
	manager.ifp_earned.connect(
		func(_species, _action, is_forlorn, _effective, _factor): seen.append(is_forlorn)
	)
	var rival := EncounterIndividual.new(sp, false, true)
	var other := EncounterIndividual.new(sp, false)
	manager.setup([EncounterIndividual.new(sp, true)], [rival, other], 1, {})
	rival.den = 0
	other.den = 0
	manager._award_dissolutions([])
	_check(seen == [true, false], "dissolving announces the Forlorn flag of each rival")
	manager.free()
	# And where the IFP go.
	GameSession.reset()
	GameSession.add_ifp(SPECIES, 10)
	var forlorn_before := GameSession.page_ifp(SPECIES, true)
	GameSession.award_ifp(SPECIES, GameEnums.IfpAction.EXAMINE_RIVAL, true)
	_check(
		GameSession.page_ifp(SPECIES, true) == forlorn_before,
		"a Forlorn rival pays the main page while it is incomplete"
	)
	GameSession.reset()


func _group_of(forlorn: bool) -> FakeGroup:
	var g := FakeGroup.new()
	var m := RivalMember.new(SPECIES, 50, 50)
	if forlorn:
		m.make_forlorn()
	g.members = [m]
	return g


func _check_camouflage(balance: BalanceData) -> void:
	print("Static Camouflage")
	GameSession.reset()
	var groups: Array = [_group_of(true)]
	for i in 4:
		groups.append(_group_of(false))
	_check(
		Scouting.has_forlorn(groups[0]) and not Scouting.has_forlorn(groups[1]),
		"a group is told Forlorn by its members"
	)
	var scouting := Scouting.new(FakeDungeon.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var first_forlorn := 0
	var shown_forlorn := 0
	var runs := 2000
	for i in runs:
		scouting.begin(groups, rng)
		if Scouting.has_forlorn(scouting.current()):
			first_forlorn += 1
		while scouting.active:
			if Scouting.has_forlorn(scouting.current()):
				shown_forlorn += 1
			scouting.wait()
	# One group in five is Forlorn: 20 % to be first by default, weight / (weight + 4) here.
	var weight := float(balance.camouflage_forlorn_weight)
	var expected := weight / (weight + 4.0)
	var share := float(first_forlorn) / runs
	_check(
		absf(share - expected) < 0.05,
		"the Forlorn group is shown first %.0f %% of the time, not 20 %%" % (100.0 * share)
	)
	_check(shown_forlorn > first_forlorn, "...and is often shown later too")
	var watch := Scouting.new(FakeDungeon.new())
	watch.begin([groups[0]], rng)
	var name := tr(GameData.species(SPECIES).name_key())
	var as_forlorn: String = tr("UI_SCOUT_MEMBER_FORLORN") % [1, name]
	var as_ordinary: String = tr("UI_SCOUT_MEMBER") % [1, name]
	_check(as_forlorn != as_ordinary, "the two lines are told apart in the translations")
	_check(watch.description().contains(as_forlorn), "a Forlorn member is shown as such")
	watch.end()
	watch.begin([groups[1]], rng)
	_check(not watch.description().contains(as_forlorn), "an ordinary one is not")
	watch.end()
	for g in groups:
		g.free()


func _check_tab() -> void:
	print("the encyclopaedia's Forlorn tab")
	GameSession.reset()
	var sp: SpeciesData = GameData.species(SPECIES)
	var info := Source.build_forlorn(SPECIES)
	_check(info.completion == 0 and not info.open and not info.unlocked, "a fresh Forlorn page")
	_check(info.ability == sp.forlorn_ability and info.fragments == 15, "it names the ability")
	GameSession.add_ifp(SPECIES, 99)
	GameSession.set_arranged_fragments(SPECIES, false, 33)
	GameSession.mark_page_assembled(SPECIES)
	GameSession.add_ifp(SPECIES, 45, true)
	GameSession.set_arranged_fragments(SPECIES, true, 15)
	info = Source.build_forlorn(SPECIES)
	_check(info.open and info.completion == 45, "with the main page complete: open, with its IFP")
	_check(info.unlocked, "15 arranged fragments reveal the ability")
	_check(Source.can_assemble(SPECIES, true), "the Forlorn page has fragments for the desk")
	var view := PageView.new()
	add_child(view)
	view.setup(SPECIES)
	view.set_forlorn_tab(true)
	var text := _texts(view)
	_check(not text.has("UI_ENCYCLOPAEDIA_FORLORN_PENDING"), "the placeholder is gone")
	_check(text.has(tr(GameData.ability(sp.forlorn_ability).name_key())), "the ability is named")
	view.free()
	GameSession.reset()


func _texts(node: Node) -> Array:
	var out: Array = []
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		out.append_array(_texts(c))
	return out
