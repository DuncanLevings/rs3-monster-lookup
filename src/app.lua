-- owns the plugin lifecycle and connects menu selections to the lookup and window

local npc_menu = require("src/game/npc_menu")
local monster_window = require("src/ui/monster_window")
local core = require("src/data/library/api")
local settings_panel = require("src/ui/settings/panel")
local search_window = require("src/ui/search/window")
local content_panel = require("src/ui/settings/content")
local settings = require("src/settings")
local location_marker = require("src/game/locations/marker")
local prices = require("src/data/drops/prices")

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

-- Translate static coverage into a result or a clear notice; never guess an identity.
local function show_monster(monster)
    local result, coverage = core.monster(monster)

    if not result and (coverage.status == "excluded" or coverage.status == "no_drops") then
        result = {
            title = monster.name,
            info = {},
            variants = {},
            sections = {},
            locations = {},
            no_drops = coverage.status == "excluded" and "not_covered" or "none",
            no_locations = "none",
            source = "bundle",
            placeholder = true,
        }
    end

    if not result then
        local problem = coverage.status == "ambiguous"
                and "This NPC matches more than one monster. Search for the specific monster name."
            or "This monster is not included in Monster Data Core. Update the data library or try searching by name."
        monster_window.show_error(problem)
        return
    end

    result.source = "bundle"
    monster_window.show_result(result, nil, { bundled = true, built = core.info().built })
end

local function on_monster_selected(monster)
    -- where to open the window (an item to filter on, a tab) isnt part of which monster it is,
    -- so it stays separate from the data-library selection
    local focus = monster.focus
    local opened = monster_window.open(monster, nil, focus)

    if opened then
        show_monster(monster)
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
    location_marker.start()
    search_window.start(on_monster_selected)
    settings_panel.start(monster_window.refresh_settings)
    content_panel.start(search_window.open, monster_window.refresh_settings)
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
