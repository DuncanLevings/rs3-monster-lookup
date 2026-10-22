-- sections and tabs other plugins add to the standard Monster Lookup window. a plugin
-- registers one with MonsterLookup.register_extension(definition) and gets back a handle,
-- handle.dispose() takes it out again. Monster Lookup never knows about the plugins
-- themselves, they register with it (so nothing depends back on them)
--
--   kind "section"  a group at the bottom of the Monster info tab. content(context) returns
--                   rows and text the window draws, like the built in stats
--   kind "tab"      a tab of its own after Locations. either content(context) like a section,
--                   or create(container) once plus update(context, container) per monster to
--                   draw anything in a container the window owns
--
-- every call into an extension is protected: an error shows a short message in its slot and
-- is logged once, the built in tabs carry on. a protected call still runs to the end though,
-- an extension thats slow is slow for the window too
--
-- context (a new table each call, changing it does nothing):
--   monster   { title, name, wiki_title, npc_id }
--   variant   the Monster info variant showing, eg "Hard mode", nil when theres only one
--   mode      the drop mode showing, eg "Normal mode", nil when the page has none
--   source    "bundle", "cache" or "wiki"
--   revision  goes up every time any of the above changes
--   is_current()  false once the window moved on (another monster, variant or mode) or the
--                 extension was disposed. check it before using an async result
--   refresh()     ask for content() / update() again for this context, ignored once stale

local registry = {}

local ID_PATTERN = "^[%w_%-]+%.[%w_%.%-]+$"
local MAX_TITLE = 40
local MAX_ROWS = 50
local MAX_TEXT = 2000

local entries = {}
local listeners = {}
local reported = {}

local function notify(change, entry)
    for callback in pairs(listeners) do
        local ok, problem = pcall(callback, change, entry)

        if not ok then
            log("Monster Lookup: extension listener failed. " .. tostring(problem))
        end
    end
end

local function check_definition(definition)
    if type(definition) ~= "table" then
        return "an extension is a table"
    end

    local id = definition.id

    if type(id) ~= "string" or not id:match(ID_PATTERN) or #id > 80 then
        return "the id must look like author.plugin.name (letters, numbers, _ - and dots)"
    end

    if definition.kind ~= "section" and definition.kind ~= "tab" then
        return id .. ": kind must be \"section\" or \"tab\""
    end

    if type(definition.title) ~= "string" or definition.title == "" or #definition.title > MAX_TITLE then
        return id .. ": the title must be 1 to " .. MAX_TITLE .. " characters"
    end

    if definition.order ~= nil and type(definition.order) ~= "number" then
        return id .. ": order must be a number"
    end

    for _, name in ipairs({ "content", "create", "update", "activate", "deactivate", "destroy" }) do
        if definition[name] ~= nil and type(definition[name]) ~= "function" then
            return id .. ": " .. name .. " must be a function"
        end
    end

    if definition.kind == "section" and not definition.content then
        return id .. ": a section needs a content function"
    end

    if definition.kind == "section" and definition.create then
        return id .. ": sections only take content, custom ui needs a tab"
    end

    if definition.kind == "tab" and not definition.content and not definition.create then
        return id .. ": a tab needs a content or a create function"
    end

    if definition.content and definition.create then
        return id .. ": a tab takes content or create, not both"
    end

    if entries[id] then
        return id .. " is already registered"
    end
end

---@class ExtensionDefinition
---@field id string namespaced, eg "jagexfan.slayer_helper.tasks"
---@field kind "section"|"tab"
---@field title string shown on the section header or tab
---@field order number? lower goes first, then by id (default 0)
---@field content (fun(context: table): table?)? rows and text to show, nil shows nothing
---@field create (fun(container: table))? tabs: make your ui in the container, once per window
---@field update (fun(context: table, container: table))? tabs with create: a new monster,
---variant or mode. defaults to doing nothing
---@field activate (fun(context: table?))? tabs: the tab was opened
---@field deactivate fun()? tabs: another tab was opened or the window closed
---@field destroy (fun(container: table))? tabs with create: the window or the extension is
---going away, let go of anything you made in the container (it gets destroyed after)

---@param definition ExtensionDefinition
---@return { id: string, dispose: fun() }? handle
---@return string? problem why it wasnt registered
function registry.register(definition)
    local problem = check_definition(definition)

    if problem then
        log("Monster Lookup: extension not registered, " .. problem)
        return nil, problem
    end

    -- a copy, so the caller changing its table later changes nothing here
    local entry = {
        id = definition.id,
        kind = definition.kind,
        title = definition.title,
        order = definition.order or 0,
        content = definition.content,
        create = definition.create,
        update = definition.update,
        activate = definition.activate,
        deactivate = definition.deactivate,
        destroy = definition.destroy,
    }
    entries[entry.id] = entry
    log("Monster Lookup: extension " .. entry.id .. " registered (" .. entry.kind .. ")")
    notify("added", entry)

    return {
        id = entry.id,
        dispose = function()
            if entries[entry.id] ~= entry then
                return
            end

            entries[entry.id] = nil
            entry.disposed = true
            log("Monster Lookup: extension " .. entry.id .. " removed")
            notify("removed", entry)
        end,
    }
end

---registered extensions of one kind, in order. the registry's own entries, read only
---@param kind "section"|"tab"
function registry.list(kind)
    local list = {}

    for _, entry in pairs(entries) do
        if entry.kind == kind then
            list[#list + 1] = entry
        end
    end

    table.sort(list, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end

        return a.id < b.id
    end)

    return list
end

---calls back with ("added"|"removed", entry) when extensions come and go
---@return fun() unsubscribe
function registry.subscribe(callback)
    listeners[callback] = true

    return function()
        listeners[callback] = nil
    end
end

---calls one of an extensions functions, protected. a failure is logged once per extension
---and function, and comes back as a message to show in its slot
---@return boolean ok
---@return any result or the message
function registry.call(entry, name, ...)
    local action = entry[name]

    -- a disposed extension still gets told to let go of its ui, nothing else
    if not action or (entry.disposed and name ~= "deactivate" and name ~= "destroy") then
        return true, nil
    end

    local ok, result = pcall(action, ...)

    if ok then
        return true, result
    end

    local key = entry.id .. ":" .. name

    if not reported[key] then
        reported[key] = true
        log("Monster Lookup: extension " .. entry.id .. " failed in " .. name .. ". " .. tostring(result))
    end

    return false, "This " .. entry.kind .. " from another plugin could not be shown."
end

---a context for one extension call. state is the windows selection state (it bumps
---state.revision when the monster, variant or mode changes), on_refresh is what refresh()
---does while its still current
function registry.context(entry, state, on_refresh)
    local revision = state.revision
    local monster = state.monster or {}
    local context = {
        monster = {
            title = monster.title,
            name = monster.name,
            wiki_title = monster.wiki_title,
            npc_id = monster.npc_id,
        },
        -- the window clears these with false, extensions just see nil
        variant = state.variant or nil,
        mode = state.mode or nil,
        source = state.source or nil,
        revision = revision,
    }

    function context.is_current()
        return not entry.disposed and state.revision == revision and not state.closed
    end

    function context.refresh()
        if context.is_current() and on_refresh then
            on_refresh()
        end
    end

    return context
end

local function plain(value, limit)
    local text = tostring(value == nil and "" or value):gsub("[<>]", ""):gsub("%c", " ")
    return text:sub(1, limit)
end

---what content() returned as a stat section the window can draw, nil when theres nothing.
---content is { rows = { { "label", "value" }, ... }, text = "a paragraph" }, both optional
---@return table? section
---@return string? problem when content isnt that shape
function registry.section(entry, content)
    if content == nil then
        return nil
    end

    if type(content) ~= "table" then
        return nil, "This " .. entry.kind .. " from another plugin returned something it cant show."
    end

    local rows = {}

    for index, row in ipairs(type(content.rows) == "table" and content.rows or {}) do
        if index > MAX_ROWS then
            break
        end

        if type(row) == "table" then
            rows[#rows + 1] = { plain(row[1], 60), plain(row[2], 300) }
        end
    end

    local text = content.text ~= nil and plain(content.text, MAX_TEXT) or nil

    if #rows == 0 and not text then
        return nil
    end

    return {
        title = entry.title,
        widths = { 0.40, 0.60 },
        labels = { true, false },
        rows = rows,
        note = text,
    }
end

---takes every extension out, for Monster Lookup shutting down
function registry.clear()
    for id, entry in pairs(entries) do
        entries[id] = nil
        entry.disposed = true
        notify("removed", entry)
    end
end

return registry
