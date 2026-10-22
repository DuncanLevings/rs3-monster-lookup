"""Extract a small map transform reference from saved Wiki map configuration JSON.

Input: the content of Module:Map coordinates/transform-data.json. No network calls
or Lua execution are needed. Dungeon connections are maintained separately in
src/data/locations/routes.lua.
"""
import argparse
import json
from pathlib import Path

DEFAULT_MAP_IDS = [0, 5, 6, 13, 15, 16, 17, 18, 19, 20, 22, 23, 24, 25, 27, 28, 30, 31, 35, 36, 40, 41, 42, 43, 45, 49, 118, 136, 164, 165, 200, 206, 211, 266, 267, 320, 332, 369, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 383, 384, 385, 420, 421, 422, 450, 452, 514, 530, 544, 545, 551, 553, 554, 560, 561, 562, 566, 569, 572, 581, 589, 590, 591, 592, 593, 596, 597, 598, 599, 601, 602, 608, 612, 613, 619, 627, 667, 674, 675, 682, 687, 716, 717, 718, 719, 735, 738, 739, 760]


def merge(rows, axis):
    changed = True
    while changed:
        changed = False
        result = []
        for row in rows:
            for existing in result:
                if row[:2] + row[6:] != existing[:2] + existing[6:]:
                    continue
                if axis == 0:
                    same_span = row[3] == existing[3] and row[5] == existing[5]
                    adjacent = row[2] == existing[4] + 1 or existing[2] == row[4] + 1
                    low, high = 2, 4
                else:
                    same_span = row[2] == existing[2] and row[4] == existing[4]
                    adjacent = row[3] == existing[5] + 1 or existing[3] == row[5] + 1
                    low, high = 3, 5
                if same_span and adjacent:
                    existing[low] = min(row[low], existing[low])
                    existing[high] = max(row[high], existing[high])
                    changed = True
                    break
            else:
                result.append(row.copy())
        rows = result
    return rows


def extract(source, selected):
    maps = {entry["id"]: entry for entry in source}
    result = {}
    for map_id in selected:
        entry = maps[map_id]
        rows = []
        for area in entry["subarea"]:
            src, dst, plane = area["src"], area["dst"], area["plane"]
            values = [plane, entry["origin"]["plane"], *src.values(), *dst.values()]
            if any(type(value) is not int for value in values):
                raise ValueError(f"Non-integer map configuration: {map_id}")
            if not 0 <= plane <= 3:
                raise ValueError(f"Invalid floor: {map_id}")
            for bounds in (src, dst):
                if not (0 <= bounds["x1"] <= bounds["x2"] <= 32767
                        and 0 <= bounds["y1"] <= bounds["y2"] <= 32767):
                    raise ValueError(f"Invalid bounds: {map_id}")
            # A destination can display only part of a source map square. Using
            # the larger source rectangle would admit tiles absent from that map.
            rows.append([
                plane, 4 - plane if map_id == 28 else 1,
                src["x1"], src["y1"],
                min(src["x2"], src["x1"] + dst["x2"] - dst["x1"]),
                min(src["y2"], src["y1"] + dst["y2"] - dst["y1"]),
                entry["origin"]["plane"] - plane,
                dst["x1"] - src["x1"], dst["y1"] - src["y1"],
            ])
        result[map_id] = merge(merge(rows, 0), 1)
    return result


def render(maps):
    text = (
        "-- how each wiki dungeon map is shifted from game coordinates, from the RuneScape Wiki\n"
        "-- contributors map config (2026-10-21). each row: source floor, floor count, source x/z\n"
        "-- bounds, then the plane/x/z offsets. generated, rebuild with tools/build_dungeon_maps.py.\n"
        "-- source revision and the CC BY-NC-SA 3.0 attribution are in THIRD_PARTY_NOTICES.txt\n"
        "return {\n"
    )
    for map_id, rows in maps.items():
        text += f"    [{map_id}] = {{\n"
        for row in rows:
            text += "        { " + ", ".join(map(str, row)) + " },\n"
        text += "    },\n"
    return text + "}\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--maps", type=int, nargs="+", default=DEFAULT_MAP_IDS)
    args = parser.parse_args()
    data = extract(json.loads(args.source.read_text(encoding="utf-8")), args.maps)
    args.output.write_text(render(data), encoding="utf-8", newline="\n")
    print(f"Wrote {len(data)} maps, {sum(map(len, data.values()))} transform areas")
