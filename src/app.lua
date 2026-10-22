-- owns the plugin lifecycle and connects menu selections to the lookup and window

local npc_menu = require("src/game/npc_menu")
local monster_window = require("src/ui/monster_window")
local lookup_service = require("src/data/lookup_service")
local settings_panel = require("src/ui/settings_panel")
local search_window = require("src/ui/monster_search_window")
local content_panel = require("src/ui/content_panel")
local settings = require("src/settings")
local location_marker = require("src/game/location_marker")
local prices = require("src/data/prices")

local app = {}
local started = false
local GAME_STATE_SUBSCRIPTION = "monster_lookup_window_lifecycle"

local function on_game_state_changed(event)
    if event.newState == GameState.LOBBY or event.newState == GameState.LOGINSCREEN then
        -- native UI belongs to the current game session; rebuild it after login
        location_marker.clear()
        lookup_service.cancel()
        monster_window.destroy()
        search_window.destroy()
        content_panel.destroy()
    end
end

local function fetch_monster(monster, force_refresh)
    lookup_service.fetch(monster, function(result, problem, metadata)
        if result then
            monster_window.show_result(result, problem, metadata)
        else
            monster_window.show_error(problem)
        end
    end, force_refresh)
end

local function on_monster_selected(monster, force_refresh)
    -- where to open the window (an item to filter on, a tab) isnt part of which monster it is,
    -- so it stays out of the lookup and the saved data
    local focus = monster.focus
    monster.focus = nil
    local opened = monster_window.open(monster, lookup_service.cancel, focus)

    if opened then
        fetch_monster(monster, force_refresh == true)
    end
end

local function refresh_monster(monster, on_complete)
    lookup_service.fetch(monster, function(result, problem, metadata)
        if metadata and metadata.refreshing then
            return
        end
        if on_complete then
            on_complete(result ~= nil and problem == nil, problem)
        end
    end, true)
end

function app.start()
    if started then
        return
    end

    assert(
        prettyui and prettyui.Window,
        "Monster Lookup requires PrettyUI; install it from the Plugin Hub"
    )
    lookup_service.start()
    location_marker.start()
    search_window.start(on_monster_selected)
    settings_panel.start(monster_window.refresh_settings, refresh_monster)
    content_panel.start(search_window.open, monster_window.refresh_settings, refresh_monster)
    npc_menu.start(on_monster_selected, settings.menu_colour_hex)
    Event.GameStateChanged.Subscribe(GAME_STATE_SUBSCRIPTION, on_game_state_changed)

    started = true

    log("Monster Lookup started.")
end

function app.stop()
    if not started then
        return
    end

    started = false
    npc_menu.stop()
    lookup_service.stop()
    location_marker.stop()
    settings_panel.stop()
    content_panel.stop()
    search_window.destroy()
    Event.GameStateChanged.Unsubscribe(GAME_STATE_SUBSCRIPTION)
    prices.stop()
    monster_window.destroy()

    log("Monster Lookup stopped.")
end

-- the GE Price Library is optional, so it can come and go while the plugin runs. redraw the
-- open drop table so its prices switch between live and saved straight away
---@param event {pluginIdentifier: string, enabled: boolean}
function app.dependency_changed(event)
    if started and event and event.pluginIdentifier == "gepl" then
        monster_window.refresh_settings()
    end
end

return app
