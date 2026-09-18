# What isn't built yet

The source carries about 80 `TODO` markers; `grep -rn TODO --include='*.gd' .` lists them.
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

- **Rivals see through walls.** The doc says "the line of sight is blocked by walls"; `_can_see`
  ignores them. The fix is described in place: walk the tiles, stop at the first opaque edge.
  (`rival_behavior.gd`, `_can_see`)
- **The turn has no reveal phase.** The doc's exploration turn is player → reveal of
  mechanisms → rivals → mechanism activation; the second phase is missing, so a trap only comes
  to light by springing and `Trap.reveal()` has no caller. This is also exactly what Reveal
  Traps' first clause needs. (`dungeon_manager.gd`, `advance_turn`; `reveal_traps.gd`)
- **Meditate is not an exploration action.** The doc lists it among the actions always
  available; today it exists only as a meditation gateway's contextual action, and recovers no
  ETH. The three steps are written out in place. (`exploration_extra_actions.gd`)
- **A known chest looks like an unknown one.** The minimap hides a trap until it is revealed but
  draws every chest regardless, so `Chest.revealed` — and Trick to Reveal's chest clause — has
  no visible effect. (`chest.gd`)
- **Some text does not reach the player in their language.** This breaks the project's own rule
  (every displayed line in both `.po` files) rather than the doc, and carries no `TODO`. Five
  ability descriptions are empty in `en.po` — Fake News, Flow State, Gaslighting, Ghosting,
  One's Ethos — though `fr.po` has them. Fifteen `fr.po` entries are still flagged `#, fuzzy`,
  left over from the old generator; Godot skips fuzzy entries, so French players see English
  there. They include every object description, which the encounter's Use / Give menu now
  shows, and seven talent names. `msgfmt --statistics translations/*.po` lists both.

## 2. Encounter hooks that unlock abilities in bulk

About 44 of the markers sit in the encounter abilities, across 34 of the 111 scripts. Most
implement their mechanic faithfully except for one clause the engine cannot express yet. Those
clauses cluster around four missing pieces; building one closes several abilities at once.

- **Reacting to what another individual does this turn** — a hook fired when an action is
  declared or resolved. Victimism and Dodge Blur (punish a rival that Talks), Unavailability
  (drain whoever targets the user), Unfocused Complaint (only if the target Meditates), Business
  Card (DEN when a rival Talks to the user), Effort of Neutrality (only if the ally's action
  deals no damage), Homeostasis (ETH at the moment of damage). *~7 abilities.*
- **An encounter history** — who did what to whom, turn by turn, and how often each ability was
  used. Halo Effect, Glorification, Moral Elevation, Catatonia, Self-Disclosure,
  Retroflection. *~6 abilities.*
- **Weighted rival choices** — rivals Talking, Meditating or using objects "more often". Radiant
  Secret, Hyping Up, Misty Secret, One's Ethos, Business Card. Needs rival action selection to
  take a per-encounter weight. *~5 abilities.*
- **Next-turn modifiers on the individual** — the next ability is free, the next Talk yields as
  much as an Examine, the damage steps up a tier. Self-Forgiveness, Active Listening, Priming.
  Timed effects now last until their author's next turn, which is most of the plumbing.

The rest are one-offs with no shared prerequisite: Shuffle (trade ETH by position), Deflection
(global doubling on weakness), Hardening (Talk info penalty), Self-Denial (per-turn drain).

**Eight abilities implement nothing** and fall back on generic per-tag effects: their first line
is `# @unimplemented` (`grep -rl '@unimplemented' scripts/encounter/effects/abilities/`). Each
can be picked up alone, after the hooks above if it needs one.

## 3. Joining exploration and encounters

- **Afflictions do not reach the encounter.** Disarray still running when an encounter opens
  should carry into it, and a rival's poison should too; `scripts/encounter/` knows nothing of
  afflictions. Needs deciding first what "a different action" means in the encounter menu.
  (`affliction_state.gd`)
- **Trick to Reveal cannot reach the dungeon.** Both ends exist; an encounter talent has no
  handle on the dungeon it was entered from. (`trick_to_reveal.gd`)
- **Static Camouflage** should reveal 2 to 4 wandering groups one at a time and offer to take one
  on. Groups exist and spawn by each dungeon's rules; the reveal and the choice do not.
  (`static_camouflage.gd`, `exploration_context.gd`)

## 4. Systems not started

Larger pieces, each of which a handful of markers wait on. Roughly in order of how much they
unblock.

- **Leaving a dungeon, and navigating between scenes.** A devitalised duo now leaves the
  dungeon, but for the scenario picker, standing in for a world map that does not exist; the
  exit interaction is still unwired. The title screen, the pause screen (the encounter's Menu
  button is hidden until it exists) and boot's hand-off belong to the same piece.
  (`exploration.gd`, `dungeon_manager.gd`, `encounter_ui.gd`, `boot.gd`)
- **Dungeon state between visits.** `GameSession.dungeon_states` is saved and loaded but never
  written: every entry is a first entry, so groups, examined decor and opened chests all reset.
  (`exploration.gd`, `examinable_decor.gd`)
- **Dialogue.** Whether a Talk is "effective" is decided by a proxy — the species'
  `talker_chance`, which really describes how likely the *rival* is to open a conversation. The
  doc conditions Talk's rewards on an effective dialogue without giving the rule, and its drafts
  make it depend on objects given to the rival. Everything built on Talk is provisional,
  including pacifying a rival as a way out of an encounter. (`encounter_manager.gd`, Talk)
- **A dungeon authoring format, and a validator.** Walls and holes are derived from the floor
  grid instead of declared; the doc's level-design rules — stairs lead to floor with nothing
  directly above, a narrow bridge always spans a floor, no bottomless hole — are checked only
  on the dev scenario, and caught at runtime otherwise. Safe areas already report their own
  faults (`safe_areas.violations()`), but only a check calls it. Becomes urgent with the first
  real dungeon. (`dungeon_manager.gd`, `stairs.gd`, `exploration.gd`, `player_controller.gd` —
  tagged `TODO(dungeon checker)`)
- **Rivals carrying objects.** Examine should "reveal objects they carry", Steal has nothing to
  take, and Altruism has nothing to destroy. (`encounter_manager.gd`, `altruism.gd`)
- **Encyclopaedia detail.** IFP are awarded and tallied, from encounters and from exploration
  alike; what is missing is the *amount* an Examine yields (so Reconnaissance Glide's +10 %
  multiplies a number with no consequence), info fragments (Examine Weakness), Forlorn variants
  on the individual, and Forlorn pages with their own percentage. (`encounter_manager.gd`,
  `examine_weakness.gd`, `game_session.gd`)
- **The exploration HUD's final form** — the stack of known abilities with its USE/CANCEL
  submenu, and the doc's layout. (`hud_exploration.gd`)
- **The Coal Vetch**, a faction that can appear mid-encounter after repeated Examines. No
  implementation at all. (`encounter_manager.gd`)
- **A QTE**, which Slick Merchant's Run Away should hide behind; until then it always succeeds.
  (`encounter_manager.gd`)
- **Save migration** between versions. Only matters once a save format has shipped.
  (`save_system.gd`)

## 5. Waiting on Notion

Not ours to settle. Placeholders live together in `data/balance.tres` where possible and are
tunable without touching code (see [data-model.md](data-model.md)); these are the figures or
pages the doc has not given yet.

- Per-species DEN and ETH (`balance_data.gd`, `game_session.gd` `MAX_ETH`).
- Object magnitudes, written "X %" and "Y DEN" (`object_data.gd`).
- Trap poison damage and duration, still letters (`trap.gd`).
- The dieverting's rival count and distance, "specifics TBD" (`dieverting.gd`).
- The generic ETH loss amount (`eth_loss_effect.gd`).
- The PSY threshold above which examining decor can spawn rivals (`examinable_decor.gd`).
- Species pages for *néarog* and *mazir*, listed in the doc's pools but absent from `data/`
  (`litter.gd`, `examinable_decor.gd`).

Two decisions were taken in code, and the doc has to catch up — or say otherwise:

- **Fleeing** takes out only the character who runs, and the rivals stay on their tile; the
  "50 % chance the rival disappears" was dropped on 2026-09-18, because from the map it looked
  exactly like the whole group being devitalised (`exploration.gd`, `_run_away`).
- **A linked elevator moves empty**, leaving whoever stands on it behind. The doc does not say
  (`elevator.gd`, `linked`).

One is waiting on play rather than on the doc: **how long a level-wide pursuit lasts**
(`rival_behavior.gd`, `level_pursuit_turns`) has never been tried in game, and goes into the
doc's "Rivals" page only once it has been.

## Cosmetic

In a dead end, the dieverting's airborne die clips into the opposite wall. Revisit with the
real visuals. (`dieverting.gd`)
