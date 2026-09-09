# Data model

Everything under `data/` is hand-maintained game-design data, and it is the **source of
truth**. There is no generator: the `.tres` files are edited directly, and
`scripts/dev/data_integrity_check.gd` is what keeps them honest.

Design lives in Notion. When a fresh Notion export lands, the data here is updated by hand
against it — this document records how each Notion field becomes a field in a `.tres`, so
that translation does not have to be re-derived every time.

Run after **any** edit under `data/` or `translations/`:

```bash
./tools/run_checks.sh data
```

---

## What lives where

| Path | Resource | Count |
|---|---|---|
| `data/species/<slug>.tres` | `SpeciesData` | 36 |
| `data/abilities/<slug>.tres` | `AbilityData` **and** `TalentData` | 111 + 10 |
| `data/objects/<slug>.tres` | `ObjectData` | 6 |
| `data/dungeons/<slug>.tres` | `DungeonConfig` | 0 (none authored yet) |

Abilities and talents deliberately share one directory: in Notion they are one database,
distinguished by a `Type` column. `GameData` routes them into separate registries by
resource type at load time.

## Slugs

The slug is the filename **and** the `id` field, and the two must match — several code
paths resolve data by string interpolation (`data/species/%s.tres`,
`assets/sprites/spirimonsters/%s.png`), so a divergence breaks them silently.

Rules: lowercase **ASCII**; every run of other characters becomes a single `_`; no leading
or trailing `_`.

Accents are folded in the slug but **kept in the name**: the species called *mastél* has id
`mastel`, file `data/species/mastel.tres`, key `SPECIES_MASTEL_NAME`, and the accented form
lives where it belongs — as the `.po` value that players actually see. The slug is an
identifier; the name is text. Docstrings that name a species keep the accent for the same
reason.

A Notion name wrapped in square brackets (`[Anomaly]`) marks a **provisional name**. Strip
the brackets for the display name; the slug never carries them.

## Translation keys

Display text never lives in a `.tres`. Each resource derives its keys from its id through
`GameEnums.key_token()` ([resources/game_enums.gd](../resources/game_enums.gd)), which
uppercases and folds accents to ASCII — `mastél` → `SPECIES_MASTEL_NAME`.

| Resource | Keys |
|---|---|
| `SpeciesData` | `SPECIES_<ID>_NAME` |
| `AbilityData` | `ABILITY_<ID>_NAME`, `ABILITY_<ID>_DESC` |
| `TalentData` | `TALENT_<ID>_NAME`, `TALENT_<ID>_DESC` |
| `ObjectData` | `OBJECT_<ID>_NAME`, `OBJECT_<ID>_DESC` |
| `DungeonConfig` | `DUNGEON_<ID>_NAME` |

Every key must exist in **both** `translations/en.po` and `translations/fr.po`. Species
names are common nouns and are not translated: both files carry the same accented value.

`_NAME` is mandatory. `_DESC` is written only where Notion actually provides a description
— today 6 abilities and 6 objects. The integrity check enforces `_NAME` and en/fr parity,
and reports missing descriptions as a count rather than a failure, so that content still
to be written never masks a real regression.

---

## Notion → enum vocabularies

These mappings are the part worth keeping: they were derived from the Notion pages and are
not recoverable from the data alone. Matching is case-insensitive; anything unrecognised
falls back to the last row.

**`Type` → `GameEnums.AbilityType`** — `talent` → `TALENT`, `exploration` → `EXPLORATION`,
anything else → `ENCOUNTER` (the common case, so most `.tres` omit the field entirely).

**`Energy` → `GameEnums.Energy`** — `heat`, `fluid`, `crystal`, `arcane`, `toxic`,
`random`, `variable`; empty → `NONE`.

**`Cost` → `GameEnums.Cost`** — `mini`, `normal`, `medium`, `a lot`; empty → `NONE`.

**`Origin` → `GameEnums.Spiricosm`** — `fiery` → `FIERY`, `wonderful` → `WONDERFUL`,
anything else → `GLOOM`. Displayed as Terne / Ardent / Merveilleux in French.

**`Damage` → `base_damage`** — Notion writes a tier and a number, `small (7)`. Only the
number is stored; **the first integer in parentheses**. No number → `-1`, meaning "no
direct damage" (a pure-effect ability). The tier words map to
`EncounterContext.DMG`: `mini` 5, `small` 7, `normal` 10, `big` 14 — **placeholder values**,
see below.

**`Talker (def. chance of init.)` → `talker_chance`** — a Notion percentage normalised to
`[0.0, 1.0]`: `30%` → `0.30`. Empty → `0.0`, meaning a species that does not open dialogue
(the aggressive ones).

**`Can join …` → `can_join`** — a Notion relation. Non-empty → `true`. Only the boolean is
kept; which special-encounter groups the species can join stays in Notion.

## Species fields sourced from the ability database

Three fields do **not** come from the species page — they are the reverse side of a
relation declared on the ability rows, and must be kept consistent by hand:

- `talent` — the ability row of `Type=Talent` whose origin is this species. The relation is
  1:1 both ways, and the integrity check enforces it: every `TalentData.owner_species`
  points at a species whose `talent` points back.
- `origin_abilities` — every ability row whose `Origin Species` is this species.
- `also_used_abilities` — from the species page's own `also uses` links.

`encyclopaedia_abilities` comes from the species page's *Abilities unlock* block, in
unlock order: `1st:` at 15 fragments, `2nd:` at 30. `forlorn_ability` is that block's
`Extreme:` entry.

`loot` is the `Potential Loot` multi-select, slugified — the same slugs as `data/objects/`.

`sprite_idle` follows a naming convention rather than a Notion field:
`res://assets/sprites/spirimonsters/<slug>.png`, set only when the file exists. 29 of the
36 species have no sprite yet; leaving the field empty is correct, and the integrity check
only verifies that a **declared** path resolves.

## Objects

Objects are not a Notion database — they are a bullet list inside the *Game Design* page,
which is why their effects are mapped **by slug** rather than inferred from prose:

| Slug | `GameEnums.ObjectEffect` | Notes |
|---|---|---|
| `notice` | `NONE` | explicitly "no effect"; exists to be given away |
| `rune_stone` | `HEAL_DEN` | |
| `smoke_bomb` | `FLEE_ENCOUNTER` | |
| `spade` | `DIG` | |
| `tea_drop` | `CURE_POISON` | |
| `torment_veil` | `AVOID_PURSUIT` | `duration_moves = 15`, the one duration Notion states |

`costume` is **deliberately absent**. The doc says the costume name indicates which
spirimonster ("e.g. fopin costume"), so there is one per species, and the species it avoids
is "specified in object description" — nothing in Notion enumerates them. Adding guesses
would be worse than the gap.

---

## Placeholders

These numbers are **not** design decisions taken here — Notion states them as `X %` and
`Y DEN`, literally highlighted placeholders. They can only be settled by playing.

| Constant | Value | Where |
|---|---|---|
| `ObjectData.magnitude` | `0` | left unset; consumers fall back to their own default |
| `OBJECT_HEAL_DEN` | 25 | `EncounterManager` |
| `MEDITATE_ETH` / `MEDITATE_DAMAGE_BONUS` | 12 / +36 % | `EncounterManager` |
| `EncounterContext.DMG` | 5 / 7 / 10 / 14 | damage tiers |
| `AbilityData.COST_ETH` | 0 / 3 / 6 / 10 / 15 | ETH per cost tier |
| `EncounterFighter.BASE_DEN` / `BASE_ETH` | 100 / 50 | no per-species stats in Notion yet |

## Updating after a Notion export

1. Diff the export against what `data/` holds — the vocabularies above are the whole
   translation layer.
2. Edit the `.tres` files, and add or remove the matching `.po` keys **in both languages**.
3. A new ability also needs an effect script in
   `scripts/encounter/effects/abilities/<slug>.gd` extending `AbilityScript`. Without one,
   `EffectCatalog` falls back to generic per-tag effects, which is a scaffold, not the
   real mechanic.

   A script whose first line is `# @unimplemented` is a placeholder: its docstring carries
   the mechanic copied from Notion, but `execute()` still defers to those generic effects.
   Implementing it means writing the real `execute()` and deleting that first line. 8 of
   the 111 abilities are in this state.
4. Run `./tools/run_checks.sh` — the integrity check catches dead references, out-of-range
   enums, missing or orphaned translation keys; the encounter check executes every ability.
