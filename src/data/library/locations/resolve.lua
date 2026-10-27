-- turns a wiki location (map id, floor, x, z) into a game tile the marker can point at.
-- wiki map coordinates often arent game coordinates (see coordinates.lua), so this decides
-- whether a location can be marked at all, and if so whether its the spawn itself or the
-- dungeon entrance you need to go through first
local location_map = {}
local SURFACE_MAP = 28
local coordinates = require("src/data/library/locations/coordinates")
local entrances =
    require("src/data/library/locations/access").new(require("src/data/library/locations/dungeons/entrances"))
local shared_maps = require("src/data/library/locations/dungeons/map_regions").strict
local portals = require("src/data/library/locations/dungeons/portals")
local map_aliases = require("src/data/library/locations/dungeons/map_aliases")
local numbers = require("src/data/library/utils/numbers")
local wiki_text = require("src/data/library/utils/wiki_text")

---@param map any
---@return boolean
function location_map.valid(map)
    return type(map) == "table"
        and numbers.is_whole(map.id, -1, 65535)
        and numbers.is_whole(map.plane, 0, 3)
        and numbers.is_whole(map.x, 0, 32767)
        and numbers.is_whole(map.z, 0, 32767)
end

local function interior_point(map, candidates)
    if not location_map.valid(map) then
        return nil
    end

    local interior = map and map.id ~= SURFACE_MAP and coordinates.world(map) or nil
    local interior_map = interior and map.id or nil
    -- wiki map -1 means the coordinates are already game coordinates. only trusted inside
    -- a known map for this exact location name
    if map and map.id == -1 then
        local point = { level = map.plane, x = map.x, z = map.z }

        for _, id in ipairs(candidates) do
            if coordinates.contains(id, point) then
                interior, interior_map = point, id
                break
            end
        end
    end

    -- a shared map can cover several unrelated caves, so when the location has an exact
    -- alias prefer the areas own map that has this spawn on it
    if interior then
        local matched = false

        for _, id in ipairs(candidates) do
            if coordinates.contains(id, interior) then
                interior_map, matched = id, true
                break
            end
        end

        if map and shared_maps[map.id] and #candidates > 0 and not matched then
            interior, interior_map = nil, nil
        end
    end

    return interior, interior_map
end

-- what the Mark button does for a location: the tile to point at, its label and tooltip,
-- and whether its the spawn itself or a dungeon entrance on the way. an entrance must never
-- be shown as if it was where the monster is
function location_map.resolve(location)
    if type(location) ~= "table" then
        return nil, "No map coordinates saved. A refresh in Customize may load them."
    end

    if location.map_issue then
        return nil, "The Wiki map coordinates are invalid or ambiguous. No marker is available."
    end

    local display_name = type(location.name) == "string" and location.name or "Location"
    local name = wiki_text.page_key(display_name)
    local page = wiki_text.page_key(location.page)
    -- quest copies of a place sit at coordinates you cant walk to. needing a quest doesnt
    -- make it one of those though, Tarn's Lair needs a quest and still has a normal entrance
    for _, label in ipairs({ name, page }) do
        if
            label:find("instance", 1, true)
            or label:find("quest area", 1, true)
            or label:find("during ", 1, true)
            or label:find("(quest)", 1, true)
            or label:find("event)", 1, true)
        then
            return nil,
                "No verified world-map destination for this quest, event or instance location."
        end
    end

    local map = location.map
    if map ~= nil and not location_map.valid(map) then
        return nil, "The Wiki map coordinates are invalid. No marker is available."
    end

    -- match on the locations wiki page link when there is one, never on the map id alone,
    -- different places can share a map or use their own unrelated grids
    local access_point, access_reason = entrances.resolve(page ~= "" and page or name, display_name)
    if access_reason then
        return nil, access_reason
    end

    if access_point then
        local candidates = map_aliases[page ~= "" and page or name] or {}
        local interior, interior_map = interior_point(map, candidates)
        local interiors, seen = {}, {}
        if type(location.spawn_maps) == "table" then
            for index, pin in ipairs(location.spawn_maps) do
                if index > 128 then
                    break
                end

                local point, id = interior_point(pin, candidates)
                if point then
                    local key = id .. ":" .. point.level .. ":" .. point.x .. ":" .. point.z
                    if not seen[key] then
                        seen[key] = true
                        interiors[#interiors + 1] = { target = point, map_id = id }
                    end
                end
            end
        end

        if #interiors > 0 then
            interior, interior_map = interiors[1].target, interiors[1].map_id
        end

        return {
            target = access_point.target,
            entry_maps = candidates,
            portal = portals[page ~= "" and page or name],
            kind = access_point.kind,
            interior = interior,
            interiors = #interiors > 0 and interiors or nil,
            interior_map = interior_map,
            destination_label = display_name,
            label = access_point.label,
            tooltip = access_point.kind == "entrance" and "Mark the entrance"
                or "Mark access point",
        }
    end

    if not map then
        return nil,
            "No map coordinates saved and no verified entrance is available. A refresh in Customize may load coordinates."
    end

    if map.id ~= SURFACE_MAP then
        return nil,
            "No verified entrance or world-map destination for this dungeon or separate map."
    end

    local target = coordinates.world(map)
    if not target then
        return nil, "No verified world-map destination for these coordinates."
    end

    return {
        target = target,
        kind = "location",
        label = display_name,
        tooltip = "Mark this location on the world map and minimap.",
    }
end

---@param location table?
---@return {level: integer, x: integer, z: integer}? target
---@return string? reason
function location_map.target(location)
    local resolution, reason = location_map.resolve(location)
    return resolution and resolution.target or nil, reason
end

return location_map
