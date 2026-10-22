-- the Monster info pieces as components anyone can place: the stat summary (or some of its
-- fields), weaknesses and immunities, Slayer info and detailed stats. the standard Monster
-- info tab (view.lua) is built from these, other plugins get the same ones
--
-- every component lives under the parent its given and only touches what it made itself.
-- it doesnt know about the standard window, tabs or settings: whatever owns it decides the
-- size and position (layout), which monster it shows (set_info) and when its destroyed.
-- a component that has nothing to show (no Slayer data) says so with empty() and draws nothing
--
--   local stats = components.stats(parent, { overlay_parent = game_area })
--   stats.set_info(info, title)  -- one variants infobox values, eg MonsterData.variants(record)[1].info
--   local height = stats.layout(300, 0)
--   ...
--   stats.destroy()

local core = require("src/data/core")
local stat_blocks = require("src/ui/info/stat_blocks")
local widgets = require("src/ui/common/widgets")

local components = {}

---@class InfoComponentOptions
---@field overlay_parent table? where tooltips draw, normally the game area. defaults to parent
---@field page table? the PrettyUI scrolling page the component sits on, if any. lets tooltip
---targets and group headers pass the scroll wheel on to it
---@field fields string[]? stats only: which summary rows to show (stat_blocks.SUMMARY_FIELDS)
---@field expanded boolean? slayer and detailed_stats only: start open (default true)
---@field on_toggle fun(open: boolean)? slayer and detailed_stats only: after the player opened or
---closed it. its height changed, so lay out again here

---@class InfoComponent
---@field set_info fun(info: table, title: string?) show one variant, title is the wiki page
---@field layout fun(width: number, y: number?): number size and place it, returns its height
---@field height fun(): number height from the last layout
---@field empty fun(): boolean nothing to show for this monster
---@field hide_tooltips fun()
---@field destroy fun()

-- builds a component around one block. make(context, parent, sections) returns the block or
-- nil when theres nothing to show
local function component(parent, options, make)
    options = options or {}
    local context = {
        page = options.page,
        overlay_parent = options.overlay_parent or parent,
        tooltips = {},
    }
    local state = { height = 0 }
    local self = {}

    local function clear()
        widgets.destroy_tooltips(context.tooltips)
        context.tooltips = {}

        if state.block then
            if state.block.toggle then
                state.block.toggle:Destroy()
            end

            state.block.root:Destroy()
            state.block = nil
        end

        state.height = 0
    end

    function self.set_info(info, title)
        if state.destroyed then
            return
        end

        clear()
        local data = core.stat_sections(type(info) == "table" and info or {}, title)
        state.block = make(context, parent, data.sections)
    end

    function self.layout(width, y)
        if state.destroyed or not state.block then
            return 0
        end

        local height = stat_blocks.layout(state.block, width, y or 0)
        state.block.root:SetSize(width, height)
        state.height = height
        return height
    end

    function self.height()
        return state.height
    end

    function self.empty()
        return state.block == nil
    end

    function self.hide_tooltips()
        widgets.hide_tooltips(context.tooltips)
    end

    function self.destroy()
        if state.destroyed then
            return
        end

        clear()
        state.destroyed = true
    end

    return self
end

local function sections_titled(sections, titles)
    local found = {}

    for _, section in ipairs(sections) do
        if titles[section.title] or (titles.detailed and section.detailed) then
            found[#found + 1] = section
        end
    end

    return found
end

---the short summary from the Monster info tab: weakness, aggressive, susceptibilities and
---immunities, or just the rows named in options.fields
---@param options InfoComponentOptions?
---@return InfoComponent
function components.stats(parent, options)
    local fields = options and options.fields

    return component(parent, options, function(context, into, sections)
        local summary = stat_blocks.summary(sections, fields)
        return summary and #summary.rows > 0 and stat_blocks.section(context, into, summary) or nil
    end)
end

---weakness, what its susceptible to and its immunities. the stats component with those rows
---@param options InfoComponentOptions?
---@return InfoComponent
function components.weaknesses(parent, options)
    local merged = {}

    for key, value in pairs(options or {}) do
        merged[key] = value
    end

    merged.fields = merged.fields
        or { "Weakness", "Susceptible to", "Poison", "Stun", "Deflect", "Stat drain" }
    return components.stats(parent, merged)
end

local function group_component(parent, options, title, titles)
    options = options or {}

    return component(parent, options, function(context, into, sections)
        local found = sections_titled(sections, titles)

        if #found == 0 then
            return nil
        end

        return stat_blocks.group(context, into, title, found, {
            expanded = options.expanded,
            on_toggle = options.on_toggle,
        })
    end)
end

---Slayer level, xp, category and masters, plus the Player-owned Slayer Dungeon entry when
---there is one, under a collapsible Slayer header
---@param options InfoComponentOptions?
---@return InfoComponent
function components.slayer(parent, options)
    return group_component(parent, options, "Slayer", {
        Slayer = true,
        ["Player-owned Slayer Dungeon"] = true,
    })
end

---combat info, offensive and defensive stats and hit chances, under a collapsible
---Detailed stats header
---@param options InfoComponentOptions?
---@return InfoComponent
function components.detailed_stats(parent, options)
    return group_component(parent, options, "Detailed stats", { detailed = true })
end

components.SUMMARY_FIELDS = stat_blocks.SUMMARY_FIELDS
return components
