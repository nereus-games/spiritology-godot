## Absorption Guard — gélmi · Variable · small (7) · [damage, examine bonus, recover DEN]
## MECHANIC: the energy is the user's current weakness. A random rival takes damage; if that
## rival acts on the user this turn, the user Examines it without reprisal and gains X DEN (half
## the percentage of info known about its species). The "acts on the user" condition is
## approximated.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.set_energy(ctx.weakness_of(ctx.user))
	var t = ctx.random_opponent()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
		ctx.grant_examine_bonus(t, 1)
		ctx.recover_den(ctx.user, ctx.dmg(&"mini"))
