-- ranks bundled monster variants by one stat for the Top stats search, read from
-- src/data/bundle/stats.lua (built by tools/search_index.lua)
--
-- raw xp per kill mostly lists big bosses, so the level filters matter as much as the stat
-- itself, and xp per life point is there to compare quick kills against damage sponges

local bundle = require("src/data/bundle")
local monster_info = require("src/data/monster_info")
local matcher = require("src/utils/item_search")

local stat_rankings = {}

-- must match tools/search_index.lua
local FORMAT = 1
local MAX_RESULTS = 50

local function thousands(text)
    local whole, rest = text:match("^(%d+)(.*)$")

    if not whole then
        return text
    end

    return whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") .. rest
end

-- "1212.5" -> "1,212.5", whole numbers lose the decimals
local function number(value, places)
    local text = string.format("%." .. (places or 1) .. "f", value):gsub("%.?0+$", "")
    return thousands(text)
end

---@class StatChoice
---@field label string shown in the stat dropdown
---@field value fun(row: table): number?
---@field show fun(value: number): string

---@type StatChoice[]
stat_rankings.STATS = {
    {
        label = "Combat XP",
        value = function(row)
            return row.xp
        end,
        show = function(value)
            return number(value) .. " XP"
        end,
    },
    {
        label = "Combat XP per life point",
        value = function(row)
            return row.xp and row.life_points and row.life_points > 0 and row.xp / row.life_points
                or nil
        end,
        show = function(value)
            return number(value, 3) .. " XP per LP"
        end,
    },
    {
        label = "Slayer XP",
        value = function(row)
            return row.slayer_xp
        end,
        show = function(value)
            return number(value) .. " Slayer XP"
        end,
    },
    {
        label = "Life points",
        value = function(row)
            return row.life_points
        end,
        show = function(value)
            return number(value) .. " LP"
        end,
    },
    {
        label = "Combat level",
        value = function(row)
            return row.combat_level
        end,
        show = function(value)
            return "Level " .. number(value)
        end,
    },
    {
        label = "Max hit",
        value = function(row)
            return row.max_hit
        end,
        show = function(value)
            return number(value) .. " max hit"
        end,
    },
}

local rows
local unavailable = false

local function field_number(text, scale)
    local value = text ~= "" and tonumber(text, 36) or nil
    return value and value / (scale or 1) or nil
end

local function load()
    if rows or unavailable then
        return rows
    end

    local ok, problem = pcall(function()
        local raw = require("src/data/bundle/stats")
        assert(type(raw) == "table" and raw.format == FORMAT, "unexpected stats format")
        local strings = require("src/data/bundle/strings")
        local titles = bundle.titles()
        local list = {}

        for _, text in ipairs(raw.rows) do
            local fields = {}

            for field in (text .. "^"):gmatch("(.-)%^") do
                fields[#fields + 1] = field
            end

            local title = titles[tonumber(fields[1], 36)]

            if title then
                local variant

                -- named the same way as the Monster info variant dropdown
                if fields[2] ~= "" then
                    local anchor = fields[3] ~= "" and strings[tonumber(fields[3], 36) + 1] or nil
                    variant = monster_info.variant_name(
                        { version_anchor = anchor },
                        tonumber(fields[2], 36)
                    )
                end

                local categories = {}

                for category in fields[10]:gmatch("[^,]+") do
                    categories[#categories + 1] = strings[tonumber(category, 36) + 1]
                end

                list[#list + 1] = {
                    title = title,
                    variant = variant,
                    -- the wiki puts 0 for some it doesnt know the level of
                    combat_level = field_number(fields[4] ~= "0" and fields[4] or ""),
                    life_points = field_number(fields[5]),
                    xp = field_number(fields[6], 100),
                    slayer_xp = field_number(fields[7], 100),
                    slayer_level = field_number(fields[8]),
                    max_hit = field_number(fields[9]),
                    -- a boss, boss minion or instanced fight, see tools/search_index.lua
                    boss = fields[11] == "1",
                    -- the name filter also matches slayer categories, eg "dragons"
                    searchable = table.concat(
                        { title, variant or "", table.concat(categories, " ") },
                        " "
                    ),
                }
            end
        end

        rows = list
    end)

    if not ok then
        unavailable = true
        log("Monster Lookup: top stats unavailable. " .. tostring(problem))
    end

    return rows
end

---@class StatFilters
---@field query string? only names (or slayer categories) matching this, like monster search
---@field max_combat integer? leave out monsters above this combat level
---@field max_slayer integer? leave out monsters that need a higher slayer level
---@field bosses "hide"|"only"|nil bosses and instanced fights, nil keeps everything

---@class StatResult
---@field title string wiki page of the monster
---@field variant string? variant name when the page has several
---@field label string the result row text

---@param stat integer position in STATS
---@param filters StatFilters?
---@return StatResult[] results best first, at most 50
---@return integer total how many variants matched the filters
function stat_rankings.rank(stat, filters)
    local choice = stat_rankings.STATS[stat] or stat_rankings.STATS[1]
    filters = filters or {}
    local query = filters.query and filters.query:match("^%s*(.-)%s*$") or ""
    local matches = query ~= "" and matcher.compile(query) or nil
    local ranked = {}

    for _, row in ipairs(load() or {}) do
        local value = choice.value(row)

        if
            value
            -- an unknown combat level could be anything, so a level cap leaves it out
            and (not filters.max_combat or (row.combat_level or math.huge) <= filters.max_combat)
            and (not filters.max_slayer or (row.slayer_level or 1) <= filters.max_slayer)
            and not (filters.bosses == "hide" and row.boss)
            and not (filters.bosses == "only" and not row.boss)
        then
            if matches then
                row.prepared = row.prepared or matcher.prepare(row.searchable)
            end

            if not matches or matches(row.prepared) then
                ranked[#ranked + 1] = { row = row, value = value }
            end
        end
    end

    table.sort(ranked, function(a, b)
        if a.value ~= b.value then
            return a.value > b.value
        end
        return a.row.searchable < b.row.searchable
    end)

    local results = {}

    for index = 1, math.min(#ranked, MAX_RESULTS) do
        local row, value = ranked[index].row, ranked[index].value
        local name = row.variant and (row.title .. " (" .. row.variant .. ")") or row.title
        local details = { choice.show(value) }

        if choice.label ~= "Combat level" and row.combat_level then
            details[#details + 1] = "combat " .. number(row.combat_level)
        end

        if choice.label ~= "Life points" and row.life_points then
            details[#details + 1] = number(row.life_points) .. " LP"
        end

        results[index] = {
            title = row.title,
            variant = row.variant,
            label = name .. " - " .. table.concat(details, " | "),
        }
    end

    return results, #ranked
end

return stat_rankings
