-- prettyui tooltip that shows under (or above) whatever its attached to, kept inside the
-- window. used for rarity footnotes and the stat icons

local text_layout = require("src/ui/text_layout")
local widgets = require("src/ui/widgets")

local hover_tooltip = {}
local GAP = 6

local function position_tooltip(tooltip, label, page, overlay_parent)
    local target = label.xyGlobal
    local origin = overlay_parent.xyGlobal
    local popup = tooltip.root
    local x = target.x - origin.x

    -- global layout coordinates don't include the viewport's scroll offset
    local target_y = target.y - origin.y - page.scrollY
    local y = target_y + label.height + GAP

    -- no room below so flip it above the target
    if y + popup.height > overlay_parent.height - GAP then
        y = target_y - popup.height - GAP
    end

    x = math.max(GAP, math.min(x, overlay_parent.width - popup.width - GAP))
    y = math.max(GAP, math.min(y, overlay_parent.height - popup.height - GAP))
    popup:SetPos(x, y)
end

---@param page table scrolling page the target sits on
---@param target table component to hover over
---@param parent table component the tooltip is drawn in, normally the whole game area
---@param text string
function hover_tooltip.attach(page, target, parent, text)
    local tooltip = prettyui.Tooltip.attach(target, parent, {
        parent = parent,
        text = text_layout.display(text),
        maxWidth = math.min(380, parent.width - 12),
    })
    target.enabled = true
    target.clickthrough = false
    target:Subscribe(ui.Hook.ONMOUSEOVER, "monster_lookup_tip_position", function()
        position_tooltip(tooltip, target, page, parent)
    end)
    widgets.forward_wheel(target, "monster_lookup_tip_wheel", page, function()
        tooltip:Hide()
    end)

    return tooltip
end

return hover_tooltip
