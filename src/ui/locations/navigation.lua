-- who handles "take me there" on the Locations tab. the view itself only lists locations, the
-- button on each row, the highlighted row, the status line above and its stop button all come
-- from the navigation provider set here
--
-- Monster Lookup's own marker is the default (src/game/locations/marker_navigation.lua).
-- another plugin can register a provider of its own, it replaces the current one until its
-- handle is disposed. every open Locations tab redraws with whichever one is current
--
-- a provider is a table of functions, only action and start are needed:
--   id              namespaced, eg "author.plugin.nav"
--   action(location)                 -> { label, active_label?, tooltip?, unavailable? } or nil
--                                       for no button on that row. unavailable is shown as the
--                                       tooltip of a greyed out button
--   start(location, source_title)    -> ok, problem   the button was pressed
--   confirmation(location, source_title) -> text?   shown for a few seconds after start worked
--   is_active(location, source_title)-> boolean       highlights the row, button shows active_label
--   status()                         -> text?, attention?   the line above the table
--   can_stop() -> boolean, stop()    the stop button next to the status (stop_label names it)
--   subscribe(callback)              -> unsubscribe   called when status or active rows change
--   column_title, stop_label, note   text for the button column, stop button and the footer
--
-- provider calls are protected, an error shows as the status line and is logged once

local navigation = {}

local ID_PATTERN = "^[%w_%-]+%.[%w_%.%-]+$"
local FUNCTIONS = {
    "action",
    "start",
    "confirmation",
    "is_active",
    "status",
    "can_stop",
    "stop",
    "subscribe",
}

local default_provider
-- registered providers, the last one is current
local stack = {}
local listeners = {}
local reported = {}

local function notify()
    for callback in pairs(listeners) do
        local ok, problem = pcall(callback)

        if not ok then
            log("Monster Lookup: navigation listener failed. " .. tostring(problem))
        end
    end
end

-- a copy with only the fields providers have, so changing the original later does nothing
local function copy_provider(provider)
    local copy = {
        id = provider.id,
        column_title = type(provider.column_title) == "string" and provider.column_title or "",
        stop_label = type(provider.stop_label) == "string" and provider.stop_label or "Stop",
        note = type(provider.note) == "string" and provider.note or nil,
    }

    for _, name in ipairs(FUNCTIONS) do
        copy[name] = provider[name]
    end

    return copy
end

local function check(provider)
    if type(provider) ~= "table" then
        return "a navigation provider is a table"
    end

    if type(provider.id) ~= "string" or not provider.id:match(ID_PATTERN) then
        return "the id must look like author.plugin.name"
    end

    for _, name in ipairs(FUNCTIONS) do
        if provider[name] ~= nil and type(provider[name]) ~= "function" then
            return provider.id .. ": " .. name .. " must be a function"
        end
    end

    if not provider.action or not provider.start then
        return provider.id .. ": needs action and start"
    end

    if (provider.stop == nil) ~= (provider.can_stop == nil) then
        return provider.id .. ": stop and can_stop go together"
    end
end

---replaces the current provider until the handle is disposed
---@return { id: string, dispose: fun() }? handle
---@return string? problem
function navigation.register(provider)
    local problem = check(provider)

    if problem then
        log("Monster Lookup: navigation provider not registered, " .. problem)
        return nil, problem
    end

    local entry = copy_provider(provider)
    stack[#stack + 1] = entry
    log("Monster Lookup: navigation provider " .. entry.id .. " in use")
    notify()

    return {
        id = entry.id,
        dispose = function()
            for index = #stack, 1, -1 do
                if stack[index] == entry then
                    table.remove(stack, index)
                    log("Monster Lookup: navigation provider " .. entry.id .. " removed")
                    notify()
                    return
                end
            end
        end,
    }
end

---the provider in use: the last one registered, else Monster Lookup's marker
function navigation.current()
    if stack[#stack] then
        return stack[#stack]
    end

    default_provider = default_provider
        or copy_provider(require("src/game/locations/marker_navigation"))
    return default_provider
end

---calls back when the current provider changes
---@return fun() unsubscribe
function navigation.subscribe(callback)
    listeners[callback] = true

    return function()
        listeners[callback] = nil
    end
end

---calls one of a providers functions, protected. returns ok and its results, or false and a
---message to show
function navigation.call(provider, name, ...)
    local action = provider and provider[name]

    if not action then
        return true
    end

    local results = table.pack(pcall(action, ...))

    if results[1] then
        return table.unpack(results, 1, results.n)
    end

    local key = provider.id .. ":" .. name

    if not reported[key] then
        reported[key] = true
        log("Monster Lookup: navigation " .. provider.id .. " failed in " .. name .. ". " .. tostring(results[2]))
    end

    return false, "Navigation from another plugin ran into a problem."
end

---every provider another plugin registered goes, for Monster Lookup shutting down
function navigation.clear()
    stack = {}
    notify()
end

return navigation
