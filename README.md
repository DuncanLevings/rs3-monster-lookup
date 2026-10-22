# Monster Lookup

Monster drops, stats and locations inside RuneScape 3. Right-click a monster and choose
**View drops**, or search from the **Plugins** ribbon or **Plugin Hub > Manage**.

Monster Lookup is also a UI and lookup library for other plugins: open its standard window,
embed its components in your own layout, or add your own sections and tabs.

**mod.io plugin ID: `6468042`**

- [Player features](#player-features)
- [Installation and data](#installation-and-data)
- [Developer guide](#developer-guide)
- [Working example plugin](https://github.com/DuncanLevings/rs3-monster-lookup-example)

## Player features

### Drops and prices

Browse drop categories, quantities, rarities, notes and prices from RuneScape Wiki reference
information. Search within the drops, collapse categories, and select a boss mode or enrage
where available. Expanded categories stay consistent when switching modes. The controls stay
visible while scrolling, and longer drop conditions sit behind Notes buttons and tooltips.

The average kill value is calculated for the selected mode from quantities, chances, rolls
and prices. With the optional GE Price Library enabled, it uses live traded prices where
available; otherwise local records use saved prices. Coins count as 1 gp each and untradeable
items as zero. Unknown quantities/rates, missing prices and conditional Always drops can leave
rows out, so incomplete totals are labelled as estimates.

### Monster information and models

- Weaknesses, behaviour, susceptibilities and immunities.
- A variant selector for pages containing multiple monster variants.
- Collapsible **Slayer** and **Detailed stats** groups that remember your preference across
  monsters and sessions.
- Slayer requirements, experience, task information and player-owned Slayer Dungeon reference
  details. Collected souls are not tracked.
- A model preview on wider windows where a matching model is available. Drag to turn or tilt,
  Shift+drag to move it vertically, and scroll to zoom; turning depends on client support.

### Locations and navigation

The **Locations** tab shows location names, levels, access requirements and spawn counts.
Use **Mark** for a world location or **Entrance** for dungeon access. The active row is
highlighted and a confirmation makes the selected destination visible.

The default navigation shows an in-world marker, minimap guidance and a red X on the world map.
Supported dungeon routes continue through known entrances, exits, parent portals and floor
transitions, using verified spawn pins and preferring the current floor where available.
These are waypoints, not calculated walking paths.

The final destination clears within 16 tiles on the matching floor. Entering a known dungeon
clears an entrance marker when interior guidance is unavailable; unsupported areas pause
navigation with instructions. Unverified or conflicting coordinates are not guessed.

### Three search modes

Name/item searches accept partial words, small typos, `*` and `?`. Type at least three
characters for name searches. Stats can show rankings without a text query. Up to 50 result
rows are shown.

| Mode | Use it to |
| --- | --- |
| **Monsters** | Find a monster by name or location qualifier, such as `Bloodveld God Wars`. |
| **Drops** | Find an item, then the monsters that drop it, best chance first. Selection opens the drop view with the item and mode already selected. |
| **Stats** | Rank variants by combat XP, XP per life point, Slayer XP, life points, combat level or max hit. Selection opens Monster info. |

Stats supports a name/Slayer category filter and maximum combat/Slayer levels. Bosses and the
index's associated instance/minion categories are hidden by default; choose to include them
or show bosses only. Drops and Stats cover local bundled records rather than saved Wiki lookups.

### Customization and saved lookups

**Customize** lets you change the View drops menu colour, show numeric rarities as percentages,
and refresh saved Wiki data for monsters missing from the local dataset. The refresh picker
stays in settings and confirms success there.

Saved Wiki lookups refresh when opened after two weeks. Manual refresh clears matching
variants and fetches the selected monster, with a shared one-hour cooldown. It does not replace
static records: those update through Monster Data Core releases. Saved results remain
available when a Wiki request fails. Search/lookup windows remember their position and size.

## Installation and data

| Dependency | Purpose | mod.io ID |
| --- | --- | --- |
| [Monster Data Core](https://github.com/DuncanLevings/rs3-monster-data-core) — required | Static records, searches, drop maths and map geometry. | `6471519` |
| PrettyUI — required, available from the Plugin Hub | Windows and controls. | `6398181` |
| [GE Price Library](https://github.com/CerenMD/ge-prices-library) — optional | Live GE prices. | `6414886` |

Most lookups are answered by **local static data** from Monster Data Core, with no Wiki
request. Coverage focuses on repeatable monsters with drops; quest/event-only encounters
can be excluded. Unknown or ambiguous selections may use Monster Lookup's Wiki fallback
when HTTP access is allowed. Unknown does not necessarily mean newly released content.

Typing a search stays local. Wiki fallback uses structured Bucket queries, not downloaded
page code. Its results can be less detailed: drop categories and named locations may be
unavailable. The optional GE Price Library performs its own price requests.

Settings, window positions and saved Wiki lookups stay on the device. Reference data and
third-party attribution are recorded in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).

## Developer guide

Use **Monster Lookup** when you want the standard window, reusable UI, managed lookups,
extensions or location actions. Use **Monster Data Core directly** when you only need static
records, searches, calculations or coordinates. Monster Lookup does not re-export the core.

The [example consumer repository](https://github.com/DuncanLevings/rs3-monster-lookup-example)
is a complete plugin demonstrating custom layouts, every search mode, embedded drops and
locations, standard-window opening and registered extensions.

### Declare dependencies

For a consumer using both data and PrettyUI containers:

```json
{
  "requiredDependencies": {
    "MonsterLookup": 6468042,
    "MonsterDataCore": 6471519,
    "prettyui": 6398181
  }
}
```

Declare the dependencies your code calls directly. If you only call `MonsterLookup.open`,
you only need the Monster Lookup entry; its own required dependencies still load normally.
For local development, use `"monster-lookup"` and `"monster-data-core"` as the corresponding
values and keep those folders beside your plugin. The example's manifest uses that setup.

The manifest aliases become Lua globals. Use dot calls such as `MonsterLookup.open(...)`.
Do not `require` files inside another plugin: a require path is relative to your own package.

### Public API at a glance

```lua
local lookup = MonsterLookup
local version = lookup.version()
assert(version.api.major == 1, "Unsupported Monster Lookup API")
```

| Export | Returns / purpose |
| --- | --- |
| `version()` | `{ api = { major, minor }, plugin, data_schema }`. Currently API `1.0`, package `0.0.3`. |
| `open(selection, options?)` | Boolean indicating whether the standard window opened; not whether its data finished loading. |
| `lookup()` | A caller-owned handle with `fetch`, `cancel` and `destroy`. |
| `components()` | A fresh table of component constructors, listed below. |
| `register_extension(definition)` | A `{ id, dispose }` handle, or `nil, problem`. |
| `register_navigation(provider)` | A `{ id, dispose }` handle, or `nil, problem`. |

The API major identifies incompatible API changes; minor versions identify additions.
The plugin package version and Monster Data Core's data schema are separate. Check the major
API/schema your consumer supports rather than requiring one exact package version. Internal
module paths, packed data formats and UI implementation details are not public API.

### Open the standard window

```lua
local opened = MonsterLookup.open("Abyssal demon", {
    tab = "drops",
    item = "Abyssal whip",
})

if not opened then
    log("Monster Lookup is not ready to open yet.")
end
```

A selection is an exact Wiki title string or `{ name, wiki_title?, npc_id? }`. For a clicked
NPC, use its numeric config id, not its entity uid. Preserve the Wiki title supplied by
search so similarly named monsters remain distinct.

Options are `tab`, `item` and `mode`. Built-in tab ids are `"drops"`, `"info"` and `"locations"`;
a registered extension's id also works. Use the mode's displayed name when setting `mode`.

### Own a lookup handle

Use a separate handle for each independent view. It follows one selection at a time; cancelling
it does not cancel another consumer's handle. Matching in-flight Wiki requests can be shared.
A callback may run immediately for local data, or more than once when saved data is followed
by a refresh, so create your UI state before calling `fetch`.

```lua
local request = MonsterLookup.lookup()
local alive = true

request.fetch({ name = "Abyssal demon", wiki_title = "Abyssal demon" },
    function(record, problem, metadata)
        if not alive then return end

        if record then
            log("Received " .. record.title)
            -- render/update your own components here
        end
        if problem then log(problem) end
    end)

function PluginShutdown()
    alive = false
    request.destroy()
end
```

`fetch(selection, callback, force_refresh?)` returns through the callback. A record and a
problem can coexist when saved data is still usable. Optional metadata includes `bundled`,
`built`, `saved_at`, `age_seconds`, `stale` and `refreshing`. Always allow metadata to be nil.

`cancel()` stops this handle's current subscription. `destroy()` cancels and removes the
handle; do not reuse it afterward. Forced refresh uses the same coverage/cooldown policy as
the standard UI and does not fetch replacements for static records.

The core can supply an immediate local record without a managed lookup:
`MonsterDataCore.monster(selection)`. See its [developer guide](https://github.com/DuncanLevings/rs3-monster-data-core#readme).

### Build your own info/model layout

Given a native `parent` container owned by your plugin:

```lua
local components = MonsterLookup.components()
local record = assert(MonsterDataCore.monster("General Graardor"))
local variant = MonsterDataCore.variants(record)[1]

local stats = components.stats(parent, {
    fields = { "Weakness", "Aggressive", "Susceptible to" },
    overlay_parent = parent,
})
stats.set_info(variant.info, record.title)
local height = stats.layout(420, 0)

local model = components.model(parent, {
    x = 432, y = 0, width = 220, height = math.max(220, height),
    zoom_min = 1, zoom_max = 1.5, turn = false,
})
model.set_monster({ title = record.title, info = variant.info })
model.set_active(true) -- only while your view is visible

function PluginShutdown()
    stats.destroy()
    model.destroy()
    -- destroy the caller-owned parent after its components
end
```

You choose layout, fields, sizing, groups and visibility. A compact or specialized view belongs
to the consumer; it does not require a separate preset in Monster Lookup.

| Constructor | Content |
| --- | --- |
| `stats(parent, options?)` | Selected summary rows, or all summary rows by default. |
| `weaknesses(parent, options?)` | Weakness, susceptibilities and immunities. |
| `slayer(parent, options?)` | Collapsible Slayer/POD sections. |
| `detailed_stats(parent, options?)` | Collapsible combat, offensive, defensive and affinity sections. |
| `model(parent, options)` | Independently positioned/framed native model preview. |

Info components expose `set_info(info, title?)`, `layout(width, y?)` returning height,
`height()`, `empty()`, `hide_tooltips()` and `destroy()`. Use a variant's infobox table,
not a whole record, with `set_info`.

Info options include `overlay_parent`, `page` for scroll-wheel forwarding, and `fields` for
summary components. `summary_fields()` lists accepted row labels. Slayer/detailed options
also accept `expanded` and `on_toggle(open)`; relayout after a toggle changes the height.
Persist any custom-view preferences in your own plugin if needed.

Model options include `x`, `y`, `width`, `height`, `zoom_min`, `zoom_max`, `scroll_zoom`, `turn`,
`background`, `overlay_parent` and `on_interact`. Model methods are `set_monster`, `set_active`,
`resize(width, height)`, `set_position(x, y)`, `showing()`, `failed()`, `can_turn()`,
`hide_tooltip()` and `destroy()`. Its selection accepts `title`, optional variant `info`,
`npc_id` and/or the original `selection`. Missing models are a supported outcome.

### Embed a search

Search, drops and locations need a **PrettyUI scrolling page**: a window or tab page with
`content`, `root`, `SetContentHeight`, `SetScrollPosition` and `ScrollBy`. A bare native layer
is sufficient for info/model components, but not for these page-based views.

Given your own PrettyUI `page`:

```lua
local components = MonsterLookup.components()
local search = components.search(page, {
    modes = { "monsters", "items", "stats" },
    on_select = function(selection)
        log("Selected " .. selection.name)
        -- update your own view; nothing opens automatically
        -- selection.focus can contain an item, mode or starting tab
    end,
})
search.set_active(true)

function PluginShutdown()
    search.destroy()
end
```

Use `search_monsters(page, options)`, `search_items(...)` or `search_stats(...)` for a single
mode without the mode picker. Each instance owns its query, filters and result handling.

Methods are `set_active(bool)`, `resize()`, `state()` and `destroy()`. Start only the visible
view; deactivating stops its runners. Name/item matching is spread across logic ticks;
stat ranking runs when its filters change. Options also include `y`, `on_height(height)`
and a saved `state` table. The saved state contains the selected mode and stat filters,
not a complete snapshot of every name/item query.

To open the standard window from your callback, call
`MonsterLookup.open(selection, selection.focus)`. For a custom view, keep selection handling
local as the example does.

### Embed drops and locations

Given two caller-owned PrettyUI pages, `drops_page` and `locations_page`:

```lua
local components = MonsterLookup.components()
local record = assert(MonsterDataCore.monster("Abyssal demon"))

local drops = components.drops(drops_page, {
    percentage_rarity = true,
    live_prices = false,
})
drops.set_monster(record, { item = "Abyssal whip" })

local locations = components.locations(locations_page)
locations.set_monster(record)

function PluginShutdown()
    drops.destroy()
    locations.destroy()
end
```

Drops methods are `set_monster(record, focus?)`, `update(record)`, `configure(options)`,
`refresh()`, `mode()`, `hide_tooltips()` and `destroy()`. `set_monster` resets view state;
`update` keeps the current search/mode/expanded sections for a refreshed record. Focus accepts
`item` and `mode`. Configuration changes apply on the next render/refresh.

Drops options include `overlay_parent`, `percentage_rarity`, `live_prices`, `search`,
`kill_value`, `status`, `problem` and `on_mode_change`. Disable search or the kill-value line
with `false`; `live_prices` defaults to true. The status may be text or a function asked on redraw.

Locations exposes `set_monster(record)` and `destroy()`. Its actions use the current shared
navigation provider. Marking a location here replaces the same destination used by the
standard window. These components do not expose a generic `set_active` method; destroy them
when no longer needed. Drops with live prices enabled may receive price updates while hidden.

### Add sections and tabs to the standard window

```lua
local extension, problem = MonsterLookup.register_extension({
    id = "my_plugin.monster_notes",
    kind = "section",
    title = "My plugin notes",
    order = 20,
    content = function(context)
        return {
            rows = {
                { "Monster", context.monster.title },
                { "Variant", context.variant or "Default" },
            },
            text = "Additional information supplied by my plugin.",
        }
    end,
})
assert(extension, problem)

function PluginShutdown()
    extension.dispose()
end
```

Use a unique namespaced id. A structured section/tab returns `{ rows = { {label, value}, ... },
text = "..." }`; returning nil shows nothing. Set `kind = "tab"` to add a structured tab.
Register a tab before opening the window; registrations changed later are reflected when
Monster Lookup next rebuilds its tab list on open.

For a fully custom tab, supply `create(container)` and `update(context, container)`, plus
optional `activate(context)`, `deactivate()` and `destroy(container)` instead of structured
`content`. The host owns the container; destroy your children/resources before it disappears.
Set its height to match your content. Custom tab callbacks are described in
[src/ui/extensions/registry.lua](src/ui/extensions/registry.lua).

Context includes `monster`, `variant`, `mode`, `source` and `revision`. Its `is_current()`
checks whether the selection/registration still applies; use it before applying an async
result. `refresh()` requests a redraw for a current context. Callback errors are contained
in the extension's slot and logged, but callbacks still need to stay fast.

### Replace location actions

`register_navigation(provider)` replaces the provider used by **all** Locations components
until its returned handle is disposed. Providers are stacked; disposing the current provider
restores the previous one, eventually Monster Lookup's default marker.

A provider has a namespaced `id` and two required functions:

| Hook | Contract |
| --- | --- |
| `action(location)` | Return `{ label, active_label?, tooltip?, unavailable? }`, or nil to omit the button. |
| `start(location, source_title)` | Perform your action and return `ok, problem`. |

Optional hooks are `confirmation`, `is_active`, `status`, `can_stop`, `stop` and `subscribe`.
`can_stop` and `stop` must be supplied together. `subscribe(callback)` returns an unsubscribe
function and should notify when status/active rows change. Text options are `column_title`,
`stop_label` and `note`. Dispose the registration and clean up any resources your provider owns.
The full hook signatures are in [src/ui/locations/navigation.lua](src/ui/locations/navigation.lua).

For coordinates without taking over Locations actions, call Monster Data Core's geometry
helpers directly. The example intentionally leaves the default navigation provider in place.

### Ownership, shutdown and dependency reloads

- Treat dependency exports as shared read-only tables. Keep consumer state in your own Lua
  tables, not on exports or native/PrettyUI objects.
- Create lookup handles and components for each independent view. Handle the possibility of
  immediate/repeated lookup callbacks and reject stale callbacks after close or selection change.
- Deactivate hidden searches/models. Destroy components **before** their parent containers,
  destroy lookup handles, and dispose extension/navigation registrations on shutdown.
- The code examples each show their own cleanup. Merge those calls into your existing
  `PluginShutdown`; do not overwrite earlier cleanup when combining examples.
- Destroy game-session UI on logout and rebuild it after login. Reloading a required dependency
  can stop consumers; enable/reload them again after the dependency is ready.
- Optional GE Price Library enable/disable changes are handled by Monster Lookup. That does
  not make Monster Lookup itself a hot-swappable optional dependency for your consumer.
- No single universal component interface is implied: info, model, search, drops and locations
  have the distinct methods listed above. Core records are data; PrettyUI/native containers
  remain owned by the plugin that creates them.

## Development checks

The Lua suite runs with LuaUnit available on `package.path`:

```sh
lua tests/run.lua
lua-language-server --check . --checklevel=Warning
```

The core test loader finds a sibling `monster-data-core` checkout by default;
`MONSTER_DATA_CORE_ROOT` overrides that path. The optional consumer integration cases use a
sibling `monster-lookup-example`, overridable with `MONSTER_LOOKUP_EXAMPLE_ROOT`.

See the [example's README](https://github.com/DuncanLevings/rs3-monster-lookup-example#readme)
for client checks covering selection callbacks, custom layouts, extensions, hidden views and
logout. The separate [Monster Data Core README](https://github.com/DuncanLevings/rs3-monster-data-core#readme)
documents static coverage, record shapes, search stepping and coordinate/value helpers.
