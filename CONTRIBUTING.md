# Contributing

Issues and bug reports are welcome. **Pull requests cannot be merged yet** — please read
why before opening one, so that neither of us wastes the effort.

## Why pull requests are on hold

Spiritology is dual-licensed in the strong sense. The public repository is copyleft, and
**Nereus Games LLC also distributes proprietary binaries of the game on some platforms**.
That second half only works while Nereus holds the rights to relicense the whole work.

A single merged contribution without a signed agreement would end that permanently: the
code could not be relicensed, and the only remedies would be tracking down its author or
ripping the work back out. There is no undo.

The authors' own rights are settled: Néd J. Édoire and al ultré co-founded and co-own
Nereus Games LLC, and the arrangement covers everything in this repository today. What is
not settled is anyone else's, and that is what a contributor licence agreement is for. One
is planned, and will be put in place when the project actually starts receiving
contributions. Until it exists, the honest thing is to say so rather than to accept patches
we could not use — hence this section.

**What you can do in the meantime, and what genuinely helps:** open an issue. Bug reports,
reproduction steps, design questions, and pointing out that something is wrong are all
useful and carry none of the problem above.

If you have already written a patch, say so in an issue. We will get back to you once the
agreement exists.

## Which licence covers what

The boundary follows the **directory tree** — no per-file headers to read:

| | Licence |
|---|---|
| `assets/`, `data/`, `translations/` | LAL-1.3 (Free Art License) |
| everything else | GPL-3.0-or-later |

The rule of thumb for a new file: if it is *executed*, it is code; if it is read, played,
displayed or balanced, it is content. A document that **is** game design rather than
technical documentation belongs in `docs/design/`, which is LAL.

`reuse lint` runs in CI and fails if any file ends up covered by neither.

## Never import third-party copyleft material

No GPL code from another project, no CC-BY-SA asset, no copyleft font. It would be
harmless for the public repository and fatal for the proprietary distribution — and
nothing would warn you. See `NOTICE`.

## Before you push

Requires Godot 4.6.

```bash
./tools/parse_check.sh   # parses every GDScript file
./tools/run_checks.sh    # headless regression suite
```

Both are also CI jobs. `run_checks.sh` rebuilds Godot's global class cache on first run,
so a fresh clone works with no extra step.

Data under `data/` is hand-maintained and is the source of truth; `docs/data-model.md`
explains how it is filled in, and `data_integrity_check` is what keeps it consistent.
