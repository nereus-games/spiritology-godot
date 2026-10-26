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

## The decision that gates the rest: the authoring format

| Option | What it is | For | Against |
|---|---|---|---|
| **A. A text grid** — `data/dungeons/<slug>.dungeon` | One ASCII grid per storey, a legend, and a table of placements (`kind  tile  key=value…`) | Readable, diffable, editable by hand, validated from the command line with no editor — the project's stated preference. Content under LAL like the rest of `data/` | A parser to write and keep honest |
| **B. A Godot resource** — `DungeonLayoutData` `.tres` | Typed fields; placements as sub-resources | No parser; fits `data/` as it is | A 40 × 40 × 3 grid in a `.tres` is unreadable in a diff and unwritable by hand |
| **C. A Godot scene** (`GridMap` or nodes) | Painted in the editor | Visual from day one | Needs the editor, and the CLI trap list says to avoid it; hard to validate headless; merge conflicts |

**Recommendation: A**, with `DungeonConfig` staying a `.tres` beside it (rules and layout
travel together by sharing a slug). Everything else below is built so that the format is a
detail of one loader: the validator, the tools and the editor all work on `DungeonLayout`
plus a list of placements, never on the file.

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

It runs as `tools/validate_dungeons.sh [slug…]` (non-zero exit on an error), as a check in
`run_checks.sh`, and from the editor. The existing `TODO(dungeon checker)` sites then shrink to
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
The *Dungeons* tab (built) lists the dungeons in `data/dungeons/` that no scenario runs
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

## What I need from you

1. **The format.** A, B or C above. Recommendation A.
2. **Severity.** Is an unreachable chest an error, or a warning for a designer who means it
   (a chest behind an object you must find)? My default: error, with an explicit
   `allow_unreachable` on the placement.
3. **Scale.** Rough expected size of a real dungeon (tiles, storeys). It decides whether the
   walker and the flood fill need care.
4. **The design doc.** Any level-design rule beyond the four tagged ones — it lives in Notion,
   and there is no `notion-export/` in this clone.
5. **Who edits.** Only the two of us, or will someone without the repository need the editor?
   It changes whether the editor must be a shipped scene or may stay a dev tool.
