-- which monsters drop an item, read from src/data/bundle/drops.lua (built by
-- tools/search_index.lua). droppers are already sorted best chance first, at most 50 per item
--
-- text in the file points into the bundles strings.lua, so this loads that too. its the same
-- require the bundle uses for lookups so its only ever read once
--
-- only bundled monsters are in here. anything newer than the bundle turns up after the next
-- build, and missing files just mean no drop search, never an error

local bundle = require("src/data/bundle")

local drop_index = {}

-- must match tools/search_index.lua
local FORMAT = 1
local FIELD, ROW = "%^", "`"

---@class DropIndexItem
---@field name string
---@field item_id integer?
---@field count integer how many bundled monsters drop it, can be more than droppers shows

---@class Dropper
---@field title string wiki page of the monster
---@field rate string as the drop table shows it
---@field quantity string
---@field mode string? drop mode its in eg "Hard mode", nil when the page has no modes

local loaded
local unavailable = false

local function load()
    if loaded or unavailable then
        return loaded
    end

    local ok, problem = pcall(function()
        local raw = require("src/data/bundle/drops")
        assert(type(raw) == "table" and raw.format == FORMAT, "unexpected drop index format")
        local strings = require("src/data/bundle/strings")
        local items = {}
        local icons, counts = {}, {}

        for value in (raw.icons .. ","):gmatch("([^,]*),") do
            icons[#icons + 1] = value ~= "" and tonumber(value, 36) or false
        end

        for value in raw.counts:gmatch("[^,]+") do
            counts[#counts + 1] = tonumber(value, 36)
        end

        for index, name in ipairs(raw.items) do
            items[index] = {
                -- "=" marks a name that wasnt in strings.lua, the rest are its positions
                name = name:sub(1, 1) == "=" and name:sub(2)
                    or assert(strings[tonumber(name, 36) + 1], "item name missing from strings"),
                item_id = icons[index] or nil,
                count = counts[index] or 0,
            }
        end

        loaded = { items = items, rows = raw.rows, modes = raw.modes, strings = strings }
    end)

    if not ok then
        unavailable = true
        log("Monster Lookup: drop search unavailable. " .. tostring(problem))
    end

    return loaded
end

---every item that a bundled monster drops, sorted by name
---@return DropIndexItem[]
function drop_index.items()
    local data = load()
    return data and data.items or {}
end

---the bundled monsters that drop the item at this position in items(), best chance first
---@param position integer
---@return Dropper[]
function drop_index.droppers(position)
    local data = load()
    local text = data and data.rows[position]

    if not text then
        return {}
    end

    local titles = bundle.titles()
    local droppers = {}

    for row in (text .. ROW):gmatch("(.-)" .. ROW) do
        local fields = {}

        for field in (row .. "^"):gmatch("(.-)" .. FIELD) do
            fields[#fields + 1] = field
        end

        local title = titles[tonumber(fields[1], 36)]
        local rate = data.strings[tonumber(fields[2], 36) + 1]

        if title and rate then
            droppers[#droppers + 1] = {
                title = title,
                rate = rate,
                quantity = fields[3] ~= "" and data.strings[tonumber(fields[3], 36) + 1] or "1",
                mode = fields[4] and fields[4] ~= "" and data.modes[tonumber(fields[4], 36)]
                    or nil,
            }
        end
    end

    return droppers
end

return drop_index
