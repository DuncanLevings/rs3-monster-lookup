-- the drop tables as a component: what the Drops tab shows, for one monster, in a
-- PrettyUI scrolling page the caller owns. each one keeps its own search text, drop mode and
-- which sections are open, and redraws itself when live GE prices turn up
--
--   local drops = drops_component.new(tab_page, { overlay_parent = game_area })
--   drops.set_monster(record)  -- a MonsterResult, eg from MonsterData.monster()
--   ...
--   drops.destroy()

local drop_table = require("src/ui/drops/table")
local core = require("src/data/core")
local prices = require("src/data/drops/prices")

local drops_component = {}
local next_id = 0

---@class DropsComponentOptions
---@field overlay_parent table? where tooltips draw, normally the game area. defaults to the page
---@field percentage_rarity boolean? rarities as percentages instead of fractions
---@field live_prices boolean? use GE Price Library prices when its installed (default true)
---@field search boolean? false leaves out the search box
---@field kill_value boolean? false leaves out the average kill line
---@field status (string|fun(): string)? a line under the buttons, eg where the data came
---from. a function is asked again on every redraw (live prices arriving change it)
---@field problem string? a refresh error, shows the status line as a warning
---@field on_mode_change fun(mode: string?)? the player picked another drop mode

---@class DropsComponentFocus
---@field item string? fill the search with this item
---@field mode string? start on this drop mode eg "Hard mode"

---@param page table PrettyUI scrolling page: content, root, SetContentHeight, SetScrollPosition
---@param options DropsComponentOptions?
function drops_component.new(page, options)
    -- a copy, configure() changes it and the callers table stays as it was
    local settings = {}

    for key, value in pairs(options or {}) do
        settings[key] = value
    end

    options = settings
    next_id = next_id + 1
    local price_key = "drops_component_" .. next_id
    local state = { search_query = "", mode = 1, section_state = {} }
    local self = {}
    local render

    local function draw()
        if state.controller then
            state.controller.destroy()
            state.controller = nil
        end

        if state.destroyed then
            return
        end

        -- no monster still draws (empty) tables, so the page height and status line reset
        local sections = state.record and state.record.sections or {}
        local live = options.live_prices ~= false
        state.controller = drop_table.render(page, sections, options.overlay_parent or page.root, {
            percentage_rarity = options.percentage_rarity == true,
            price_for = live and prices.for_drop or nil,
            unit_price = live and prices.unit or nil,
            status = type(options.status) == "function" and options.status() or options.status,
            problem = options.problem,
            search = options.search,
            kill_value = options.kill_value,
            search_query = state.search_query,
            on_search_change = function(query)
                state.search_query = query
            end,
            mode = state.mode,
            section_state = state.section_state,
            on_mode_change = function(mode)
                state.mode = mode
                state.controller.hide_tooltips()
                render()
                page:SetScrollPosition(0)

                if options.on_mode_change then
                    options.on_mode_change(self.mode())
                end
            end,
        })
    end

    render = function()
        draw()

        -- gepl may still be loading prices. draw with the saved ones now and once more when
        -- the live ones arrive, if this is still the monster showing
        local sections = state.record and state.record.sections or {}

        if #sections > 0 and options.live_prices ~= false then
            local record = state.record

            prices.when_live(price_key, function()
                if not state.destroyed and state.record == record then
                    draw()
                end
            end)
        end
    end

    ---show a monster, a fresh search, mode and open sections unless focus says otherwise
    ---@param record MonsterResult?
    ---@param focus DropsComponentFocus?
    function self.set_monster(record, focus)
        if state.destroyed then
            return
        end

        state.record = record
        state.search_query = focus and focus.item or ""
        state.mode = 1
        state.section_state = {}

        if record and focus and focus.mode then
            for index, group in ipairs(core.drop_modes(record.sections or {}) or {}) do
                if group.name == focus.mode then
                    state.mode = index
                end
            end
        end

        render()
    end

    ---a newer copy of the same monster (a refresh came in), keeping the search, mode and open
    ---sections the player picked
    ---@param record MonsterResult?
    function self.update(record)
        if state.destroyed then
            return
        end

        state.record = record
        render()
    end

    ---change options from DropsComponentOptions (overlay_parent excepted). takes effect on the
    ---next set_monster, update or refresh
    ---@param changes DropsComponentOptions
    function self.configure(changes)
        for key, value in pairs(changes or {}) do
            if key ~= "overlay_parent" then
                options[key] = value
            end
        end
    end

    ---draw again with the same monster, keeping the search, mode and open sections (eg after
    ---the caller changed an option or prices came and went)
    function self.refresh()
        if not state.destroyed then
            render()
        end
    end

    ---the drop mode showing, eg "Hard mode", nil when the page isnt split into modes
    ---@return string?
    function self.mode()
        local groups = state.record and core.drop_modes(state.record.sections or {})
        local group = groups and groups[math.min(state.mode, #groups)]
        return group and group.name or nil
    end

    function self.hide_tooltips()
        if state.controller then
            state.controller.hide_tooltips()
        end
    end

    function self.destroy()
        if state.destroyed then
            return
        end

        state.destroyed = true
        prices.forget(price_key)

        if state.controller then
            state.controller.destroy()
            state.controller = nil
        end
    end

    return self
end

return drops_component
