-- build-time half of src/bundle/shapes.lua: turns a MonsterResult into fixed-order lists.
-- any field not in the shapes lists stops the build, so the plugin can never silently lose one

local shapes = require("src/data/library/bundle/shapes")
local drop_odds = require("src/data/library/drops/odds")
local NIL = require("tests/support/core_tools/bundle/encoder").NIL

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
        assert(
            known[key] or (skip and skip[key]),
            "bundle: " .. label .. " has unlisted field " .. tostring(key)
        )
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

local function pack_section(section, items)
    local copy = {}
    for key, value in pairs(section) do
        copy[key] = value
    end
    local drops = {}
    for index, drop in ipairs(section.drops) do
        local row = {}
        for key, value in pairs(drop) do
            row[key] = value
        end
        -- leave the notes out when the plugin can rebuild them from the marker
        if drop.notes == shapes.notes_for(drop.note_marker, section.notes or {}) then
            row.notes = nil
        end
        -- same for anything it can work out (shapes.DERIVED), false when it would guess wrong
        -- with nothing there
        local item = items[drop.name]
        for _, field in ipairs(shapes.DERIVED) do
            if deep_equal(shapes.derive[field](drop, item), drop[field]) then
                row[field] = nil
            elseif drop[field] == nil then
                row[field] = false
            end
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
---@param items table name -> {id, unit}, from pack.items
function pack.page(page, items)
    local copy = {}
    for key, value in pairs(page) do
        copy[key] = value
    end
    copy.variants = pack_variants(page.variants)
    local sections = {}
    for index, section in ipairs(page.sections) do
        sections[index] = pack_section(section, items)
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

-- the unit price a drop rows saved price is worked out from, nil when it isnt a clean one
local function unit_of(drop)
    if drop.price == "Not sold" then
        return drop.price
    end
    local low, high = drop_odds.bounds(drop.quantity)
    local price = drop.price
    if type(price) == "table" then
        price = price.minimum
    end
    price = type(price) == "number" and math.tointeger(price)
    if not low or low == 0 or not price or price % low ~= 0 then
        return nil
    end
    return price // low
end

local function most_common(counts)
    local best
    for value, count in pairs(counts) do
        -- ties go to the smaller one (Not sold sorts as a string after any number) so two
        -- builds of the same data come out the same
        if
            not best
            or count > counts[best]
            or count == counts[best] and tostring(value) < tostring(best)
        then
            best = value
        end
    end
    return best
end

---one item id and unit price per drop name, what nearly every row of that item has. rows
---that differ still store their own, see pack_section
---@param pages MonsterResult[]
---@return table<string, {id: integer?, unit: integer|string|nil}>
function pack.items(pages)
    local ids, units = {}, {}
    for _, page in ipairs(pages) do
        for _, section in ipairs(page.sections) do
            for _, drop in ipairs(section.drops) do
                local name = drop.name
                local unit = unit_of(drop)
                if drop.item_id then
                    ids[name] = ids[name] or {}
                    ids[name][drop.item_id] = (ids[name][drop.item_id] or 0) + 1
                end
                if unit then
                    units[name] = units[name] or {}
                    units[name][unit] = (units[name][unit] or 0) + 1
                end
            end
        end
    end
    local items = {}
    for name in pairs(ids) do
        items[name] = { id = most_common(ids[name]) }
    end
    for name, counts in pairs(units) do
        items[name] = items[name] or {}
        items[name].unit = most_common(counts)
    end
    return items
end

---the items table as shapes.read_items reads it
---@param items table from pack.items
---@param string_index table<string, integer> the encoders string -> 0 based position
---@return string
function pack.items_text(items, string_index)
    local base36 = require("tests/support/core_tools/bundle/encoder").base36
    local entries = {}
    for name, item in pairs(items) do
        entries[#entries + 1] = {
            position = assert(string_index[name], "bundle: item name not in strings"),
            id = item.id and base36(item.id) or "",
            unit = item.unit == "Not sold" and "-" or item.unit and base36(item.unit) or "",
        }
    end
    table.sort(entries, function(a, b)
        return a.position < b.position
    end)
    local text = {}
    for index, entry in ipairs(entries) do
        text[index] = base36(entry.position) .. ":" .. entry.id .. ":" .. entry.unit
    end
    return table.concat(text, ",")
end

pack.deep_equal = deep_equal
return pack
