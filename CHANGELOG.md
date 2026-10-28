# Changelog

## 0.0.5 - 2026-10-28

- Remove options and parameters left over from the old public API (window close callback, refresh warnings, model viewer zoom/turn/position options).
- Mount the Plugin Hub and ribbon settings pages from one module.
- Remove small pieces of dead code in the stats, locations, search and settings code. No player-facing behavior changes.

## 0.0.4 - 2026-10-26

- Bundle Monster Data Core code and records in one installable plugin; remove the separate data-plugin dependency.
- Use static monster data exclusively, retaining optional live prices from GE Price Library. Remove Wiki requests, downloaded-data caching and refresh controls.
- Preserve the public plugin/component API and Wiki/cache features on separate feature branches, each with its own feature guide.
- Simplify internal UI components, combine related rendering and cleanup, and reuse the bundled library's utilities.
- Use PrettyUI's public search-field helpers for clipping, wheel input and managed cleanup; retain documented native and nested-tooltip safeguards.
- Remove unused clock work and redundant lookup/import layers.
- Add reproducible library imports, updated attribution, a development guide and a runtime-only release packager.

## 0.0.3

- Require Monster Data Core for local monster data, shared with other plugins.
- Allow other plugins to open Monster Lookup and show its information in their own layouts.
- Keep a saved-data refresh running when another monster is opened.

## 0.0.2

- Search monsters by name or location from the Plugins ribbon or Plugin Hub, including partial names, small typos and wildcards.
- Add a Locations tab with spawn locations, levels, access requirements and spawn counts.
- Simplify Monster info, with collapsible Slayer and Detailed stats sections that remember your preferences, plus player-owned Slayer Dungeon information.
- Add boss enrage selection and remember expanded drop categories when switching modes.
- Keep drop controls visible while scrolling and tuck lengthy explanations behind Notes buttons.
- Refresh saved lookups after two weeks, with searchable manual refresh in Customize that clears matching variants and shares a one-hour cooldown.
- Improve variant selection, search results and saved-data availability when the Wiki is unreachable.
- Mark world locations, dungeon entrances and supported interior waypoints, including resource-dungeon return routes and known floor transitions. Use actual spawn pins and prefer your current floor when available. Clear entrance markers after entering a known dungeon when interior guidance is unavailable; unknown areas pause guidance.
- Bundle Wiki data for monsters you can meet repeatedly, so most lookups need no Wiki request.
- Show live GE prices when the optional GE Price Library plugin is installed.
- Look up monsters added after the bundle date through Wiki Bucket data only, never full pages.
- Search by dropped item to see which monsters drop it, best chance first, and open a monster straight to that drop.
- Rank monsters by combat XP, XP per life point, Slayer XP and other stats, with level caps and bosses hidden by default.
- Show a 3D model of the monster on the Monster info tab that you can turn, tilt, move and zoom.
- Show the average value of a kill for the selected mode, worked out from the drop tables with live GE prices, in place of the Wiki's saved figures.

## 0.0.1

- Look up Wiki drop tables and monster information through the View drops right-click option.
- Search and collapse drop categories, compare boss modes and monster variants, and view drop notes and GE guide prices.
- Customize menu colours and rarity display, save lookups, and remember the window position and size.
