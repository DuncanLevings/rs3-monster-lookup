-- small native ui building blocks that more than one view needs

local theme = require("src/ui/theme")

local widgets = {}

function widgets.layer(parent, height)
    local layer = ui.Layer.new(parent)
    layer:SetSize(0, height, 1, 0)
    layer.clickthrough = true
    return layer
end

function widgets.background(parent, colour)
    local background = ui.Rectangle.new(parent)
    background:SetSize(0, 0, 1, 1)
    background.fill = true
    background.rgba = colour
    background.clickthrough = true
    return background
end

-- anything that takes mouse input swallows the scroll wheel, so pass it on to the page instead or
-- scrolling stops dead whenever the cursor is over a button or tooltip target
function widgets.forward_wheel(component, id, page, before_scroll)
    component:Subscribe(ui.Hook.ONSCROLLWHEEL, id, function(_, delta)
        if before_scroll then
            before_scroll()
        end

        page:ScrollBy(delta * theme.WHEEL_STEP)
        return false
    end)
end

-- runs a layout pass safely when resizing during layout fires resize hooks that ask for
-- another layout. a nested request just flags that one more pass is needed, and cap it
-- at two passes so a size that keeps flip flopping cant loop forever
function widgets.run_layout(state, layout)
    if state.laying_out then
        state.layout_requested = true
        return
    end

    state.laying_out = true

    for _ = 1, 2 do
        state.layout_requested = false
        layout()

        if not state.layout_requested then
            break
        end
    end

    state.laying_out = false
end

-- pick one of a few options. prettyuis ComboBox is built on the native ComboField which
-- always lets you type to filter, so this uses the native dropdown List instead which you
-- can only pick from
---@class DropdownOptions
---@field x number
---@field y number
---@field width number
---@field widthAnchor number? 1 makes width relative to the parent like other components
---@field height number
---@field entries {text: string, id: integer}[]
---@field selected integer id shown when it opens
---@field on_change fun(id: integer) only called when a different entry is picked

---@param options DropdownOptions
function widgets.dropdown(parent, options)
    local list = ui.List.new(parent)
    list.stylesheetID = id.StyleSheet.DROPDOWN_DEFAULT
    list:SetPos(options.x, options.y)
    list:SetSize(options.width, options.height, options.widthAnchor or 0, 0)
    list.entryHeight = 24
    list.dropdownMaxVisibleEntries = math.min(#options.entries, 8)

    for _, entry in ipairs(options.entries) do
        list:Add(entry.text, entry.id)
    end

    local current = options.selected
    list:SetEntrySelected(current, true, false)
    list:Subscribe(
        ui.Hook.ONSELECTIONCHANGED,
        "monster_lookup_dropdown",
        function(_, entry_id, selection_event)
            if selection_event == ui.SelectionChangeEvent.SELECTED and entry_id ~= current then
                current = entry_id
                options.on_change(entry_id)
            end

            return false
        end
    )

    return list
end

function widgets.hide_tooltips(tooltips)
    for _, tooltip in ipairs(tooltips) do
        tooltip:Hide()
    end
end

function widgets.destroy_tooltips(tooltips)
    for _, tooltip in ipairs(tooltips) do
        tooltip:Destroy()
    end
end

return widgets
