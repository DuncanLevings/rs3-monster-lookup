-- owns the plugin lifecycle and connects menu selections to the lookup and window

local npc_menu = require("src/game/npc_menu")
local monster_window = require("src/ui/monster_window")
local lookup_service = require("src/data/lookup_service")
local settings_panel = require("src/ui/settings_panel")
local search_window = require("src/ui/monster_search_window")
local content_panel = require("src/ui/content_panel")
local settings = require("src/settings")

local app = {}
local started = false
local GAME_STATE_SUBSCRIPTION = "monster_lookup_window_lifecycle"

local function on_game_state_changed(event)
    if event.newState == GameState.LOBBY or event.newState == GameState.LOGINSCREEN then
        -- native UI belongs to the current game session; rebuild it after login
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
    local opened = monster_window.open(monster, lookup_service.cancel)

    if opened then
        fetch_monster(monster, force_refresh == true)
    end
end

local function refresh_monster(monster)
    on_monster_selected(monster, true)
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
    settings_panel.stop()
    content_panel.stop()
    search_window.destroy()
    Event.GameStateChanged.Unsubscribe(GAME_STATE_SUBSCRIPTION)
    monster_window.destroy()

    log("Monster Lookup stopped.")
end

return app
