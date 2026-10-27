-- owns the plugin lifecycle and connects menu selections to the lookup and window

local npc_menu = require("src/game/npc_menu")
local monster_window = require("src/ui/monster_window")
local lookup_service = require("src/data/lookup/service")
local settings_panel = require("src/ui/settings/panel")
local search_window = require("src/ui/search/window")
local content_panel = require("src/ui/settings/content")
local settings = require("src/settings")
local clock = require("src/utils/clock")
local location_marker = require("src/game/locations/marker")
local prices = require("src/data/drops/prices")
local extensions = require("src/ui/extensions/registry")
local navigation = require("src/ui/locations/navigation")

local app = {}
local started = false
local GAME_STATE_SUBSCRIPTION = "monster_lookup_window_lifecycle"

local function on_game_state_changed(event)
    if event.newState == GameState.LOBBY or event.newState == GameState.LOGINSCREEN then
        -- native UI belongs to the current game session; rebuild it after login
        location_marker.clear()
        monster_window.destroy()
        search_window.destroy()
        content_panel.destroy()
    end
end

local function fetch_monster(monster)
    local result, problem, metadata = lookup_service.get(monster)
    if result then
        monster_window.show_result(result, nil, metadata)
    else
        monster_window.show_error(problem)
    end
end

local function on_monster_selected(monster)
    -- where to open the window (an item to filter on, a tab) isnt part of which monster it is,
    -- so it stays separate from the data-library selection
    local focus = monster.focus
    local opened = monster_window.open(monster, nil, focus)

    if opened then
        fetch_monster(monster)
    end

    return opened
end

function app.start()
    if started then
        return
    end

    assert(
        prettyui and prettyui.Window,
        "Monster Lookup requires PrettyUI; install it from the Plugin Hub"
    )
    clock.start()
    location_marker.start()
    search_window.start(on_monster_selected)
    settings_panel.start(monster_window.refresh_settings)
    content_panel.start(search_window.open, monster_window.refresh_settings)
    npc_menu.start(on_monster_selected, settings.menu_colour_hex)
    Event.GameStateChanged.Subscribe(GAME_STATE_SUBSCRIPTION, on_game_state_changed)

    started = true

    log("Monster Lookup started.")
end

---opens the standard window for a monster, what the menu entry and search do. for other
---plugins through src/api.lua
---@param monster MonsterSelection with an optional focus (WindowFocus)
---@return boolean opened false before the plugin started or while the game area isnt ready
function app.open(monster)
    if not started then
        return false
    end

    return on_monster_selected(monster) == true
end

function app.started()
    return started
end

function app.stop()
    if not started then
        return
    end

    started = false
    -- other plugins sections, tabs and navigation go first, while the window theyre in still
    -- exists
    extensions.clear()
    navigation.clear()
    npc_menu.stop()
    clock.stop()
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
        log(
            "Monster Lookup: GE Price Library turned "
                .. (event.enabled and "on, using live prices" or "off, using saved prices")
        )
        monster_window.refresh_settings()
    end
end

return app
