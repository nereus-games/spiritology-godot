# Dungeon tooling: format, validator, editor

A proposal, not a description. Nothing here exists yet except where it says so. It follows
the order the rest of the project was prepared in: a net before a refactor, a format before an
editor, a validator before either is trusted.

## Where things stand

- A dungeon's **layout** is `dungeon_layout.gd`: floor, holes, pits, derived walls, entrance,
  exits. It is filled tile by tile by code — one builder per test scenario in
  `scenario_catalog.gd`. There is **no authored dungeon** and no file a level designer could
  write.
- What sits **on** the layout (traps, gates, chests, stairs, lifts, bridges, decor…) is
  instantiated by the same builders with `_place(dm, Script, tile, props)`.
- The **rules** of a dungeon (spawns, species, rarity) are a `DungeonConfig` `.tres`, and
  those are already checked by `data_integrity_check` and `geometry_check`.
- The **level-design rules** from the design doc are checked almost nowhere:
  - stairs lead to floor and nothing sits directly above them (`stairs.gd`);
  - a narrow bridge always spans a floor, with a way back up (`exploration.gd`);
  - a bottomless hole is always a mistake (`player_controller.gd`);
  - a safe area holds no hazard, no unrailed ledge and no spawn point
    (`safe_areas.violations()` — only a check calls it).

  Each carries a `TODO(dungeon checker)` and is caught, at best, at runtime.
- The dev selection screen lists test scenarios only. It now has a second tab for real
  dungeons (see below); it is empty because there is nothing to put in it.

## How dungeons are authored, and the format

The workflow decides the format. Level design draws **one 2D map per storey**, with notes on
many of the tiles; those maps are handed to Claude, who turns them into a dungeon; the result
is then adjusted by hand in a text editor or in the dev editor's GUI. So the file is mostly
*written by Claude and read by humans*, and what matters is that a person can open it,
understand it, and fix a tile.

Constraints from that: plain text, readable in a diff, no editor needed, no size limit
(a dungeon has none in theory, so nothing may assume one), and one storey per file so that
the maps handed over map one to one onto the files.

**The format** (built: `scripts/dungeon/`) — a folder per dungeon, one `.map` file per
storey, beside the `DungeonConfig` `.tres` that already carries its rules:

```
data/dungeons/<slug>/floor_00.map     # y = 0
data/dungeons/<slug>/floor_01.map     # y = 1
data/dungeons/<slug>.tres             # the DungeonConfig (optional until it has spawn rules)
```

```
[floor]
y = 0

[grid]            # x to the right, z downwards; the top-left character is tile (0, 0)
##########
#E..T..c.#
#..^.....#
##########

[legend]          # every character beyond  . # ~ _ E X  and space
T = trap type=poison poison_turns=4
c = chest loot=rune_stone,spade
^ = stairs dir=up face=E

[tiles]           # one tile, by x,z (or x,y,z)
3,1 note="the rival waits here" tags=unreachable_ok
7,1 chest trapped=true asset=res://assets/props/old_chest.glb

[zones]           # named areas, shared across storeys by name
hall tags=safe,no_teleport rect=1,1:3,2
```

`.` floor, `#` or space nothing, `~` a hole, `_` a pit, `E` the entrance, `X` an exit. A kind's
properties are typed and checked (`scripts/dungeon/dungeon_kinds.gd` is the table; N is up the
page for directions).

**Special cases have a place in the format from the start**, and none needs code:

- a **specific visual** is `asset=res://…` on any placement or annotated tile, and the validator
  checks that it exists;
- a **specific rule** is a **tag** on a tile or a zone. `no_teleport` (no teleport may land
  there), `safe` (a safe area) and `unreachable_ok` (not an error if nothing reaches it) mean
  something to the validator today; any other tag is kept for the day a rule needs it;
- the designer's **notes** are kept as `note=` and otherwise ignored;
- a property the table does not know yet is written `custom.<name>=…` and passes unchecked,
  while a plain typo is a warning.

Linking storeys is implicit: they share coordinates, and stairs say where they go.

## Status

Built: the format's parser (`dungeon_map_parser.gd`), the plan it fills (`dungeon_plan.gd`),
the validator (`dungeon_validator.gd`) with its checks (`dungeon_validator_check`), and
`tools/validate_dungeons.sh`, which CI runs on every push and pull request. Not built: the
loader that turns a plan into a playable dungeon, the other command-line tools, the editor, and
the *Dungeons* tab's Edit and Play buttons. There is no real dungeon in `data/dungeons/` yet.

## Proposed work, in order

Each step ends with a green `run_checks.sh`, and a check that has been seen to fail.

### 1. Placements as data
Give `_place(...)` a data form: a `Placement` (kind, tile, props) that the builders *and* the
loader both go through. The mechanisms already take their configuration as exported
properties, so this is mostly naming the kinds (`trap`, `gate`, `chest`, `stairs`, `lift`,
`bridge`…). Move one scenario from code to the new form as the proof, and let
`geometry_check` and its siblings confirm nothing changed.

### 2. The validator — the step with the best return, and independent of the format
A `DungeonValidator` (`RefCounted`, no `class_name`) that takes a layout, its placements and
its config and returns a list of issues: a code, a severity (`error` / `warning`), a tile, and
a translation key — it is a dev tool, but the rule on displayed text has no exception.
First rules, all of them already written down above or in `data-model.md`:

- **Geometry:** no bottomless hole; stairs land on floor with nothing above; a bridge spans
  a floor and has a way back up; a guardrail edge actually protects a drop.
- **Connectivity:** every tile and every chest is reachable from the entrance, through gates,
  stairs and linked lifts; an exit exists and is reachable; no lift or teleport gate points
  nowhere.
- **Safe areas:** `safe_areas.violations()`, finally called.
- **Spawns:** spawn points and fixed-group tiles are floor and outside safe areas (today
  `geometry_check` does this for the dev scenario only).
- **Config:** what `data_integrity_check` already knows about a `DungeonConfig`, plus a
  `scene_path` that resolves, if one is set.

It runs **on demand** — `tools/validate_dungeons.sh [slug…]` (non-zero exit on an error) and
a *Validate* button in the editor — and **automatically** as a CI job on every pull request that
touches `data/dungeons/` (and in `run_checks.sh`, for the dungeons already committed). The existing `TODO(dungeon checker)` sites then shrink to
a runtime guardrail pointing at the rule's code. Test scenarios that break a rule on purpose
(the bottomless fall, the bridge over nothing) say so explicitly rather than being exempt.

### 3. The loader
`DungeonLoader.load(slug, dm)`: parse the file, fill `dm.layout`, place the mechanisms, hand
`dm` its `DungeonConfig`. It returns the player's start tile, like `ScenarioCatalog.build`.
Round-trip check: write a layout, load it, dump it, compare.

### 4. Command-line tools
Each one is a thin scene under `scenes/dev/`, like the screenshot scenes:

- `dungeon_dump` — an ASCII rendering of each storey with the placements overlaid, for a
  review in a terminal or a pull request.
- `dungeon_shot` — a top-down PNG of a dungeon from a fixed seed, so two runs compare.
- `dungeon_stats` — tiles per storey, spawn points, chests, reachable fraction.
- A headless **walker** — a bot that walks from the entrance to every exit and chest through
  the real movement code. The validator's connectivity is a model; this is the proof.

### 5. The selection screen
The *Dungeons* tab (built; it is the editor's entry point too, an *Edit* button per dungeon)
lists the dungeons in `data/dungeons/` that no scenario runs
under, with the validator's verdict beside each. Entering one goes through the loader. Until
then the entries are greyed out with the reason.

### 6. The editor
A dev scene on top of what exists, not a second renderer:

- the existing `DungeonRenderer` draws the dungeon; a top-down grid view paints floor, holes,
  pits and exits per storey;
- a palette generated from the placement kinds of step 1, with their properties as a form;
- the validator's issues in a side panel, each one jumping to its tile;
- Save writes the format of option A, byte-stable so a diff shows only what changed.

It is the last step because it is the only one whose design depends on how it feels to use —
and everything before it is useful with a text editor alone.

## Still open

1. **A real example.** One of the colleague's maps with its notes. The legend, the property
   names and the validator's rules are so far written from the code, not from a real dungeon;
   the first one will probably move some of them.
2. **Design-doc rules beyond the ones implemented.** The doc is in Notion and there is no
   `notion-export/` in this clone. A second pass from a clone that has it should check the
   validator's rules, and the property names in `dungeon_kinds.gd`, against it.

Settled: unreachable tiles are errors unless a tag says otherwise; storeys are linked implicitly;
there is no size limit; the editor is a dev tool reached from the test screen.
