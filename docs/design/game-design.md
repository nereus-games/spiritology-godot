# The systems, in short

Enough of the design to read the code. The design itself lives in Notion; this is the part
the code assumes, written down so that nobody has to guess.

## The shape of a game

A **monster-cataloguing dungeon crawler**. You explore as a **duo** — a main character the
player names, and a teammate — and both are playable in an encounter. Three modes: a 2D
top-down world map between dungeons, first-person 3D dungeons on an orthogonal grid, and
first-person 2D turn-based encounters.

Two resources: **DEN** (density, which is health) and **ETH** (ether, which pays for
abilities). ETH is fully restored on entering a dungeon; DEN is not, and carries across
encounters.

Lineage: SMT Strange Journey, Labyrinth of Galleria, The Dark Spire, Mary Skelter — and
Undertale, for the idea that fighting need not be the way through.

## The point of the game is the encyclopaedia

Not levels. One page per species, filled with **info points**, where 1 point is 1 % of a
page. Four ways to earn them:

| | |
|---|---|
| Examining decor or ground while exploring | capped at 15 points per species, ever |
| Examining a rival in an encounter | works every time |
| Talking to a rival | only if the dialogue is effective |
| Dissolving a rival | |

How much each yields depends on the player's **PSY score**, in three bands (≤10, 10–30,
>30). Notice what that means: how you play changes how fast you learn, and dissolving
rivals is the *least* rewarding of the four.

Every 3 points produce one true fragment **and one parasitic false one**. A page holds 33
true fragments, and they are assembled by hand in a puzzle the player can open at any time,
including mid-encounter — orthogonal moves and 90° rotations, with compatible neighbours
snapping together. Assembling wrongly destroys parasitic fragments noisily and damages true
ones; handling a fragment gradually stains it, making it harder to read.

Fifteen fragments assembled unlock the species' first ability, thirty the second.

Each species also has a second, **Forlorn** page for its variant, holding a third exclusive
ability at fifteen fragments. Forlorn rivals yield more info points — but only once the
ordinary page is already complete. The two pages merge visually when both are done.

## Encounters

Turn order is drawn **at random** when the encounter begins, and abilities can change it
(Shuffle, Tumult). When several reordering effects land on the same individual in one turn,
only the last counts.

That matters more than it sounds, because of weaknesses.

**Every species has three weaknesses — one for going first, one for in-between, one for
last.** Only the one matching its current position is exposed. So moving someone in the
turn order changes what they are vulnerable to, and reordering is an attack in its own
right.

Five energies: **heat, fluid, crystal, arcane, toxic**. Some abilities have a random or
variable energy that changes every turn — the same for everyone using one that turn.

Damage is raised by a fixed step **per condition met**, and conditions add up before being
applied, rounded up:

- the ability's energy matches the target's exposed weakness
- attacker and target share a Spiricosm of origin (Gloom, Fiery, Wonderful)
- the target's encyclopaedia page is complete
- attacker and target are the same species

Actions available in an encounter: Talk, Examine, Use Ability, Use/Give Object, Meditate.
Unusable ones stay visible and greyed rather than hidden. Fleeing and Stealing are not
offered by default — a talent adds them, replacing another action.

## Three kinds of ability

**Talents** are passive, one per species, neither learnable nor unlockable. A duo of the
same species stacks its talent.

**Exploration abilities** are usable once per dungeon visit. Refresh crystals restore them
all; the litter's Recycle action restores one at random.

**Encounter abilities** are available to players and rivals alike. Some are once per
encounter. Some change the turn order, and some interfere with the interface itself —
Tumult moves UI elements around, Anodyne Excess hides the rivals' stats.

There are over a hundred, and they are named after psychological concepts: Gaslighting,
Ghosting, Emotional Blackmail, Love Bombing, Flow State. That is the game's register, and
it is worth preserving when writing new ones.

## Objects

Every object is consumable and stackable, and "there is no necessary object in this game" —
none is needed to finish it. They come from merchants and from Pr Shadako, a ravbak.

Giving one to a rival is a real move, not a waste: it feeds the dialogue.
