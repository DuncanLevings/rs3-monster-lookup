-- turns a clicked npc into a full drop table from the wiki
--
-- three steps, each one waits for the last:
--   1. find the monsters page in the infobox_monster bucket by npc id (or exact name if the
--      id isnt on the wiki)
--   2. fetch that page as rendered html and pull the drop tables out of it
--   3. look up item ids for the drops in batches so the table can show item icons
--      (skipped when the page has no drops)

local http = require("src/data/wiki_http")
local queries = require("src/data/wiki_queries")
local parser = require("src/data/wiki_page")
local json = require("src/utils/json")

---@class MonsterResult
---@field title string wiki page title
---@field info table infobox values for the first variant
---@field variants table[] infobox values for every variant on the page
---@field sections DropSection[] empty when the page has no drops that can be showed
---@field no_drops "none"|"unreadable"|nil why sections is empty, nil when it isnt

local lookup = {}

-- item names per request, keeps each query url well short of the path limit in the policy
local ITEM_BATCH_SIZE = 40

local function choose_monster(rows)
    if type(rows) ~= "table" or #rows == 0 then
        return nil
    end

    local first = rows[1]

    if type(first) ~= "table" or type(first.page_name) ~= "string" then
        return nil, "The Wiki returned an invalid monster record."
    end

    -- several rows for one page are variants, rows from different pages that cannot be choosen between
    for _, row in ipairs(rows) do
        if type(row) ~= "table" or row.page_name ~= first.page_name then
            return nil, "The Wiki has several matches for this NPC."
        end
    end

    local variants = {}

    for _, row in ipairs(rows) do
        variants[#variants + 1] = json.decode(row.json or "{}") or {}
    end

    return { title = first.page_name, info = variants[1], variants = variants }
end

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

local function request_item_batch(result, names, offset, item_ids, on_complete)
    if offset > #names then
        apply_item_ids(result.sections, item_ids)
        on_complete(result)
        return
    end

    local batch = {}

    for index = offset, math.min(offset + ITEM_BATCH_SIZE - 1, #names) do
        batch[#batch + 1] = names[index]
    end

    http.get(queries.items(batch), function(response, problem)
        if not response then
            on_complete(nil, problem)
            return
        end

        for _, item in ipairs(response.bucket or {}) do
            if type(item.item_id) == "table" then
                item_ids[item.page_name] = tonumber(item.item_id[1])
            end
        end

        request_item_batch(result, names, offset + #batch, item_ids, on_complete)
    end)
end

local function request_page(result, on_complete)
    http.get(queries.page(result.title), function(response, problem)
        if not response then
            on_complete(nil, problem)
            return
        end

        local html = response.parse and response.parse.text
        local sections, parse_problem = parser.parse(html)

        if not sections then
            on_complete(nil, parse_problem)
            return
        end

        result.sections = sections

        -- plenty of monsters just dont drop anything. thats still a
        -- good result, the Monster info tab has stats to show and the drops tab says why its
        -- empty instead of showing an error
        if #sections == 0 then
            result.no_drops = parser.has_drop_markup(html) and "unreadable" or "none"
            on_complete(result)
            return
        end

        request_item_batch(result, collect_item_names(sections), 1, {}, on_complete)
    end)
end

local function resolve_monster(monster, field, value, allow_fallback, on_complete)
    http.get(queries.monster(field, value), function(response, problem)
        if not response then
            on_complete(nil, problem)
            return
        end

        local result, match_problem = choose_monster(response.bucket)

        if result then
            request_page(result, on_complete)
        elseif match_problem then
            on_complete(nil, match_problem)
        elseif allow_fallback then
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
    resolve_monster(monster, "id", monster.npc_id, true, on_complete)
end

lookup.cancel = http.cancel
lookup.start = http.start
lookup.stop = http.stop
return lookup
