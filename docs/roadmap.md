# What isn't built yet

The source carries about 40 `TODO` markers, in some 30 files; `grep -rn TODO --include='*.gd' .` lists them.
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
Deflection, Self-Denial, Tactical Retreat — are done too. A few markers are left in the
encounter abilities, and they no longer share a missing piece of engine. The amount an Examine yields is built too (`examine_yield.gd`, see *The encounter loop*):
Halo Effect, Priming and Catatonia now raise it, as Reconnaissance Glide does, and so do the
other "Examine bonus" abilities (Absorption Guard, Steep In, Shadow Work, Bystander Effect and the
generic effect), and Deflection enforces its condition through the history. What remains waits on:

- **Rivals carrying objects**: Misty Secret's weight on using objects is recorded and inert;
  Altruism has nothing to destroy, and the encounter engine rightly knows no inventory (section 4).

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
  The amount an Examine yields follows the info bonuses (Reconnaissance Glide, Halo Effect,
  Priming, Catatonia; `examine_bonus_step` in `data/balance.tres`, a placeholder). What is
  missing: most `encyclopaedia_*` signals are still announced nowhere (only the assembly screen and
  the selector's memory listen); and Forlorn variants on the individual. (`encounter_manager.gd`, `encyclopaedia_model.gd`)
- **The encyclopaedia's screens.** The grid and the read-only page view are built and read the
  fragment model (see [architecture.md](architecture.md), *The encyclopaedia screens*), reachable
  only from the dev scenario picker. The assembly screen is built too (*The assembly screen*), reached from a page's
  Accept. What is left: sounds for it (a hook only), art for the fragments, its controls page
  in the doc (TBD there); the Forlorn tab, a placeholder until the Forlorn individual exists; real icons and the pages'
  remaining sections (personality, environment, routine, the illustration carousel); the order
  of the pages, which is by identifier meanwhile; and a way in from the real menus, which do
  not exist. The selector's starting species is remembered by `encyclopaedia_recent.gd`, not
  saved with the session.
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
- **The QTE's finish.** Slick Merchant's Run Away is behind a working quick-time event
  (`qte.gd`, `encounter_qte_overlay.gd`), but a minimal one: no art, no sound, no controls page in
  the doc, and the form itself (a marker over a zone) is ours. See section 5.
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
- The worth of "more info": one point of info bonus is +10 % of an Examine's IFP
  (`examine_bonus_step`; the 10 % is Reconnaissance Glide's figure, borrowed). Halo Effect gives 2
  points per criterion, Catatonia 2 per step, Priming 2, Shadow Work 2 per species, the generic
  effect 1, Bystander Effect 5 (all placeholders in their scripts).
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

- **Slick Merchant's QTE** (`qte.gd`, `qte_*` in `balance.tres`, all placeholders): the doc says
  only that Run Away is "behind a QTE" that can fail. A marker sweeps a bar (1.2 s from end to end
  and back), the player presses Accept once, and the press succeeds when the marker is inside a
  zone 30 % of the bar wide at its middle; no press within 3 s fails. The 10 ETH are paid whether
  it succeeds or not; a failure leaves the character in the encounter with its turn spent. Only a
  player character plays it: a rival with the talent gets away unconditionally. Run Away 2 has none,
  as its text says. Where `EncounterManager.qte_runner` is not set (checks, headless) the QTE is
  skipped and passed.
- **Deflection's condition**: "has not used the same action twice" is read as the user's last two
  turns not being the same action (the same kind, and for abilities the same one; a pass is no
  action), whatever rounds they fell in. It is `is_usable`: greyed out in the menu, left alone by
  the automatic agent, and a no-op if used regardless, as Moral Elevation.
- **The "Examine bonus" abilities** make a real Examine (`ExamineYield.examine`): Absorption Guard
  and Steep In a plain one (their text gives no bonus, so 0 points; Absorption Guard keeps its
  unconditional "acts on the user" approximation), Shadow Work one per species present, not per
  individual, with 2 points each (placeholder), the generic effect 1 point on each target
  (placeholder). Bystander Effect's "far more" is 5 points on the others' Examines (+50 %) and the
  same factor on the IFP of their Talks, until the user's next turn (placeholder).

- **Info bonuses** add up as points, then multiply with talents (Reconnaissance Glide), and the IFP
  of an Examine are rounded **up** when the factor is above 1 (a penalty rounds down), so that a
  bonus always gives at least one point more. Only a player character's Examine of a rival earns
  IFP, whoever an ability "Examines".

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

The encyclopaedia, built on 2026-10-22 from the "Encyclopaedia" page, which leaves these open:

- **Examine yield** (`examine_bonus_step`, `balance.tres`). One point of info bonus is +10 % of
  an Examine's IFP, borrowed from Reconnaissance Glide. Points add up (4 points are +40 %, not
  1.1 to the fourth), then multiply with the talent factor. A factor above 1 rounds the IFP up,
  one below 1 rounds down (otherwise +10 % on 6 to 9 IFP would give nothing). Placeholder
  amounts: Halo Effect 2 points per criterion met, Catatonia 2 per step, Priming 2. Priming's
  bonus lasts until its user's next turn and an Examine does not spend it; Catatonia's covers
  exactly the user's next turn. Only a player character's Examine of a rival earns IFP, so Halo
  Effect on a teammate, or used by a rival, earns none. Active Listening's Talk, which counts as
  an Examine, does not use the bonus. Known gap: two bonus sources on one individual share one
  expiry timer.
- **Examine Weakness** (`examine_weakness.gd`, `GameSession.IFP_TABLE`). The doc says only "a
  little info" on the other individual. Read as one info fragment, 3 IFP at every PSY tier
  (`WEAKNESS_INFO`), announced through `ifp_earned` and so under the usual page rules (99 % cap,
  a true and a parasitic fragment, Forlorn page once the main one is complete). It goes to a rival
  only and only when the bearer is a player character, so a teammate as the other individual, or
  a rival bearing the talent, earns nothing. Examine's info bonuses do not scale it, it does not
  count as an Examine, and the weakness is not exposed on the encyclopaedia side. Each ability
  that strikes an exposed weakness gives it once per such target.
- **Abilities and the starting duo.** The data lists a species' encyclopaedia and Forlorn
  abilities among its origin abilities too, so a player character's list is the native ones
  minus the gated ones, plus those revealed; rivals keep all of them. A starting character's 15
  arranged fragments also credit 45 IFP (30 and 90 for a same-species duo), with no parasitic
  fragment left behind. Saves from before the model load: fragments are formed from the IFP and
  none counts as arranged.
- **Pages.** Forlorn IFP go to the Forlorn page only once the main page is at 100, and pay the
  ordinary row into the main page before. A page at 99 % takes nothing, and the attempt does not
  use up the 15-IFP decor allowance. A destroyed fragment costs 3 IFP and lowers the arranged
  count but never an ability tier; a complete page cannot lose fragments.
- **The assembly desk** (`puzzle_destroy_chance` 0.25, the doc's X; `puzzle_stain_rate` 0.02 a
  second; `puzzle_stain_max` 0.85, below 1 so the edges stay visible). Fragments are squares of
  at least 4 tiles; a group turns about the top-left corner of its bounding box. Edges are 6-bit
  profiles that fit when XOR-complementary. A snap needs the gap between facing sides below 2
  tiles and the offset along the side below 2; it brings the group flush and aligned; one snap
  at most per request, a correct candidate winning over a closer incorrect one. An incorrect
  snap is classed PARASITIC, then MISMATCH (not page neighbours in that direction, or rotated
  differently), then HOLE (off the desk, over a third fragment, or enclosing empty tiles); it
  puts back whatever the player moved. A group is a set of bonds, so destroying a member leaves
  the others standing, and completion counts correct fragments bonded to at least one other,
  destroyed ones included in the total.
- **The assembly screen.** The manipulation area is 48 x 28 tiles (the whole page, 3 x 11 fragments,
  fits lying on its side, 44 x 12); the new fragment area is a panel on the right whose fragments
  shrink to fit. A fragment taken from it enters the desk on the free tile nearest the middle, at
  least 2 tiles from any other (so nothing snaps on arrival), and that is its first move. The stain
  grows only while a move or turn is being made (a key held, or the glide running), not while a
  fragment is merely held. Parasites are drawn like true fragments, from another picture of the
  same style, so only the picture betrays them. Only a HOLE is announced; a mismatch just damages,
  and a destroyed fragment is announced. A new desk starts with the page's arranged fragments
  (the starting duo's 15 or 30) already bonded, lying on their side. A saved layout is dropped
  for a fresh desk when it holds more fragments than the model counts, or fewer arranged; new IFP
  add fragments to the new area (lowest free page cell first, parasites numbered after the old).
  Selecting is separate from moving: Accept picks up (the grid shows), arrows move, Accept or
  Cancel puts down; Backspace sends a lone fragment back. A refused move shakes the fragment.
  Fragments in the new area are in a fixed shuffled order. Key repeat: 0.28 s then every 0.1 s.
  The Forlorn tab cannot open the desk yet.
- **The screens.** Pages are ordered by species identifier in a grid (6 x 6 for 36 species);
  the doc gives no order.

One is waiting on play rather than on the doc: **how long a level-wide pursuit lasts**
(`rival_behavior.gd`, `level_pursuit_turns`) has never been tried in game, and goes into the
doc's "Rivals" page only once it has been.

## Cosmetic

In a dead end, the dieverting's airborne die clips into the opposite wall. Revisit with the
real visuals. (`dieverting.gd`)
