-- Local name search: typing never sends a request. Result selection uses the normal lookup.
local names = require("src/data/monster_names")
local cache = require("src/data/monster_cache")
local identity = require("src/utils/monster_identity")
local matcher = require("src/utils/item_search")
local clock = require("src/utils/cache_clock")

local search = {}
local next_subscription = 0
local DEBOUNCE_TICKS = math.ceil(0.15 * clock.TICKS_PER_SECOND)
local ROWS_PER_TICK = 250
local MAX_RESULTS = 50
local LEGACY_READS_PER_TICK = 3

local function normalize(text)
    return tostring(text or ""):sub(1, 80):gsub("[%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function build_index(saved_only)
    local entries, seen = {}, {}
    local function add(monster, saved)
        local key = identity.key(monster)

        if seen[key] then
            seen[key].saved = seen[key].saved or saved
        else
            local entry = {
                monster = monster,
                label = monster.name,
                key = key,
                saved = saved,
                summary = monster.summary,
                resolved = monster.summary ~= nil,
            }
            seen[key] = entry
            entries[#entries + 1] = entry
        end
    end

    if not saved_only then
        for _, title in ipairs(names) do
            add({ name = title, wiki_title = title }, false)
        end
    end

    for _, monster in ipairs(cache.list(saved_only)) do
        -- NPC names and levels do not identify their Wiki page (eg Bloodveld).
        -- Keep the picker page-based; clicked NPCs retain their separate cache identity.
        if saved_only then
            add(monster, true)
        elseif monster.wiki_title and seen[identity.key(monster)] then
            add({ name = monster.wiki_title, wiki_title = monster.wiki_title }, true)
        end
    end
    return entries
end

local function score(entry, query)
    local name = entry.prepared.name
    local rank = name == query and 0
        or name:sub(1, #query) == query and 10
        or name:find(query, 1, true) and 20
        or 30
    return rank + (entry.saved and 0 or 1)
end

local function insert_match(matches, entry, rank)
    local candidate = { entry = entry, score = rank }
    local position = #matches + 1

    for index, current in ipairs(matches) do
        if rank < current.score or (rank == current.score and entry.key < current.entry.key) then
            position = index
            break
        end
    end

    if position <= MAX_RESULTS then
        table.insert(matches, position, candidate)

        if #matches > MAX_RESULTS then
            table.remove(matches)
        end
    end
end

local function publish(state, results, message)
    state.results = results
    state.on_update(results, message)
end

local function prepare_saved_entry(entry)
    local summary = entry.summary

    if not summary then
        return false
    end

    if entry.base_label then
        entry.label = entry.base_label
        return true
    end

    entry.label = summary.title

    if summary.variant and summary.variant ~= "" and summary.variant ~= summary.title then
        entry.label = entry.label .. " - " .. summary.variant
    end

    entry.base_label = entry.label
    local searchable = entry.label .. (summary.level and (" Level " .. summary.level) or "")
    entry.prepared = matcher.prepare(searchable)
    return true
end

local function distinguish_saved_results(results)
    local counts = {}

    for _, entry in ipairs(results) do
        counts[entry.label] = (counts[entry.label] or 0) + 1
    end

    local variants = {}

    for _, entry in ipairs(results) do
        local label = entry.label

        if counts[label] > 1 then
            variants[label] = (variants[label] or 0) + 1
            entry.label = label
                .. " - "
                .. (entry.monster.wiki_title and "All variants" or "Variant " .. variants[label])
        end
    end
end

local function scan_batch(state)
    local last = math.min(state.position + ROWS_PER_TICK - 1, #state.index)

    local reads = 0

    for index = state.position, last do
        local entry = state.index[index]

        if state.saved_only and not entry.resolved then
            if reads >= LEGACY_READS_PER_TICK then
                break
            end

            entry.summary = cache.describe(entry.monster)
            entry.resolved = true
            reads = reads + 1
        end

        local available = not state.saved_only or prepare_saved_entry(entry)
        entry.prepared = entry.prepared or matcher.prepare(entry.monster.name)

        if available and state.matches(entry.prepared) then
            insert_match(state.top, entry, score(entry, state.key))
        end

        state.position = index + 1
    end

    if #state.index == 0 then
        state.position = 1
    end

    if state.position <= #state.index then
        return
    end

    state.position = nil
    local results = {}

    for _, candidate in ipairs(state.top) do
        results[#results + 1] = candidate.entry
    end

    if state.saved_only then
        distinguish_saved_results(results)
    end

    publish(
        state,
        results,
        #results == 0 and "No monsters match your search."
            or state.saved_only and "Select a monster to refresh its Wiki data."
            or "Select a monster."
    )
end

function search.new(on_update, saved_only)
    next_subscription = next_subscription + 1
    local subscription = "monster_lookup_search_" .. next_subscription
    local state = { tick = 0, on_update = on_update, results = {}, saved_only = saved_only == true }
    local controller = {}

    function controller.get_query()
        return state.query or ""
    end

    function controller.set_query(text)
        if not state.started then
            return
        end

        local query = normalize(text)
        local key = query:lower()

        if key == state.key then
            return
        end

        state.query, state.key, state.due, state.position = query, key, nil, nil
        if #query >= 3 or (state.saved_only and #query > 0) then
            state.matches = matcher.compile(query)
            state.due = state.tick + DEBOUNCE_TICKS
            publish(state, {}, "Searching names...")
        else
            publish(
                state,
                {},
                state.saved_only and "Search saved monsters by name or location."
                    or "Type at least 3 characters to search monsters."
            )
        end
    end

    function controller.stop()
        state.started = false
        state.due, state.position = nil, nil
        Event.Logic.Unsubscribe(subscription)
    end

    function controller.choose(result)
        if state.started then
            -- Only buttons from the current results can select a monster.
            for _, current in ipairs(state.results) do
                if current == result then
                    local monster = result.monster
                    controller.stop()
                    return {
                        name = monster.name,
                        npc_id = monster.npc_id,
                        wiki_title = monster.wiki_title,
                    }
                end
            end
        end
    end

    function controller.start()
        if state.started then
            return
        end

        state.index = build_index(state.saved_only)
        state.started = true
        Event.Logic.Subscribe(subscription, function()
            state.tick = state.tick + 1

            if state.due and state.tick >= state.due then
                state.due = nil
                state.position, state.top = 1, {}
            end

            if state.position then
                scan_batch(state)
            end
        end)
        local previous = state.query or ""
        state.key = nil
        controller.set_query(previous)
    end

    return controller
end

return search
