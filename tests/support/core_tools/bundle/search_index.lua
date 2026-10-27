-- builds the two small search indexes that ship next to the bundle, from the same pages
-- build.lua packs:
--
--   drops.lua  every dropped item and the monsters that drop it, best chance first, so the
--              search window can answer "who drops this" without unpacking every page
--   stats.lua  the numbers the Top stats search ranks by, one row per monster variant
--
-- both are lists of short strings. numbers are base36, and text points into the bundles
-- strings.lua (its 0 based position) instead of being copied, the plugin loads that file for
-- the first lookup anyway. the readers are src/search/drops.lua and src/search/stats.lua

local drop_groups = require("src/data/library/drops/groups")
local base36 = require("tests/support/core_tools/bundle/encoder").base36

local search_index = {}

-- must match FORMAT in the two readers
search_index.FORMAT = 1
-- droppers kept per item. nobody reads past this many and coins alone has 900+
search_index.MAX_DROPPERS = 50

-- wiki text has commas, slashes, tildes and semicolons in it ("~1/1,000; 1/950") so the
-- separators are two characters it never uses, the build stops if that ever changes. keep
-- these the same as the readers
search_index.FIELD = "^"
search_index.ROW = "`"

-- rough chances for the wikis rarity words, only used to sort them amongst real fractions
local WORDS = {
    always = 1,
    common = 1 / 8,
    uncommon = 1 / 32,
    rare = 1 / 128,
    ["very rare"] = 1 / 512,
}

---chance of a drop as a number from 0 to 1, 0 when the rate cant be read
---@param rate string eg "1/128", "86/1,000", "1/384; 1/378", "Always", "Rare"
---@return number
function search_index.chance(rate)
    local text = tostring(rate or ""):lower():gsub(",", "")
    local top, bottom = text:match("(%d+%.?%d*)%s*/%s*(%d+%.?%d*)")

    if top and tonumber(bottom) > 0 then
        return math.min(1, tonumber(top) / tonumber(bottom))
    end

    local percent = text:match("(%d+%.?%d*)%s*%%")

    if percent then
        return math.min(1, tonumber(percent) / 100)
    end

    return WORDS[text:match("^%s*(.-)%s*$")] or 0
end

-- the page tables mark members and free-to-play rows as "Bronze spear (m)"/"Bronze dagger(f)",
-- both are still the same item to search for
function search_index.item_name(name)
    return (name:gsub("%s*%([mf]%)$", ""))
end

local function check_text(value)
    assert(
        not value:find("[%^`%c]"),
        "search index text cant contain ^ ` or control characters: " .. value
    )
    return value
end

-- position of a string in strings.lua, or nil when the bundle never used it
local function string_ref(string_index, value)
    local position = string_index[check_text(value)]
    return position and base36(position) or nil
end

-- which mode each section is in, nil for pages without a mode picker and for tables every
-- mode shares (eg Amascuts tertiary drops)
local function section_modes(sections)
    local groups = drop_groups.mode_groups(sections)
    local modes = {}

    if not groups then
        return modes
    end

    for _, section in ipairs(sections) do
        local found = {}

        for _, group in ipairs(groups) do
            for _, member in ipairs(group.sections) do
                if member == section then
                    found[#found + 1] = group.name
                    break
                end
            end
        end

        modes[section] = #found < #groups and found[1] or nil
    end

    return modes
end

local function lua_string_list(values)
    local lines = {}

    for _, value in ipairs(values) do
        lines[#lines + 1] = string.format("%q", value) .. ","
    end

    return "{\n" .. table.concat(lines, "\n") .. "\n}"
end

local function lua_file(header, fields)
    local parts = { header, "return {\n", "format = ", search_index.FORMAT, ",\n" }

    for _, field in ipairs(fields) do
        parts[#parts + 1] = field[1] .. " = " .. field[2] .. ",\n"
    end

    parts[#parts + 1] = "}\n"
    return table.concat(parts)
end

local function collect_droppers(pages)
    local by_item, items = {}, {}

    for page_number, page in ipairs(pages) do
        local modes = section_modes(page.sections)

        for _, section in ipairs(page.sections) do
            for _, drop in ipairs(section.drops) do
                local name = search_index.item_name(drop.name)

                if name ~= "" and name ~= "Nothing" then
                    local item = by_item[name]

                    if not item then
                        item = { name = name, best = {}, droppers = {} }
                        by_item[name] = item
                        items[#items + 1] = item
                    end

                    item.item_id = item.item_id or drop.item_id
                    local chance = search_index.chance(drop.rate)
                    local best = item.best[page_number]

                    -- one row per monster, its best chance at the item
                    if not best then
                        best = { page = page_number, chance = -1 }
                        item.best[page_number] = best
                        item.droppers[#item.droppers + 1] = best
                    end

                    if chance > best.chance then
                        best.chance, best.rate = chance, drop.rate
                        best.quantity, best.mode = drop.quantity, modes[section]
                    end
                end
            end
        end
    end

    table.sort(items, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    return items
end

---@param pages MonsterResult[] in bundle page order
---@param header string comment lines for the top of the file
---@param string_index table<string, integer> the encoders string -> 0 based position
---@return string source lua source for src/bundle/generated/drops.lua
---@return table counts item and row counts for the build summary
function search_index.drops(pages, header, string_index)
    local modes, mode_id = {}, {}
    local names, icons, counts, rows = {}, {}, {}, {}
    local kept = 0

    for index, item in ipairs(collect_droppers(pages)) do
        -- best chance first, ties in page order so the build output doesnt shuffle
        table.sort(item.droppers, function(a, b)
            if a.chance ~= b.chance then
                return a.chance > b.chance
            end
            return a.page < b.page
        end)

        local parts = {}

        for position = 1, math.min(#item.droppers, search_index.MAX_DROPPERS) do
            local row = item.droppers[position]
            -- most drops are a single item, an empty quantity means 1
            local fields = {
                base36(row.page),
                assert(string_ref(string_index, row.rate), "rate not in strings"),
                row.quantity ~= "1" and assert(
                    string_ref(string_index, row.quantity),
                    "quantity not in strings"
                ) or "",
            }

            if row.mode then
                if not mode_id[row.mode] then
                    modes[#modes + 1] = check_text(row.mode)
                    mode_id[row.mode] = base36(#modes)
                end
                fields[4] = mode_id[row.mode]
            end

            parts[#parts + 1] = table.concat(fields, search_index.FIELD)
        end

        kept = kept + #parts
        -- the plain name is often in strings already, otherwise it goes in as text
        names[index] = string_ref(string_index, item.name) or ("=" .. item.name)
        icons[index] = item.item_id and base36(item.item_id) or ""
        counts[index] = base36(#item.droppers)
        rows[index] = table.concat(parts, search_index.ROW)
    end

    local source = lua_file(header, {
        { "modes", lua_string_list(modes) },
        { "items", lua_string_list(names) },
        { "icons", '"' .. table.concat(icons, ",") .. '"' },
        { "counts", '"' .. table.concat(counts, ",") .. '"' },
        { "rows", lua_string_list(rows) },
    })

    return source, { items = #names, rows = kept }
end

-- bosses and instanced fights (elite dungeons, raids, dominion tower) take over every top
-- list, so top stats can hide them. the wikis own boss categories catch most, a variant named
-- after a mode ("Story mode", "Hard mode", "Rumble Mode", "1000% enrage") catches the rest
local function is_boss(page, bosses)
    if bosses[page.title] then
        return true
    end

    for _, info in ipairs(page.variants) do
        local anchor = type(info.version_anchor) == "string" and info.version_anchor:lower() or ""

        if anchor:find("%f[%a]mode%f[%A]") or anchor:find("%f[%a]enrage") then
            return true
        end
    end

    return false
end

-- a stat as base36, times scale first so xp keeps its decimals (12.5 xp at 100 -> 1250).
-- empty when the infobox doesnt have it
local function scaled_number(value, scale)
    if type(value) ~= "number" or value < 0 then
        return ""
    end

    return base36(math.floor(value * (scale or 1) + 0.5))
end

local function max_hit(info)
    local best

    for _, style in ipairs({ "melee", "ranged", "magic", "necromancy", "special" }) do
        local value = info[style .. "_max_hit"]

        if type(value) == "number" and (not best or value > best) then
            best = value
        end
    end

    return best
end

---@param pages MonsterResult[] in bundle page order
---@param header string comment lines for the top of the file
---@param string_index table<string, integer> the encoders string -> 0 based position
---@param bosses table<string, boolean>? page titles in the wikis boss categories
---@return string source lua source for src/bundle/generated/stats.lua
---@return integer rows variants written
function search_index.stats(pages, header, string_index, bosses)
    local rows = {}

    for page_number, page in ipairs(pages) do
        local boss = is_boss(page, bosses or {}) and "1" or ""

        for position, info in ipairs(page.variants) do
            local categories = {}

            for _, category in
                ipairs(type(info.slayer_category) == "table" and info.slayer_category or {})
            do
                categories[#categories + 1] = string_ref(string_index, tostring(category))
            end

            -- only pages with several variants need a name, the rest show the page title.
            -- the reader names it the same way the Monster info dropdown does
            local several = #page.variants > 1
            local anchor = several
                    and type(info.version_anchor) == "string"
                    and string_ref(string_index, info.version_anchor)
                or ""

            rows[#rows + 1] = table.concat({
                base36(page_number),
                several and base36(position) or "",
                anchor,
                scaled_number(info.combat_level),
                scaled_number(info.life_points),
                -- xp can have decimals, kept to two places
                scaled_number(info.combat_experience, 100),
                scaled_number(info.slayer_experience, 100),
                scaled_number(info.slayer_level),
                scaled_number(max_hit(info)),
                table.concat(categories, ","),
                boss,
            }, search_index.FIELD)
        end
    end

    return lua_file(header, { { "rows", lua_string_list(rows) } }), #rows
end

return search_index
