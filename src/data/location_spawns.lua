-- The HTML map link stores a viewport centre. Spawn pins live in LocLine's
-- source parameters; keep only those numeric points, never the page source.
local coordinates = require("src/data/map_coordinates")
local map = require("src/data/location_map")
local spawns = {}
local LIMIT = 128

local function key(value)
    return value:gsub("_", " "):gsub("%s+", " "):match("^%s*(.-)%s*$"):lower()
end

local function records(source)
    local result, depth, active = {}, 0, nil
    source = source:gsub("<!%-%-.-%-%->", "")
    -- A token scan stays linear even if optional source text is malformed.
    for first, token, last in source:gmatch("()([{}][{}])()") do
        if token == "{{" then
            depth = depth + 1
            if not active and source:sub(last, last + 20):match("^%s*[Ll]oc[Ll]ine[%s|]") then
                active = { first = first, depth = depth }
            end
        elseif token == "}}" then
            if active and depth == active.depth then
                local block = source:sub(active.first, last - 1)
                local loc = block:match("|%s*[Ll][Oo][Cc]%s*=%s*([^\r\n]+)")
                    or block:match("|%s*[Ll]ocation%s*=%s*([^\r\n]+)")
                local page = loc and loc:match("%[%[([^]|#]+)")
                if page then
                    local name = key(page)
                    result[name] = result[name] or {}
                    result[name][#result[name] + 1] = block
                end
                active = nil
            end
            depth = math.max(0, depth - 1)
        end
    end
    return result
end

local function pins(block, fallback)
    local id = block:lower():match("|%s*mapid%s*=%s*([^|\r\n}]+)")
    local plane = block:lower():match("|%s*plane%s*=%s*([^|\r\n}]+)")
    if id then
        id = tonumber(id)
    else
        id = (fallback and fallback.id) or 28
    end
    if plane then
        plane = tonumber(plane)
    else
        plane = 0
    end
    local points, seen, floors = {}, {}, {}
    for raw_segment in block:gmatch("[^|]+") do
        local segment = raw_segment:lower()
        local x = segment:match("[,:]%s*x%s*:%s*([^,%s|}]+)")
            or segment:match("^%s*x%s*:%s*([^,%s|}]+)")
        local z = segment:match("[,:]%s*y%s*:%s*([^,%s|}]+)")
        if x and z then
            local level = segment:match("plane%s*:%s*([^,%s|}]+)")
                or segment:match("[,:]%s*z%s*:%s*([^,%s|}]+)")
            local pin_plane = plane
            if level then
                pin_plane = tonumber(level)
            end
            local point = { id = id, plane = pin_plane, x = tonumber(x), z = tonumber(z) }
            if map.valid(point) then
                local native = coordinates.world(point)
                local floor = native and native.level or point.plane
                local identity = point.id .. ":" .. point.plane .. ":" .. point.x .. ":" .. point.z
                -- Reserve space on every native floor rather than letting a long
                -- first-floor list discard all pins on the other floors.
                if
                    floor ~= nil
                    and not seen[identity]
                    and (floors[floor] or 0) < LIMIT / 4
                    and #points < LIMIT
                then
                    seen[identity] = true
                    floors[floor] = (floors[floor] or 0) + 1
                    points[#points + 1] = point
                end
            end
        end
    end
    return #points > 0 and points or nil
end

function spawns.attach(rows, source)
    if type(source) ~= "string" or #source > 2 * 1024 * 1024 then
        return
    end
    local by_page, used = records(source), {}
    for _, row in ipairs(rows) do
        if row.page and not row.map_issue then
            local name = key(row.page)
            used[name] = (used[name] or 0) + 1
            local block = by_page[name] and by_page[name][used[name]]
            if block then
                row.spawn_maps = pins(block, row.map)
            end
        end
    end
end

return spawns
