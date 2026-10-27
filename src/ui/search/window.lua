-- Owns search-window placement, visibility and opening the selected monster.

local search_view = require("src/ui/search/view")
local window_state = require("src/ui/common/window_state")

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

local window, view, on_select
-- the mode and stat filters, kept for the session so reopening (even after a logout
-- rebuilt the window) goes back to the last search
local saved_state

local function ensure_window()
    if window then
        return true
    end

    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)

    if not parent or parent.width <= 0 or parent.height <= 0 then
        return false
    end

    local options = window_state.load(parent, GEOMETRY)
    options.title = "Monster search"
    options.resizable = true
    options.onClose = function()
        window_state.save(window, GEOMETRY)

        if view then
            view.set_active(false)
        end
    end
    window = prettyui.Window.new(parent, options)
    view = search_view.new(window, {
        state = saved_state,
        on_select = function(selection)
            window:Close()

            if on_select then
                on_select(selection)
            end
        end,
    })
    return true
end

---@param select fun(selection: SearchSelection) opens the Monster Lookup window
function search_window.start(select)
    on_select = select
end

function search_window.open()
    if ensure_window() then
        window:Show()
        view.set_active(true)
    end
end

function search_window.destroy()
    if view then
        saved_state = view.state()
        view.destroy()
        view = nil
    end

    if window then
        window_state.save(window, GEOMETRY)
        window:Destroy()
        window = nil
    end
end

return search_window
