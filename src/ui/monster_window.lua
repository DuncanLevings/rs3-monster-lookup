-- the one Monster Lookup window, with Drops, Monster info and Locations tabs
-- its created the first time a monster is picked and then reused, closing just hides it.
-- logout and plugin shutdown destroy it properly
--
-- each tab is a component other plugins can use too (drops/component.lua, info/view.lua
-- built from info/components.lua, locations/component.lua). this adds the window, the
-- loading and error states, the cache status line and the players settings. sections and
-- tabs other plugins register (src/ui/extensions/) are added here too

local window_state = require("src/ui/common/window_state")
local drops_component = require("src/ui/drops/component")
local monster_info_view = require("src/ui/info/view")
local locations_component = require("src/ui/locations/component")
local lookup_notice = require("src/ui/lookup_notice")
local extensions = require("src/ui/extensions/registry")
local extension_tabs = require("src/ui/extensions/tabs")
local core = require("src/data/core")
local theme = require("src/ui/common/theme")

local settings = require("src/settings")
local prices = require("src/data/drops/prices")

local monster_window = {}
-- tab numbers, in the order add_content_tabs adds them. extension tabs come after these
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
-- what extensions get as their context (registry.context). one table for the whole session,
-- its revision goes up whenever the monster, variant or drop mode changes so contexts from
-- before can tell theyre stale
local extension_state = { revision = 0 }
-- the extension tabs in this window, the ones registered when it was made
local extension_host
local extension_tab_entries = {}
-- an extension tab came or went since the window was made, its made again on the next open
local tabs_stale = false
local unsubscribe_extensions

-- the info tab only animates its preview while its the tab showing
local function set_info_active(active)
    info_active = active

    if info_controller then
        info_controller.set_active(active)
    end
end

-- the monster, variant or mode moved on: tell the extension tabs
local function move_extensions_on(changes)
    for key, value in pairs(changes) do
        extension_state[key] = value
    end

    extension_state.revision = extension_state.revision + 1

    if extension_host then
        extension_host.update()
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

    if extension_host then
        extension_host.activate(nil)
    end

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
    extension_tab_entries = extensions.list("tab")

    for _, entry in ipairs(extension_tab_entries) do
        entries[#entries + 1] = { text = entry.title }
    end

    tabs = window:AddTabs(entries, {
        height = 320,
        scrollStep = theme.WHEEL_STEP,
        onChange = function(_, index)
            if destroying then
                return
            end
            hide_window_tooltips()
            set_info_active(index == INFO_TAB)

            if extension_host then
                extension_host.activate(index > LOCATIONS_TAB and index - LOCATIONS_TAB or nil)
            end
        end,
    })
    tabs.root:SetSize(-tabs.root.x * 2, -tabs.root.y - 8, 1, 1)
    drops_page = tabs:GetPage(DROPS_TAB)
    info_page = tabs:GetPage(INFO_TAB)
    locations_page = tabs:GetPage(LOCATIONS_TAB)

    loading_label = drops_page:AddText({
        text = "Loading monster data...",
        colour = theme.TEXT_WARNING,
        height = 40,
    })
    drops = drops_component.new(drops_page, {
        overlay_parent = window.parent,
        on_mode_change = function(mode)
            move_extensions_on({ mode = mode })
        end,
    })
    drops.set_monster(nil)
    error_notice = lookup_notice.new(drops_page)
    info_label = info_page:AddText({ text = "", height = 60 })
    locations_label = locations_page:AddText({ text = "", height = 60 })
    locations = locations_component.new(locations_page)

    extension_host = extension_tabs.new(extension_tab_entries, extension_state, window.parent)

    for index in ipairs(extension_tab_entries) do
        extension_host.attach(index, tabs:GetPage(LOCATIONS_TAB + index))
    end
end

local show_monster_info

-- extensions coming and going while the window is open. sections are redrawn straight away,
-- tabs cant be added to tabs that already exist so the window is made again on the next open
local function on_extensions_changed(change, entry)
    if entry.kind == "section" then
        if current_result and info_page then
            show_monster_info(current_result)
        end

        return
    end

    tabs_stale = true

    if change == "removed" and extension_host then
        extension_host.remove(entry)
    end
end

local function create_window(parent)
    window = prettyui.Window.new(parent, create_window_options(parent))
    tabs_stale = false
    add_content_tabs()
    unsubscribe_extensions = extensions.subscribe(on_extensions_changed)
end

-- a tab id (drops, info, locations or an extensions id) as a tab number
local function tab_number(tab)
    if BUILT_IN_TABS[tab] then
        return BUILT_IN_TABS[tab]
    end

    for index, entry in ipairs(extension_tab_entries) do
        if entry.id == tab then
            return LOCATIONS_TAB + index
        end
    end
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

-- static source date, with an optional live price layer supplied by GEPL.
local function source_status(metadata)
    local built = metadata and metadata.built
    local source = built and ("Monster Data Core: " .. built) or "Monster Data Core"
    return source .. (prices.live() and " | Live GE prices" or " | Bundled GE prices")
end

-- the players settings and the current status line, read on every redraw
local function configure_drops()
    drops.configure({
        percentage_rarity = settings.get().percentage_rarity,
        status = function()
            return source_status(current_metadata)
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

show_monster_info = function(result)
    clear_monster_info()
    info_label.hidden = true
    info_controller =
        monster_info_view.render(info_page, result, window.parent, current_selection, {
            extension_state = extension_state,
            on_variant = function(variant)
                move_extensions_on({ variant = variant })
            end,
        })
    info_controller.set_active(info_active)
end

-- the library branch exposes only static monster records.
local function data_source()
    return "bundle"
end

-- the variant the Monster info tab starts on, named only when theres a choice
local function first_variant(result)
    local variants = core.variants(result)
    return #variants > 1 and variants[1].name or nil
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
    -- an extension tab came or went, the tabs have to be made again
    if window and tabs_stale then
        monster_window.destroy()
    end

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
    -- extensions see the new monster straight away, without a title or source until it loads
    move_extensions_on({
        monster = { name = monster.name, wiki_title = monster.wiki_title, npc_id = monster.npc_id },
        variant = false,
        mode = false,
        source = false,
    })
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

    -- the title remains the player's selected monster name
    if current_selection then
        window:SetTitle(current_selection.name)
    end

    lookup_notice.hide(error_notice)
    loading_label.hidden = true

    -- only the first result for this monster, a refresh arriving later keeps what the player
    -- has picked since
    local focus = pending_focus
    pending_focus = nil

    show_drops(result, focus)
    local selection = current_selection or {}
    move_extensions_on({
        monster = {
            title = result.title,
            name = selection.name,
            wiki_title = selection.wiki_title,
            npc_id = selection.npc_id,
        },
        variant = first_variant(result) or false,
        mode = drops.mode() or false,
        source = data_source() or false,
    })
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

    if extension_host then
        extension_host.destroy()
        extension_host = nil
    end

    if unsubscribe_extensions then
        unsubscribe_extensions()
        unsubscribe_extensions = nil
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
