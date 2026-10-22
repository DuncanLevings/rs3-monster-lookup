-- builds location rows from the wikis coordinates bucket, used for monsters that arent in the
-- saved data yet
--
-- the bucket only has map pins, no area names, levels or requirements. so each map the monster
-- spawns on becomes one row named after that map, with its pins on it for the map marker.
-- surface pins far apart get split into areas, otherwise a monster found all over the world
-- would only ever mark the first spot

local core = require("src/data/core")

local spawn_locations = {}

local SURFACE_MAP = 28
local MAX_ROWS = 1000
local PINS_PER_ROW = 128
-- surface pins further apart than this are treated as a different area
local AREA_TILES = 64

local function pins_of(row)
    if type(row) ~= "table" or type(row.x) ~= "table" or type(row.y) ~= "table" then
        return {}
    end

    local pins = {}

    for index, x in ipairs(row.x) do
        local pin = { id = row.mapid, plane = row.plane or 0, x = x, z = row.y[index] }

        -- map -1 is an instance or a grid with no map, the marker cant do anything with those
        if pin.id ~= -1 and core.location_valid(pin) then
            pins[#pins + 1] = pin
        end
    end

    return pins
end

local function near(a, b)
    return a.plane == b.plane
        and math.abs(a.x - b.x) <= AREA_TILES
        and math.abs(a.z - b.z) <= AREA_TILES
end

local function add_pin(group, pin)
    local key = pin.plane .. ":" .. pin.x .. ":" .. pin.z

    if not group.seen[key] and #group.pins < PINS_PER_ROW then
        group.seen[key] = true
        group.pins[#group.pins + 1] = pin
    end
end

---@param rows table[]? records from the coordinates bucket for one page
---@return MonsterLocation[]? locations
---@return "none"|nil reason "none" when theres nothing to show
function spawn_locations.parse(rows)
    if type(rows) ~= "table" or #rows > MAX_ROWS then
        return nil
    end

    local groups, by_map = {}, {}

    for _, row in ipairs(rows) do
        for _, pin in ipairs(pins_of(row)) do
            local group

            if pin.id == SURFACE_MAP then
                for _, existing in ipairs(groups) do
                    if existing.id == SURFACE_MAP and near(existing.pins[1], pin) then
                        group = existing
                        break
                    end
                end
            else
                group = by_map[pin.id]
            end

            if not group then
                group = { id = pin.id, pins = {}, seen = {} }
                groups[#groups + 1] = group

                if pin.id ~= SURFACE_MAP then
                    by_map[pin.id] = group
                end
            end

            add_pin(group, pin)
        end
    end

    local surface_areas = 0

    for _, group in ipairs(groups) do
        if group.id == SURFACE_MAP then
            surface_areas = surface_areas + 1
        end
    end

    local locations, area = {}, 0

    for _, group in ipairs(groups) do
        -- maps without a name are mostly instances or small areas, the id at least tells them apart
        local name = core.map_name(group.id) or ("Wiki map " .. group.id)

        if group.id == SURFACE_MAP and surface_areas > 1 then
            area = area + 1
            name = name .. ", area " .. area
        end

        local first = group.pins[1]
        locations[#locations + 1] = {
            name = name,
            levels = "",
            requirements = "",
            spawns = tostring(#group.pins),
            -- own copy, the cache saves it seperately from the pin list
            map = { id = first.id, plane = first.plane, x = first.x, z = first.z },
            spawn_maps = group.pins,
        }
    end

    if #locations == 0 then
        return locations, "none"
    end

    return locations
end

return spawn_locations
