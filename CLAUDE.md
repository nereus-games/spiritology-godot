# Working on Spiritology

Short and operational. Background is in [docs/architecture.md](docs/architecture.md),
[docs/data-model.md](docs/data-model.md) and
[docs/design/game-design.md](docs/design/game-design.md).

The design document itself lives in Notion, outside this repository, and that is where the
two of us actually write it. A local HTML export may sit in `notion-export/` — gitignored,
disposable, refreshed by hand, and usually stale. Read it for detail the repository does not
carry; take nothing from it as current without checking, and ask rather than guess if the
directory is empty.

## Commands

Requires **Godot 4.6**, and the binary is not on the PATH on the author's machine:
`/Applications/Godot.app/Contents/MacOS/Godot`. Set `GODOT` if yours is elsewhere.

```bash
godot --path .                 # runs the game — a scenario picker, then a dungeon
./tools/run_checks.sh          # 7 headless regression checks (~25 s)
./tools/parse_check.sh         # parses every GDScript file (~45 s)
```

`run_checks.sh` takes filters: `./tools/run_checks.sh encounter data`.

Two things headless checks cannot judge have screenshot scenes. They open a window briefly
and write a PNG — no editor involved:

```bash
godot --path . res://scenes/dev/encounter_shot.tscn -- shot.png
godot --path . res://scenes/dev/screenshot.tscn -- chests shot.png
```

The encounter screen is reachable in game only by walking into a rival, so that first one
is the only quick way to look at it. It uses a fixed seed, so two runs of the same code
give the same image and an A/B comparison means something.

**Prefer the command line to the editor.** Everything above runs without opening Godot.

## Rules that are not preferences

**Data is edited by hand, and `data_integrity_check` is what keeps it honest.** There was a
generator once; there is not any more. `data/` is the source of truth. It holds no code, so
editing species, abilities, balance or scenario text needs no programming — see
[docs/data-model.md](docs/data-model.md).

**No displayed text in the source.** Everything the player reads goes through a translation
key, present in **both** `translations/en.po` and `translations/fr.po`. The one place that
breaks this rule is the combat log, whose lines are hardcoded French; that is a known bug,
not a precedent (docs/roadmap.md).

**Species names are common nouns.** Lowercase, never translated, and they keep their
accents in prose — *mastél*, *érzélak*. Their identifiers are ASCII: `mastel`.
[method GameEnums.key_token] is the one place that bridges the two.

**Say "encounter", not "battle".** Fighting is one way through an encounter among several,
and the vocabulary is load-bearing.

**Licence follows the directory.** `assets/`, `data/`, `translations/` are content
(LAL-1.3); everything else is code (GPL-3.0-or-later). If it is executed it is code; if it
is read, played, displayed or balanced it is content. `reuse lint` runs in CI.

**Never import third-party copyleft material** — no GPL code from another project, no
CC-BY-SA asset, no copyleft font. It would be harmless for the public repository and fatal
for the proprietary binaries Nereus distributes, and nothing would warn you. See `NOTICE`.

## Engine traps, each of which has cost time

**A new `class_name` breaks command-line launches.** The global class cache lives in
`.godot/`, and only the editor regenerates it — so a `class_name` added to a new script is
absent from it and fails with "Identifier not declared", even though the script parses
fine. The rule in force:

- **Data resources** (`resources/*.gd`) declare a `class_name`, like the five that already do.
- **Everything else** does not. Reference another script with `const X := preload("res://…")`,
  and inherit from one with `extends "res://…"`. The 26 subclass files all do this.

`tools/run_checks.sh` rebuilds the cache with `--import` when `.godot/` is missing, so a
fresh clone works; an existing clone that pulls a new `class_name` will not until it
reimports.

**`--check-only` reports autoloads as undefined.** They are not registered in that mode.
`parse_check.sh` filters exactly those, reading the names from `project.godot` rather than
hardcoding them.

**Do not use `--script` to run anything.** Autoloads are not registered, so scenes load
*without their scripts, silently*. Test harnesses are run as the MAIN SCENE instead:
`godot --headless --path . res://scenes/dev/<x>.tscn`.

**`add_child` fails in `_ready`** with "parent busy setting up children". Do
`await get_tree().process_frame` first. Every dev harness starts that way.

**`gdformat` mangles a multi-line lambda inside a call chain** and can produce code that no
longer compiles. It has happened once. Write an explicit loop instead of
`.filter(func(x): …).size()` spread over several lines.

**`EncounterFighter` holds references to other fighters** (`last_damager`, `redirect_to`).
Two that have hit each other form a RefCounted cycle, which Godot does not collect.
`release_cross_references()` breaks them, and `_finish()` calls it — do not remove that.

## Adding things

**A check** goes in `scripts/dev/<name>_check.gd` with a scene beside it; `run_checks.sh`
picks up anything matching `scenes/dev/*_check.tscn`. Copy the conventions from
`dieverting_check.gd`: `_check(cond, label)`, failures accumulated, `quit(0/1)` at the end.

**Before refactoring anything, check it has a net.** That is the order the whole
preparation followed, and it caught a formatter breaking a file within seconds. If the code
you are about to change is not covered, cover it first.

**A test that has never failed is not a test.** Break the thing on purpose, watch the check
go red, put it back.
