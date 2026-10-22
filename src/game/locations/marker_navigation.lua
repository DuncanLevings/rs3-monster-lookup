-- Monster Lookup's own navigation for the Locations tab: the native arrow and map X from
-- marker.lua, as a provider (see src/ui/locations/navigation.lua). everything the tab says
-- about marking comes from here, so a plugin that registers its own navigation replaces it all

local marker = require("src/game/locations/marker")
local wiki_text = require("src/utils/wiki_text")

return {
    id = "monster_lookup.marker",
    column_title = "Map",
    stop_label = "Clear marker",
    note = "Dungeon markers continue in mapped areas; unsupported routes pause with instructions.",

    action = function(location)
        local label, tooltip, reason = marker.action(location)
        return { label = label, active_label = "Marked", tooltip = tooltip, unavailable = reason }
    end,

    start = function(location, source_title)
        return marker.mark(location, source_title)
    end,

    confirmation = function(location, source_title)
        return "Marked: "
            .. source_title
            .. " - "
            .. wiki_text.plain(location.name or "Location")
            .. " - open the world map to see it."
    end,

    is_active = function(location, source_title)
        return marker.is_target(location, source_title)
    end,

    status = function()
        return marker.status()
    end,

    can_stop = function()
        return marker.has_target()
    end,

    stop = function()
        marker.clear()
    end,

    subscribe = function(callback)
        return marker.subscribe(callback)
    end,
}
