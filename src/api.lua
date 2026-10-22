-- what other plugins get from Monster Lookup: main.lua returns this, the client hands it to
-- every plugin that lists Monster Lookup as a dependency (as MonsterLookup, or whatever alias
-- they give it). docs/API.md has the full rules and an example
--
-- the client gives every plugin the same table, nothing is copied (checked in the client),
-- so this only holds functions and every call hands back new tables. a plugin changing what
-- it got only changes its own copy. dont change this table itself, that would change it for
-- every plugin
--
-- what the caller makes, the caller destroys: components, lookup handles, extensions. anything
-- still around when Monster Lookup shuts down is cleaned up then

local app = require("src/app")
local core = require("src/data/core")
local lookup_service = require("src/data/lookup/service")
local extensions = require("src/ui/extensions/registry")
local navigation = require("src/ui/locations/navigation")
local info_components = require("src/ui/info/components")
local model_viewer = require("src/ui/info/model")
local drops_component = require("src/ui/drops/component")
local locations_component = require("src/ui/locations/component")
local search_view = require("src/ui/search/view")

-- bump the first number for changes that break callers, the second for additions
local API_VERSION = { major = 1, minor = 0 }
local PLUGIN_VERSION = "0.0.3"

local api = {}

-- components other plugins made and havent destroyed yet, destroyed on shutdown
local owned = {}

local function track(component)
    owned[component] = true
    local destroy = component.destroy

    component.destroy = function()
        owned[component] = nil
        destroy()
    end

    return component
end

-- a copy of a table of functions, so callers each get their own and cant change anyone elses
local function functions_of(source)
    local copy = {}

    for key, value in pairs(source) do
        if type(value) == "function" then
            copy[key] = value
        end
    end

    return copy
end

---@return { api: { major: integer, minor: integer }, plugin: string, data_schema: integer }
function api.version()
    return {
        api = { major = API_VERSION.major, minor = API_VERSION.minor },
        plugin = PLUGIN_VERSION,
        data_schema = core.SCHEMA,
    }
end

---opens the standard Monster Lookup window, like View drops does
---@param monster { name: string, wiki_title: string?, npc_id: integer? }|string a selection, or a wiki page title
---@param options { tab: string?, item: string?, mode: string? }? tab to start on ("drops",
---"info", "locations" or an extension tabs id), an item to search the drops for, a drop mode
---@return boolean opened false while Monster Lookup isnt running or the game area isnt ready
function api.open(monster, options)
    if type(monster) == "string" then
        monster = { name = monster, wiki_title = monster }
    end

    if type(monster) ~= "table" or type(monster.name) ~= "string" then
        return false
    end

    options = type(options) == "table" and options or {}
    local focus

    if options.tab or options.item or options.mode then
        focus = {
            tab = type(options.tab) == "string" and options.tab or nil,
            item = type(options.item) == "string" and options.item or nil,
            mode = type(options.mode) == "string" and options.mode or nil,
        }
    end

    return app.open({
        name = monster.name,
        wiki_title = type(monster.wiki_title) == "string" and monster.wiki_title or nil,
        npc_id = math.type(monster.npc_id) == "integer" and monster.npc_id or nil,
        focus = focus,
    })
end

---a lookup handle of your own: fetch(monster, on_complete, force_refresh?) gets bundled,
---saved or Wiki data (Wiki only for monsters newer than the bundle), cancel() and destroy()
---only ever touch this handle. on_complete can run twice, saved data first then a refresh
function api.lookup()
    return functions_of(lookup_service.new_handle())
end

---constructors for the components the standard window is made of. each call makes a new
---one you own and destroy, see docs/API.md for every option
function api.components()
    return {
        stats = function(parent, options)
            return track(info_components.stats(parent, options))
        end,
        weaknesses = function(parent, options)
            return track(info_components.weaknesses(parent, options))
        end,
        slayer = function(parent, options)
            return track(info_components.slayer(parent, options))
        end,
        detailed_stats = function(parent, options)
            return track(info_components.detailed_stats(parent, options))
        end,
        model = function(parent, options)
            return track(model_viewer.new(parent, options))
        end,
        drops = function(page, options)
            return track(drops_component.new(page, options))
        end,
        locations = function(page)
            return track(locations_component.new(page))
        end,
        ---any of the searches together, modes = { "monsters", "items", "stats" } (default all)
        search = function(page, options)
            return track(search_view.new(page, options))
        end,
        search_monsters = function(page, options)
            local merged = {}

            for key, value in pairs(options or {}) do
                merged[key] = value
            end

            merged.modes = { "monsters" }
            return track(search_view.new(page, merged))
        end,
        search_items = function(page, options)
            local merged = {}

            for key, value in pairs(options or {}) do
                merged[key] = value
            end

            merged.modes = { "items" }
            return track(search_view.new(page, merged))
        end,
        search_stats = function(page, options)
            local merged = {}

            for key, value in pairs(options or {}) do
                merged[key] = value
            end

            merged.modes = { "stats" }
            return track(search_view.new(page, merged))
        end,
        summary_fields = function()
            local fields = {}

            for index, field in ipairs(info_components.SUMMARY_FIELDS) do
                fields[index] = field
            end

            return fields
        end,
    }
end

---adds a section or tab to the standard window, see src/ui/extensions/registry.lua
---@param definition ExtensionDefinition
---@return { id: string, dispose: fun() }? handle, nil when it wasnt valid
---@return string? problem
function api.register_extension(definition)
    local handle, problem = extensions.register(definition)
    return handle and { id = handle.id, dispose = handle.dispose } or nil, problem
end

---replaces what the Locations tab buttons do (Monster Lookup's marker by default) with your
---own navigation until the handle is disposed. see src/ui/locations/navigation.lua for the
---provider functions
---@return { id: string, dispose: fun() }? handle, nil when it wasnt valid
---@return string? problem
function api.register_navigation(provider)
    local handle, problem = navigation.register(provider)
    return handle and { id = handle.id, dispose = handle.dispose } or nil, problem
end

-- destroys whatever other plugins left behind, main.lua calls it on shutdown. its not part
-- of the export, no other plugin should be able to call it
local function shutdown()
    for component in pairs(owned) do
        pcall(component.destroy)
    end

    owned = {}
end

return { export = api, shutdown = shutdown }
