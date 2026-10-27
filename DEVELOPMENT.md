# Development and review guide

## Runtime flow

`main.lua` starts `src/app.lua`, which owns menu integration, search, the lookup window,
settings and location markers. Its selection handler reads the bundled library directly,
translates coverage into results/notices, and opens the three window tabs.

| Location | Responsibility |
| --- | --- |
| `src/data/library/` | Embedded Monster Data Core snapshot: records, indexes, matching, statistics, drop calculations and map geometry |
| `src/data/search/` | Debounced searches with bounded work per tick |
| `src/game/` | NPC menu integration and native marker lifetime |
| `src/ui/` | Player-facing views, settings and placement |
| `src/ui/common/prettyui_internals.lua` | Dependency implementation details used by controls |
| `tests/` | LuaUnit checks and client/PrettyUI doubles; not shipped |

Locations tab ownership and marker controls live in `src/ui/locations/view.lua`; drop price
and rarity text share `src/ui/drops/formatting.lua`. Stat rendering and block lifecycle
share `src/ui/info/stat_blocks.lua`; lookup notices belong to the monster window.
Application modules use the embedded library and its utilities directly. Search control/layout code stays separate from window
lifecycle, and native marker geometry stays separate from marker state and routing.

The main plugin does not export a public API. Its own view modules remain composable internally;
an internal module table is not a supported third-party interface. There is no HTTP path,
downloaded-monster cache, refresh picker or wall-clock synchronization. GEPL remains an optional
price layer; its enable/disable notification redraws the current drop table.

## Must-follow implementation rules

- Imagine a junior developer must review, explain and modify the code. Use descriptive names,
  plain-language comments and blank lines between meaningful steps. Explain ownership and
  constraints rather than narrating assignments. Avoid dense one-line branches and Lua tutorials.
- Use Lua 5.4 and the checked-in formatter. Verify native API signatures and config identifiers;
  do not invent APIs or treat observations as documented guarantees.
- Implement current requirements. Add an abstraction only to remove meaningful duplication,
  clarify a boundary, isolate a verified workaround or enable useful tests.
- Keep source records separate from behavior. Do not minify generated data or add codecs merely
  to reduce line counts. Preserve provenance and source notices.
- Give subscriptions and native objects an owner and cleanup path. Keep the marker replacement
  gap and retained coordinates: these protect against observed client lifetime failures.
- Prefer events; throttle necessary polling and skip unchanged rendering. Keep expensive scans
  out of Draw callbacks. Do not claim performance improvements without measurements.
- Validate uncertain inputs at boundaries. Protected calls must have a real failure case and
  useful handling. Do not silently mask programming errors or duplicate validation everywhere.
- Preserve user settings and placement keys. Old downloaded-cache keys are left untouched but
  are never read by the main version; switching to the Wiki branch can still use them.
- Keep changes focused, comments current and developer tools outside release archives. Never
  assume a passing simulated test proves native rendering or lifetime safety.

## Updating the static library

`tools/import_core.py PATH_TO_MONSTER_DATA_CORE` refreshes the embedded snapshot. It rewrites
only module paths, replaces the generated library and types trees, records source hashes/version,
and regenerates shipped notices from `tools/PLUGIN_NOTICES.txt` plus upstream notices. Removed
upstream files are removed from the snapshot too. Keep local attribution in PLUGIN_NOTICES.txt;
do not edit the generated library, types or embedded notice section directly. Update the
separate data-library repository first when rebuilding data; its offline builders remain there.
Inspect the generated diff and rerun checks after importing. The separate repository is not a
runtime dependency.

## Verification

From the plugin root, with LuaUnit on the Lua path:

```text
lua tests/run.lua --shuffle
python -m unittest discover -s tests -p "test_*.py"
stylua --check main.lua src tests
lua-language-server --check=. --checklevel=Warning
```

In-game checks: reload and disable/re-enable; menu selection; all three searches; selected
item/mode/tab focus; variants; model interaction; settings; optional GEPL on/off; marker clear,
replacement and floor transitions; unknown NPCs; window resize and logout/login.

Build the upload with `tools/package.ps1`. The archive includes main.lua, plugin.json, src/, README
and third-party notices. It excludes tests, tools, docs, work directories and previous archives.
Do not push or publish before the user has reviewed and tested the result.

## PrettyUI compatibility

Checked the public documentation and changelog at https://prettyui.j3.gg/ on 2026-10-26.
The latest released entry and installed package both report 1.2.0. Search inputs use
the page's public AddTextField method with absolute placement, so PrettyUI owns input
clipping, wheel forwarding and managed cleanup. Explicit positions remain for responsive
search controls and variable-height tables.

The drop-search toolbar sits outside scrolling content; its raw controls retain wheel
forwarding. Nested table tooltips retain a coordinate correction because the installed
tooltip context uses direct-child x/y positions. SimpleButton still has no public SetText,
so label/font access and CollapseButton sprite styling remain isolated in
prettyui_internals.lua. These are specific dependency gaps, not a general UI framework.
