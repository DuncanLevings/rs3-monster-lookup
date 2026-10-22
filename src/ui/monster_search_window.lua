-- the search window from the Plugins ribbon and Plugin Hub. a dropdown picks what to search:
--   Monsters   by name or location, as before
--   Drops      by dropped item, then the monsters that drop it best chance first
--   Stats      bundled monsters ranked by a stat, bosses and instanced fights hidden unless
--              asked for, with optional level caps and a name filter
-- every mode answers from data on this device, typing never sends a request

local search = require("src/data/monster_search")
local stat_rankings = require("src/data/stat_rankings")
local window_state = require("src/ui/window_state")
local widgets = require("src/ui/widgets")
local text_layout = require("src/ui/text_layout")
local theme = require("src/ui/theme")
local internals = require("src/ui/prettyui_internals")

local search_window = {}
local GEOMETRY = {
    storage_key = "monster_lookup_search_window",
    width = 480,
    height = 360,
    minWidth = 320,
    minHeight = 220,
    maxWidth = 760,
    maxHeight = 700,
}

local MONSTERS, DROPS, STATS = 1, 2, 3
local MODES = {
    { name = "Monsters", placeholder = "Search monsters..." },
    { name = "Drops", placeholder = "Search dropped items..." },
    { name = "Stats", placeholder = "Filter by name or Slayer category..." },
}
local MODE_WIDTH = 120
local STAT_WIDTH = 220
local BOSS_WIDTH = 180
-- what Stats does with bosses, minions and instanced fights (see stat_rankings)
local BOSS_CHOICES = {
    { name = "No bosses or instances", filter = "hide" },
    { name = "Include bosses", filter = nil },
    { name = "Bosses only", filter = "only" },
}

local window, field, status, results_layer, on_select, mode_picker
local models = {}
local buttons = {}
local status_message = ""
local measured_width
local destroying = false
-- kept for the session, so reopening the window goes back to the last search
local mode = MONSTERS
local stats_state = { stat = 1, bosses = 1, query = "" }
local stat_controls

local function clear_results()
    for _, button in ipairs(buttons) do
        button:Destroy()
    end

    buttons = {}
end

-- bottom of the controls above the status line
local function controls_bottom(width)
    if not stat_controls then
        return 38
    end

    -- Fill each row rather than leaving the fixed-width fields stranded on the
    -- left. Stack dropdowns in narrow windows so their choices remain readable.
    local available = math.max(1, width - 16)
    local first_width = math.floor((available - 8) / 2)
    local second_width = available - first_width - 8
    local wide = width >= 420
    stat_controls.stat:SetPos(8, 44)
    stat_controls.stat:SetSize(wide and first_width or available, 28)
    stat_controls.bosses:SetPos(wide and (16 + first_width) or 8, wide and 44 or 78)
    stat_controls.bosses:SetSize(wide and second_width or available, 28)
    local level_y = wide and 78 or 112
    stat_controls.combat.root:SetPos(8, level_y)
    stat_controls.combat.root:SetSize(first_width, 28)
    stat_controls.slayer.root:SetPos(16 + first_width, level_y)
    stat_controls.slayer.root:SetSize(second_width, 28)
    return level_y + 28
end

local function layout()
    local width = window.content.width
    measured_width = width
    field.root:SetPos(16 + MODE_WIDTH, 8)
    field.root:SetSize(math.max(1, width - MODE_WIDTH - 24), 30)
    local top = controls_bottom(width) + 8
    local status_height = text_layout.height(
        status_message,
        math.max(1, width - 16),
        config.Font.MUSEO_SANS_11PT_REGULAR,
        16
    )
    status:SetPos(8, top)
    status:SetSize(-16, status_height, 1, 0)
    results_layer:SetPos(0, top + 8 + status_height)
    results_layer:SetHeight(#buttons * 36)
    window:SetContentHeight(top + 16 + status_height + #buttons * 36)
end

local function open_selection(monster)
    if monster then
        window:Close()
        on_select(monster)
    end
end

local function show_results(results, message, choose)
    if not window then
        return
    end

    clear_results()
    status_message = message
    status.content = text_layout.display(message)

    for index, result in ipairs(results) do
        local button = prettyui.SimpleButton.new(results_layer, result.label, function()
            choose(result)
        end, {
            x = 8,
            y = (index - 1) * 36,
            width = -16,
            widthAnchor = 1,
            height = 30,
            colour = theme.TEXT,
        })
        button.root:SetSize(-16, 30, 1, 0)
        widgets.forward_wheel(button.root, "monster_lookup_result_wheel", window)
        buttons[#buttons + 1] = button
    end

    layout()
    window:SetScrollPosition(0)
end

local function choose_from(model)
    return function(result)
        local selection = model.choose(result)

        -- an item from the drops list: fill in its full name, which lists who drops it
        if selection and selection.item then
            field:SetText(selection.item)
            model.set_query(selection.item)
            return
        end

        open_selection(selection)
    end
end

-- one model per search mode, the drops one only once its first used
local function model_for(which)
    if not models[which] then
        local model
        model = search.new(function(results, message)
            if mode == which then
                show_results(results, message, choose_from(model))
            end
        end, false, which == DROPS and "items" or nil)
        models[which] = model
    end

    return models[which]
end

local function whole_number(text)
    local digits = tostring(text or ""):match("^%s*(%d+)%s*$")
    return digits and tonumber(digits) or nil
end

local function open_stat_result(result)
    -- the info tab, since thats where the stat being ranked is
    open_selection({
        name = result.title,
        wiki_title = result.title,
        focus = { tab = "info" },
    })
end

local function rank_stats()
    if not window or mode ~= STATS then
        return
    end

    local choice = stat_rankings.STATS[stats_state.stat]
    local results, total = stat_rankings.rank(stats_state.stat, {
        query = stats_state.query,
        max_combat = stats_state.max_combat,
        max_slayer = stats_state.max_slayer,
        bosses = BOSS_CHOICES[stats_state.bosses].filter,
    })
    local message

    if total == 0 then
        message = "No monsters match these filters."
    else
        message = (
            total > #results and ("Top " .. #results .. " of " .. total) or (total .. " monsters")
        )
            .. " by "
            .. choice.label
            .. ". Select one to open its Monster info."
    end

    show_results(results, message, open_stat_result)
end

local function level_field(placeholder, value, on_change)
    local options = internals.text_field_scroll_options(window)
    options.width, options.widthAnchor, options.height = -16, 1, 28
    options.text = value and tostring(value) or ""
    options.maxLength = 5
    options.placeholder = placeholder
    options.onChange = function(_, _, text)
        on_change(whole_number(text))
        rank_stats()
    end
    local level = prettyui.TextField.new(window.content, options)
    widgets.forward_wheel(level.root, "monster_lookup_level_field_wheel", window)
    return level
end

local function destroy_stat_controls()
    if stat_controls then
        stat_controls.stat:Destroy()
        stat_controls.bosses:Destroy()
        stat_controls.combat:Destroy()
        stat_controls.slayer:Destroy()
        stat_controls = nil
    end
end

local function create_stat_controls()
    local entries, boss_entries = {}, {}

    for index, choice in ipairs(stat_rankings.STATS) do
        entries[index] = { text = choice.label, id = index - 1 }
    end

    for index, choice in ipairs(BOSS_CHOICES) do
        boss_entries[index] = { text = choice.name, id = index - 1 }
    end

    stat_controls = {
        stat = widgets.dropdown(window.content, {
            x = 8,
            y = 48,
            width = STAT_WIDTH,
            height = 28,
            entries = entries,
            selected = stats_state.stat - 1,
            on_change = function(entry_id)
                stats_state.stat = entry_id + 1
                rank_stats()
            end,
        }),
        bosses = widgets.dropdown(window.content, {
            x = 16 + STAT_WIDTH,
            y = 48,
            width = BOSS_WIDTH,
            height = 28,
            entries = boss_entries,
            selected = stats_state.bosses - 1,
            on_change = function(entry_id)
                stats_state.bosses = entry_id + 1
                rank_stats()
            end,
        }),
        combat = level_field("Max combat level", stats_state.max_combat, function(value)
            stats_state.max_combat = value
        end),
        slayer = level_field("Max Slayer level", stats_state.max_slayer, function(value)
            stats_state.max_slayer = value
        end),
    }
end

local function current_query()
    if mode == STATS then
        return stats_state.query
    end

    return model_for(mode).get_query()
end

local function create_search_field()
    local options = internals.text_field_scroll_options(window)
    options.x, options.y = 16 + MODE_WIDTH, 8
    options.width, options.widthAnchor, options.height = -(24 + MODE_WIDTH), 1, 30
    options.text = current_query()
    options.maxLength = 80
    options.placeholder = MODES[mode].placeholder
    options.onChange = function(_, _, text)
        if mode == STATS then
            stats_state.query = text
            rank_stats()
        else
            model_for(mode).set_query(text)
        end
    end
    field = prettyui.TextField.new(window.content, options)
    widgets.forward_wheel(field.root, "monster_lookup_name_field_wheel", window)
end

-- starts whatever the current mode needs, the field and stat controls are already there
local function start_mode()
    if mode == STATS then
        rank_stats()
    else
        model_for(mode).start()
    end
end

local function switch_mode(next_mode)
    if next_mode == mode or not MODES[next_mode] then
        return
    end

    if models[mode] then
        models[mode].stop()
    end

    mode = next_mode
    field:Destroy()
    destroy_stat_controls()
    clear_results()
    create_search_field()

    if mode == STATS then
        create_stat_controls()
    end

    start_mode()
    layout()
end

local function create_mode_picker()
    local entries = {}

    for index, entry in ipairs(MODES) do
        entries[index] = { text = entry.name, id = index - 1 }
    end

    mode_picker = widgets.dropdown(window.content, {
        x = 8,
        y = 8,
        width = MODE_WIDTH,
        height = 30,
        entries = entries,
        selected = mode - 1,
        on_change = function(entry_id)
            switch_mode(entry_id + 1)
        end,
    })
end

local function stop_models()
    for _, model in pairs(models) do
        model.stop()
    end
end

local function ensure_window()
    if window then
        return true
    end

    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)

    if not parent or parent.width <= 0 or parent.height <= 0 then
        return false
    end

    destroying = false
    local options = window_state.load(parent, GEOMETRY)
    options.title = "Monster search"
    options.resizable = true
    options.onClose = function()
        window_state.save(window, GEOMETRY)
        stop_models()
    end
    window = prettyui.Window.new(parent, options)
    create_mode_picker()
    create_search_field()

    if mode == STATS then
        create_stat_controls()
    end

    status = prettyui.Text.new(window.content, {
        x = 8,
        y = 48,
        width = -16,
        widthAnchor = 1,
        maxLines = 0,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        colour = theme.TEXT_MUTED,
        shadowed = false,
    })
    status.clickthrough, status.enabled = true, false
    results_layer = widgets.layer(window.content, 1)
    window.content:Subscribe(ui.Hook.ONRESIZE, "monster_lookup_name_search_resize", function()
        if not destroying and window and window.content.width ~= measured_width then
            layout()
        end
    end)
    return true
end

function search_window.start(select)
    on_select = select
    -- made now so the monster search is ready the moment the window opens
    model_for(MONSTERS)
end

function search_window.open()
    if ensure_window() then
        window:Show()
        start_mode()
    end
end

function search_window.destroy()
    destroying = true
    stop_models()
    clear_results()

    if window then
        window_state.save(window, GEOMETRY)
        field:Destroy()
        destroy_stat_controls()
        mode_picker:Destroy()
        window:Destroy()
        window, field, status, results_layer, measured_width = nil, nil, nil, nil, nil
        mode_picker = nil
    end

    models = {}
end

return search_window
