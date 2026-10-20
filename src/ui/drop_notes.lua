-- the "Show drop notes (n)" toggle under a table and the numbered footnotes it reveals
-- notes start hidden since some boss pages have a lot of them

local text_layout = require("src/ui/text_layout")
local theme = require("src/ui/theme")
local widgets = require("src/ui/widgets")
local internals = require("src/ui/prettyui_internals")

local drop_notes = {}

local function update_toggle(controller)
    local action = controller.expanded and "Hide" or "Show"
    internals.set_button_text(
        controller.toggle,
        action .. " drop notes (" .. #controller.entries .. ")"
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
function drop_notes.new(parent, entries, on_toggle, page)
    local controller = { entries = entries, expanded = false }
    controller.toggle = prettyui.SimpleButton.new(parent, "", function()
        controller.expanded = not controller.expanded
        update_toggle(controller)
        on_toggle()
    end, {
        x = 8,
        width = 176,
        height = 24,
        colour = theme.TEXT_MUTED,
        shadowed = false,
    })
    controller.toggle.content.font = id.Font.MUSEO_SANS_11PT_REGULAR
    update_toggle(controller)
    widgets.forward_wheel(controller.toggle.root, "monster_lookup_notes_wheel", page)

    return controller
end

-- positions the toggle and any visible notes from y down, returns the y below them
function drop_notes.layout(controller, width, y)
    controller.toggle.root:SetPos(8, y + 8)
    y = y + 40

    for _, entry in ipairs(controller.entries) do
        entry.label.hidden = not controller.expanded

        if controller.expanded then
            local height =
                text_layout.height(entry.value, width - 16, entry.font, entry.line_height)
            entry.label:SetPos(8, y)
            entry.label:SetSize(-16, height, 1, 0)
            y = y + height + 8
        end
    end

    return y
end

return drop_notes
