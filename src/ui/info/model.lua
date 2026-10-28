-- the monster model beside the Monster info summary. the info view gives it a parent, size
-- and position and says which monster to show, everything about the model itself (picking
-- the npc, framing it, cutting it off at the edges, the native model) stays in here and
-- preview.lua
--
-- it only draws while active: set_active(false) destroys the native model and its frame,
-- set_active(true) makes them again. so a hidden tab, a closed window or anything off
-- screen costs nothing. drag to turn only where the client supports it (see preview.lua)

local preview = require("src/ui/info/preview")
local widgets = require("src/ui/common/widgets")

local model_viewer = {}

local TURN_HINT =
    "Drag to turn the monster preview, Shift+drag to move it up or down, scroll to zoom."
local ZOOM_HINT = "Scroll to zoom the monster preview."

---@class ModelOptions
---@field width number
---@field height number
---@field overlay_parent table? where the controls hint tooltip draws, no hint without it

---@class MonsterModelSelection
---@field title string wiki page title, the bundled npc ids come from it
---@field info table? the variants infobox values, its combat level picks the matching npc
---@field selection table? the MonsterSelection it was opened from, its npc_id is tried first

---@param options ModelOptions
function model_viewer.new(parent, options)
    local state = {
        width = options.width,
        height = options.height,
        x = 0,
        y = 0,
        active = false,
    }
    local viewer = {}

    local function clear()
        if state.tooltip then
            state.tooltip:Destroy()
            state.tooltip = nil
        end

        if state.component then
            preview.destroy(state.component)
            state.component = nil
        end

        if state.frame then
            state.frame:Destroy()
            state.frame = nil
        end
    end

    local function place()
        if not state.frame then
            return
        end

        state.frame:SetSize(state.width, state.height)
        state.frame:SetScrollSize(state.width, state.height)
        state.frame:SetPos(state.x, state.y)

        if state.component then
            preview.resize(state.component, state.width, state.height)
            state.component:SetPos(0, 0)
        end
    end

    local function build()
        local monster = state.monster

        if state.component or state.failed or not monster or state.destroyed then
            return
        end

        -- the model can draw outside its own box, so it sits in a layer of its own that cuts
        -- it off at the edges, the same way a scrolling page does
        state.frame = widgets.layer(parent, state.height)
        state.component = preview.create(
            state.frame,
            monster.title,
            monster.info or {},
            monster.selection,
            function()
                if state.tooltip then
                    state.tooltip:Hide()
                end
            end
        )

        -- no model for this monster (new to the wiki, or the client cant draw it). dont try
        -- again until its given another monster
        if not state.component then
            state.failed = true
            clear()
            return
        end

        if options.overlay_parent then
            -- a plain prettyui tooltip, not the stat tooltip helper. that one passes the
            -- scroll wheel on to the page, which would scroll it while zooming
            state.tooltip = prettyui.Tooltip.attach(state.component, options.overlay_parent, {
                text = preview.can_turn(state.component) and TURN_HINT or ZOOM_HINT,
                maxWidth = 260,
            })
        end

        place()
    end

    ---the monster to show. replaces the current model, nothing is drawn until its active
    ---@param monster MonsterModelSelection?
    function viewer.set_monster(monster)
        clear()
        state.failed = false
        state.monster = monster

        if state.active then
            build()
        end
    end

    ---true makes the native model, false destroys it (no drawing while hidden)
    function viewer.set_active(active)
        state.active = active == true

        if state.active then
            build()
        else
            clear()
        end
    end

    function viewer.resize(width, height)
        state.width, state.height = width, height
        place()
    end

    function viewer.set_position(x, y)
        state.x, state.y = x, y
        place()
    end

    ---true while a model is showing
    function viewer.showing()
        return state.component ~= nil
    end

    function viewer.hide_tooltip()
        if state.tooltip then
            state.tooltip:Hide()
        end
    end

    function viewer.destroy()
        if state.destroyed then
            return
        end

        clear()
        state.destroyed = true
    end

    return viewer
end

return model_viewer
