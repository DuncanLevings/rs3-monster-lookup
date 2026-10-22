"""Download the Wiki data the bundle is built from, into work/wiki/, and write the search list.

Steps:
  1. scan the dropsline bucket for which pages have drops (page_name + item_name only)
  2. keep monsters from tools/monster_candidates.json that have drops, leaving out quest-only
     monsters, ones you cant meet repeatedly, and removed content (see main for the rules)
     the rest become "known, no drops" or "not covered" (only their NPC IDs are kept).
     a full run also rewrites
     src/data/monster_names.lua, the plugins search list, with just the kept monsters
  3. scan infobox_monster for every page's NPC IDs
  4. for kept monsters: infobox_monster rows (stats/variants) and the page HTML, re-fetched
     only when the page revision changed since the last run
  5. infobox_item IDs for every dropped item

Scraping static data once is what the Wiki asks plugin devs to do instead of live calls:
https://runescape.wiki/w/RuneScape:How_to_safely_use_wiki_data_in_RuneScape_plugins
so this stays polite: one request per second, maxlag, a contact in the User-Agent.

Usage: python -I tools/fetch_wiki_data.py [--only "General Graardor" ...] [--limit 10]
To pick up a few new monsters between full runs: --rescan-monsters --only-new
Run with -I so nothing in the download folders can shadow a module.
"""
import argparse
import http.client
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "work" / "wiki"
API = "https://runescape.wiki/api.php"
BUCKET_PAGE = 5000  # the most rows the bucket api returns per request
TITLES_PER_QUERY = 20
ITEMS_PER_QUERY = 40
REVIDS_PER_QUERY = 50
# location_restriction values for variants a player can meet again and again
REPEATABLE = {None, "", "surface", "minigame"}
# group boss pages: one drop table (and locations) for several monsters whose stats are on
# their own pages. the wiki doesnt link them up, so the members are listed by hand. the group
# page is bundled in their place, with every members variants, and clicking any member in
# game opens it
GROUP_PAGES = {
    "The Ghrazi Blood Knights": ["Lady Karmina Ghrazi", "Lord Vasily Ghrazi"],
}


class Wiki:
    def __init__(self, contact, delay):
        self.agent = f"MonsterLookup-build/1.0 ({contact})"
        self.delay = delay
        self.last = 0.0
        self.count = 0

    def get(self, params):
        params = dict(params, format="json", maxlag=5)
        url = API + "?" + urllib.parse.urlencode(params)
        for attempt in range(6):
            wait = self.last + self.delay - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            self.last = time.monotonic()
            self.count += 1
            request = urllib.request.Request(url, headers={"User-Agent": self.agent})
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    data = json.loads(response.read().decode("utf-8"))
            except urllib.error.HTTPError as error:
                # 429 or 5xx, back off and try again
                if error.code in (429, 500, 502, 503, 504):
                    time.sleep(int(error.headers.get("Retry-After") or 5 * (attempt + 1)))
                    continue
                raise
            except (urllib.error.URLError, TimeoutError, ConnectionError,
                    http.client.HTTPException, json.JSONDecodeError):
                # dropped connections and cut-off bodies (IncompleteRead) are worth a retry
                time.sleep(5 * (attempt + 1))
                continue
            # the wiki asks bots to wait when its replicas are lagging
            if data.get("error", {}).get("code") == "maxlag":
                time.sleep(5 * (attempt + 1))
                continue
            return data
        raise RuntimeError(f"giving up on {url}")

    def bucket(self, query):
        data = self.get({"action": "bucket", "query": query})
        if "error" in data:
            raise RuntimeError(f"bucket error {data['error']} for {query}")
        return data["bucket"]


def literal(value):
    # bucket queries are lua, so quote like the plugins url.literal does
    return "'" + str(value).replace("\\", "\\\\").replace("'", "\\'") + "'"


def slug(title):
    return re.sub(r"[^A-Za-z0-9]+", "_", title).strip("_")[:80] + "-" + str(abs(hash_title(title)))


def hash_title(title):
    # stable across runs (pythons hash() isnt)
    value = 0
    for character in title.encode("utf-8"):
        value = (value * 131 + character) % 1000000007
    return value


def load_json(path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    temp.replace(path)


def candidate_titles():
    # every monster tools/build_monster_index.py found, drops or not
    return load_json(ROOT / "tools/monster_candidates.json", [])


def write_monster_names(kept):
    # the plugins search list: only monsters with drops, the rest have nothing to show
    output = ["-- Generated by tools/fetch_wiki_data.py from the RuneScape Wiki.",
              "-- RuneScape Wiki contributors, CC BY-NC-SA 3.0; see THIRD_PARTY_NOTICES.txt.",
              "return {"]
    output.extend("    " + json.dumps(title, ensure_ascii=False) + "," for title in sorted(kept))
    output.extend(["}", ""])
    target = ROOT / "src/data/monster_names.lua"
    target.write_text("\n".join(output), encoding="utf-8", newline="\n")
    print(f"wrote {len(kept)} names to {target.relative_to(ROOT)}", flush=True)


def scan(wiki, bucket, fields, label):
    rows, offset = [], 0
    while True:
        select = ",".join(literal(field) for field in fields)
        page = wiki.bucket(f"bucket('{bucket}').select({select}).limit({BUCKET_PAGE})"
                          f".offset({offset}).run()")
        rows.extend(page)
        print(f"  {label}: {len(rows)} rows", flush=True)
        if len(page) < BUCKET_PAGE:
            return rows
        offset += BUCKET_PAGE


def scan_drops(wiki, rescan):
    path = WORK / "dropsline_pages.json"
    if path.exists() and not rescan:
        return load_json(path, {})
    drops = {}
    for row in scan(wiki, "dropsline", ["page_name", "item_name"], "dropsline"):
        items = drops.setdefault(row["page_name"], [])
        if row.get("item_name") and row["item_name"] not in items:
            items.append(row["item_name"])
    save_json(path, drops)
    return drops


def scan_monsters(wiki, rescan):
    # every infobox_monster row: npc ids per page, plus where each variant can be met
    # (location_restriction: empty for the normal world, or quest, minigame, dungeoneering,
    # familiar, limited, surface, removed)
    ids_path, rows_path = WORK / "npc_ids.json", WORK / "monster_variants.json"
    if ids_path.exists() and rows_path.exists() and not rescan:
        return load_json(ids_path, {}), load_json(rows_path, {})
    ids, variants = {}, {}
    fields = ["page_name", "id", "version_anchor", "location_restriction"]
    for row in scan(wiki, "infobox_monster", fields, "infobox_monster"):
        found = ids.setdefault(row["page_name"], [])
        numbers = []
        for value in row.get("id") or []:
            try:
                numbers.append(int(value))
            except (TypeError, ValueError):
                continue
        found.extend(number for number in numbers if number not in found)
        variants.setdefault(row["page_name"], []).append({
            "version": row.get("version_anchor"),
            "restriction": row.get("location_restriction"),
            "ids": numbers,
        })
    save_json(ids_path, ids)
    save_json(rows_path, variants)
    return ids, variants


def apply_groups(npc_ids, variants):
    # members npc ids and variants move onto their group page, saved so the bundle build maps
    # the ids to the group too. a member thats gone already (from an earlier run) is skipped
    for group, members in GROUP_PAGES.items():
        ids = list(npc_ids.get(group, []))
        rows = list(variants.get(group, []))
        for member in members:
            ids.extend(number for number in npc_ids.pop(member, []) if number not in ids)
            rows.extend(variants.pop(member, []))
        npc_ids[group], variants[group] = ids, rows
    save_json(WORK / "npc_ids.json", npc_ids)
    save_json(WORK / "monster_variants.json", variants)


def group_infobox(member_rows):
    # each member keeps its own variants, named after it so the Monster info dropdown says
    # whose stats they are, eg "Lady Karmina Ghrazi - Regular"
    rows = []
    for member, texts in member_rows:
        for text in texts:
            info = json.loads(text)
            anchor = info.get("version_anchor")
            info["version_anchor"] = f"{member} - {anchor}" if anchor else member
            rows.append(json.dumps(info))
    return rows


def category_members(wiki, category, kind="page"):
    titles, cursor = [], None
    while True:
        params = {"action": "query", "list": "categorymembers", "cmtitle": category,
                  "cmtype": kind, "cmlimit": 500, "formatversion": 2}
        if cursor:
            params["cmcontinue"] = cursor
        data = wiki.get(params)
        titles.extend(member["title"] for member in data["query"]["categorymembers"])
        cursor = data.get("continue", {}).get("cmcontinue")
        if not cursor:
            return titles


def scan_lists(wiki, rescan):
    # category lists used by the exclusion rules, cached together
    path = WORK / "lists.json"
    if path.exists() and not rescan:
        saved = load_json(path, {})
        return {key: set(value) for key, value in saved.items()}
    # quest items: a monster only dropping these (eg the Zogre Flesh Eaters zombies and their
    # ruined backpack) has nothing worth showing outside the quest
    quest_items = category_members(wiki, "Category:Quest items")
    # bones and ashes, plus its subcategories
    bones = set(category_members(wiki, "Category:Bones and ashes"))
    for sub in category_members(wiki, "Category:Bones and ashes", "subcat"):
        bones.update(category_members(wiki, sub))
    # each quest has a category of the same name holding the monsters it uses
    quests = ["Category:" + title for title in category_members(wiki, "Category:Quests")]
    lists = {"quest_items": set(quest_items), "bones": bones, "quest_categories": set(quests)}
    save_json(path, {key: sorted(value) for key, value in lists.items()})
    print(f"  {len(quest_items)} quest items, {len(bones)} bones/ashes, {len(quests)} quests",
          flush=True)
    return lists


def scan_page_categories(wiki, titles, rescan):
    path = WORK / "page_categories.json"
    known = {} if rescan else load_json(path, {})
    missing = [title for title in titles if title not in known]
    for start in range(0, len(missing), REVIDS_PER_QUERY):
        batch = missing[start:start + REVIDS_PER_QUERY]
        params = {"action": "query", "prop": "categories", "cllimit": "max",
                  "titles": "|".join(batch), "formatversion": 2}
        found = {title: set() for title in batch}
        while True:
            data = wiki.get(params)
            for page in data.get("query", {}).get("pages", []):
                found.setdefault(page["title"], set()).update(
                    category["title"] for category in page.get("categories", []))
            if "continue" not in data:
                break
            params = dict(params, **data["continue"])
        for title, categories in found.items():
            known[title] = sorted(categories)
        save_json(path, known)
    return {title: set(categories) for title, categories in known.items()}


def scan_removal_dates(wiki, rescan):
    path = WORK / "removal_dates.json"
    if path.exists() and not rescan:
        return load_json(path, {})
    dates = {row["page_name"]: {"date": row.get("date"), "text": row.get("date_text")}
             for row in scan(wiki, "removal_date", ["page_name", "date", "date_text"], "removal_date")}
    save_json(path, dates)
    return dates


def latest_revisions(wiki, titles):
    revisions = {}
    for start in range(0, len(titles), REVIDS_PER_QUERY):
        batch = titles[start:start + REVIDS_PER_QUERY]
        data = wiki.get({"action": "query", "prop": "info", "titles": "|".join(batch),
                         "formatversion": 2})
        for page in data.get("query", {}).get("pages", []):
            if "lastrevid" in page:
                revisions[page["title"]] = page["lastrevid"]
    return revisions


def fetch_infoboxes(wiki, titles):
    rows = {}
    for start in range(0, len(titles), TITLES_PER_QUERY):
        batch = titles[start:start + TITLES_PER_QUERY]
        conditions = ",".join("{'page_name'," + literal(title) + "}" for title in batch)
        for row in wiki.bucket("bucket('infobox_monster').select('page_name','json')"
                               f".where(bucket.Or({conditions})).limit(500).run()"):
            rows.setdefault(row["page_name"], []).append(row["json"])
    return rows


def fetch_pages(wiki, titles, refresh, only_new=False):
    folder = WORK / "pages"
    # only_new skips the revision check, so pages already saved stay as they are even if the
    # wiki changed them since. for picking up a few new monsters between full runs
    if only_new:
        stale = [title for title in titles if not (folder / (slug(title) + ".json")).exists()]
    else:
        revisions = latest_revisions(wiki, titles)
        stale = []
        for title in titles:
            saved = load_json(folder / (slug(title) + ".json"), None)
            if refresh or not saved or saved.get("revid") != revisions.get(title):
                stale.append(title)
    print(f"  {len(titles) - len(stale)} pages unchanged, fetching {len(stale)}", flush=True)
    members = [member for title in stale for member in GROUP_PAGES.get(title, [])]
    infoboxes = fetch_infoboxes(wiki, stale + members)
    for title in stale:
        if title in GROUP_PAGES:
            infoboxes[title] = group_infobox(
                [(member, infoboxes.get(member, [])) for member in GROUP_PAGES[title]])
    for number, title in enumerate(stale, 1):
        data = wiki.get({"action": "parse", "page": title, "prop": "text|wikitext|revid",
                         "formatversion": 2, "redirects": 1})
        if "error" in data:
            print(f"  ! {title}: {data['error'].get('info')}", flush=True)
            continue
        parse = data["parse"]
        save_json(folder / (slug(title) + ".json"), {
            "title": title,
            "parsed_title": parse.get("title"),
            "revid": parse.get("revid"),
            "infobox": infoboxes.get(title, []),
            "html": parse.get("text", ""),
            "wikitext": parse.get("wikitext"),
        })
        if number % 25 == 0 or number == len(stale):
            print(f"  pages: {number}/{len(stale)}", flush=True)


def fetch_items(wiki, names, refresh):
    path = WORK / "item_ids.json"
    known = {} if refresh else load_json(path, {})
    missing = sorted(name for name in names if name not in known)
    for start in range(0, len(missing), ITEMS_PER_QUERY):
        batch = missing[start:start + ITEMS_PER_QUERY]
        conditions = ",".join("{'page_name'," + literal(name) + "}" for name in batch)
        found = {}
        for row in wiki.bucket("bucket('infobox_item').select('page_name','item_id')"
                               f".where(bucket.Or({conditions})).limit(500).run()"):
            ids = row.get("item_id") or []
            for value in ids:
                try:
                    found.setdefault(row["page_name"], int(value))
                except (TypeError, ValueError):
                    pass
        for name in batch:
            # null means "asked, no item record" (ability unlocks etc) so reruns skip it
            known[name] = found.get(name)
        save_json(path, known)
    return known


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", action="append", default=[], help="fetch just these titles")
    parser.add_argument("--limit", type=int, help="fetch only the first N kept monsters")
    parser.add_argument("--rescan", action="store_true", help="redo the bucket scans")
    parser.add_argument("--rescan-monsters", action="store_true",
                        help="redo just the infobox_monster scan, for new npc ids and variants")
    parser.add_argument("--only-new", action="store_true",
                        help="only download pages that arent saved yet, skip the revision check")
    parser.add_argument("--refresh", action="store_true", help="refetch pages even if unchanged")
    parser.add_argument("--delay", type=float, default=1.0, help="seconds between requests")
    parser.add_argument("--names-only", action="store_true",
                        help="just rewrite src/data/monster_names.lua from the scans")
    args = parser.parse_args()

    contact = json.loads((ROOT / "plugin.json").read_text(encoding="utf-8"))["contactEmailAddress"]
    wiki = Wiki(contact, max(args.delay, 1.0))
    started = time.monotonic()

    print("scanning drops", flush=True)
    drops = scan_drops(wiki, args.rescan)
    print("scanning monsters", flush=True)
    npc_ids, variants = scan_monsters(wiki, args.rescan or args.rescan_monsters)
    apply_groups(npc_ids, variants)
    print("scanning categories", flush=True)
    lists = scan_lists(wiki, args.rescan)
    removal_dates = scan_removal_dates(wiki, args.rescan)

    candidates = args.only or candidate_titles()
    if not candidates:
        raise SystemExit("no candidates, run tools/build_monster_index.py first")
    # group pages stand in for their members, which have no drop table of their own
    grouped = {member for members in GROUP_PAGES.values() for member in members}
    candidates = [title for title in candidates if title not in grouped]
    if not args.only:
        candidates += [group for group in GROUP_PAGES if group not in candidates]

    # removed content: every variant marked removed, or a "(historical)" copy of an old version.
    # a removal date alone isnt enough, eg Dark wizard has one for an old version but is
    # still in the game
    def restrictions(title):
        return {row["restriction"] for row in variants.get(title, [])} or {None}

    removed = [title for title in candidates
               if title.endswith("(historical)") or restrictions(title) == {"removed"}]
    no_drops = [title for title in candidates if not drops.get(title) and title not in removed]
    with_drops = [title for title in candidates if drops.get(title) and title not in removed]

    # only monsters you can find and kill again and again: a variant out in the world
    # (no restriction, or "surface") or in a minigame. quest, dungeoneering, limited-time
    # event and familiar-only monsters are left out
    not_repeatable = [title for title in with_drops if not restrictions(title) & REPEATABLE]

    # quest monsters the restriction doesnt mark: only quest items, or met in a quest and
    # dropping nothing better than quest items and bones/ashes. being in a quest category
    # alone isnt enough, bosses like Commander Zilyana are in several
    print("scanning page categories", flush=True)
    categories = scan_page_categories(wiki, with_drops, args.rescan)
    quest_items, bones = lists["quest_items"], lists["bones"]
    quest_drops = []
    for title in with_drops:
        items = drops[title]
        only_quest_items = all(item in quest_items for item in items)
        in_quest = bool(categories.get(title, set()) & lists["quest_categories"])
        only_filler = all(item in quest_items or item in bones for item in items)
        if only_quest_items or (in_quest and only_filler):
            quest_drops.append(title)

    not_covered = sorted(set(not_repeatable) | set(quest_drops))
    kept = [title for title in with_drops if title not in set(not_covered)]
    # only a full run may replace the search list, a test with --only/--limit would shrink it
    full_run = not args.only and not args.limit
    if args.limit:
        kept = kept[:args.limit]
    save_json(WORK / "selection.json", {
        "kept": kept,
        "no_drops": {title: npc_ids.get(title, []) for title in no_drops},
        "not_covered": {title: npc_ids.get(title, []) for title in not_covered},
        "removed": sorted(removed),
        "repeatable": sorted(restriction or "" for restriction in REPEATABLE),
    })
    print(f"{len(candidates)} candidates: {len(kept)} kept, {len(no_drops)} without drops, "
          f"{len(not_covered)} not repeatable or quest only "
          f"({len(not_repeatable)} by restriction), {len(removed)} removed", flush=True)

    # theres no category for announced removals, so a future removal date is a warning to
    # check by hand rather than a rule (the date can be for just one version of a monster)
    now = time.time()
    for title in kept:
        removal = removal_dates.get(title)
        if removal and isinstance(removal.get("date"), (int, float)) and removal["date"] > now:
            print(f"  check: {title} has a removal date in the future ({removal['text']})",
                  flush=True)
    if full_run:
        write_monster_names(kept)
    if args.names_only:
        return

    print("fetching pages", flush=True)
    fetch_pages(wiki, kept, args.refresh, args.only_new)
    print("fetching item ids", flush=True)
    names = {name for title in kept for name in drops.get(title, [])}
    items = fetch_items(wiki, names, args.refresh)

    with_ids = sum(1 for name in names if items.get(name))
    minutes = (time.monotonic() - started) / 60
    print(f"done: {wiki.count} requests in {minutes:.1f} min; "
          f"{with_ids}/{len(names)} dropped items have ids", flush=True)


if __name__ == "__main__":
    sys.exit(main())
