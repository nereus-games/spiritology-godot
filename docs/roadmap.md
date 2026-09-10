# What isn't built yet

The code carries 81 `TODO` markers. Scattered through the source they read like neglect;
grouped, they are something else — an accurate map of what the game still needs, and most
of them are not debt at all. They are one system waiting on another that does not exist.

This page groups them by what they are actually waiting for. Each `TODO` in the source
stays where it is, next to the code it affects; this is the index.

## Abilities whose mechanic is approximated — ~41 markers

The largest group by far, and the most specific. Every one of the 111 encounter abilities
has a dedicated script carrying its Notion mechanic in the docstring, and most implement it
faithfully. The rest approximate a clause the engine cannot yet express — "double the damage
matching each individual's weakness this turn", "only if the ally's action deals no damage",
"modulated by damage history".

Eight go further and implement nothing: their first line is `# @unimplemented`, and they
fall back to generic per-tag effects, which is a scaffold rather than the real mechanic.
`grep -rl '@unimplemented' scripts/encounter/effects/abilities/` lists them.

These are the ones that can be picked up one at a time, with no prerequisite.

## No dialogue system — ~10 markers

Talk resolves, earns encyclopaedia points and triggers talent hooks, but whether a dialogue
is "effective" is decided by a proxy: the species' `talker_chance`, which actually describes
how likely the *rival* is to open a conversation. The doc conditions Talk's reward on an
effective dialogue without ever giving the rule, and its dialogue drafts make it depend on
objects given to the rival — a system that does not exist either.

Everything about Talk is therefore provisional, including the talents built on it.

## The map does not draw mechanisms — ~10 markers

`Trap.revealed` and `Chest.revealed` exist and are set correctly; the minimap simply does
not render them. Two talents are blocked on this alone: Reveal Traps' first clause (show the
three nearest traps on entering a level) and Trick to Reveal. Their other clauses already
work.

## Encyclopaedia and information gain — ~5 markers

IFP are awarded and tallied, but the *amount* of information an Examine yields is
not modelled, so talents that modify it (Reconnaissance Glide's +10 %) multiply a number
that has no consequence yet. Exploration is also still missing as a source of points:
examining decor and ground should grant them and does not.

## Objects in encounters — ~4 markers

Objects are consumed and their effects resolve, but rivals carry none, so Examine cannot
"reveal objects they carry" and Steal has nothing to take. Abilities that destroy an object
in exchange for an effect (Altruism) have nothing to destroy.

## Rival groups and the Coal Vetch — ~4 markers

Several abilities and mechanisms reveal, summon, or avoid *groups* of rivals; the dungeon
spawns individuals. The Coal Vetch — a faction that can appear mid-encounter after repeated
Examines — has no implementation at all.

## Fleeing — 2 markers

Both routes into it are wired (a talent adds it to the menu, an ability triggers it
directly) and both stop at the same wall: leaving an encounter means teleporting 3–5 tiles
away in exploration, with a 50 % chance the rival disappears. That has not been built.

## Figures the design doc does not give — 3 markers

Mostly resolved: the placeholders now live together in `data/balance.tres` and are tunable
without touching code (see [data-model.md](data-model.md)). What remains are figures Notion
must supply rather than ones we can choose — per-species stats, per-object durations.

## Smaller, isolated items

Save-file migration between versions; a distinct completion percentage for Forlorn
encyclopaedia pages; a title screen for boot to chain into.
