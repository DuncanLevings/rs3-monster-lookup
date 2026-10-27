-- owns the Drops, Monster info and Locations tabs and their selection state.
-- closing hides the window for reuse; logout and shutdown destroy its native objects.

local window_state = require("src/ui/common/window_state")
local drops_component = require("src/ui/drops/component")
local monster_info_view = require("src/ui/info/view")
local locations_component = require("src/ui/locations/component")
local lookup_notice = require("src/ui/lookup_notice")
local core = require("src/data/core")
local theme = require("src/ui/common/theme")

local settings = require("src/settings")
local clock = require("src/utils/cache_clock")
local plural = require("src/utils/number_format").plural
local prices = require("src/data/drops/prices")

local monster_window = {}
-- tab numbers, in the order add_content_tabs adds them
local DROPS_TAB = 1
local INFO_TAB = 2
local LOCATIONS_TAB = 3
local BUILT_IN_TABS = { drops = DROPS_TAB, info = INFO_TAB, locations = LOCATIONS_TAB }

local window
local destroying = false
local tabs
local drops_page
local info_page
local info_controller
local info_label
local locations_page
local locations
local locations_label
local loading_label
local drops
local error_notice
local current_result
local current_metadata
local current_problem
local current_selection
-- set by the search window: an item to filter drops on, its mode, or a tab to start on
local pending_focus
local info_active = false
local close_action
-- false until the first result for the current monster, later ones are refreshes and keep
-- the drop search, mode and open sections the player picked since
local drops_selected = false
-- the info tab only animates its preview while its the tab showing
local function set_info_active(active)
    info_active = active

    if info_controller then
        info_controller.set_active(active)
    end
end

local function hide_window_tooltips()
    if drops then
        drops.hide_tooltips()
    end

    if info_controller then
        info_controller.hide_tooltips()
    end
end

-- the window is only hidden on close so it can be reused, nothing is destroyed here
local function on_window_closed(closed_window)
    if destroying then
        return
    end
    hide_window_tooltips()
    set_info_active(false)

    window_state.save(closed_window)

    if close_action then
        close_action()
    end
end

local function create_window_options(parent)
    local options = window_state.load(parent)
    options.title = "Monster Lookup"
    options.resizable = true
    options.scrollable = false
    options.destroyOnClose = false
    options.onClose = on_window_closed

    return options
end

local function add_content_tabs()
    local entries = { { text = "Drops" }, { text = "Monster info" }, { text = "Locations" } }
    tabs = window:AddTabs(entries, {
        height = 320,
        scrollStep = theme.WHEEL_STEP,
        onChange = function(_, index)
            if destroying then
                return
            end
            hide_window_tooltips()
            set_info_active(index == INFO_TAB)
        end,
    })
    tabs.root:SetSize(-tabs.root.x * 2, -tabs.root.y - 8, 1, 1)
    drops_page = tabs:GetPage(DROPS_TAB)
    info_page = tabs:GetPage(INFO_TAB)
    locations_page = tabs:GetPage(LOCATIONS_TAB)

    loading_label = drops_page:AddText({
        text = "Loading RuneScape Wiki...",
        colour = theme.TEXT_WARNING,
        height = 40,
    })
    drops = drops_component.new(drops_page, {
        overlay_parent = window.parent,
    })
    drops.set_monster(nil)
    error_notice = lookup_notice.new(drops_page)
    info_label = info_page:AddText({ text = "", height = 60 })
    locations_label = locations_page:AddText({ text = "", height = 60 })
    locations = locations_component.new(locations_page)
end

local function create_window(parent)
    window = prettyui.Window.new(parent, create_window_options(parent))
    add_content_tabs()
end

-- search results select one of the three built-in tabs.
local function tab_number(tab)
    return BUILT_IN_TABS[tab]
end

local function ensure_window_exists()
    if window then
        return true
    end

    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)

    if not parent or parent.width <= 0 or parent.height <= 0 then
        log("Monster Lookup: the game window is not available yet")
        return false
    end

    create_window(parent)

    return true
end

local function show_drops_tab()
    set_info_active(false)
    tabs:SetActive(DROPS_TAB, false)
    drops_page:SetScrollPosition(0)
end

local function describe_age(age)
    if not age then
        return "Saved Wiki data"
    elseif age < 60 then
        return "Updated just now"
    elseif age < 3600 then
        return "Updated " .. plural(math.floor(age / 60), "minute") .. " ago"
    elseif age < 86400 then
        return "Updated " .. plural(math.floor(age / 3600), "hour") .. " ago"
    end

    return "Updated " .. plural(math.floor(age / 86400), "day") .. " ago"
end

-- anything not from the bundle was looked up on the wiki for a monster thats newer than the
-- bundle, those have less detail (no drop categories or area names) so it says so up front
local function is_live(metadata)
    return metadata ~= nil and not metadata.bundled
end

local LIVE_LABEL = "Live Wiki data"

local function cache_status(metadata, problem)
    if not metadata then
        return ""
    end

    local live = prices.live()
    local price_note = live and " | Live GE prices" or ""

    -- bundled data has no age to track, it is as new as this plugin version
    if metadata.bundled then
        if not metadata.built then
            return live and "Live GE prices" or ""
        end

        return live and ("Wiki data from " .. metadata.built .. price_note)
            or ("Wiki data and GE prices from " .. metadata.built)
    end

    local now = clock.now()
    local age = now and metadata.saved_at and math.max(0, now - metadata.saved_at)
        or metadata.age_seconds
    local updated = LIVE_LABEL .. " | " .. describe_age(age) .. price_note

    if metadata.refreshing then
        return updated .. " | Refreshing from Wiki..."
    elseif problem then
        return updated .. " | Refresh failed; showing saved data.\n" .. problem
    elseif metadata.stale then
        return updated .. " | Refresh due"
    end

    return updated
end

-- the players settings and the current status line, read on every redraw
local function configure_drops()
    drops.configure({
        percentage_rarity = settings.get().percentage_rarity,
        status = function()
            return cache_status(current_metadata, current_problem)
        end,
        problem = current_problem,
    })
end

local function clear_monster_info()
    if info_controller then
        info_controller.destroy()
        info_controller = nil
    end

    info_label.hidden = false
    info_label:SetHeight(60)
    info_page:SetContentHeight(84)
end

local function show_monster_info(result)
    clear_monster_info()
    info_label.hidden = true
    info_controller = monster_info_view.render(info_page, result, window.parent, current_selection)
    info_controller.set_active(info_active)
end

local function clear_locations(message)
    locations.set_monster(nil)
    locations_label.hidden = false
    locations_label.content = message or ""
    locations_page:SetContentHeight(84)
    locations_page:SetScrollPosition(0)
end

local function show_locations(result)
    clear_locations()
    locations_label.hidden = true
    locations.set_monster(result)
end

local function show_loading()
    lookup_notice.hide(error_notice)
    configure_drops()
    drops.set_monster(nil)
    loading_label.hidden = false
    drops_page:SetContentHeight(64)
    clear_monster_info()
    info_label.content = "Loading monster information..."
    clear_locations("Loading monster locations...")
    show_drops_tab()
end

---@class WindowFocus
---@field item string? fill the drop search with this item
---@field mode string? drop mode to start on eg "Hard mode"
---@field tab "info"? start on the Monster info tab instead of Drops

---opens (or reuses) the window for a monster and shows the loading state
---@param monster MonsterSelection
---@param on_close fun()? called when the player closes the window, eg to stop the lookup
---@param focus WindowFocus? where to start, from a drop or top stats search
---@return boolean opened false if the game area isnt ready yet
function monster_window.open(monster, on_close, focus)
    if not ensure_window_exists() then
        return false
    end

    current_result = nil
    current_selection = monster
    current_metadata = nil
    current_problem = nil
    drops_selected = false
    pending_focus = focus
    close_action = on_close
    window:SetTitle(monster.name)
    show_loading()
    window:Show()

    return true
end

-- message for a monster whose page has no drop tables it can show. the notice goes on
-- after the (empty) tables are rendered since rendering resets the page height
local function show_no_drops_notice(result)
    local message

    if result.no_drops == "not_covered" then
        message = "Monster Lookup only covers monsters you can find and fight again and again, "
            .. "so "
            .. result.title
            .. " isn't included. Quest, Dungeoneering, event and familiar-only monsters are "
            .. "left out."
    elseif result.placeholder then
        -- known to have no drops, so nothing about it was bundled
        message = "The RuneScape Wiki doesn't list any drops for " .. result.title .. "."
    elseif result.no_drops == "unreadable" then
        message = "The Wiki page for "
            .. result.title
            .. " has drops, but they're laid out in a way Monster Lookup can't read yet. "
            .. "Check the Wiki page for the full list. Monster info is still available."
    else
        message = "The RuneScape Wiki doesn't list any drops for "
            .. result.title
            .. ". Its combat stats are on the Monster info tab."
    end

    local title = result.no_drops == "not_covered" and "Not covered" or "No drops to show"
    lookup_notice.show(error_notice, message, title, "info")
end

-- the component redraws itself once live GE prices arrive, if this is still the monster
local function show_drops(result, focus)
    configure_drops()

    if drops_selected then
        drops.update(result)
    else
        drops_selected = true
        drops.set_monster(result, focus)
    end

    if #result.sections == 0 then
        show_no_drops_notice(result)
    end
end

function monster_window.show_result(result, problem, metadata)
    if not window then
        return
    end

    current_result = result
    current_metadata = metadata
    current_problem = problem

    -- the title bar shows on every tab, so the live label cant be missed there
    if current_selection then
        local suffix = is_live(metadata) and " - " .. LIVE_LABEL or ""
        window:SetTitle(current_selection.name .. suffix)
    end

    lookup_notice.hide(error_notice)
    loading_label.hidden = true

    -- only the first result for this monster, a refresh arriving later keeps what the player
    -- has picked since
    local focus = pending_focus
    pending_focus = nil

    show_drops(result, focus)
    show_monster_info(result)
    show_locations(result)

    local tab = focus and focus.tab and tab_number(focus.tab)

    if tab and tab ~= DROPS_TAB then
        tabs:SetActive(tab)
    end
end

-- only the drops view depends on these settings; leave the chosen info variant alone
function monster_window.refresh_settings()
    if current_result then
        show_drops(current_result)
    end
end

function monster_window.show_error(problem)
    if not window then
        return
    end

    current_result = nil
    configure_drops()
    drops.set_monster(nil)
    loading_label.hidden = true
    clear_monster_info()
    info_label.content = "Monster information could not be loaded. See the error in Drops."
    clear_locations("Monster locations could not be loaded. See the error in Drops.")

    lookup_notice.show(error_notice, problem)
    show_drops_tab()
end

function monster_window.destroy()
    if not window or destroying then
        return
    end

    destroying = true
    local old_window = window
    hide_window_tooltips()
    window_state.save(old_window)

    -- the views are just destroyed here, not reset to their loading labels first. resetting
    -- sizes fires layout callbacks, and those would run on a half destroyed window
    if info_controller then
        info_controller.destroy()
    end

    if locations then
        locations.destroy()
    end

    if drops then
        drops.destroy()
    end

    window = nil
    current_selection = nil
    info_active = false
    tabs = nil
    drops_page = nil
    info_page = nil
    info_controller = nil
    info_label = nil
    locations_page = nil
    locations = nil
    locations_label = nil
    loading_label = nil
    drops = nil
    error_notice = nil
    current_result = nil
    current_metadata = nil
    current_problem = nil
    close_action = nil
    old_window:Destroy()
    destroying = false
end

return monster_window
