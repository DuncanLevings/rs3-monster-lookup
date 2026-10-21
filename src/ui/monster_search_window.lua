local search = require("src/data/monster_search")
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
local model, window, field, status, results_layer, on_select
local buttons = {}
local status_message = ""
local measured_width
local destroying = false

local function clear_results()
    for _, button in ipairs(buttons) do
        button:Destroy()
    end

    buttons = {}
end

local function layout()
    local width = window.content.width
    measured_width = width
    local status_height = text_layout.height(
        status_message,
        math.max(1, width - 16),
        config.Font.MUSEO_SANS_11PT_REGULAR,
        16
    )
    status:SetSize(-16, status_height, 1, 0)
    results_layer:SetPos(0, 56 + status_height)
    results_layer:SetHeight(#buttons * 36)
    window:SetContentHeight(64 + status_height + #buttons * 36)
end

local function open_selection(monster)
    if monster then
        window:Close()
        on_select(monster)
    end
end

local function select_result(result)
    open_selection(model.choose(result))
end

local function show_results(results, message)
    if not window then
        return
    end

    clear_results()
    status_message = message
    status.content = text_layout.display(message)

    for index, result in ipairs(results) do
        local button = prettyui.SimpleButton.new(results_layer, result.label, function()
            select_result(result)
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

local function create_search_field()
    local options = internals.text_field_scroll_options(window)
    options.x, options.y = 8, 8
    options.width, options.widthAnchor, options.height = -16, 1, 32
    options.text = model.get_query()
    options.maxLength = 80
    options.placeholder = "Search monsters..."
    options.onChange = function(_, _, text)
        model.set_query(text)
    end
    field = prettyui.TextField.new(window.content, options)
    widgets.forward_wheel(field.root, "monster_lookup_name_field_wheel", window)
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
        model.stop()
    end
    window = prettyui.Window.new(parent, options)
    create_search_field()
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
    model = search.new(show_results)
end

function search_window.open()
    if ensure_window() then
        window:Show()
        model.start()
    end
end

function search_window.destroy()
    destroying = true
    if model then
        model.stop()
    end

    clear_results()

    if window then
        window_state.save(window, GEOMETRY)
        field:Destroy()
        window:Destroy()
        window, field, status, results_layer, measured_width = nil, nil, nil, nil, nil
    end
end

return search_window
