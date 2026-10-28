-- Three local searches: monster names/locations, dropped items and stat rankings.
-- The search window owns this view; searches run only while it is active.

local search = require("src/data/search/monsters")
local core = require("src/data/library/api")
local widgets = require("src/ui/common/widgets")
local text_layout = require("src/ui/common/text_layout")
local theme = require("src/ui/common/theme")

local search_view = {}

local MODES = {
    monsters = { name = "Monsters", placeholder = "Search monsters..." },
    items = { name = "Drops", placeholder = "Search dropped items..." },
    stats = { name = "Stats", placeholder = "Filter by name or Slayer category..." },
}
local MODE_ORDER = { "monsters", "items", "stats" }

local MODE_WIDTH = 120
local STAT_WIDTH = 220
local BOSS_WIDTH = 180
-- what Stats does with bosses, minions and instanced fights (see stat_rankings)
local BOSS_CHOICES = {
    { name = "No bosses or instances", filter = "hide" },
    { name = "Include bosses", filter = nil },
    { name = "Bosses only", filter = "only" },
}

-- hook ids have to differ between two views on the same page
local next_id = 0

local function whole_number(text)
    local digits = tostring(text or ""):match("^%s*(%d+)%s*$")
    return digits and tonumber(digits) or nil
end

---@class SearchSelection
---@field name string
---@field wiki_title string?
---@field npc_id integer?
---@field focus WindowFocus? where the standard window would start: an item to filter the
---drops on and its mode (drop search), or the info tab (stat search)

---@class SearchViewState
---@field mode string
---@field stats { stat: integer, bosses: integer, query: string, max_combat: integer?, max_slayer: integer? }

---@class SearchViewOptions
---@field on_select fun(selection: SearchSelection) a monster was picked
---@field state SearchViewState? from an earlier view's state(), to carry on where it was

---@param page table PrettyUI scrolling page: content, SetContentHeight, SetScrollPosition, ScrollBy
---@param options SearchViewOptions
function search_view.new(page, options)
    next_id = next_id + 1
    local resize_hook = "monster_lookup_search_resize_" .. next_id
    local saved = options.state or {}
    local self = {}
    local view = {
        mode = MODE_ORDER[1],
        stats = {
            stat = 1,
            bosses = 1,
            query = "",
        },
        runners = {},
        buttons = {},
        status_message = "",
        active = false,
    }

    for _, name in ipairs(MODE_ORDER) do
        if name == saved.mode then
            view.mode = name
        end
    end

    for key, value in pairs(saved.stats or {}) do
        view.stats[key] = value
    end

    local picker_width = MODE_WIDTH + 8

    local function clear_results()
        for _, button in ipairs(view.buttons) do
            button:Destroy()
        end

        view.buttons = {}
    end

    -- bottom of the controls above the status line
    local function controls_bottom(width)
        local controls = view.stat_controls

        if not controls then
            return 38
        end

        -- the controls share the full width instead of sitting at a fixed width on the left,
        -- and in a narrow window the dropdowns stack so their text still fits
        local available = math.max(1, width - 16)
        local first_width = math.floor((available - 8) / 2)
        local second_width = available - first_width - 8
        local wide = width >= 420
        controls.stat:SetPos(8, 44)
        controls.stat:SetSize(wide and first_width or available, 28)
        controls.bosses:SetPos(wide and (16 + first_width) or 8, wide and 44 or 78)
        controls.bosses:SetSize(wide and second_width or available, 28)
        local level_y = wide and 78 or 112
        controls.combat.root:SetPos(8, level_y)
        controls.combat.root:SetSize(first_width, 28)
        controls.slayer.root:SetPos(16 + first_width, level_y)
        controls.slayer.root:SetSize(second_width, 28)
        return level_y + 28
    end

    local function layout()
        if view.destroyed then
            return
        end

        local width = page.content.width
        view.measured_width = width
        view.field.root:SetPos(8 + picker_width, 8)
        view.field.root:SetSize(math.max(1, width - picker_width - 16), 30)
        local top = controls_bottom(width) + 8
        local status_height = text_layout.height(
            view.status_message,
            math.max(1, width - 16),
            config.Font.MUSEO_SANS_11PT_REGULAR,
            16
        )
        view.status:SetPos(8, top)
        view.status:SetSize(-16, status_height, 1, 0)
        view.results:SetPos(0, top + 8 + status_height)
        view.results:SetHeight(#view.buttons * 36)
        local height = top + 16 + status_height + #view.buttons * 36

        page:SetContentHeight(height)
    end

    local function show_results(results, message, choose)
        if view.destroyed then
            return
        end

        clear_results()
        view.status_message = message
        view.status.content = text_layout.display(message)

        for index, result in ipairs(results) do
            local button = prettyui.SimpleButton.new(view.results, result.label, function()
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
            widgets.forward_wheel(button.root, "monster_lookup_result_wheel", page)
            view.buttons[#view.buttons + 1] = button
        end

        layout()
        page:SetScrollPosition(0)
    end

    local function select(selection)
        if selection and options.on_select then
            options.on_select(selection)
        end
    end

    local function choose_from(runner)
        return function(result)
            local selection = runner.choose(result)

            -- an item from the drops list: fill in its full name, which lists who drops it
            if selection and selection.item then
                view.field:SetText(selection.item)
                runner.set_query(selection.item)
                return
            end

            select(selection)
        end
    end

    -- one runner per name search mode, made the first time that mode is used
    local function runner_for(mode)
        if not view.runners[mode] then
            local runner
            runner = search.new(function(results, message)
                if view.mode == mode and not view.destroyed then
                    show_results(results, message, choose_from(runner))
                end
            end, mode == "items" and "items" or nil)
            view.runners[mode] = runner
        end

        return view.runners[mode]
    end

    local function open_stat_result(result)
        -- the info tab, since thats where the stat being ranked is
        select({
            name = result.title,
            wiki_title = result.title,
            focus = { tab = "info" },
        })
    end

    local function rank_stats()
        if view.destroyed or view.mode ~= "stats" or not view.active then
            return
        end

        local stats = view.stats
        local choice = core.stat_choices()[stats.stat] or core.stat_choices()[1]
        local results, total = core.stat_ranking(stats.stat, {
            query = stats.query,
            max_combat = stats.max_combat,
            max_slayer = stats.max_slayer,
            bosses = BOSS_CHOICES[stats.bosses].filter,
        })
        local message

        if total == 0 then
            message = "No monsters match these filters."
        else
            message = (
                total > #results and ("Top " .. #results .. " of " .. total)
                or (total .. " monsters")
            )
                .. " by "
                .. choice.label
                .. ". Select one to open its Monster info."
        end

        show_results(results, message, open_stat_result)
    end

    local function level_field(placeholder, value, on_change)
        local field_options = { absolute = true }
        field_options.width, field_options.widthAnchor, field_options.height = -16, 1, 28
        field_options.text = value and tostring(value) or ""
        field_options.maxLength = 5
        field_options.placeholder = placeholder
        field_options.onChange = function(_, _, text)
            on_change(whole_number(text))
            rank_stats()
        end

        return page:AddTextField(field_options)
    end

    local function destroy_stat_controls()
        local controls = view.stat_controls

        if controls then
            controls.stat:Destroy()
            controls.bosses:Destroy()
            controls.combat:Destroy()
            controls.slayer:Destroy()
            view.stat_controls = nil
        end
    end

    local function create_stat_controls()
        local entries, boss_entries = {}, {}
        local stats = view.stats

        for index, choice in ipairs(core.stat_choices()) do
            entries[index] = { text = choice.label, id = index - 1 }
        end

        for index, choice in ipairs(BOSS_CHOICES) do
            boss_entries[index] = { text = choice.name, id = index - 1 }
        end

        view.stat_controls = {
            stat = widgets.dropdown(page.content, {
                x = 8,
                y = 48,
                width = STAT_WIDTH,
                height = 28,
                entries = entries,
                selected = stats.stat - 1,
                on_change = function(entry_id)
                    stats.stat = entry_id + 1
                    rank_stats()
                end,
            }),
            bosses = widgets.dropdown(page.content, {
                x = 16 + STAT_WIDTH,
                y = 48,
                width = BOSS_WIDTH,
                height = 28,
                entries = boss_entries,
                selected = stats.bosses - 1,
                on_change = function(entry_id)
                    stats.bosses = entry_id + 1
                    rank_stats()
                end,
            }),
            combat = level_field("Max combat level", stats.max_combat, function(value)
                stats.max_combat = value
            end),
            slayer = level_field("Max Slayer level", stats.max_slayer, function(value)
                stats.max_slayer = value
            end),
        }
    end

    local function current_query()
        if view.mode == "stats" then
            return view.stats.query
        end

        -- a mode thats never been started has no runner yet, and no query
        local runner = view.runners[view.mode]
        return runner and runner.get_query() or ""
    end

    local function create_search_field()
        local field_options = { absolute = true }
        field_options.x, field_options.y = 8 + picker_width, 8
        field_options.width, field_options.widthAnchor, field_options.height =
            -(16 + picker_width), 1, 30
        field_options.text = current_query()
        field_options.maxLength = 80
        field_options.placeholder = MODES[view.mode].placeholder
        field_options.onChange = function(_, _, text)
            if view.mode == "stats" then
                view.stats.query = text
                rank_stats()
            else
                runner_for(view.mode).set_query(text)
            end
        end
        view.field = page:AddTextField(field_options)
    end

    -- starts whatever the current mode needs, the field and stat controls are already there
    local function start_mode()
        if view.mode == "stats" then
            rank_stats()
        else
            runner_for(view.mode).start()
        end
    end

    local function stop_runners()
        for _, runner in pairs(view.runners) do
            runner.stop()
        end
    end

    local function switch_mode(next_mode)
        if next_mode == view.mode or not MODES[next_mode] then
            return
        end

        if view.runners[view.mode] then
            view.runners[view.mode].stop()
        end

        view.mode = next_mode
        view.field:Destroy()
        destroy_stat_controls()
        clear_results()
        create_search_field()

        if view.mode == "stats" then
            create_stat_controls()
        end

        if view.active then
            start_mode()
        end

        layout()
    end

    do
        local entries, selected = {}, 0

        for index, name in ipairs(MODE_ORDER) do
            entries[index] = { text = MODES[name].name, id = index - 1 }

            if name == view.mode then
                selected = index - 1
            end
        end

        view.picker = widgets.dropdown(page.content, {
            x = 8,
            y = 8,
            width = MODE_WIDTH,
            height = 30,
            entries = entries,
            selected = selected,
            on_change = function(entry_id)
                switch_mode(MODE_ORDER[entry_id + 1])
            end,
        })
    end

    create_search_field()

    if view.mode == "stats" then
        create_stat_controls()
    end

    view.status = prettyui.Text.new(page.content, {
        x = 8,
        y = 48,
        width = -16,
        widthAnchor = 1,
        maxLines = 0,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        colour = theme.TEXT_MUTED,
        shadowed = false,
    })
    view.status.clickthrough, view.status.enabled = true, false
    view.results = widgets.layer(page.content, 1)
    page.content:Subscribe(ui.Hook.ONRESIZE, resize_hook, function()
        if view.active and not view.destroyed and page.content.width ~= view.measured_width then
            layout()
        end
    end)

    ---true starts searching (the index loads, a stored query runs again), false stops it
    function self.set_active(active)
        active = active == true

        if view.destroyed or view.active == active then
            return
        end

        view.active = active

        if active then
            start_mode()
            layout()
        else
            stop_runners()
        end
    end

    ---the mode and stat filters, to start a later view where this one was
    ---@return SearchViewState
    function self.state()
        local stats = {}

        for key, value in pairs(view.stats) do
            stats[key] = value
        end

        return { mode = view.mode, stats = stats }
    end

    function self.destroy()
        if view.destroyed then
            return
        end

        stop_runners()
        clear_results()
        view.destroyed = true
        view.field:Destroy()
        destroy_stat_controls()
        view.picker:Destroy()
        view.status:Destroy()
        view.results:Destroy()
        view.runners = {}
    end

    return self
end

return search_view
