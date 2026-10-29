## The Coal Vetch in a dungeon: agents who arrive if the player stays too long.
##
## The rule, from level design and the design doc:
## - the dungeon lists arrivals ([member DungeonConfig.coal_vetch_arrivals]), each a hand-placed
##   tile and a hand-set turn of the visit;
## - at its turn an agent appears on its tile and takes the shortest path to the player, one step a
##   turn (`coal_vetch_agent.gd`);
## - some dungeons hold a corruptible agent ([member DungeonConfig.has_corruptible_agent]), who for
##   a price delays every agent still to arrive. The price rises each time.
##
## The price is a number of objects ([member BalanceData.coal_vetch_bribe_base], then
## [member BalanceData.coal_vetch_bribe_step] more for each earlier bribe): the one thing the duo
## carries that is not the duo. Which objects is not asked: the most plentiful stack goes first, the
## identifier breaking ties. A screen to choose would call [method pay] with its own choice.
##
## What an agent does on reaching the player is the exploration scene's business; this class only
## brings the agents in. No `class_name` (the CLI class-cache trap): preloaded.
extends RefCounted

const Agent := preload("res://scripts/exploration/coal_vetch_agent.gd")
const RivalMember := preload("res://scripts/exploration/rival_member.gd")
const CorruptibleAgent := preload("res://scripts/exploration/mechanisms/corruptible_agent.gd")

var config: DungeonConfig

## How many times the corruptible agent has been paid in this visit.
var bribes := 0

## How many agents have come so far, whether or not they are still on the map.
var arrived := 0

var _dungeon
## Arrivals still to come: {tile, due}, `due` being the turn they happen on, delays included.
var _pending: Array[Dictionary] = []


func _init(p_config: DungeonConfig, dungeon) -> void:
	config = p_config
	_dungeon = dungeon
	for arrival in config.coal_vetch_arrivals:
		if arrival != null:
			_pending.append({"tile": arrival.tile, "due": arrival.turn})


## Sets the corruptible agent on its tile, when the dungeon has one. Returns it, or null.
func populate() -> Node:
	if not config.has_corruptible_agent:
		return null
	var agent := CorruptibleAgent.new()
	agent.director = self
	agent.position = _dungeon.tile_to_world(config.corruptible_agent_tile)
	_dungeon.add_child(agent)
	return agent


## Called on every exploration turn: the agents due now arrive. Returns them.
func on_turn(turn: int) -> Array:
	var came: Array = []
	var still: Array[Dictionary] = []
	for entry in _pending:
		if int(entry.due) <= turn:
			came.append(_arrive(entry.tile))
		else:
			still.append(entry)
	_pending = still
	return came


## Arrivals still to come.
func pending_count() -> int:
	return _pending.size()


## The turn the next arrival is due on, or -1 when none is left.
func next_due() -> int:
	var best := -1
	for entry in _pending:
		if best < 0 or int(entry.due) < best:
			best = int(entry.due)
	return best


func _arrive(at: Vector3i) -> Node:
	var agent := Agent.new()
	agent.members = [RivalMember.new(Agent.IDENTITY, 1, 0)]
	agent.position = _dungeon.tile_to_world(_dungeon.tile_search.free_tile_near(at))
	_dungeon.add_child(agent)
	arrived += 1
	return agent


## An agent has reached the player: it takes [member BalanceData.coal_vetch_catch_den] DEN from each
## member of the duo, never taking one below 1, and leaves the map. Returns the largest amount
## actually taken.
func catch_player(agent: Node) -> int:
	var taken := 0
	for slot in [GameSession.PartySlot.MAIN, GameSession.PartySlot.TEAMMATE]:
		var toll := mini(BalanceData.current().coal_vetch_catch_den, GameSession.get_den(slot) - 1)
		toll = maxi(toll, 0)
		GameSession.apply_den_damage(slot, toll)
		taken = maxi(taken, toll)
	if is_instance_valid(agent):
		agent.remove_from_dungeon()
	return taken


# --- The corruptible agent ---


## What the next bribe costs, in objects.
func price() -> int:
	var balance := BalanceData.current()
	return balance.coal_vetch_bribe_base + balance.coal_vetch_bribe_step * bribes


## Whether a bribe would do anything: there is an agent still to arrive, and the duo can pay.
func can_bribe() -> bool:
	return not _pending.is_empty() and objects_held() >= price()


func objects_held() -> int:
	var total := 0
	for id in GameSession.inventory:
		total += int(GameSession.inventory[id])
	return total


## Pays the corruptible agent: every agent still to arrive is delayed by
## [member BalanceData.coal_vetch_delay_turns], and the next bribe costs more. `payment` is
## object id -> count, summing to [method price]; left empty, the most plentiful stacks pay.
## Returns whether it was done; nothing changes when it was not.
func pay(payment: Dictionary = {}) -> bool:
	if _pending.is_empty():
		return false
	var cost := price()
	if payment.is_empty():
		payment = _default_payment(cost)
	var total := 0
	for id in payment:
		var count := int(payment[id])
		if count < 0 or GameSession.object_count(id) < count:
			return false
		total += count
	if total != cost:
		return false
	for id in payment:
		if int(payment[id]) > 0:
			GameSession.remove_object(id, int(payment[id]))
	var delay := BalanceData.current().coal_vetch_delay_turns
	for entry in _pending:
		entry.due = int(entry.due) + delay
	bribes += 1
	return true


## `cost` objects taken from the biggest stacks first; empty when the duo cannot pay.
func _default_payment(cost: int) -> Dictionary:
	var ids: Array = GameSession.inventory.keys()
	ids.sort_custom(_bigger_stack)
	var payment := {}
	var left := cost
	for id in ids:
		if left <= 0:
			break
		var take := mini(left, int(GameSession.inventory[id]))
		payment[id] = take
		left -= take
	return payment if left <= 0 else {}


func _bigger_stack(a: StringName, b: StringName) -> bool:
	var count_a: int = GameSession.inventory[a]
	var count_b: int = GameSession.inventory[b]
	if count_a != count_b:
		return count_a > count_b
	return String(a) < String(b)
