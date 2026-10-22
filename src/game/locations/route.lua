-- works out the next step towards a marked location for the marker, finding ladders and
-- doors listed in routes.lua among the scenery loaded around the player. it never scans the
-- whole world, and never treats just any ladder or door as the way out
local coordinates = require("src/data/locations/coordinates")
local planner =
    require("src/data/locations/navigation").new(require("src/data/locations/routes"), coordinates)
local route = {}

local function resolve_exit(query, position, map_id)
    if not LocList or type(LocList.Filter) ~= "function" then
        return nil
    end

    local range = math.min(query.range or 64, 64)
    local ok, entries = pcall(function()
        return LocList.Filter({
            name = query.name,
            coordGrid = CoordGrid.new((position.level << 28) | (position.x << 14) | position.z),
            range = range,
            sameLevel = true,
        })
    end)
    if not ok or type(entries) ~= "table" then
        return nil
    end

    local nearest, distance, count = nil, nil, 0

    for index, entry in ipairs(entries) do
        if index > 128 then
            break
        end

        local point = entry.coordGrid
        if point and point.level == position.level and coordinates.contains(map_id, point) then
            local dx, dz = point.x - position.x, point.z - position.z
            local squared = dx * dx + dz * dz
            if squared <= range * range then
                count = count + 1
                if query.unique and count > 1 then
                    return nil
                end

                if not distance or squared < distance then
                    nearest = { level = point.level, x = point.x, z = point.z }
                    distance = squared
                end
            end
        end
    end

    return nearest
end

local last_position, gate_cache
local function find_exit(query, position, map_id)
    -- the marker passes the same position table for a whole second, so scenery searches
    -- are only done once per position even when the marker asks again
    if last_position ~= position then
        last_position, gate_cache = position, {}
    end

    if gate_cache[query] == nil then
        gate_cache[query] = resolve_exit(query, position, map_id) or false
    end

    return gate_cache[query] or nil
end

function route.next(goal, position)
    return planner.next(goal, position, find_exit)
end

return route
