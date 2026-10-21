-- Wiki map coordinates are not interchangeable with game-world coordinates.
---@class WikiLocationMap
---@field id integer Wiki map ID; only map 28 is currently mapped to world coordinates
---@field plane integer zero-based floor
---@field x integer Wiki longitude
---@field z integer Wiki latitude

local location_map = {}
local SURFACE_MAP = 28

local function whole(value, minimum, maximum)
    return type(value) == "number"
        and value == value
        and value % 1 == 0
        and value >= minimum
        and value <= maximum
end

---@param map any
---@return boolean
function location_map.valid(map)
    return type(map) == "table"
        and whole(map.id, -1, 65535)
        and whole(map.plane, 0, 3)
        and whole(map.x, 0, 32767)
        and whole(map.z, 0, 32767)
end

---@param location table?
---@return {level: integer, x: integer, z: integer}? target
---@return string? reason
function location_map.target(location)
    local map = type(location) == "table" and location.map or nil
    if not location_map.valid(map) then
        return nil, "No map coordinates saved. A refresh in Customize may load them."
    end

    ---@cast map WikiLocationMap

    -- Other Wiki maps may use a local diagram grid, even when their numbers look valid.
    if map.id ~= SURFACE_MAP then
        return nil, "Markers for this dungeon or separate map are not supported yet."
    end

    if map.x > 12799 or map.z > 12799 then
        return nil, "This location is outside the supported world map."
    end

    return { level = map.plane, x = map.x, z = map.z }
end

return location_map
