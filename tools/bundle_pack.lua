-- build-time half of src/data/bundle_shapes.lua: turns a MonsterResult into fixed-order lists.
-- any field not in the shapes lists stops the build, so the plugin can never silently lose one

local shapes = require("src/data/bundle_shapes")
local NIL = require("tools/bundle_encoder").NIL

local pack = {}

local function deep_equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not deep_equal(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

local function pack_fields(value, fields, label, skip)
    local known = {}
    for _, field in ipairs(fields) do
        known[field] = true
    end
    for key in pairs(value) do
        assert(known[key] or (skip and skip[key]), "bundle: " .. label .. " has unlisted field " .. tostring(key))
    end

    local list = {}
    for index, field in ipairs(fields) do
        local item = value[field]
        list[index] = item == nil and NIL or item
    end
    -- trailing gaps cost bytes and decode to nil anyway
    while list[#list] == NIL do
        list[#list] = nil
    end
    return list
end

local function pack_variants(variants)
    local list = {}
    local base = variants[1]
    if not base then
        return list
    end
    list[1] = pack_fields(base, shapes.INFO, "info")

    for index = 2, #variants do
        local variant = variants[index]
        pack_fields(variant, shapes.INFO, "info") -- only for its unlisted field check
        local changes = {}
        for position, field in ipairs(shapes.INFO) do
            if variant[field] == nil then
                if base[field] ~= nil then
                    changes[#changes + 1] = -position
                end
            elseif not deep_equal(variant[field], base[field]) then
                changes[#changes + 1] = position
                changes[#changes + 1] = variant[field]
            end
        end
        list[index] = changes
    end
    return list
end

local function pack_section(section)
    local copy = {}
    for key, value in pairs(section) do
        copy[key] = value
    end
    local drops = {}
    for index, drop in ipairs(section.drops) do
        -- leave the notes out when the plugin can rebuild them from the marker
        local row = drop
        if drop.notes == shapes.notes_for(drop.note_marker, section.notes or {}) then
            row = {}
            for key, value in pairs(drop) do
                row[key] = value
            end
            row.notes = nil
        end
        drops[index] = pack_fields(row, shapes.DROP, "drop")
    end
    copy.drops = drops
    return pack_fields(copy, shapes.SECTION, "section")
end

local function pack_location(location)
    local copy = {}
    for key, value in pairs(location) do
        copy[key] = value
    end
    if copy.map then
        copy.map = pack_fields(copy.map, shapes.MAP, "location map")
    end
    return pack_fields(copy, shapes.LOCATION, "location")
end

---@param page MonsterResult without info (its variants[1] when unpacked)
function pack.page(page)
    local copy = {}
    for key, value in pairs(page) do
        copy[key] = value
    end
    copy.variants = pack_variants(page.variants)
    local sections = {}
    for index, section in ipairs(page.sections) do
        sections[index] = pack_section(section)
    end
    copy.sections = sections
    if page.locations then
        local locations = {}
        for index, location in ipairs(page.locations) do
            locations[index] = pack_location(location)
        end
        copy.locations = locations
    end
    return pack_fields(copy, shapes.PAGE, "page", { info = true })
end

pack.deep_equal = deep_equal
return pack
