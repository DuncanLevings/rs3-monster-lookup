# Plugin library API branch

Branch: `feature/plugin-library-api`.

This branch adds the reusable library interface to the static standalone plugin:

- `api.open` opens the normal lookup window at a chosen monster, item, mode or tab.
- `api.lookup` returns an independent callback-style lookup handle. Reads are static and
  complete immediately; cancel/destroy are retained for consumer compatibility.
- `api.components` exposes independently owned stats, models, drops, locations and search views.
- `api.register_extension` adds sections or custom tabs to the standard window.
- `api.register_navigation` temporarily replaces the built-in location-marker controls.
- Consumer-owned controls and registrations have explicit destruction/disposal semantics.

Monster Data Core is embedded here too. This branch has no Wiki requests or downloaded-data cache;
optional live GE prices remain available. The lookup handle's old refresh argument is ignored; it no longer downloads anything. Runtime code is in `src/api.lua`,
`src/ui/extensions/`, and `src/ui/locations/navigation.lua`.

Test the LuaUnit extension/navigation suites, multiple consumers, disposal, stale callbacks and
shutdown with embedded controls. The optional external example-plugin tests require that example
checkout and may skip when it is absent. Do not assume main exports these functions.

## Minimal consumer example

Declare Monster Lookup as a required dependency in the consumer's plugin.json and access the
export under that declared dependency identifier. For an identifier of `MonsterLookup`:

```lua
MonsterLookup.open("General Graardor", { tab = "info" })

local lookup = MonsterLookup.lookup()
lookup.fetch("Goblin", function(result, problem, metadata)
    -- Use the result in UI owned by the consumer.
end)
lookup.destroy()
```

Component constructors return controllers with their own destroy methods. Registering an
extension or navigation provider returns a disposable handle. Dispose registrations and
destroy components before your consumer shuts down. Check api.version() before depending
on a particular interface version. The source signatures in src/api.lua document the full
component options and registration entry points.
