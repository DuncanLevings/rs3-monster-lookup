local npc_menu = require("src/game/npc_menu")
local monster_window = require("src/ui/monster_window")
local lookup_service = require("src/data/lookup_service")
local settings_panel = require("src/ui/settings_panel")

local app = {}
local started = false
local GAME_STATE_SUBSCRIPTION = "monster_lookup_window_lifecycle"

local function on_game_state_changed(event)
    if event.newState == GameState.LOBBY or event.newState == GameState.LOGINSCREEN then
        lookup_service.cancel()
        monster_window.destroy()
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

local function on_monster_selected(monster)
    local opened = monster_window.open(monster, function()
        fetch_monster(monster, true)
    end, lookup_service.cancel)

    if opened then
        fetch_monster(monster, false)
    end
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
    settings_panel.start(monster_window.refresh_settings)
    npc_menu.start(on_monster_selected)
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
    Event.GameStateChanged.Unsubscribe(GAME_STATE_SUBSCRIPTION)
    monster_window.destroy()

    log("Monster Lookup stopped.")
end

return app
