-- the static monster data export returned by this plugins main.lua
--
-- rules this file keeps, because the client hands the same tables to every plugin (checked
-- in the client, nothing is copied between plugins):
--   - everything returned is a fresh table, never one the core keeps. callers can change
--     what they get, it wont reach anyone else
--   - the export only holds functions, nothing here reads its own fields back (a plugin
--     could overwrite them for everyone)
--   - static data only: no requests, no storage, no subscriptions. searches do as much work
--     as the caller asks for per step() so the caller owns the timing
--
-- the shapes returned here are the public schema (SCHEMA). the packed bundle format behind
-- them (src/bundle/) is free to change without touching this

local bundle = require("src/data/library/bundle/reader")
local names = require("src/data/library/monsters/names")
local identity = require("src/data/library/monsters/identity")
local monster_info = require("src/data/library/monsters/info")
local drop_index = require("src/data/library/search/drops")
local stat_rankings = require("src/data/library/search/stats")
local scan = require("src/data/library/search/scan")
local matcher = require("src/data/library/search/matcher")
local location_map = require("src/data/library/locations/resolve")
local coordinates = require("src/data/library/locations/coordinates")
local map_names = require("src/data/library/locations/dungeons/map_names")
local drop_groups = require("src/data/library/drops/groups")
local drop_odds = require("src/data/library/drops/odds")
local kill_value = require("src/data/library/drops/value")

-- bump when a returned shape changes in a way callers would notice
local SCHEMA = 1

local api = {}

local function copy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}

    for key, item in pairs(value) do
        result[key] = copy(item)
    end

    return result
end

-- a selection callers pass in, read and copied so its later changes dont matter
local function selection_of(monster)
    if type(monster) == "string" then
        return { name = monster, wiki_title = monster }
    end

    if type(monster) ~= "table" then
        return nil
    end

    return {
        name = type(monster.name) == "string" and monster.name or monster.wiki_title,
        npc_id = math.type(monster.npc_id) == "integer" and monster.npc_id or nil,
        wiki_title = type(monster.wiki_title) == "string" and monster.wiki_title or nil,
    }
end

---@class CoreInfo
---@field schema integer public schema version
---@field built string? date the bundle was built
---@field monsters integer bundled pages

---@return CoreInfo
function api.info()
    return { schema = SCHEMA, built = bundle.built(), monsters = #bundle.titles() }
end

---what the data knows about a monster. status is one of "covered", "no_drops" (known, no
---drops so not bundled), "excluded" (known, left out: quest, event and other one off
---monsters), "ambiguous" (the npc id is on several pages) or "unknown" (newer than the data)
---@param monster MonsterSelection|string|nil a selection, or a wiki page title
---@return { status: string }
function api.coverage(monster)
    local selection = selection_of(monster)
    return { status = selection and bundle.coverage(selection).status or "unknown" }
end

---the full record for a covered monster: title, info (first variant), variants, sections
---(drop tables), locations. nil plus the coverage when its not covered
---@param monster MonsterSelection|string
---@return MonsterResult? record a fresh copy every call
---@return { status: string } coverage
function api.monster(monster)
    local selection = selection_of(monster)
    local coverage = selection and bundle.coverage(selection) or { status = "unknown" }

    if coverage.status ~= "covered" then
        return nil, { status = coverage.status }
    end

    -- each load decodes a new copy, nothing in it is shared with the core
    local record = bundle.load(coverage.page)
    return record, { status = record and "covered" or "unknown" }
end

---every bundled wiki page title, sorted the same way the bundle stores them
---@return string[]
function api.titles()
    return copy(bundle.titles())
end

---the npc ids bundled for a page, eg for showing its model
---@param title string
---@return integer[]
function api.npc_ids(title)
    return copy(bundle.npc_ids(title))
end

-- identity: how monsters are told apart and grouped

---the key a monster is saved and matched under: "page:<title>" for a wiki page, "<npc id>:<name>"
---for a clicked npc. a string is taken as a wiki page title
---@param monster MonsterSelection|string
---@return string?
function api.identity_key(monster)
    if type(monster) == "string" then
        return identity.key({ name = monster, wiki_title = monster })
    end

    return type(monster) == "table" and identity.key(monster) or nil
end

---the selection a key from identity_key stands for ({ name, npc_id } or { name, wiki_title }),
---nil for a key it didnt make. a new table, add your own fields to it if you like
---@param key string
---@return table?
function api.identity_selection(key)
    return type(key) == "string" and identity.selection(key) or nil
end

---the base name every variant of a monster shares, "Goblin (level 5)#Armed" -> "goblin"
function api.family(name)
    return identity.family(name)
end

-- searches

-- wraps a core scan so results come back as fresh tables the caller owns
local function stepped(entries, query, to_result)
    local search = scan.new(entries, query)
    local wrapper = {}

    ---does up to budget more rows, true once the search is finished
    function wrapper.step(budget)
        return search.step(math.max(1, math.floor(tonumber(budget) or 250)))
    end

    function wrapper.done()
        return search.done()
    end

    ---the best matches so far, best first, at most 50
    function wrapper.results()
        local results = {}

        for index, entry in ipairs(search.results()) do
            results[index] = to_result(entry)
        end

        return results
    end

    return wrapper
end

---a monster name search. nothing runs until step() is called, so the caller decides how
---much to do per tick (the search window does 250 rows)
---@param query string fuzzy words, or * and ? wildcards
function api.search_monsters(query)
    local entries = {}

    for index, title in ipairs(names) do
        entries[index] = { name = title }
    end

    return stepped(entries, tostring(query or ""), function(entry)
        return { name = entry.name, wiki_title = entry.name }
    end)
end

---every item a bundled monster drops, sorted by name, as new tables
---@return { name: string, item_id: integer?, count: integer }[]
function api.items()
    local items = {}

    for index = 1, #drop_index.items() do
        items[index] = drop_index.item(index)
    end

    return items
end

---a bounded name search over your own entries (anything with a name), the same matching and
---ranking the monster and item searches use. nothing runs until step(budget). results() are
---your own entries, best first. see src/search/scan.lua for the options
---@param entries table[]
---@param query string
---@param options ScanOptions?
function api.scan(entries, query, options)
    return scan.new(entries, tostring(query or ""), options)
end

---a name prepared for name_matcher, prepare once and match it against many queries
function api.prepare_name(name)
    return matcher.prepare(tostring(name or ""))
end

---a function that says whether a prepared name matches the query: fuzzy words, or * and ?
---wildcards
function api.name_matcher(query)
    return matcher.compile(tostring(query or ""))
end

---a dropped item name search, same as search_monsters
---@param query string
function api.search_items(query)
    local entries = {}

    for index, item in ipairs(drop_index.items()) do
        entries[index] = { name = item.name, position = index }
    end

    return stepped(entries, tostring(query or ""), function(entry)
        return drop_index.item(entry.position)
    end)
end

---the bundled monsters that drop an item (exact name, any case), best chance first, at most
---50. total is how many drop it, which can be more than listed
---@param item_name string
---@return { item: table?, total: integer, droppers: Dropper[] }
function api.droppers(item_name)
    local position = drop_index.find(item_name)
    local item = position and drop_index.item(position)

    if not position or not item then
        return { total = 0, droppers = {} }
    end

    return { item = item, total = item.count, droppers = drop_index.droppers(position) }
end

---what stat_ranking can rank by, ids for stat_ranking
---@return { id: integer, label: string }[]
function api.stat_choices()
    local choices = {}

    for index, choice in ipairs(stat_rankings.STATS) do
        choices[index] = { id = index, label = choice.label }
    end

    return choices
end

---bundled monster variants ranked by one stat, best first, at most 50
---@param stat integer an id from stat_choices
---@param filters StatFilters?
---@return StatResult[] results
---@return integer total how many matched the filters
function api.stat_ranking(stat, filters)
    local results, total = stat_rankings.rank(stat, copy(filters))
    return results, total
end

-- maths over drop tables. they read the sections passed in and return new tables, so they
-- work on a record from monster() or on drops the caller got anywhere else

---a monsters variants (what the info tab variant picker lists) and their names
function api.variants(record)
    local variants = {}

    for index, info in ipairs(monster_info.variants(record or {})) do
        variants[index] = { name = monster_info.variant_name(info, index), info = copy(info) }
    end

    return variants
end

---the stat sections the Monster info tab shows for one variant, see src/monsters/info.lua
---@param info table one variants infobox values, eg variants(record)[1].info
---@param title string? the page title, for the Slayer Codex note
function api.stat_sections(info, title)
    return monster_info.build(copy(info or {}), title)
end

---the drop modes a page splits into (normal / hard mode, enrage tables), nil if it doesnt
api.drop_modes = function(sections)
    return drop_groups.mode_groups(sections)
end

---chance per roll from 0 to 1, nil when its a word like Rare
api.drop_chance = function(drop)
    return drop_odds.chance(drop)
end

---fills chance, rolls and the quantity bounds on a drop you made, from its rate (a wiki
---percent like "3 x 0.0667" when is_percent, or a fraction like "1/128") and its quantity
function api.fill_odds(drop, rate, is_percent)
    drop_odds.fill(drop, rate, is_percent)
end

---a drop sections text without the wikis "the average kill is worth" sentences, theyre at
---the prices from when the page was saved
api.without_wiki_averages = function(text)
    return kill_value.without_wiki_averages(text)
end

-- locations: where the wiki maps put a monster, as game tiles. static data only, finding a
-- way there is up to the caller (Monster Lookup's marker, or a navigation plugin)

---true when a wiki map pin has a usable map id, floor and x/z
function api.location_valid(map)
    return location_map.valid(map)
end

---what a location row from a record can be navigated to: the tile to point at, its label and
---tooltip, and whether its the spawn or a dungeon entrance on the way. nil and a reason when
---it cant be
---@return table? resolution
---@return string? reason
function api.location_resolve(location)
    local resolution, reason = location_map.resolve(location)
    return copy(resolution), reason
end

---just the tile from location_resolve, or nil
function api.location_target(location)
    return copy(location_map.target(location))
end

---true when a game tile is on this wiki map
function api.map_contains(map_id, point)
    return coordinates.contains(map_id, point)
end

---true for wiki maps that draw separate areas on one map
function api.map_is_shared(map_id)
    return coordinates.is_shared(map_id)
end

---which connected part of a shared map a tile is in, nil when the map isnt split
function api.map_region(map_id, point)
    return coordinates.region(map_id, point)
end

---true when two tiles on one map can be walked between (not split by a teleport or stairs)
function api.maps_connected(map_id, first, second)
    return coordinates.connected(map_id, first, second)
end

---a wiki map pin as a game tile { level, x, z }, nil when it cant be converted
function api.map_world(map)
    return copy(coordinates.world(map))
end

---the wikis name for a map id, nil when it has none
function api.map_name(map_id)
    return map_names[map_id]
end

---every map id with a name, as a new table
function api.map_names()
    return copy(map_names)
end

---the average value of one kill for the sections given (one mode), saved prices unless
---unit_price gives a better one for an item id
---@param unit_price (fun(item_id: integer, reference: number?): number?)?
api.kill_value = function(sections, unit_price)
    return kill_value.calculate(sections, unit_price)
end

api.SCHEMA = SCHEMA
return api
