#!/usr/bin/env python3
"""Turns a map exported by the top-down mapper into a dungeon's `.map` files.

    tools/import_mapper.py https://top-down-mapper.vercel.app/maps/<slug> data/dungeons/<id>
    tools/import_mapper.py ./downloaded-export data/dungeons/<id>

The source is a mapper export: `map.json`, `terrain.json`, `features.json` and one PNG per
floor. The terrain becomes the grid of each floor and the features become `[tiles]` lines, named
by cell like in the viewer. What the export does not state is read off the floor images:

  - a staircase's direction: its widest, brightest bar is the end that goes up;
  - which edge a gate sits on, and which way a cracked wall is crossed;
  - the extent of a hatched event area.

It is a BOOTSTRAP, not a build step. Run it to start a dungeon, then edit the files by hand: a
second run overwrites them. Whatever it could not settle is written as a `note=` and listed on
the console, so that nothing is guessed in silence.

Needs Python 3, Pillow and NumPy. The output is content (LAL-1.3), this script is code.
"""

import json
import re
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image

CELL = 60
TOP = 2  # the grid starts two pixels down the image

# Terrain characters of the export -> grid characters of a `.map` file. `d` is the dark floor of
# the underground levels, which the mapper draws that way to keep stacked floors readable.
TERRAIN = {"#": "#", "d": ".", ".": ".", "~": "~", "i": "i", "_": "_", "w": "_", "x": "_"}

DIRS = {"N": (0, -1), "S": (0, 1), "E": (1, 0), "W": (-1, 0)}
OPPOSITE = {"N": "S", "S": "N", "E": "W", "W": "E"}
UP_CHAR = {"N": "^", "E": ">", "S": "v", "W": "<"}
DOWN_CHAR = {"N": "n", "E": "e", "S": "s", "W": "w"}

notes: list[str] = []  # everything the importer could not settle


def warn(message: str) -> None:
    notes.append(message)


def fetch(source: str, name: str) -> bytes:
    if re.match(r"https?://", source):
        with urllib.request.urlopen(source.rstrip("/") + "/" + name) as response:
            return response.read()
    return (Path(source) / name).read_bytes()


def cell_name(x: int, z: int) -> str:
    column, n = "", x + 1
    while n:
        n, r = divmod(n - 1, 26)
        column = chr(65 + r) + column
    return f"{column}{z + 1}"


def cell_xz(name: str) -> tuple[int, int]:
    m = re.fullmatch(r"([A-Z]+)(\d+)", name)
    x = 0
    for ch in m.group(1):
        x = x * 26 + ord(ch) - 64
    return x - 1, int(m.group(2)) - 1


def pixel_rect(x: int, z: int, w: int = 1, h: int = 1, margin: int = 0):
    return (
        x * CELL - margin,
        TOP + z * CELL - margin,
        (x + w) * CELL + margin,
        TOP + (z + h) * CELL + margin,
    )


def crop(img: np.ndarray, rect) -> np.ndarray:
    x0, y0, x1, y1 = rect
    return img[max(y0, 0) : y1, max(x0, 0) : x1]


# --------------------------------------------------------------------------
# Reading the icons
# --------------------------------------------------------------------------


def bright_cyan(region: np.ndarray) -> np.ndarray:
    r, g, b = region[..., 0].astype(int), region[..., 1].astype(int), region[..., 2].astype(int)
    return (r < 70) & (g > 200) & (b > 200)


def stairs_up_direction(img: np.ndarray, x: int, z: int, w: int, h: int):
    """The side of the icon where its widest, brightest bar is: the way up."""
    mask = bright_cyan(crop(img, pixel_rect(x, z, w, h)))
    rows, cols = mask.sum(axis=1), mask.sum(axis=0)
    horizontal = rows.max() >= 0.55 * mask.shape[1]
    vertical = cols.max() >= 0.55 * mask.shape[0]
    if horizontal == vertical:
        return None
    if horizontal:
        return "N" if rows.argmax() < mask.shape[0] / 2 else "S"
    return "W" if cols.argmax() < mask.shape[1] / 2 else "E"


def orange(region: np.ndarray) -> np.ndarray:
    r, g, b = region[..., 0].astype(int), region[..., 1].astype(int), region[..., 2].astype(int)
    return (r > 140) & (g > 50) & (g < 120) & (b < 60) & (r - g > 70)


def gate_edge(img: np.ndarray, x: int, z: int):
    """The border of the listed cell that the gate's bar lies along."""
    x0, y0, x1, y1 = pixel_rect(x, z)
    region = crop(img, (x0 - 20, y0 - 20, x1 + 20, y1 + 20))
    mask = orange(region)
    rows, cols = mask.sum(axis=1), mask.sum(axis=0)
    if rows.max() >= 30 and rows.max() >= cols.max():
        y = rows.argmax() + y0 - 20 - 0
        return "N" if abs(y - y0) <= abs(y - y1) else "S"
    if cols.max() >= 30:
        xx = cols.argmax() + x0 - 20
        return "W" if abs(xx - x0) <= abs(xx - x1) else "E"
    return None


def cracked_axis(img: np.ndarray, x: int, z: int):
    """`ew` when the diamonds sit on the west and east sides of the wall cell, `ns` otherwise."""
    x0, y0, x1, y1 = pixel_rect(x, z)
    region = crop(img, (x0 - 35, y0 - 35, x1 + 35, y1 + 35))
    mask = orange(region) | pink_diamond(region)
    ys, xs = np.nonzero(mask)
    if len(xs) < 20:
        return None
    # Positions relative to the wall cell's own box.
    rx, ry = xs - 35, ys - 35
    sides = abs(rx - CELL / 2) - CELL / 2
    ends = abs(ry - CELL / 2) - CELL / 2
    horizontal = np.count_nonzero((sides > -8) & (ends < 0))
    vertical = np.count_nonzero((ends > -8) & (sides < 0))
    if horizontal == vertical:
        return None
    return "ew" if horizontal > vertical else "ns"


def pink_diamond(region: np.ndarray) -> np.ndarray:
    r, g, b = region[..., 0].astype(int), region[..., 1].astype(int), region[..., 2].astype(int)
    return (r > 200) & (g > 100) & (g < 200) & (b > 90) & (b < 190) & (r - g > 40)


def exit_edge(img: np.ndarray, x: int, z: int):
    """The border of the cell along which the green exit line runs, or None.

    Counts green pixels in a thin strip along each of the four borders; the line is the one with
    clearly the most. The green view cone on a start tile sits inside the cell, not on a border.
    """
    x0, y0, x1, y1 = pixel_rect(x, z)
    region = crop(img, (x0 - 8, y0 - 8, x1 + 8, y1 + 8)).astype(int)
    r, g, b = region[..., 0], region[..., 1], region[..., 2]
    mask = (g > 150) & (r < 120) & (b < 120)
    n = CELL + 16
    strips = {
        "N": mask[3:12, 8:-8].sum(),
        "S": mask[n - 12 : n - 3, 8:-8].sum(),
        "W": mask[8:-8, 3:12].sum(),
        "E": mask[8:-8, n - 12 : n - 3].sum(),
    }
    ranked = sorted(strips.items(), key=lambda kv: -kv[1])
    if ranked[0][1] < 12 or ranked[0][1] < 2 * ranked[1][1]:
        return None
    return ranked[0][0]


def hatched_cells(img: np.ndarray, near: tuple[int, int, int, int]):
    """Cells inside the rectangle (x0, z0, x1, z1) whose ground carries the red stripes."""
    out = []
    for z in range(near[1], near[3] + 1):
        for x in range(near[0], near[2] + 1):
            region = crop(img, pixel_rect(x, z))
            r, g, b = (region[..., i].astype(int) for i in range(3))
            stripes = (r > 140) & (r - g > 25) & (r - b > 15) & (g < 160)
            if stripes.mean() > 0.06:
                out.append((x, z))
    return out


# --------------------------------------------------------------------------
# Building the files
# --------------------------------------------------------------------------


def main(source: str, out_dir: Path) -> None:
    terrain = json.loads(fetch(source, "terrain.json"))
    features = json.loads(fetch(source, "features.json"))["features"]
    meta = json.loads(fetch(source, "map.json"))
    floors = [int(f) for f in terrain["floors"]]
    images = {}
    for f in floors:
        path = Path(out_dir.parent / f".import-{f}.png")
        path.write_bytes(fetch(source, f"{f}.png"))
        images[f] = np.array(Image.open(path).convert("RGB"))
        path.unlink()

    by_floor = defaultdict(list)
    for e in features:
        by_floor[e["floor"]].append(e)

    grids = {f: [list(row) for row in terrain["floors"][str(f)]] for f in map(str, floors)}
    grids = {int(f): g for f, g in grids.items()}
    for f, g in grids.items():
        for row in g:
            for i, ch in enumerate(row):
                if ch in TERRAIN:
                    row[i] = TERRAIN[ch]
                elif ch in "st":
                    pass  # stairs and the start tile are written below
                else:
                    warn(f"floor {f}: terrain '{ch}' has no grid character, left empty")
                    row[i] = "_"

    stairs, ramps = plan_stairs(by_floor, images, floors, grids)
    tile_lines: dict[int, list[tuple[str, int, int, str]]] = {f: [] for f in floors}
    zones: list[str] = []
    legend_used: dict[int, dict[str, str]] = {f: {} for f in floors}

    for f in floors:
        for e in by_floor[f]:
            x, z = cell_xz(e["cell"])
            t = e["type"]
            line = None
            if t == "stairs":
                continue
            elif t in ("exit", "side_exit", "start_tile"):
                grids[f][z][x] = "E" if t == "start_tile" else "X"
                edge = exit_edge(images[f], x, z)
                if edge is None:
                    warn(f"floor {f} {e['cell']}: no green exit line found on a border")
                props = [f"exit_edge={edge}"] if edge else []
                if t == "side_exit":
                    props.append("tags=side_exit")
                if t == "start_tile":
                    props.append('facing=N note="facing guessed: the export gives no arrow"')
                    warn(f"floor {f} {e['cell']}: start tile facing guessed as N")
                line = ("exit" if t != "start_tile" else "start", " ".join(props))
            elif t == "trap_disarray":
                line = ("trap", "trap type=disarray")
            elif t == "trap_teleport":
                line = ("trap", "trap type=teleport")
            elif t == "trap_poison":
                line = ("trap", "trap type=poison")
            elif t == "chest":
                line = ("chest", "chest")
            elif t == "refresh_crystal":
                line = ("crystal", "crystal")
            elif t == "rival_spawn":
                line = ("spawn", "rival_spawn")
            elif t == "litter":
                line = ("litter", "litter")
            elif t == "crumbly_grounds":
                line = ("crumbly", "crumbly")
            elif t in ("gooey_marks", "scratch_marks", "posters"):
                line = ("decor", f"decor type={t}")
            elif t == "decor_column":
                line = ("scenery", "scenery type=column corner=true")
            elif t == "decor_stone_tree":
                line = ("scenery", "scenery type=stone_tree")
            elif t == "text_label" and e.get("label") == "COAL VETCH SPAWN":
                line = ("spawn", "special_spawn faction=coal_vetch")
            elif t == "text_label" and e.get("label") == "BIG SUB MARINE":
                line = ("scenery", "scenery type=submarine")
            elif t == "narrow_bridge":
                under = grids[f][z][x]
                over = "water" if under == "~" else "void"
                if under not in "~_":
                    warn(f"floor {f} {e['cell']}: bridge over '{under}', taken as void")
                line = ("bridge", f"bridge over={over}")
            elif t in ("gate_meditation", "gate_automated"):
                kind = t.split("_")[1]
                edge = gate_edge(images[f], x, z)
                if edge is None:
                    warn(f"floor {f} {e['cell']}: gate edge not found, assumed N")
                    edge = "N"
                line = ("gate", f"gate type={kind} edge={edge}")
            elif t in ("gate_locked_spades", "gate_locked_runestones"):
                warn(f"floor {f} {e['cell']}: locked gate left out (costs are not read)")
            elif t == "cracked_wall":
                axis = cracked_axis(images[f], x, z)
                if axis is None:
                    warn(f"floor {f} {e['cell']}: cracked wall axis not found, both ways")
                line = ("cracked", "cracked_wall" + (f" axis={axis}" if axis else ""))
            elif t == "hatched_zone":
                continue
            elif t in ("void", "other", "edge_fall"):
                continue
            else:
                warn(f"floor {f} {e['cell']}: feature '{t}' not handled")
            if line:
                tile_lines[f].append((line[0], z, x, line[1]))

    for f, x, z in ramps:
        grids[f][z][x] = "."
    # Stairs: a character in the grid for each, and the legend that explains it.
    for (f, x, z), info in stairs.items():
        ch = (UP_CHAR if info["dir"] == "up" else DOWN_CHAR)[info["face"]]
        grids[f][z][x] = ch
        legend_used[f][ch] = f"stairs dir={info['dir']} face={info['face']}"
        if info.get("note"):
            tile_lines[f].append(("stairs", z, x, f'note="{info["note"]}"'))

    # The event area: hatched grey ground, found on the image around the listed cells.
    for e in features:
        if e["type"] == "hatched_zone" and e["floor"] == 0 and "part 2" in e.get("note", ""):
            x, z = cell_xz(e["cell"])
            first = [ft for ft in by_floor[0] if ft["type"] == "hatched_zone"][0]
            fx, fz = cell_xz(first["cell"])
            cells = hatched_cells(images[0], (min(x, fx), min(z, fz) - 1, x + 4, z + 3))
            if cells:
                xs, zs = [c[0] for c in cells], [c[1] for c in cells]
                zones.append(
                    "event_area tags=event_area custom.event=shadako_gives_encyclopaedia "
                    "custom.event_steps=4 note=\"event area (hatched on the map)\" "
                    "tiles=" + ";".join(cell_name(cx, cz) for cx, cz in cells)
                )
                warn(
                    f"event area read off the image: {cell_name(min(xs), min(zs))} to "
                    f"{cell_name(max(xs), max(zs))}, {len(cells)} cells"
                )

    write_floors(out_dir, meta, floors, grids, tile_lines, legend_used, zones)
    print(f"wrote {len(floors)} floors to {out_dir}")
    for n in notes:
        print("  note:", n)


def plan_stairs(by_floor, images, floors, grids):
    """Pairs the staircases across floors and settles their direction.

    A staircase is drawn on both floors it joins, in the same cell: the lower floor's is the
    flight going up, the upper floor's the same flight seen from above. The up direction comes
    from the icon's widest bar; the lower member climbs that way and the upper member descends
    the opposite way.

    An icon spanning several cells (a long flight) is one staircase: the cell at its up end is
    the stairs, and the others are floor, the ramp leading to it. Returns the stairs, keyed by
    (floor, x, z), and the ramp cells as a set of the same keys.
    """
    icons = []  # (floor, x, z, up direction)
    for f in floors:
        for e in by_floor[f]:
            if e["type"] == "stairs":
                x, z = cell_xz(e["cell"])
                w, h = e.get("span", [1, 1])
                icons.append((f, x, z, w, h))
    ends = {}
    ramps = set()
    for f, x, z, w, h in icons:
        up = stairs_up_direction(images[f], x, z, w, h)
        name = f"floor {f} {cell_name(x, z)}"
        note = None
        if up is None:
            warn(f"{name}: stairs direction not readable from the icon, assumed N")
            up, note = "N", "direction guessed"
        cells = [(x + dx, z + dz) for dx in range(w) for dz in range(h)]
        pick = {"N": min(cells, key=lambda c: c[1]), "S": max(cells, key=lambda c: c[1]),
                "W": min(cells, key=lambda c: c[0]), "E": max(cells, key=lambda c: c[0])}[up]
        for c in cells:
            if c != pick:
                ramps.add((f, c[0], c[1]))
                warn(f"{name}: long flight, {cell_name(*c)} is the ramp (floor), {cell_name(*pick)} the stairs")
        ends[(f, pick[0], pick[1])] = (up, note)
    out = {}
    for (f, x, z), (up, note) in sorted(ends.items()):
        name = f"floor {f} {cell_name(x, z)}"
        below = (f - 1, x, z) in ends
        above = (f + 1, x, z) in ends
        if below and above:
            warn(f"{name}: stairs on three floors in a row; taken as the top of the lower flight")
            above = False
        if above and not below:
            out[(f, x, z)] = {"dir": "up", "face": up}
        elif below:
            out[(f, x, z)] = {"dir": "down", "face": OPPOSITE[up]}
        else:
            # No partner drawn. If there is ground right under it, the flight comes down onto it.
            under = grids.get(f - 1, [[]])[z][x] if (f - 1) in grids else "_"
            if under in ".i":
                out[(f, x, z)] = {"dir": "down", "face": OPPOSITE[up],
                                  "note": note or "no stairs drawn below; goes down onto the ground"}
                warn(f"{name}: no partner, ground below, taken as going down")
            else:
                out[(f, x, z)] = {"dir": "up", "face": up, "note": note or "unpaired stairs"}
                warn(f"{name}: stairs with no partner on the floor above or below")
    return out, ramps


def write_floors(out_dir, meta, floors, grids, tile_lines, legend_used, zones):
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in floors:
        rows = ["".join(r) for r in grids[f]]
        text = [
            f"# {meta['title']} - floor {f}",
            "# Started by tools/import_mapper.py; edit freely, a second import overwrites it.",
            "# Cell names (AB24) are the viewer's; columns A.. left to right, rows 1.. top to bottom.",
            "",
            "[floor]",
            f"y = {f}",
            "",
            "[grid]",
            *rows,
            "",
        ]
        if legend_used[f]:
            text += ["[legend]", "# stairs: ^ > v < climb north/east/south/west, n e s w descend"]
            text += [f"{ch} = {props}" for ch, props in sorted(legend_used[f].items())]
            text.append("")
        if tile_lines[f]:
            text.append("[tiles]")
            last = None
            for group, z, x, props in sorted(tile_lines[f], key=lambda t: (t[0], t[1], t[2])):
                if group != last:
                    text.append(f"# {group}")
                    last = group
                text.append(f"{cell_name(x, z)} {props}")
            text.append("")
        if f == 0 and zones:
            text += ["[zones]", *zones, ""]
        (out_dir / f"floor_{f}.map").write_text("\n".join(text), encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], Path(sys.argv[2]))
