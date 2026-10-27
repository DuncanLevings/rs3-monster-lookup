-- debounced, bounded name and dropped-item searches over Monster Data Core.

local core = require("src/data/core")
local clock = require("src/utils/clock")
local plural = require("src/utils/number_format").plural

local search = {}
local next_subscription = 0
local DEBOUNCE_TICKS = math.ceil(0.15 * clock.TICKS_PER_SECOND)
local ROWS_PER_TICK = 250

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

local function build_index()
    local entries = {}
    for _, title in ipairs(core.titles()) do
        entries[#entries + 1] = {
            monster = { name = title, wiki_title = title },
            name = title,
            label = title,
            key = title:lower(),
        }
    end
    return entries
end

local function publish(state, results, message)
    state.results = results
    state.on_update(results, message)
end

-- names are prepared lazily and reused when the query changes.
local function prepare_entry(entry)
    entry.prepared = entry.prepared or core.prepare_name(entry.name)
    return entry.prepared
end

local function finish(state)
    local results = state.scan.results()
    state.scan = nil

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
        #results == 0 and "No monsters match your search." or "Select a monster."
    )
end

local function start_scan(state)
    state.scan = core.scan(state.index, state.query, {
        prepare = prepare_entry,
        key = function(entry)
            return entry.key
        end,
    })
end

---@param on_update fun(results: table[], message: string)
---@param kind "items"? search dropped items instead of monsters
function search.new(on_update, kind)
    next_subscription = next_subscription + 1
    local subscription = "monster_lookup_search_" .. next_subscription
    local state = {
        tick = 0,
        on_update = on_update,
        results = {},
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
        elseif #query >= 3 then
            state.due = state.tick + DEBOUNCE_TICKS
            publish(state, {}, state.items and "Searching items..." or "Searching names...")
        else
            publish(
                state,
                {},
                state.items and "Type at least 3 characters to search dropped items."
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
            state.index = build_index()
        end

        state.started = true
        Event.Logic.Subscribe(subscription, function()
            state.tick = state.tick + 1

            if state.due and state.tick >= state.due then
                state.due = nil
                start_scan(state)
            end

            if state.scan then
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
