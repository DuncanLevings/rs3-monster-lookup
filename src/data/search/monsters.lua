-- runs the name searches for the search window and the saved monster picker. the matching
-- and ranking is the cores (Monster Data Core name scanner), this adds what only Monster Lookup
-- has: a tick to spread the work over, typing delay, saved Wiki lookups (they go first, and
-- the picker only lists those) and the messages under the field
--
-- the "items" kind searches dropped item names instead, and an exact item name lists the
-- monsters that drop it (Monster Data Core drop index)

local core = require("src/data/core")
local cache = require("src/data/lookup/cache")
local clock = require("src/utils/cache_clock")
local plural = require("src/utils/number_format").plural

local search = {}
local next_subscription = 0
local DEBOUNCE_TICKS = math.ceil(0.15 * clock.TICKS_PER_SECOND)
local ROWS_PER_TICK = 250
-- older saved lookups have no label in the index, reading one means decoding its payload
local LEGACY_READS_PER_TICK = 3

local function normalize(text)
    return tostring(text or ""):sub(1, 80):gsub("[%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function build_item_index()
    local entries, exact = {}, {}

    for _, item in ipairs(core.items()) do
        local entry = {
            item_name = item.name,
            name = item.name,
            label = item.name .. " - " .. plural(item.count, "monster"),
            key = item.name:lower(),
            saved = false,
            monster = { name = item.name },
        }
        entries[#entries + 1] = entry
        exact[entry.key] = entry
    end

    return entries, exact
end

-- results for an exact item name: who drops it, best chance first
local function dropper_results(entry)
    local found = core.droppers(entry.item_name)
    local count = found.total
    local results = {}

    for _, dropper in ipairs(found.droppers) do
        local name = dropper.mode and (dropper.title .. " (" .. dropper.mode .. ")")
            or dropper.title
        local quantity = dropper.quantity ~= "1" and (" | x" .. dropper.quantity) or ""
        results[#results + 1] = {
            label = name .. " - " .. dropper.rate .. quantity,
            key = dropper.title:lower(),
            monster = { name = dropper.title, wiki_title = dropper.title },
            -- opens the monster on this item, in the mode the chance is for
            focus = { item = entry.item_name, mode = dropper.mode },
        }
    end

    local name = entry.item_name

    -- only if the index and the bundle titles dont agree, eg a half updated install
    if #results == 0 then
        return results, "No monsters in the saved data drop " .. name .. "."
    end

    if #results < count then
        return results,
            "Showing the "
                .. #results
                .. " best chances of the "
                .. count
                .. " monsters that drop "
                .. name
                .. "."
    end

    local verb = count == 1 and " drops " or " drop "
    return results, plural(count, "monster") .. verb .. name .. ", best chance first."
end

local function build_index(saved_only)
    local entries, seen = {}, {}

    local function add(monster, saved)
        local key = assert(core.identity_key(monster), "search entry has no monster identity")

        if seen[key] then
            seen[key].saved = seen[key].saved or saved
        else
            local entry = {
                monster = monster,
                name = monster.name,
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
        for _, title in ipairs(core.titles()) do
            add({ name = title, wiki_title = title }, false)
        end
    end

    for _, monster in ipairs(cache.list(saved_only)) do
        -- an npcs name and level dont say which wiki page its on (eg Bloodveld), so the
        -- search lists pages. clicked npcs still keep their own saved entry
        if saved_only then
            local status = core.coverage(monster).status

            if status == "unknown" or status == "ambiguous" then
                add(monster, true)
            end
        elseif monster.wiki_title and seen[core.identity_key(monster)] then
            add({ name = monster.wiki_title, wiki_title = monster.wiki_title }, true)
        end
    end

    return entries
end

-- the picker searches saved lookups by their label (title, variant and level)
local function prepare_saved_entry(entry)
    local summary = entry.summary

    if not summary then
        return false
    end

    if entry.base_label then
        entry.label = entry.base_label
        return entry.prepared
    end

    entry.label = summary.title

    if summary.variant and summary.variant ~= "" and summary.variant ~= summary.title then
        entry.label = entry.label .. " - " .. summary.variant
    end

    entry.base_label = entry.label
    local searchable = entry.label .. (summary.level and (" Level " .. summary.level) or "")
    entry.prepared = core.prepare_name(searchable)
    return entry.prepared
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

local function publish(state, results, message)
    state.results = results
    state.on_update(results, message)
end

-- how the core scan reads an entry. the picker reads missing labels a few per tick, nil
-- tells the scan to stop and come back to this entry next tick
local function entry_preparer(state)
    return function(entry)
        if not state.saved_only then
            entry.prepared = entry.prepared or core.prepare_name(entry.name)
            return entry.prepared
        end

        if not entry.resolved then
            if state.reads >= LEGACY_READS_PER_TICK then
                return nil
            end

            entry.summary = cache.describe(entry.monster)
            entry.resolved = true
            state.reads = state.reads + 1
        end

        return prepare_saved_entry(entry)
    end
end

local function finish(state)
    local results = state.scan.results()
    state.scan = nil

    if state.saved_only then
        distinguish_saved_results(results)
    end

    if state.items then
        publish(
            state,
            results,
            #results == 0 and "No dropped items match your search."
                or "Select an item to see which monsters drop it."
        )
        return
    end

    publish(
        state,
        results,
        #results == 0 and "No monsters match your search."
            or state.saved_only and "Select a monster to refresh its Wiki data."
            or "Select a monster."
    )
end

local function start_scan(state)
    state.scan = core.scan(state.index, state.query, {
        prepare = entry_preparer(state),
        -- saved lookups first, then by identity so ties always come out the same way
        bonus = function(entry)
            return entry.saved and 0 or 1
        end,
        key = function(entry)
            return entry.key
        end,
    })
end

---@param on_update fun(results: table[], message: string)
---@param saved_only boolean? only monsters with saved lookups, for refreshing them
---@param kind "items"? search dropped items instead of monsters
function search.new(on_update, saved_only, kind)
    next_subscription = next_subscription + 1
    local subscription = "monster_lookup_search_" .. next_subscription
    local state = {
        tick = 0,
        reads = 0,
        on_update = on_update,
        results = {},
        saved_only = saved_only == true,
        items = kind == "items",
    }
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

        state.query, state.key, state.due, state.scan = query, key, nil, nil
        local exact = state.items and state.exact[key]

        if exact then
            publish(state, dropper_results(exact))
        elseif #query >= 3 or (state.saved_only and #query > 0) then
            state.due = state.tick + DEBOUNCE_TICKS
            publish(state, {}, state.items and "Searching items..." or "Searching names...")
        else
            publish(
                state,
                {},
                state.saved_only and "Search saved Wiki monsters by name or location."
                    or state.items and "Type at least 3 characters to search dropped items."
                    or "Type at least 3 characters to search monsters."
            )
        end
    end

    function controller.stop()
        state.started = false
        state.due, state.scan = nil, nil
        Event.Logic.Unsubscribe(subscription)
    end

    function controller.choose(result)
        if state.started then
            -- only a result thats still showing can be picked, not one from an old search
            for _, current in ipairs(state.results) do
                if current == result then
                    -- picking an item from the list asks for its droppers, the search keeps
                    -- going and the window fills the field with the full name
                    if result.item_name then
                        return { item = result.item_name }
                    end

                    local monster = result.monster
                    controller.stop()
                    return {
                        name = monster.name,
                        npc_id = monster.npc_id,
                        wiki_title = monster.wiki_title,
                        focus = result.focus,
                    }
                end
            end
        end
    end

    function controller.start()
        if state.started then
            return
        end

        if state.items then
            state.index, state.exact = build_item_index()
        else
            state.index = build_index(state.saved_only)
        end

        state.started = true
        Event.Logic.Subscribe(subscription, function()
            state.tick = state.tick + 1

            if state.due and state.tick >= state.due then
                state.due = nil
                start_scan(state)
            end

            if state.scan then
                state.reads = 0

                if state.scan.step(ROWS_PER_TICK) then
                    finish(state)
                end
            end
        end)
        local previous = state.query or ""
        state.key = nil
        controller.set_query(previous)
    end

    return controller
end

return search
