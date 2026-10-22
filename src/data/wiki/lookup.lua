-- turns a clicked npc into a full drop table from the wiki, for monsters that arent in the
-- saved bundle yet. only bucket queries, never the full page
--
-- four steps, each one waits for the last:
--   1. find the monsters page in the infobox_monster bucket by npc id (or exact name if the
--      id isnt on the wiki)
--   2. get that pages rows from the dropsline bucket and group them by mode
--   3. get its map pins from the coordinates bucket for the locations tab
--   4. look up item ids for the drops in batches so the table can show item icons
--      (skipped when the page has no drops)

local clock = require("src/utils/cache_clock")
local http = require("src/data/wiki/http")
local queries = require("src/data/wiki/queries")
local wiki_response = require("src/data/wiki/response")
local dropsline = require("src/data/wiki/dropsline")
local spawn_locations = require("src/data/wiki/spawn_locations")

---@class MonsterResult
---@field title string wiki page title
---@field info table infobox values for the first variant
---@field variants table[] infobox values for every variant on the page
---@field sections DropSection[] empty when the page has no drops that can be showed
---@field no_drops "none"|"unreadable"|"not_covered"|nil why sections is empty, nil when it isnt
---@field locations MonsterLocation[]? nil only for saved lookups from older versions
---@field no_locations "none"|"unreadable"|nil why locations is empty

local lookup = {}

-- item names per request, keeps each query url well short of the path limit in the policy
local ITEM_BATCH_SIZE = 40

local function choose_monster(rows)
    if #rows == 0 then
        return nil
    end

    local first = rows[1]

    if type(first) ~= "table" or type(first.page_name) ~= "string" or first.page_name == "" then
        return nil, "The Wiki returned an invalid monster record."
    end

    -- rows for one page are variants; different pages need disambiguation
    for _, row in ipairs(rows) do
        if type(row) ~= "table" or type(row.page_name) ~= "string" or row.page_name == "" then
            return nil, "The Wiki returned an invalid monster record."
        end

        if row.page_name ~= first.page_name then
            return nil, "The Wiki has several matches for this NPC."
        end
    end

    local variants = {}

    for _, row in ipairs(rows) do
        local info, problem = wiki_response.monster_info(row.json)

        if not info then
            return nil, problem
        end

        variants[#variants + 1] = info
    end

    return { title = first.page_name, info = variants[1], variants = variants }
end

-- use Wiki page titles for ID queries; displayed names can include membership or noted suffixes
local function collect_item_names(sections)
    local seen = {}
    local names = {}

    for _, section in ipairs(sections) do
        for _, drop in ipairs(section.drops) do
            if not seen[drop.wiki_name] then
                seen[drop.wiki_name] = true
                names[#names + 1] = drop.wiki_name
            end
        end
    end

    return names
end

local function apply_item_ids(sections, item_ids)
    for _, section in ipairs(sections) do
        for _, drop in ipairs(section.drops) do
            drop.item_id = item_ids[drop.wiki_name]
        end
    end
end

-- icons are optional enrichment. keep the parsed drops and IDs from earlier batches
-- if a later batch fails, rather than losing the whole lookup or sending more requests
local function finish_item_resolution(result, item_ids, on_complete, problem)
    apply_item_ids(result.sections, item_ids)

    if problem then
        log(
            "Monster Lookup: some item icons could not be loaded; showing available data. "
                .. problem
        )
    end

    on_complete(result)
end

local function request_item_batch(result, names, offset, item_ids, on_complete)
    if offset > #names then
        finish_item_resolution(result, item_ids, on_complete)
        return
    end

    local batch = {}

    for index = offset, math.min(offset + ITEM_BATCH_SIZE - 1, #names) do
        batch[#batch + 1] = names[index]
    end

    http.get(queries.items(batch), function(response, problem)
        local resolved

        if response then
            resolved, problem = wiki_response.item_ids(response)
        end

        if not resolved then
            finish_item_resolution(result, item_ids, on_complete, problem)
            return
        end

        for name, item_id in pairs(resolved) do
            item_ids[name] = item_id
        end

        request_item_batch(result, names, offset + #batch, item_ids, on_complete)
    end)
end

-- a failed bucket request fails the whole lookup, so a half loaded monster never gets cached
local function request_rows(query, on_complete)
    http.get(query, function(response, problem)
        if not response then
            on_complete(nil, problem)
            return
        end

        on_complete(wiki_response.bucket(response))
    end)
end

local function request_spawns(result, on_complete)
    request_rows(queries.spawns(result.title), function(rows, problem)
        if not rows then
            on_complete(nil, problem)
            return
        end

        result.locations, result.no_locations = spawn_locations.parse(rows)

        if not result.locations then
            on_complete(nil, "The Wiki returned an invalid list of spawn locations.")
            return
        end

        -- plenty of monsters just dont drop anything. thats still a good result, the Monster
        -- info tab has stats to show and the drops tab says why its empty instead of an error
        if #result.sections == 0 then
            result.no_drops = "none"
            on_complete(result)
            return
        end

        request_item_batch(result, collect_item_names(result.sections), 1, {}, on_complete)
    end)
end

local function request_drops(result, on_complete)
    request_rows(queries.drops(result.title), function(rows, problem)
        local sections

        if rows then
            sections, problem = dropsline.sections(rows)
        end

        if not sections then
            on_complete(nil, problem)
            return
        end

        result.sections = sections
        request_spawns(result, on_complete)
    end)
end

local function resolve_monster(monster, field, value, allow_fallback, on_complete)
    http.get(queries.monster(field, value), function(response, problem)
        if not response then
            on_complete(nil, problem)
            return
        end

        local rows, response_problem = wiki_response.bucket(response)

        if not rows then
            on_complete(nil, response_problem)
            return
        end

        local result, match_problem = choose_monster(rows)

        if result then
            request_drops(result, on_complete)
        elseif match_problem then
            on_complete(nil, match_problem)
        elseif allow_fallback then
            -- only an empty ID match warrants trying the name; ambiguity or bad data stays visible
            resolve_monster(monster, "page_name", monster.name, false, on_complete)
        else
            on_complete(nil, "No matching monster was found on the RuneScape Wiki.")
        end
    end)
end

---starts a lookup, anything still running from a previous one is cancelled first
---@param monster MonsterSelection
---@param on_complete fun(result: MonsterResult?, problem: string?)
function lookup.fetch(monster, on_complete)
    http.cancel()
    if monster.wiki_title then
        resolve_monster(monster, "page_name", monster.wiki_title, false, on_complete)
    else
        resolve_monster(monster, "id", monster.npc_id, true, on_complete)
    end
end

function lookup.synchronize_clock(on_complete)
    http.cancel()
    http.get(queries.time(), function(response, problem)
        if not response then
            on_complete(false, problem)
        elseif clock.synchronize(response.curtimestamp) then
            on_complete(true)
        else
            on_complete(false, "The Wiki did not return a valid time for checking saved data.")
        end
    end)
end

lookup.cancel = http.cancel
lookup.start = http.start
lookup.stop = http.stop
return lookup
