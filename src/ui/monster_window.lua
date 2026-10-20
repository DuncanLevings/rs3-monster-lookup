-- the one Monster Lookup window, with Drops and Monster info tabs
-- its created the first time a monster is picked and then reused, closing just hides it.
-- logout and plugin shutdown destroy it properly

local window_state = require("src/ui/window_state")
local drop_table = require("src/ui/drop_table")
local monster_info_view = require("src/ui/monster_info_view")
local lookup_notice = require("src/ui/lookup_notice")
local theme = require("src/ui/theme")

local settings = require("src/settings")
local clock = require("src/utils/cache_clock")

local monster_window = {}
local window
local info_controller
local info_label
local loading_label
local tabs
local drop_table_controller
local current_result
local current_metadata
local current_problem
local refresh_action
local close_action
local error_notice
local search_query = ""

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

local function add_loading_message(page)
    loading_label = page:AddText({
        text = "Loading RuneScape Wiki...",
        colour = theme.TEXT_WARNING,
        height = 40,
    })
end

local function add_monster_info(page)
    info_label = page:AddText({ text = "", height = 60 })
end

local function add_content_tabs()
    tabs = window:AddTabs(
        { { text = "Drops" }, { text = "Monster info" } },
        { height = 320, scrollStep = theme.WHEEL_STEP, onChange = hide_window_tooltips }
    )
    tabs.root:SetSize(-tabs.root.x * 2, -tabs.root.y - 8, 1, 1)

    add_loading_message(tabs:GetPage(1))
    drop_table_controller = drop_table.render(tabs:GetPage(1), {}, window.parent)
    error_notice = lookup_notice.new(tabs:GetPage(1))
    add_monster_info(tabs:GetPage(2))
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
    tabs:GetPage(1):SetScrollPosition(0)
end

local function clear_window_references()
    window = nil
    info_label = nil
    info_controller = nil
    loading_label = nil
    tabs = nil
    drop_table_controller = nil
    error_notice = nil
    current_result = nil
    current_metadata = nil
    current_problem = nil
    refresh_action = nil
    close_action = nil
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

local function cache_status(metadata, problem)
    if not metadata then
        return ""
    end

    local now = clock.now()
    local age = now and metadata.saved_at and math.max(0, now - metadata.saved_at)
        or metadata.age_seconds
    local updated = describe_age(age)

    if metadata.refreshing then
        return updated .. " | Refreshing from Wiki..."
    elseif problem then
        return updated .. " | Refresh failed; showing saved data.\n" .. problem
    elseif metadata.stale then
        return updated .. " | Refresh due"
    end

    return updated
end

local function replace_drop_tables(sections)
    drop_table_controller.destroy()
    drop_table_controller = drop_table.render(tabs:GetPage(1), sections, window.parent, {
        percentage_rarity = settings.get().percentage_rarity,
        on_refresh = refresh_action,
        refreshing = current_metadata and current_metadata.refreshing,
        status = cache_status(current_metadata, current_problem),
        problem = current_problem,
        search_query = search_query,
        on_search_change = function(query)
            search_query = query
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
    tabs:GetPage(2):SetContentHeight(84)
end

local function show_monster_info(result)
    clear_monster_info()
    info_label.hidden = true
    info_controller = monster_info_view.render(tabs:GetPage(2), result, window.parent)
end

---opens (or reuses) the window for a monster and shows the loading state
---@param monster MonsterSelection
---@param on_refresh fun() for the Refresh button
---@param on_close fun()? called when the player closes the window, eg to stop the lookup
---@return boolean opened false if the game area isnt ready yet
function monster_window.open(monster, on_refresh, on_close)
    if not ensure_window_exists() then
        return false
    end

    current_result = nil
    current_metadata = nil
    current_problem = nil
    search_query = ""
    refresh_action = on_refresh
    close_action = on_close
    window:SetTitle(monster.name)
    lookup_notice.hide(error_notice)
    replace_drop_tables({})
    loading_label.hidden = false
    tabs:GetPage(1):SetContentHeight(64)
    clear_monster_info()
    info_label.content = "Loading monster information..."

    show_drops_tab()
    window:Show()

    return true
end

-- message for a monster whose page has no drop tables we can show. the notice goes on
-- after the (empty) tables are rendered since rendering resets the page height
local function show_no_drops_notice(result)
    local message

    if result.no_drops == "unreadable" then
        message = "The Wiki page for "
            .. result.title
            .. " has drops, but they're laid out in a way Monster Lookup can't read yet. "
            .. "Check the Wiki page for the full list. Monster info is still available."
    else
        message = "The RuneScape Wiki doesn't list any drops for "
            .. result.title
            .. ". Its combat stats are on the Monster info tab."
    end

    lookup_notice.show(error_notice, message, "No drops to show", "info")
end

local function show_drops(result)
    replace_drop_tables(result.sections)

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
    lookup_notice.hide(error_notice)
    loading_label.hidden = true
    show_drops(result)
    show_monster_info(result)
end

function monster_window.refresh_settings()
    if current_result then
        show_drops(current_result)
    end
end

function monster_window.show_error(problem)
    if not window then
        return
    end

    replace_drop_tables({})
    loading_label.hidden = true
    clear_monster_info()
    info_label.content = "Monster information could not be loaded. See the error in Drops."

    lookup_notice.show(error_notice, problem)
    show_drops_tab()
end

function monster_window.destroy()
    if not window then
        return
    end

    window_state.save(window)
    clear_monster_info()
    drop_table_controller.destroy()
    window:Destroy()
    clear_window_references()
end

return monster_window
