"""Build the list of candidate monsters (tools/monster_candidates.json) from saved Wiki Bucket API JSON responses.

Fetch compact infobox_monster metadata, excluding Category:Removed content.
For entries without levels or life points, supply saved infobox and drop checks.
Usage: python tools/build_monster_index.py page-1.json [page-2.json ...]
Only names are retained; no fetched code is executed.
"""
import argparse
import json
from pathlib import Path


NUMERIC_INFO = ("combat_level", "life_points", "armour", "slayer_level", "slayer_experience",
                "attack_level", "ranged_level", "magic_level", "attack_rate", "melee_accuracy",
                "ranged_accuracy", "magic_accuracy", "melee_max_hit", "ranged_max_hit", "magic_max_hit")


def has_useful_info(info):
    # Scaled quest monsters can have zero HP/level but still expose useful weaknesses
    # or attack stats. An examine line or the template's empty defaults are not enough.
    if any(isinstance(info.get(key), (int, float)) and info[key] > 0 for key in NUMERIC_INFO):
        return True
    if info.get("is_aggressive") in (True, "true"):
        return True
    return any(value.lower() not in ("", "none", "nothing", "unknown")
               for value in info.get("weakness_text", []) if isinstance(value, str))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", type=Path, nargs="+")
    parser.add_argument("--info", type=Path, nargs="*", default=[], help="Extra info checks for zero-level pages")
    parser.add_argument("--drops", type=Path, nargs="*", default=[], help="Drop existence checks for zero-level pages")
    args = parser.parse_args()
    checked, useful, removed = set(), set(), set()
    for path in args.info:
        check = json.loads(path.read_text(encoding="utf-8"))
        checked.add(check["title"])
        for row in check["response"]["bucket"]:
            info = json.loads(row["json"])
            if info.get("location_restriction") == "removed":
                removed.add(check["title"])
            elif has_useful_info(info):
                useful.add(check["title"])
    for path in args.drops:
        check = json.loads(path.read_text(encoding="utf-8"))
        if check["response"]["bucket"]:
            useful.add(check["title"])

    titles, seen = set(), set()
    for path in args.inputs:
        response = json.loads(path.read_text(encoding="utf-8"))
        if ".where(bucket.Not('Category:Removed content'))" not in response.get("bucketQuery", ""):
            raise ValueError("Expected a query excluding removed content")
        rows = response["bucket"]
        if not isinstance(rows, list):
            raise ValueError("Expected an array of Bucket rows")
        for row in rows:
            title = row["page_name"]
            if not isinstance(title, str) or not title.strip() or len(title.encode("utf-8")) > 240:
                raise ValueError("Invalid monster title")
            if any(ord(character) < 32 for character in title) or ":" in title:
                raise ValueError("Expected a mainspace page title")
            seen.add(title)
            if has_useful_info(row) or title in useful:
                titles.add(title)

    if seen - titles - checked:
        raise ValueError(f"Missing info/drop checks for {sorted(seen - titles - checked)}")
    titles.difference_update(removed)
    if len(titles) < 1000:
        raise ValueError("Index appears incomplete")
    # every candidate monster, drops or not. tools/fetch_wiki_data.py narrows this down to
    # the ones with drops and writes the plugin's own src/data/monsters/names.lua from it
    target = Path(__file__).resolve().parent / "monster_candidates.json"
    target.write_text(json.dumps(sorted(titles), ensure_ascii=False, indent=0) + "\n",
                      encoding="utf-8", newline="\n")
    print(f"{len(titles)} candidates; {target.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
