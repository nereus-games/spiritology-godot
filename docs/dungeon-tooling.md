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

**Proposal** — a folder per dungeon, beside the `DungeonConfig` that already carries its
rules:

```
data/dungeons/<slug>/
  dungeon.toml        # name key, entrance, exits, links between storeys
  floor_00.map        # one file per storey: y = 0, 1, 2…
  floor_01.map
data/dungeons/<slug>.tres   # the DungeonConfig, unchanged
```

A `.map` file is a grid, a legend and a list of annotated tiles:

```
# x grows to the right, z downwards, the top-left character is tile (0, 0).
[grid]
##########
#..T..c..#
#..^..#..#
#..>.....#
##########

[legend]
# floor  . | wall  # | hole  ~ | pit  _
# the other characters are placements, defined below

[tiles]
T   trap    kind=poison        hidden=true
c   chest   loot=rune_stone
^   stairs  up
3,2 note="the rival waits here"      # one tile, by coordinate
```

The grid is the part a designer recognises from their own map. A character stands for a
*kind* of thing; a coordinate line overrides or adds to one tile. Free-text notes from the
designer's map are kept as `note=` so they are not lost, and they cost the validator nothing.
Godot's `ConfigFile` reads the `dungeon.toml`-style sections natively; only the grid needs a
few lines of parser. Any format that stays readable would do — this one is a recommendation,
and it is isolated behind one loader.

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

1. **A real example.** One of the colleague's maps with its notes, even rough. Everything above
   is a guess at what the notes look like; the legend, the property names and the validator's
   first rules should come from a real one.
2. **Stairs and lifts across storeys.** Do the maps say where a staircase on one storey comes
   out on the next, or is that implied by drawing them aligned on the same coordinates? I
   assume the second.
3. **Severity.** My default: an unreachable chest is an error, unless the placement says
   `allow_unreachable=true`. Tell me if some rules should only warn.
4. **Design-doc rules beyond the four tagged ones.** The doc is in Notion and there is no
   `notion-export/` in this clone.
