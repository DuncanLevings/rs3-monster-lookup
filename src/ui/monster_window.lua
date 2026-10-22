-- the one Monster Lookup window, with Drops, Monster info and Locations tabs
-- its created the first time a monster is picked and then reused, closing just hides it.
-- logout and plugin shutdown destroy it properly

local window_state = require("src/ui/window_state")
local drop_table = require("src/ui/drop_table")
local monster_info_view = require("src/ui/monster_info_view")
local locations_view = require("src/ui/locations_view")
local lookup_notice = require("src/ui/lookup_notice")
local theme = require("src/ui/theme")

local settings = require("src/settings")
local clock = require("src/utils/cache_clock")
local prices = require("src/data/prices")

local monster_window = {}
local window
local tabs
local drops_page
local info_page
local info_controller
local info_label
local locations_page
local locations_controller
local locations_label
local loading_label
local drop_table_controller
local error_notice
local current_result
local current_metadata
local current_problem
local current_selection
local close_action
local search_query = ""
local drop_mode = 1
local drop_section_state = {}

local function hide_window_tooltips()
    if drop_table_controller then
        drop_table_controller.hide_tooltips()
    end

    if info_controller then
        info_controller.hide_tooltips()
    end
end

-- the window is only hidden on close so it can be reused, nothing is destroyed here
local function on_window_closed(closed_window)
    hide_window_tooltips()
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
    tabs = window:AddTabs(
        { { text = "Drops" }, { text = "Monster info" }, { text = "Locations" } },
        { height = 320, scrollStep = theme.WHEEL_STEP, onChange = hide_window_tooltips }
    )
    tabs.root:SetSize(-tabs.root.x * 2, -tabs.root.y - 8, 1, 1)
    drops_page = tabs:GetPage(1)
    info_page = tabs:GetPage(2)
    locations_page = tabs:GetPage(3)

    loading_label = drops_page:AddText({
        text = "Loading RuneScape Wiki...",
        colour = theme.TEXT_WARNING,
        height = 40,
    })
    drop_table_controller = drop_table.render(drops_page, {}, window.parent)
    error_notice = lookup_notice.new(drops_page)
    info_label = info_page:AddText({ text = "", height = 60 })
    locations_label = locations_page:AddText({ text = "", height = 60 })
end

local function create_window(parent)
    window = prettyui.Window.new(parent, create_window_options(parent))
    add_content_tabs()
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
    tabs:SetActive(1, false)
    drops_page:SetScrollPosition(0)
end

local function plural(count, unit)
    return count .. " " .. unit .. (count == 1 and "" or "s")
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

local show_drops

-- refreshes rebuild the view but keep search, mode and category choices. picking
-- another monster resets these in open(), so an old filter cannot hide its drops
local function replace_drop_tables(sections)
    drop_table_controller.destroy()
    drop_table_controller = drop_table.render(drops_page, sections, window.parent, {
        percentage_rarity = settings.get().percentage_rarity,
        price_for = prices.for_drop,
        status = cache_status(current_metadata, current_problem),
        problem = current_problem,
        search_query = search_query,
        on_search_change = function(query)
            search_query = query
        end,
        mode = drop_mode,
        section_state = drop_section_state,
        on_mode_change = function(mode)
            drop_mode = mode
            hide_window_tooltips()

            if current_result then
                show_drops(current_result)
                drops_page:SetScrollPosition(0)
            end
        end,
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
    info_controller = monster_info_view.render(info_page, result, window.parent)
end

local function clear_locations(message)
    if locations_controller then
        locations_controller.destroy()
        locations_controller = nil
    end

    locations_label.hidden = false
    locations_label.content = message or ""
    locations_page:SetContentHeight(84)
    locations_page:SetScrollPosition(0)
end

local function show_locations(result)
    clear_locations()
    locations_label.hidden = true
    locations_controller = locations_view.render(locations_page, result)
end

local function show_loading()
    lookup_notice.hide(error_notice)
    replace_drop_tables({})
    loading_label.hidden = false
    drops_page:SetContentHeight(64)
    clear_monster_info()
    info_label.content = "Loading monster information..."
    clear_locations("Loading monster locations...")
    show_drops_tab()
end

---opens (or reuses) the window for a monster and shows the loading state
---@param monster MonsterSelection
---@param on_close fun()? called when the player closes the window, eg to stop the lookup
---@return boolean opened false if the game area isnt ready yet
function monster_window.open(monster, on_close)
    if not ensure_window_exists() then
        return false
    end

    current_result = nil
    current_selection = monster
    current_metadata = nil
    current_problem = nil
    search_query = ""
    drop_mode = 1
    drop_section_state = {}
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

show_drops = function(result)
    replace_drop_tables(result.sections)

    if #result.sections == 0 then
        show_no_drops_notice(result)
        return
    end

    -- gepl may still be loading prices right after login. draw with the saved prices now and
    -- once more when the live ones arrive, if this monster is still the one showing
    prices.when_live("monster_window", function()
        if window and current_result == result then
            show_drops(result)
        end
    end)
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
    show_drops(result)
    show_monster_info(result)
    show_locations(result)
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
    replace_drop_tables({})
    loading_label.hidden = true
    clear_monster_info()
    info_label.content = "Monster information could not be loaded. See the error in Drops."
    clear_locations("Monster locations could not be loaded. See the error in Drops.")

    lookup_notice.show(error_notice, problem)
    show_drops_tab()
end

function monster_window.destroy()
    if not window then
        return
    end

    hide_window_tooltips()
    window_state.save(window)
    clear_monster_info()
    clear_locations()
    drop_table_controller.destroy()
    window:Destroy()

    window = nil
    tabs = nil
    drops_page = nil
    info_page = nil
    info_controller = nil
    info_label = nil
    locations_page = nil
    locations_controller = nil
    locations_label = nil
    loading_label = nil
    drop_table_controller = nil
    error_notice = nil
    current_result = nil
    current_metadata = nil
    current_problem = nil
    close_action = nil
end

return monster_window
