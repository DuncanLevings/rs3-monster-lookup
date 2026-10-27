# Wiki lookup and cache branch

Branch: `feature/wiki-cache`.

This branch adds on-demand RuneScape Wiki fallback to the standalone plugin:

- Local embedded records are preferred. Unknown or ambiguous NPC selections may query the Wiki.
- Bounded, cancellable requests are queued and completed from Logic ticks.
- Responses are validated and decoded before they reach the UI.
- Saved lookups use size-limited chunked payloads and a paged index in PersistentDB.
- Cached records appear immediately; stale results can refresh while remaining usable on failure.
- A settings picker refreshes downloaded monsters, with a shared one-hour family cooldown.
- A verified Wiki timestamp supports real-time cache ages when the client lacks os.time.
- The window identifies live/saved Wiki data and refresh failures separately from bundled records.

Monster Data Core is embedded. This branch does not export the public plugin/component API.
Optional GEPL remains available. The manifest requests optional HTTP permission for
`https://runescape.wiki`; main requests no such permission.

Runtime: `src/data/wiki/`, `src/data/lookup/cache.lua`, `src/data/lookup/service.lua`,
`src/utils/cache_clock.lua`, and `src/ui/settings/picker.lua`.

Verification: LuaUnit request/cache/refresh suites; denied permission; failures and timeouts;
reload with saved records; rapid selection changes; refresh cancellation; unknown variants;
settings picker disposal; source labels and normal static lookups with HTTP disabled.
