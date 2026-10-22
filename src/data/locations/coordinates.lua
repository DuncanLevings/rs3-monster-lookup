-- the wikis dungeon maps dont always use game coordinates, a floor can be drawn shifted
-- sideways or whole map squares moved somewhere else. this undoes those shifts using the
-- hand checked list in dungeons/maps.lua, and only when the tile lands inside the area that
-- shift is for
local maps = require("src/data/locations/dungeons/maps")
local regions = require("src/data/locations/dungeons/map_regions")
local coordinates = {}

local function inside(area, point)
    return point.level >= area[1]
        and point.level < area[1] + area[2]
        and point.x >= area[3]
        and point.z >= area[4]
        and point.x <= area[5]
        and point.z <= area[6]
end

function coordinates.contains(map_id, point)
    if not point then
        return false
    end

    for _, area in ipairs(regions[map_id] or maps[map_id] or {}) do
        if inside(area, point) then
            return true
        end
    end

    return false
end

-- one wiki map can show rooms that arent connected in game (a teleport or stairs apart).
-- maps like that are listed, so two spots on the same map arent taken as walkable from one
-- to the other just because they share the map id
function coordinates.is_shared(map_id)
    return regions.shared[map_id] == true
end

local region_cache = {}
function coordinates.region(map_id, point)
    if not point then
        return nil
    end

    local cache_key = tostring(map_id) .. ":" .. tostring(point.level)
    local groups = region_cache[cache_key]
    local areas = regions[map_id] or maps[map_id] or {}
    if not groups then
        groups = {}

        for i, area in ipairs(areas) do
            if point.level >= area[1] and point.level < area[1] + area[2] then
                groups[i] = i
            end
        end

        local function root(i)
            while groups[i] ~= i do
                i = groups[i]
            end

            return i
        end

        for i, a in ipairs(areas) do
            if groups[i] then
                for j = 1, i - 1 do
                    local b = areas[j]
                    if
                        groups[j]
                        and a[3] <= b[5] + 1
                        and b[3] <= a[5] + 1
                        and a[4] <= b[6] + 1
                        and b[4] <= a[6] + 1
                    then
                        groups[root(i)] = root(j)
                    end
                end
            end
        end

        for i in pairs(groups) do
            groups[i] = root(i)
        end
        region_cache[cache_key] = groups
    end

    for i, area in ipairs(areas) do
        if inside(area, point) then
            return groups[i]
        end
    end

    return nil
end

function coordinates.connected(map_id, first, second)
    if not first or not second or first.level ~= second.level then
        return false
    end

    local region = coordinates.region(map_id, first)
    return region ~= nil and region == coordinates.region(map_id, second)
end

function coordinates.world(map)
    local found

    for _, area in ipairs(maps[map.id] or {}) do
        local point = { level = map.plane - area[7], x = map.x - area[8], z = map.z - area[9] }
        if inside(area, point) then
            if
                found and (found.level ~= point.level or found.x ~= point.x or found.z ~= point.z)
            then
                return nil -- Reused diagram tiles cannot identify one game destination.
            end
            found = point
        end
    end

    return found
end

return coordinates
