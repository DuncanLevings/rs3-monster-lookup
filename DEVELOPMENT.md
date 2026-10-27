# Development and review guide

## Runtime flow

`main.lua` starts `src/app.lua`, which owns menu integration, search, the lookup window,
settings, the elapsed clock and location markers. A selection passes through
`src/data/lookup/service.lua` to the bundled library, then into the three window tabs.

| Location | Responsibility |
| --- | --- |
| `src/data/library/` | Embedded Monster Data Core snapshot: records, indexes, matching, statistics, drop calculations and map geometry |
| `src/data/core.lua` | Single internal import of the embedded library |
| `src/data/search/` | Debounced searches with bounded work per tick |
| `src/game/` | NPC menu integration and native marker lifetime |
| `src/ui/` | Player-facing views, settings and placement |
| `src/ui/common/prettyui_internals.lua` | Dependency implementation details used by controls |
| `tests/` | LuaUnit checks and client/PrettyUI doubles; not shipped |

The main plugin does not export a public API. Its own view modules remain composable internally;
an internal module table is not a supported third-party interface. This feature branch restores the HTTP, cache, refresh-picker and clock paths documented in WIKI_CACHE.md. GEPL remains an optional
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
only module paths, records source hashes/version, and preserves upstream notices. Update the
separate data-library repository first when rebuilding data; its offline builders remain there.
Inspect the generated diff and rerun checks after importing. The separate repository is not a
runtime dependency.

## Verification

From the plugin root, with LuaUnit on the Lua path:

```text
lua tests/run.lua --shuffle
stylua --check main.lua src tests
lua-language-server --check=. --checklevel=Warning
```

In-game checks: reload and disable/re-enable; menu selection; all three searches; selected
item/mode/tab focus; variants; model interaction; settings; optional GEPL on/off; marker clear,
replacement and floor transitions; unknown NPCs; window resize and logout/login.

Build the upload with `tools/package.ps1`. The archive includes main.lua, plugin.json, src/, README
and third-party notices. It excludes tests, tools, docs, work directories and previous archives.
Do not push or publish before the user has reviewed and tested the result.
