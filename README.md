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

Other plugins can use Monster Lookup in three ways:

| What you want | Where to start |
| --- | --- |
| Open the existing monster window from your plugin. | `MonsterLookup.open(...)` |
| Put searches, stats, models or drop tables in your own window. | `MonsterLookup.components()` |
| Add your own information to the existing window. | `MonsterLookup.register_extension(...)` |

For a complete working plugin, start with the
[Monster Lookup Example](https://github.com/DuncanLevings/rs3-monster-lookup-example).
It shows all three approaches, including how to create the windows and clean them up.

If you only need monster data and no UI, use
[Monster Data Core](https://github.com/DuncanLevings/rs3-monster-data-core) directly.

### 1. Add the dependencies

Add these entries to your plugin's `plugin.json`, keeping its other fields:

```json
{
  "requiredDependencies": {
    "MonsterLookup": 6468042,
    "MonsterDataCore": 6471519,
    "prettyui": 6398181
  }
}
```

The names on the left become variables your Lua code can use. The numbers identify the
plugins on mod.io. This setup covers all the examples below. If you only open the standard
window, you can keep just the `MonsterLookup` entry.

For local development, use `"monster-lookup"` and `"monster-data-core"` instead of their
numbers, with those folders beside your plugin. The example repository is set up this way.

Call functions with a dot, such as `MonsterLookup.open(...)`. You do not need to `require`
Monster Lookup's files.

### 2. Open a monster window

```lua
MonsterLookup.open("Abyssal demon", {
    tab = "drops",
    item = "Abyssal whip",
})
```

This opens Abyssal demon's drops, filtered to Abyssal whip. Leave out the options to open
normally. `tab` can be `"drops"`, `"info"`, `"locations"` or an extension tab's id; `mode`
can select a boss mode by its displayed name.

Use an exact Wiki page title. You can also pass a table such as
`{ name = "General Graardor", npc_id = 6260 }` for an NPC your plugin selected. Use the NPC's
config id, not its entity uid. For search results, keep their `wiki_title` so similarly named
monsters are not mixed up.

`open` returns false if the game window is not ready. A true result means the window opened;
its data may still be loading.

### 3. Get data for your own view

A lookup handle is a small object that follows your current monster request. Give each
independent window its own handle so closing one does not cancel another's request.

```lua
local request = MonsterLookup.lookup()

request.fetch({ name = "Abyssal demon", wiki_title = "Abyssal demon" },
    function(record, problem)
        if record then
            log("Loaded " .. record.title)
            -- update your window here
        end

        if problem then
            log(problem)
        end
    end)

function PluginShutdown()
    request.destroy()
end
```

The function passed to `fetch` runs when data is available. It can run immediately for local
data, and again if a saved result is refreshed. Create your window before fetching, and handle
both a result and a possible warning. Call `request.cancel()` when closing that view, or
`request.destroy()` when finished with the handle.

For static local data only, use `MonsterDataCore.monster(...)` instead. That returns the
record directly and makes no network request.

### 4. Choose pieces for your own layout

A component is a ready-made piece of UI. You decide which pieces to use and where to put them.
For this example, `parent` is a window container your plugin has already created; the
[demo's view code](https://github.com/DuncanLevings/rs3-monster-lookup-example/blob/main/src/view.lua)
shows how to create one.

```lua
local parts = MonsterLookup.components()
local record = assert(MonsterDataCore.monster("General Graardor"))

local stats = parts.stats(parent, {
    fields = { "Weakness", "Aggressive", "Susceptible to" },
})
stats.set_info(record.info, record.title)
stats.layout(400, 0) -- width, vertical position

local model = parts.model(parent, {
    x = 420, y = 0, width = 220, height = 220,
})
model.set_monster({ title = record.title, info = record.info })
model.set_active(true)

function PluginShutdown()
    stats.destroy()
    model.destroy()
end
```

This puts selected stats on the left and a model on the right. Change the fields, positions
and sizes to suit your plugin. `record.info` is the first variant; use
`MonsterDataCore.variants(record)` if you want a variant picker.

| Piece | What it shows |
| --- | --- |
| `stats` | All summary rows, or just the labels in `fields`. |
| `weaknesses` | Weakness, susceptibilities and immunities. |
| `slayer` | Collapsible Slayer and POD information. |
| `detailed_stats` | Collapsible combat stats. |
| `model` | A model preview, where a matching model is available. |

Stats pieces use `set_info(info, title)` to change the monster, then `layout(width, y)` to
position them. `layout` returns the height used. For collapsible pieces, use `on_toggle`
to lay out your window again after their height changes.

Call `model.set_active(false)` when hiding its view, and true when showing it again. This
releases the hidden model rather than continuing to draw it.

### 5. Add a search to your window

Here, `page` is a scrolling PrettyUI window or tab page your plugin created:

```lua
local parts = MonsterLookup.components()
local search = parts.search(page, {
    on_select = function(selection)
        MonsterLookup.open(selection, selection.focus)
    end,
})
search.set_active(true)

function PluginShutdown()
    search.destroy()
end
```

This adds the combined search and opens Monster Lookup when a monster is selected. To show
the result in your own window instead, replace the `on_select` function with your own code.
The component only does what your function asks it to do.

Use `parts.search_monsters`, `parts.search_items` or `parts.search_stats` for a single search
mode. With `parts.search`, you can choose modes using
`modes = { "monsters", "items", "stats" }`.

Each search keeps its own state. Set it inactive while hidden with `search.set_active(false)`
and destroy it when finished. The example demonstrates switching between several searches.

### 6. Add drop tables or locations

These also need scrolling PrettyUI pages. In this example, `drops_page` and `locations_page`
are two pages your window already owns:

```lua
local parts = MonsterLookup.components()
local record = assert(MonsterDataCore.monster("Abyssal demon"))

local drops = parts.drops(drops_page, { live_prices = false })
drops.set_monster(record, { item = "Abyssal whip" })

local locations = parts.locations(locations_page)
locations.set_monster(record)

function PluginShutdown()
    drops.destroy()
    locations.destroy()
end
```

Drop options let you hide its search or average-value line, show percentage rarities and
choose live or saved prices. Use `drops.update(record)` for a refreshed copy of the same
monster to keep the user's search, mode and expanded categories.

Location buttons use **the same marker** as the standard window. Selecting a destination
in your plugin replaces that shared destination too.

### 7. Add your own information to Monster Lookup

You can add a section to Monster info without creating your own window:

```lua
local section, problem = MonsterLookup.register_extension({
    id = "my_plugin.notes",
    kind = "section",
    title = "My plugin notes",
    content = function(context)
        return {
            rows = {
                { "Monster", context.monster.title },
                { "Variant", context.variant or "Default" },
            },
            text = "Extra information from my plugin.",
        }
    end,
})
assert(section, problem)

function PluginShutdown()
    section.dispose()
end
```

Choose an id unique to your plugin. Monster Lookup draws the rows and text returned by
`content`, and supplies the current monster and variant in `context`. Change `kind` to
`"tab"` to put that information in a separate tab. Register it before opening the window.

The example repository includes both a section and a tab. More advanced tabs can draw their
own controls rather than returning rows.

### Cleaning up

The examples each show a `PluginShutdown` function. When combining them, put all cleanup
calls in **one** shutdown function.

- Stop hidden searches and models with `set_active(false)`.
- Destroy components before destroying the window/container holding them.
- Cancel or destroy lookup handles and remove extensions with `dispose()`.
- Ignore late results if a view has closed or changed monster; the example's selection
  checks show how to do this.
- Recreate game windows after logout/login. If a dependency is reloaded, your plugin may
  need to be enabled again afterward.

Keep your own state in Lua tables. Do not change the shared `MonsterLookup` export or add
custom fields to native/PrettyUI objects.

### Further options

The walkthrough covers the usual starting points. These references cover additional controls
when you need them:

| Area | Reference |
| --- | --- |
| Info fields, collapse settings and tooltips | [Info components](src/ui/info/components.lua) |
| Model zoom, turning, background and sizing | [Model component](src/ui/info/model.lua) |
| Drop display settings and refresh methods | [Drops component](src/ui/drops/component.lua) |
| Search modes, saved state and positioning | [Search component](src/ui/search/view.lua) |
| Custom tab controls and update callbacks | [Extension registration](src/ui/extensions/registry.lua) |
| Replacing the actions on all Locations views | [Navigation provider](src/ui/locations/navigation.lua) |

<details>
<summary>Additional API notes</summary>

- `MonsterLookup.version()` reports `api.major`, `api.minor`, `plugin` and `data_schema`.
  The current API is **1.0**. Check the API major your plugin supports; the package version
  and data schema are separate version numbers.
- `request.fetch(selection, callback, true)` asks for a forced refresh. This follows the
  normal cooldown rules and does not replace static records. Its callback can also receive
  metadata describing where the data came from and whether it is stale or refreshing.
- Info pieces take a native container. Search, drops and locations need a PrettyUI scrolling
  page; a bare layer does not provide their scrolling controls.
- Components have different methods: stats use `set_info`/`layout`, models use
  `set_monster`/`resize`/`set_active`, and page-based views use the methods shown above.
  Drops and locations do not have `set_active`; destroy them when no longer needed.
- An extension's context also includes `mode`, `source`, `revision`, `is_current()` and
  `refresh()`. Use `is_current()` before applying a delayed result, then `refresh()` to ask
  Monster Lookup to redraw that section/tab.
- `register_navigation(provider)` lets a plugin replace the buttons/actions used by all
  Locations views. It returns a handle; `dispose()` restores the previous provider.
  This changes shared navigation, so only register one when your plugin intends to take over.
- Registration functions return `nil, problem` on failure. Keep the returned handle and
  call `dispose()` when your plugin stops.

</details>

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
