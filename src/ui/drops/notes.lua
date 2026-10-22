-- wiki text that can be shown or hidden: the numbered footnotes under a drop table and long
-- explanations above it. both start hidden so the drops are easy to scan

local text_layout = require("src/ui/common/text_layout")
local theme = require("src/ui/common/theme")
local widgets = require("src/ui/common/widgets")
local internals = require("src/ui/common/prettyui_internals")

local drop_notes = {}

local function update_toggle(controller)
    local action = controller.expanded and "Hide" or "Show"
    internals.set_button_text(
        controller.toggle,
        controller.caption and (controller.expanded and "Hide notes" or controller.caption)
            or action .. " drop notes (" .. #controller.entries .. ")"
    )
end

-- note numbers some row in the table actually points at, eg markers "1" and "1,3" -> {1, 3}
function drop_notes.referenced_numbers(drops)
    local numbers = {}

    for _, drop in ipairs(drops) do
        for number in (drop.note_marker or ""):gmatch("%d+") do
            numbers[tonumber(number)] = true
        end
    end

    return numbers
end

---@param parent table section body the toggle goes in
---@param entries table[] text entries made by drop_table for each note
---@param on_toggle fun() called after showing or hiding so the table can relayout
---@param page table page to forward wheel scrolling to
---@param caption string? label for the explanation button above a table
function drop_notes.new(parent, entries, on_toggle, page, caption)
    local controller = { entries = entries, expanded = false, caption = caption }

    controller.toggle = prettyui.SimpleButton.new(parent, "", function()
        controller.expanded = not controller.expanded
        update_toggle(controller)
        on_toggle()
    end, {
        x = 8,
        width = caption and 96 or 176,
        height = 24,
        colour = theme.TEXT_MUTED,
        shadowed = false,
    })
    internals.set_button_font(controller.toggle, id.Font.MUSEO_SANS_11PT_REGULAR)

    update_toggle(controller)
    widgets.forward_wheel(controller.toggle.root, "monster_lookup_notes_wheel", page)

    return controller
end

-- positions the toggle and any visible notes from y down, returns the y below them
function drop_notes.layout(controller, width, y)
    local gap = controller.caption and 0 or 8
    controller.toggle.root:SetPos(8, y + gap)

    y = y + gap + 32

    for _, entry in ipairs(controller.entries) do
        entry.label.hidden = not controller.expanded

        if controller.expanded then
            local height = text_layout.entry_height(entry, width - 16)
            entry.label:SetPos(8, y)
            entry.label:SetSize(-16, height, 1, 0)
            y = y + height + 8
        end
    end

    return y
end

return drop_notes
