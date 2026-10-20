-- small native ui building blocks that more than one view needs

local theme = require("src/ui/theme")

local widgets = {}

-- full width layer that doesnt take mouse input
function widgets.layer(parent, height)
    local layer = ui.Layer.new(parent)
    layer:SetSize(0, height, 1, 0)
    layer.clickthrough = true
    return layer
end

-- solid rectangle filling its parent
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
