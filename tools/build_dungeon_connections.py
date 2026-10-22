"""Build offline route tables from the reviewed native-coordinate manifest.

The manifest records Wiki source revisions and deliberate coverage exceptions.
It contains data only: downloaded Lua and image-map pixels are never executed or
used as game coordinates. Native membership checks live in the Lua test suite.
"""
import argparse
import json
from pathlib import Path


def point(value):
    return (isinstance(value, dict)
            and all(type(value.get(k)) is int for k in ("level", "x", "z"))
            and 0 <= value["level"] <= 3
            and 0 <= value["x"] <= 16383 and 0 <= value["z"] <= 16383)


def literal(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{ " + ", ".join(literal(v) for v in value) + " }"
    if isinstance(value, dict):
        return "{ " + ", ".join("[" + literal(k) + "] = " + literal(v) for k, v in value.items()) + " }"
    if type(value) is not int:
        raise ValueError("Route tables must contain integer coordinates")
    return str(value)


def build(manifest, output):
    data = json.loads(manifest.read_text(encoding="utf-8"))
    edges = []
    for edge in data["connections"]:
        for key in ("from", "to", "to_level"):
            if type(edge.get(key)) is not int:
                raise ValueError("Missing integer route field: " + key)
        for key in ("target", "arrival"):
            if edge.get(key) is not None and not point(edge[key]):
                raise ValueError("Invalid route coordinate: " + edge["label"])
        if edge.get("arrival") and edge["arrival"]["level"] != edge["to_level"]:
            raise ValueError("Arrival floor mismatch: " + edge["label"])
        query = edge.get("query")
        if query and not (query.get("unique") is True and 1 <= query.get("range", 0) <= 64):
            raise ValueError("Scenery queries must be unique and bounded")
        edges.append({k: v for k, v in edge.items() if k != "source"})
    output.write_text(
        "-- the ladders, doors and portals between dungeon floors, each one checked by hand. where\n"
        "-- each came from (and the odd exception) is in resources/DUNGEON_ROUTE_SOURCES.json.\n"
        "-- generated, rebuild with tools/build_dungeon_connections.py\n"
        "return {\n" + "".join("    " + literal(e) + ",\n" for e in edges) + "}\n",
        encoding="utf-8", newline="\n")
    instructions = {int(k): v for k, v in data.get("manual_guidance", {}).items()}
    output.with_name("route_instructions.lua").write_text(
        "-- written directions for floor changes where the exact spot you leave from isnt known\n"
        "return " + literal(instructions) + "\n", encoding="utf-8", newline="\n")
    print(f"Wrote {len(edges)} route connections and {len(instructions)} area instructions")


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=root / "resources/DUNGEON_ROUTE_SOURCES.json")
    parser.add_argument("--output", type=Path, default=root / "src/data/locations/dungeons/connections.lua")
    options = parser.parse_args()
    build(options.manifest, options.output)
