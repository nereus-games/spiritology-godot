# What isn't built yet

The source carries about 45 `TODO` markers; `grep -rn TODO --include='*.gd' .` lists them.
Scattered through the code they read like neglect; grouped, they are an accurate map of what
the game still needs, and most of them are not debt at all — they are one system waiting on
another.

This page groups them by what they are waiting for, **in the order they are worth doing**.
Each `TODO` stays in the source, next to the code it affects; this is the index. When one is
done, or turns out to be stale, fix this page in the same commit.

The order follows three questions, asked in turn: does the game contradict the design doc
today? does one piece of work unlock several markers at once? can it be done without waiting
on Notion?

## 1. The game contradicts the design doc — do these first

Each is explicit in the doc, has no prerequisite, and is wrong in play right now.

Nothing at present. Every place where the game contradicts the doc and where nothing blocks
the fix is done; what remains of rival spawning waits on a system, and is listed in section 4.

## 2. What the encounter abilities still wait on

The four pieces this page used to list are built, and with them most of the abilities that
waited on them (see [architecture.md](architecture.md), *The encounter loop*): **reactions**
(an ability watches what others do or suffer until its user's next turn), an **encounter
history**, **weighted rival choices**, and **next-turn modifiers**; the one-offs — Shuffle,
Deflection, Self-Denial, Tactical Retreat — are done too. About 12 markers are left in the
encounter abilities, across 11 of the 111 scripts, and they no longer share a missing piece of
engine. They wait on:

- **The amount an Examine yields**, so that "more info" has something to raise: Halo Effect's
  Examine and its info bonus, Priming's "they get more info", Catatonia's Examine clause (its
  Meditate clauses are built). The bonuses are computed and logged, and nothing consumes them.
  See *Encyclopaedia detail* in section 4.
- **Rivals carrying objects**: Misty Secret's weight on using objects is recorded and inert;
  Altruism has nothing to destroy, and the encounter engine rightly knows no inventory (section 4).
- **A decision on Deflection**: its docstring adds "requires that the user has not used the same
  action twice", which nothing enforces and which the history could now answer.

**Five abilities implement nothing** — Anti-Stress, Avoidant Gaze, Distancing, Flow State,
Self-Sabotage — and fall back on generic per-tag effects: their first line is `# @unimplemented`
(`grep -rl '@unimplemented' scripts/encounter/effects/abilities/`). None waits on the engine: the
design doc gives them no mechanic ("still to be defined", or flavour text only), so they are in
section 5. Three more abilities carried the marker in error and no longer do — Cranny Crossing,
Fog Mantel and Static Camouflage are *exploration* abilities, implemented on that side; their
encounter-side scripts are now explicit no-ops that say so.

## 3. Joining exploration and encounters

- **Afflictions do not reach the encounter.** Disarray still running when an encounter opens
  should carry into it, and a rival's poison should too; `scripts/encounter/` knows nothing of
  afflictions. Needs deciding first what "a different action" means in the encounter menu.
  (`affliction_state.gd`)
- **Static Camouflage's unknown species and Forlorn shapes.** The watch itself is built (2 to
  4 groups, one at a time, take one on or keep waiting; `scouting.gd`), but the doc's chances of
  including unknown species and variations — higher next to litter, and Forlorn shapes likelier
  than by default — and the rule that it does not stack with a costume wait on the Forlorn
  individual (section 4) and on the costume rethink (section 5). The groups are shown as text,
  not as their sprites.

Trick to Reveal now reaches the dungeon through a narrow handle the encounter is given
(`EncounterManager.map_reveal`, like `object_provider`), and reveals the closest hidden chest or
trap after an effective dialogue — the rule is ours, the doc does not give one.

## 4. Systems not started

Larger pieces, each of which a handful of markers wait on. Roughly in order of how much they
unblock.

- **Leaving a dungeon, and navigating between scenes.** A devitalised duo now leaves the
  dungeon, but for the scenario picker, standing in for a world map that does not exist; the
  exit interaction is still unwired, and a secondary exit should unlock a bonus dungeon. The
  title screen, the pause screen (the encounter's Menu
  button is hidden until it exists) and boot's hand-off belong to the same piece.
  (`exploration.gd`, `dungeon_layout.gd`, `encounter_ui.gd`, `boot.gd`)
- **Dungeon state between visits.** `GameSession.dungeon_states` is saved and loaded but never
  written: every entry is a first entry, so groups, examined decor and opened chests all reset.
  The doc ("Exit + Reentry") wants rivals that had not disappeared to stay where they were,
  initial spawns not to happen again, and periodic spawns to resume. (`exploration.gd`,
  `examinable_decor.gd`)
- **Dialogue.** Whether a Talk is "effective" is decided by a proxy — the species'
  `talker_chance`, which really describes how likely the *rival* is to open a conversation. The
  doc conditions Talk's rewards on an effective dialogue without giving the rule, and its drafts
  make it depend on objects given to the rival. Everything built on Talk is provisional,
  including pacifying a rival as a way out of an encounter. (`encounter_manager.gd`, Talk)
- **A dungeon authoring format, and a validator.** An authored dungeon will fill
  `dungeon_layout.gd`, which holds the floor, holes, pits, walls and exits and nothing that
  happens on them, and the validator will check that object. Walls and holes are derived from
  the floor grid instead of declared; the doc's level-design rules — stairs lead to floor with
  nothing directly above, a narrow bridge always spans a floor, no bottomless hole — are
  checked only on the dev scenario, and caught at runtime otherwise. Safe areas already report
  their own faults (`safe_areas.violations()`), but only a check calls it. Becomes urgent with
  the first real dungeon. (`dungeon_layout.gd`, `stairs.gd`, `exploration.gd`,
  `player_controller.gd` — tagged `TODO(dungeon checker)`)
- **Rivals carrying objects.** Examine should "reveal objects they carry", Steal has nothing to
  take, Altruism has nothing to destroy, and Misty Secret's weight on using objects acts on no
  one. (`encounter_manager.gd`, `altruism.gd`, `misty_secret.gd`)
- **Encyclopaedia detail.** The *model* is built (see architecture.md): pages and Forlorn pages
  with their own percentage, fragments (3 IFP: one true, one parasitic), the 99 % cap, the
  assembly API, the 15 / 30 / Forlorn-15 ability thresholds, the starting duo, and persistence.
  What is missing: the *puzzle* and its screens (nothing calls `set_arranged_fragments`,
  `destroy_fragments`, `remove_parasitic_fragments` or `mark_page_assembled` yet, nor shows the
  `encyclopaedia_*` signals); the *amount* an Examine yields (so Reconnaissance Glide's +10 %
  multiplies a number with no consequence, as do Halo Effect's, Catatonia's and Priming's
  bonuses); info fragments granted by Examine Weakness; and Forlorn variants on the individual.
  (`encounter_manager.gd`, `examine_weakness.gd`, `encyclopaedia_model.gd`)
- **Forlorn rivals at spawn.** About 1 % of spawned rivals should be Forlorn. The rest of
  "Rival Spawning" is built: species weighted by dungeon rarity, the spawn limit, a new group
  pushing the occupant of a taken spawn point aside, preset compositions in 0 to 50 % of
  spawns, waves wider at a high PSY, and examined decor spawning rivals above PSY 20. What is
  left needs the Forlorn individual (see *Encyclopaedia detail*, above): the roll, and the
  doc's table of bonuses. (`rival_spawner.gd`, `TODO(forlorn)`)
- **The exploration HUD's final form** — the stack of known abilities with its USE/CANCEL
  submenu, and the doc's layout. (`hud_exploration.gd`)
- **The Coal Vetch**, a faction with two entrances, neither implemented. In an encounter, an
  agent can appear after repeated Examines (`encounter_manager.gd`). In a dungeon, if the player
  stays too long, agents arrive at hand-placed arrival points on hand-set timestamps and take
  the shortest path to the player; some dungeons hold a corruptible agent who delays the others
  for a price that rises each time.
- **PSY's consequences.** Built so far (`GameSession.psy_above`): the IFP bands, the narrow
  bridge, the width of spawn waves, rivals spawned by examined decor, and parts of every rung
  but the second.
  Above 10: the group stays when the duo flees (it always does; the 50 % disappearance was
  dropped), the duo lands 2 to 3 walkable steps off on a tile with no trap and no rival on it,
  facing the group, and that group's Talk chance is 10 % lower while PSY stays above 10
  (`psy_flee_*` in `balance.tres`; `RivalMember.talk_malus`, carried into the encounter by
  `encounter_state`, applied last in `EncounterManager._resolve_talk`). The malus is a
  placeholder reading: relative, not stacking, ignored whenever PSY is 10 or less at the time of
  the Talk (the flag stays on the group), and aimed at a group, not at one rival.
  Above 30: a rival's density is hidden in the encounter's turn order (Talk's IFP already drops
  to its top-tier row). Above 40: rivals have no cooldown turn on the map, a poisoned player
  cannot Meditate or use objects, in exploration or in encounters, with a warning
  (`UI_PSY_POISON_FORBIDS`), and the teammate refuses the first action of a visit's first
  encounter, then one action in five (`EncounterManager.enable_refusal`,
  `psy_teammate_refusal_chance`).
  Still unbuilt. Above 20: more risk of losing damaged fragments, and temporary oddities such as
  swapped icons (after event 3). Above 30: one more wrong fragment each time (the wider spawn
  waves are built, at a placeholder threshold of 20; see section 5). Above 40: poison also
  forbids the map, encyclopaedia and team views (those views do not exist yet; TODO in
  `GameSession.psy_forbids_while_poisoned`), and dungeons stay dark. (`game_session.gd`)
- **Dark dungeons** ("In the Dark"): sight limited to one tile, rivals heard but not seen,
  Meditate revealing them for 2 moves, and NPC quests that light an area. No implementation.
- **A QTE**, which Slick Merchant's Run Away should hide behind; until then it always succeeds.
  (`encounter_manager.gd`)
- **Save migration** between versions. Only matters once a save format has shipped.
  (`save_system.gd`)

## 5. Waiting on Notion

Not ours to settle. Placeholders live together in `data/balance.tres` where possible and are
tunable without touching code (see [data-model.md](data-model.md)); these are the figures or
pages the doc has not given yet.

- **Five abilities with no mechanic**: Anti-Stress, Avoidant Gaze, Distancing, Flow State and
  Self-Sabotage have only tags, flavour text or a name in the doc. They need a mechanic written
  in Notion before there is anything to implement.
- Per-species DEN and ETH (`balance_data.gd`, `game_session.gd` `MAX_ETH`).
- Object magnitudes, written "X %" and "Y DEN" (`object_data.gd`).
- Trap poison damage and duration, still letters (`trap.gd`).
- The dieverting's rival count and distance, "specifics TBD" (`dieverting.gd`).
- The generic ETH loss amount (`eth_loss_effect.gd`), which Unavailability also uses.
- "More often", with no figure (Radiant Secret, Hyping Up, Misty Secret, Business Card): the
  rival's chance to Talk or Meditate rises by `action_weight_bonus` (0.36, the per-condition
  step borrowed); One's Ethos has its 5 % (`ethos_talk_bonus`). Hardening's Talk penalty is
  `hardening_talk_penalty`, 0.36 likewise. All in `data/balance.tres`.
- Catatonia's step: each step it earns makes the next Meditate recover and leave a damage bonus
  larger by the per-condition step (`modifier_per_condition`, 0.36, borrowed).
- Self-Disclosure's unit (one "small" tier per ability used, split equally among the living) and
  Tactical Retreat's rate (1 DEN avoided for 1 ETH).
- The multipliers for common and normal species against rare ones in spawning (proposed 3 and
  2, not yet answered; `spawn_weight_common` and `spawn_weight_normal` in `data/balance.tres`),
  and the Forlorn bonuses still marked X, Y or TBD (`rival_spawner.gd`).
- Spawning figures the doc leaves open, placeholders in `data/balance.tres`: what "high PSY"
  means for wider waves and by how many groups (`wave_psy_*`; 20 and +1), how many groups and
  how near "one or more groups nearby" is for examined decor (`decor_spawn_groups_max` and
  `decor_spawn_radius`; 2 and 4), and whether the spawn limit counts rival groups or
  individuals (groups, in `DungeonConfig.rival_limit`; no dungeon sets it yet).
- The costume object, which has to be rethought: raising encounter odds and avoiding a second
  species fits neither spawning nor pursuit (commented 2026-10-21).
- Species pages for *néarog* and *mazir*, listed in the doc's pools but absent from `data/`
  (`litter.gd`, `examinable_decor.gd`).

Decisions taken in code, where the doc has to catch up — or say otherwise:

- **"Origin"** (Business Card, One's Ethos) is read as the species' Spiricosm, and **"X % more
  often"** as percentage points added to the chance of the action that turn: rivals never Talk
  or Meditate otherwise, so a multiplier would do nothing.
- **"Recently"** (Moral Elevation's mutual aid, Catatonia's damage) is this round or the
  previous one; **"this turn"** is until the ability user's next turn, as for every timed effect.
- **Effort of Neutrality**: the teammate keeps its weakness until it has acted, and loses it from
  then if the action dealt no damage, until the user's next turn.
- **Trick to Reveal** reveals the closest hidden chest or trap to the player after an effective
  dialogue; **Static Camouflage** draws the groups it shows at random among those on the map.

- **Fleeing** takes out only the character who runs, and the rivals stay on their tile; the
  "50 % chance the rival disappears" was dropped on 2026-09-18, because from the map it looked
  exactly like the whole group being devitalised (`exploration.gd`, `_run_away`).
- **A linked elevator moves empty**, leaving whoever stands on it behind. The doc now describes
  linked elevators, but not who rides them (`elevator.gd`, `linked`).

One is waiting on play rather than on the doc: **how long a level-wide pursuit lasts**
(`rival_behavior.gd`, `level_pursuit_turns`) has never been tried in game, and goes into the
doc's "Rivals" page only once it has been.

## Cosmetic

In a dead end, the dieverting's airborne die clips into the opposite wall. Revisit with the
real visuals. (`dieverting.gd`)
