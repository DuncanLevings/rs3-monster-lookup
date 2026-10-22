-- turns rows from the wikis dropsline bucket into drop table sections, used for monsters that
-- arent in the saved data yet
--
-- the bucket knows which mode a drop belongs to (the bit after # in "Dropped from") but not the
-- headings from the page, so each mode gets one Drops section plus one for anything rolled on
-- the shared rare drop table. prices arent in there either, the drop value is the alch value,
-- so the drop table fills them in from the GE Price Library when its installed

local json = require("src/utils/json")
local text = require("src/utils/wiki_text")
local wiki_notes = require("src/utils/wiki_notes")
local drop_odds = require("src/data/drop_odds")

---@class Drop
---@field name string item name as shown on the page
---@field wiki_name string? item page name, used to look up the item id. saved data has the id already
---@field item_id integer? filled in later for the item icon
---@field quantity string
---@field rate string rarity text exactly as the wiki shows it eg "1/128" or "Rare"
---@field price number|{minimum: number, maximum: number}|"Not sold"|nil
---@field notes string footnote text for this row, "" if none
---@field note_marker string footnote numbers eg "1,3", "" if none
---@field chance string? percent per roll, see src/data/drop_odds.lua
---@field rolls integer? rolls per kill, nil means 1
---@field quantity_low integer? lowest quantity when its not just a number
---@field quantity_high integer? highest quantity when its not the same as the lowest

---@class DropSection
---@field title string headings above the table joined with " / "
---@field description string? paragraphs between the heading and the table
---@field afterword string? paragraphs after the table
---@field drops Drop[]
---@field notes string[] footnotes used in this table, numbered in order
---@field note_ids table<string, integer>
---@field drop_mode string? Wiki switch label for an enrage-dependent table
---@field drop_threshold number? minimum enrage, -1 for normal mode
---@field drop_switch integer? identifies tables from the same Wiki switcher

local dropsline = {}

-- one big boss is around 200 rows, anything way past this is junk not a drop table
local MAX_ROWS = 2000

local NOTE_FIELDS = { "Name NotesP", "Quantity Notes", "Rarity Notes" }

-- bucket text still has wiki markup in it, bold/italic quotes and templates on top of links
local function clean(value)
    if type(value) ~= "string" then
        return ""
    end

    value = value:gsub("{{[^{}]*}}", ""):gsub("'''", ""):gsub("''", "")
    return text.plain(value)
end

local function whole(value)
    return type(value) == "number" and value >= 0 and value % 1 == 0 and value < math.huge
end

-- "1/384" with "1/378" next to it is how the page shows a luck boosted rate, and the dash
-- version is for rates that go up to something like "Varies"
local function rate_text(data)
    local rate = clean(data["Rarity"])
    local alternative = clean(data["Alt Rarity"])

    if alternative == "" then
        return rate
    end

    local separator = (data["Alt Rarity Dash"] or "") ~= "" and "–" or "; "
    return rate .. separator .. alternative
end

-- GE prices come from the price library, this only covers what it cant. coins are worth their
-- amount and things the wiki doesnt track on the GE are not sold
local function price(data, wiki_name)
    if wiki_name == "Coins" then
        local low, high = data["Quantity Low"], data["Quantity High"]

        if whole(low) and whole(high) then
            return low == high and low or { minimum = low, maximum = high }
        end
    end

    if data["Drop GEMW"] == false then
        return "Not sold"
    end

    return nil
end

local function row_notes(data)
    local values = {}

    for _, field in ipairs(NOTE_FIELDS) do
        local list = data[field]

        if type(list) == "table" then
            for _, note in ipairs(list) do
                local content = type(note) == "table" and note.content or note
                local cleaned = wiki_notes.clean(clean(content))

                if cleaned ~= "" then
                    values[#values + 1] = cleaned
                end
            end
        end
    end

    return values
end

-- "Goblin#Normal mode,Hard mode" is a drop shared by both modes, plain "Goblin" has no mode
local function modes_of(data)
    local from = type(data["Dropped from"]) == "string" and data["Dropped from"] or ""
    local anchor = from:match("#(.+)$")
    local modes = {}

    for part in (anchor or ""):gmatch("[^,]+") do
        local mode = text.plain(part)

        if mode ~= "" then
            modes[#modes + 1] = mode
        end
    end

    return modes
end

local function read_row(row)
    if type(row) ~= "table" or type(row.drop_json) ~= "string" then
        return nil, "The Wiki returned an invalid drop record."
    end

    local data = json.decode(row.drop_json)

    if type(data) ~= "table" then
        return nil, "The Wiki returned a drop record that could not be read."
    end

    local item = data["Dropped item"] or data["Dropped item from RDT"]
    local wiki_name = type(row.item_name) == "string" and row.item_name ~= "" and row.item_name
        or type(item) == "string" and item

    if not wiki_name or wiki_name == "" then
        return false
    end

    local name = clean(type(item) == "string" and item or wiki_name)
    local name_note = clean(data["Name Notes"])
    local drop = {
        name = name_note ~= "" and name .. " " .. name_note or name,
        wiki_name = wiki_name,
        quantity = clean(tostring(data["Drop Quantity"] or "")),
        rate = rate_text(data),
        price = price(data, wiki_name),
    }

    -- the base rarity, not the luck boosted one, same as the wikis own average value
    drop_odds.fill(drop, clean(data["Rarity"]))
    local rolls, low, high = data["Rolls"], data["Quantity Low"], data["Quantity High"]

    if drop.chance and whole(rolls) and rolls > 1 then
        drop.rolls = rolls
    end

    -- the bucket has the bounds as numbers already, theyre better than the text
    if whole(low) and whole(high) and low <= high and tostring(low) ~= drop.quantity then
        drop.quantity_low = low
        drop.quantity_high = high ~= low and high or nil
    end

    return {
        drop = drop,
        notes = row_notes(data),
        modes = modes_of(data),
        rare = row.rare_drop_table == true or data["Dropped item from RDT"] ~= nil,
    }
end

-- numbers notes per section in the order theyre first used, same as the page tables do
local function add_drop(section, entry)
    local drop = {}

    for key, value in pairs(entry.drop) do
        drop[key] = value
    end

    local numbers = {}

    for _, note in ipairs(entry.notes) do
        if not section.note_ids[note] then
            section.notes[#section.notes + 1] = note
            section.note_ids[note] = #section.notes
        end

        numbers[#numbers + 1] = tostring(section.note_ids[note])
    end

    drop.notes = table.concat(entry.notes, "\n\n")
    drop.note_marker = table.concat(numbers, ",")

    -- pages with a few drop tables for different levels repeat rows like bones, theres no way
    -- to tell those tables apart here so an exact repeat is just left out
    local key = table.concat({ drop.name, drop.quantity, drop.rate, drop.notes }, "\0")

    if not section.seen[key] then
        section.seen[key] = true
        section.drops[#section.drops + 1] = drop
    end
end

---@param rows table[]? records from the dropsline bucket for one page
---@return DropSection[]? sections empty when the page has no drops
---@return string? problem
function dropsline.sections(rows)
    if type(rows) ~= "table" or #rows > MAX_ROWS then
        return nil, "The Wiki returned an invalid list of drops."
    end

    local entries = {}
    local modes, known = {}, {}

    for _, row in ipairs(rows) do
        local entry, problem = read_row(row)

        if entry == nil then
            return nil, problem
        end

        if entry then
            entries[#entries + 1] = entry

            for _, mode in ipairs(entry.modes) do
                if not known[mode] then
                    known[mode] = true
                    modes[#modes + 1] = mode
                end
            end
        end
    end

    -- with just one mode a picker would be pointless, so name the sections like a plain page
    local split = #modes > 1
    local groups = split and modes or { "" }
    local by_key = {}

    local function section_for(mode, rare)
        local key = mode .. (rare and "\0rare" or "")

        if not by_key[key] then
            local title = rare and "Rare drop table" or "Drops"
            by_key[key] = {
                title = mode ~= "" and mode .. " / " .. title or title,
                drops = {},
                notes = {},
                note_ids = {},
                seen = {},
            }
        end

        return by_key[key]
    end

    for _, entry in ipairs(entries) do
        -- a row with no mode on a page that has modes is a drop for all of them
        local targets = split and #entry.modes > 0 and entry.modes or groups

        for _, mode in ipairs(targets) do
            add_drop(section_for(mode, entry.rare), entry)
        end
    end

    -- each modes sections stay next to each other, main drops before the rare drop table
    local sections = {}

    for _, mode in ipairs(groups) do
        for _, rare in ipairs({ false, true }) do
            local section = by_key[mode .. (rare and "\0rare" or "")]

            if section then
                section.seen = nil
                sections[#sections + 1] = section
            end
        end
    end

    return sections
end

return dropsline
