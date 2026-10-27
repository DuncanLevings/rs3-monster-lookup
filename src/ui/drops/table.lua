-- the Drops tab: toolbar, search, then one collapsible table per wiki drop section
--
-- everything here is positioned explicitly to keep search, collapse and resize behavior together.
-- big boss pages can have hundreds of rows and need to hide rows for search, collapse sections and
-- reflow notes when the window is resized without rebuilding the lot. so each section is a
-- CollapseButton header plus a plain layer body, and position_sections() stacks them
--
-- render() returns a small controller, the window throws it away and calls render again
-- whenever the data or settings change

local formatting = require("src/ui/drops/formatting")
local text_layout = require("src/ui/common/text_layout")
local hover_tooltip = require("src/ui/common/hover_tooltip")
local theme = require("src/ui/common/theme")
local widgets = require("src/ui/common/widgets")
local internals = require("src/ui/common/prettyui_internals")

local core = require("src/data/library/api")
local drop_search = require("src/ui/drops/search")
local drop_notes = require("src/ui/drops/notes")
local wiki_notes = require("src/data/library/utils/wiki_notes")

local drop_table = {}
local ROW_HEIGHT = 40
local HEADER_HEIGHT = 30
local SECTION_HEIGHT = 28
local SECTION_GAP = 12
local CONTENT_TOP_PADDING = 12
local TOOLBAR_CONTENT_GAP = 6
local NO_MATCHES_HEIGHT = 36
local LONG_DESCRIPTION_LENGTH = 240
local ICON_SIZE = 32

local MODE_PICKER_WIDTH = 150

-- columns are anchored to the right edge so the item name column takes whatever width is left
local ITEM_X = 44
local ITEM_WIDTH = -450 -- full width minus the three right hand columns
local QUANTITY_X = -394
local QUANTITY_WIDTH = 88
local RARITY_X = -298
local RARITY_WIDTH = 130
local RARITY_CELL_WIDTH = 138
local PRICE_X = -158
local PRICE_WIDTH = 146

local function create_row(parent, y, height, colour)
    local row = widgets.layer(parent, height)
    row:SetPos(0, y)
    widgets.background(row, colour)
    return row
end

local function add_text(parent, text, x, width, right_anchored, colour)
    local label = widgets.text(parent, {
        text = text,
        x = x,
        y = 0,
        xAnchor = right_anchored and 1 or 0,
        width = width,
        widthAnchor = width < 0 and 1 or 0,
        height = parent.height,
        maxLines = 1,
        colour = colour or theme.TEXT,
        alignHorizontal = right_anchored and ui.AlignMode.BOTTOMRIGHT or ui.AlignMode.TOPLEFT,
    })

    return label
end

local function add_header(parent, y)
    local row = create_row(parent, y, HEADER_HEIGHT, theme.HEADER)
    add_text(row, "Item", ITEM_X, ITEM_WIDTH, false)
    add_text(row, "Quantity", QUANTITY_X, QUANTITY_WIDTH, true)
    add_text(row, "Rarity", RARITY_X, RARITY_WIDTH, true)
    add_text(row, "GE price", PRICE_X, PRICE_WIDTH, true)
end

-- for drops with no item id, eg ability unlocks like Cremation that never sit in the
-- inventory so the wiki has no item record for them. drawn natively so no image is needed
local function add_missing_icon(row)
    local slot = widgets.layer(row, ICON_SIZE)
    slot:SetPos(6, (ROW_HEIGHT - ICON_SIZE) / 2)
    slot:SetSize(ICON_SIZE, ICON_SIZE)
    widgets.background(slot, theme.MISSING_ICON)

    widgets.text(slot, {
        text = "?",
        x = 0,
        y = 0,
        width = ICON_SIZE,
        height = ICON_SIZE,
        colour = theme.TEXT_MUTED,
        alignHorizontal = ui.AlignMode.CENTRE,
    })
end

local function add_item_icon(row, item_id)
    if not item_id then
        add_missing_icon(row)
        return
    end

    local icon = ui.Sprite.new(row)
    icon:SetPos(6, (ROW_HEIGHT - ICON_SIZE) / 2)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetAssociatedObject(item_id)
    icon.clickthrough = true
end

local function add_tooltip(controller, label, text)
    local tooltip = hover_tooltip.attach(controller.page, label, controller.overlay_parent, text)
    controller.tooltips[#controller.tooltips + 1] = tooltip
end

local function add_rarity_cell(row, drop, controller)
    local background = widgets.background(row, drop.rarity_colour or theme.RARITY_CELL)
    background:SetPos(RARITY_X - 4, 1, 1, 0)
    background:SetSize(RARITY_CELL_WIDTH, ROW_HEIGHT - 2)

    local marker = drop.note_marker and drop.note_marker ~= "" and " [" .. drop.note_marker .. "]"
        or ""
    local label = add_text(
        row,
        formatting.rarity(drop.rate, controller.options.percentage_rarity) .. marker,
        RARITY_X,
        RARITY_WIDTH,
        true
    )
    label.maxLines = 2

    if drop.notes and drop.notes ~= "" then
        add_tooltip(controller, label, drop.notes)
    end
end

-- quantities like "30-40 (noted)" dont fit the column and get cut off with "...", so those
-- get a tooltip with the whole thing. measured with the same font the label draws with
local function add_quantity(row, drop, controller)
    local label = add_text(row, drop.quantity, QUANTITY_X, QUANTITY_WIDTH, true)
    local font = config.Font.MUSEO_SANS_15PT_REGULAR

    if font:GetStringLineCount(drop.quantity, QUANTITY_WIDTH) > 1 then
        add_tooltip(controller, label, "Quantity: " .. drop.quantity)
    end
end

local function add_drop_row(parent, drop, y, index, controller)
    local row = create_row(parent, y, ROW_HEIGHT, theme.row_colour(index))
    add_item_icon(row, drop.item_id)
    add_text(row, drop.name, ITEM_X, ITEM_WIDTH, false)
    add_quantity(row, drop, controller)
    add_rarity_cell(row, drop, controller)

    -- live price when the window has one, otherwise the one saved with the drop
    local price_for = controller.options.price_for
    local price = price_for and price_for(drop) or drop.price
    add_text(row, formatting.price(price), PRICE_X, PRICE_WIDTH, true, theme.TEXT_PRICE)

    return row
end

-- text that goes above the table (before_table) or below it. reference notes are the
-- footnotes the drop_notes toggle shows and hides
local function add_section_text(section, value, before_table, reference_note)
    if not value or value == "" then
        return
    end

    local explanation = before_table and #value > LONG_DESCRIPTION_LENGTH
    local large_text = before_table and not explanation
    local label = widgets.text(section.body, {
        text = text_layout.display(value),
        x = 8,
        width = -16,
        widthAnchor = 1,
        height = 22,
        colour = large_text and theme.TEXT_SOFT or theme.TEXT_MUTED,
        font = large_text and id.Font.MUSEO_SANS_15PT_REGULAR or id.Font.MUSEO_SANS_11PT_REGULAR,
        shadowed = large_text,
    })
    local entry = {
        label = label,
        value = value,
        before_table = before_table,
        reference_note = reference_note,
        explanation = explanation,
        -- id.Font picks the font for drawing, config.Font is the same font for measuring
        font = large_text and config.Font.MUSEO_SANS_15PT_REGULAR
            or config.Font.MUSEO_SANS_11PT_REGULAR,
        line_height = large_text and 22 or 16,
    }
    section.texts[#section.texts + 1] = entry

    if reference_note then
        section.reference_notes[#section.reference_notes + 1] = entry
    elseif explanation then
        section.explanations[#section.explanations + 1] = entry
    end
end

local function layout_text(entry, width, y)
    local height = text_layout.entry_height(entry, width - 16)
    entry.label:SetPos(8, y)
    entry.label:SetSize(-16, height, 1, 0)
    return height
end

-- text wrapping only changes with width so skip the measuring if the width hasnt moved
local function layout_section_body(section)
    if section.measured_width == section.body.width then
        return
    end

    local width = section.body.width
    section.measured_width = width
    local y = 0

    for _, entry in ipairs(section.texts) do
        if entry.before_table and not entry.explanation then
            y = y + layout_text(entry, width, y) + 8
        end
    end

    if section.explanation_controller then
        y = drop_notes.layout(section.explanation_controller, width, y)
    end

    section.table_layer:SetPos(0, y)
    y = y + section.table_height

    if section.notes_controller then
        y = drop_notes.layout(section.notes_controller, width, y)
    end

    for _, entry in ipairs(section.texts) do
        if not entry.before_table and not entry.reference_note then
            y = y + layout_text(entry, width, y + 8) + 8
        end
    end

    section.height = y
    section.body:SetSize(0, y, 1, 0)
end

local function create_section_body(controller, data)
    local body = widgets.layer(controller.page.content, 1)

    local section = {
        body = body,
        texts = {},
        reference_notes = {},
        explanations = {},
        rows = {},
        expanded = true,
    }
    add_section_text(section, core.without_wiki_averages(data.description), true)

    local table_layer = widgets.layer(body, 1)
    section.table_height = HEADER_HEIGHT + #data.drops * ROW_HEIGHT
    table_layer:SetSize(0, section.table_height, 1, 0)
    section.table_layer = table_layer

    add_header(table_layer, 0)

    for index, drop in ipairs(data.drops) do
        local y = HEADER_HEIGHT + (index - 1) * ROW_HEIGHT
        local row = add_drop_row(table_layer, drop, y, index, controller)
        section.rows[#section.rows + 1] = {
            root = row,
            search_item = core.prepare_name(drop.name),
            hidden = false,
            y = y,
        }
    end

    local references = drop_notes.referenced_numbers(data.drops)

    for number, note in ipairs(data.notes or {}) do
        add_section_text(section, "[" .. number .. "] " .. note, false, references[number])
    end

    add_section_text(section, core.without_wiki_averages(data.afterword), false)

    return section
end

local function layout_toolbar(controller)
    local y = CONTENT_TOP_PADDING
    local last_button = controller.toggle_all
    local right = last_button.root.x + last_button.root.width

    if controller.mode_picker then
        local x = right + 12

        if x + MODE_PICKER_WIDTH + 8 > controller.page.content.width then
            x = 8
            y = y + 32
        end

        controller.mode_picker:SetPos(x, y - 2)
        right = x + MODE_PICKER_WIDTH
    end

    -- without a search box the toolbar is just the buttons row
    local bottom = controller.search and controller.search.layout(right + 16, y) or (y + 26)
    controller.toolbar:SetSize(controller.page.content.width, bottom + 8)

    y = bottom + 8 + TOOLBAR_CONTENT_GAP

    if controller.status_label then
        controller.status_label:SetPos(8, y)
        y = y + controller.status_label.height + 4
    end

    -- the kill value and its note wrap with the page width, so theyre measured each time
    local width = math.max(1, controller.page.content.width - 16)

    for _, line in ipairs(controller.value_lines or {}) do
        local height = text_layout.height(line.text, width, line.measure, line.line_height)
        line.label:SetPos(8, y)
        line.label:SetSize(-16, height, 1, 0)
        y = y + height + 4
    end

    if y == bottom + 8 + TOOLBAR_CONTENT_GAP then
        return bottom + 12 + TOOLBAR_CONTENT_GAP
    end

    return y + 4
end

local function position_sections(controller)
    local y = controller.toggle_all and layout_toolbar(controller) or CONTENT_TOP_PADDING

    if controller.search then
        controller.search.no_matches:SetPos(8, y)

        if not controller.search.no_matches.hidden then
            y = y + NO_MATCHES_HEIGHT
        end
    end

    for _, section in ipairs(controller.sections) do
        section.button.root.hidden = section.filtered_out == true
        section.body.hidden = section.filtered_out == true or not section.expanded

        if not section.filtered_out then
            layout_section_body(section)
            section.button.root:SetPos(0, y)
            y = y + SECTION_HEIGHT

            if section.expanded then
                section.body:SetPos(0, y)
                y = y + section.height
            end

            y = y + SECTION_GAP
        end
    end

    controller.page:SetContentHeight(y)
end

local function has_expanded_sections(controller)
    for _, section in ipairs(controller.sections) do
        if not section.filtered_out and section.expanded then
            return true
        end
    end

    return false
end

local function layout_sections(controller)
    -- building/updating_sections are set while lots of sections change at once, the caller
    -- does one layout at the end instead of one per section
    if controller.destroyed or controller.building or controller.updating_sections then
        return
    end

    if controller.toggle_all then
        internals.set_button_text(
            controller.toggle_all,
            has_expanded_sections(controller) and "Collapse all" or "Expand all"
        )
    end

    widgets.run_layout(controller, function()
        position_sections(controller)
    end)
end

-- the rows hidden and y are kept in lua too, so unchanged rows dont get written to the
-- client again
local function update_filtered_row(entry, visible, y)
    local hidden = not visible

    if entry.hidden ~= hidden then
        entry.root.hidden = hidden
        entry.hidden = hidden
    end

    if visible and entry.y ~= y then
        entry.root:SetPos(0, y)
        entry.y = y
    end
end

-- hides rows that dont match and moves the rest up. sections with no matches are hidden
-- altogether, and every section is opened while searching then put back how it was after.
-- the same rows and controls are reused so the search field keeps keyboard focus, and the
-- notes are left alone so the numbers on the rows still point at the right one
local function apply_search(controller, query)
    local searching = query:find("%S") ~= nil
    local matches = core.name_matcher(query)
    local total = 0
    controller.updating_sections = true
    controller.filtering_sections = true

    for _, section in ipairs(controller.sections) do
        if searching and not controller.searching then
            section.saved_expanded = section.expanded
            section.button:SetExpanded(true)
        elseif not searching and controller.searching then
            section.button:SetExpanded(section.saved_expanded)
            section.saved_expanded = nil
        end

        local count = 0

        for _, entry in ipairs(section.rows) do
            local visible = matches(entry.search_item)
            update_filtered_row(entry, visible, HEADER_HEIGHT + count * ROW_HEIGHT)

            if visible then
                count = count + 1
            end
        end

        section.filtered_out = searching and count == 0
        local height = HEADER_HEIGHT + count * ROW_HEIGHT

        if section.table_height ~= height then
            section.table_height = height
            section.table_layer:SetSize(0, height, 1, 0)
            section.measured_width = nil
        end

        total = total + count
    end

    controller.searching = searching
    controller.filtering_sections = false
    controller.updating_sections = false
    controller.search.no_matches.hidden = not searching or total > 0
end

local function style_section_button(button, expanded)
    internals.set_collapse_alpha(button, expanded and 0.35 or 0.55, expanded and 0.60 or 0.75)
end

local function toggle_all_sections(controller)
    local expanded = not has_expanded_sections(controller)

    if not controller.searching then
        controller.section_state.default_expanded = expanded
        controller.section_state.categories = {}
    end

    widgets.hide_tooltips(controller.tooltips)
    controller.updating_sections = true

    for _, section in ipairs(controller.sections) do
        if not section.filtered_out then
            section.button:SetExpanded(expanded)
        end
    end

    controller.updating_sections = false
    layout_sections(controller)
end

local function create_toolbar_button(controller, text, x, width, action, wheel_id, disabled)
    local button = prettyui.SimpleButton.new(controller.toolbar, text, action, {
        x = x,
        y = CONTENT_TOP_PADDING,
        width = width,
        height = 24,
        colour = theme.TEXT_SOFT,
        disabled = disabled,
    })
    widgets.forward_wheel(button.root, wheel_id, controller.page)
    return button
end

local function create_status(controller)
    local options = controller.options

    if not options.status or options.status == "" then
        return
    end

    controller.status_label = widgets.text(controller.page.content, {
        text = text_layout.display(options.status or ""),
        x = 8,
        y = CONTENT_TOP_PADDING + 30,
        width = -16,
        widthAnchor = 1,
        height = options.problem and 40 or 18,
        maxLines = 2,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        colour = options.problem and theme.TEXT_WARNING or theme.TEXT_MUTED,
        shadowed = false,
    })
end

-- the text and its font are kept next to the label rather than on it, client components
-- wont take fields of our own (putting one there stopped the whole toolbar laying out).
-- big and gold like the prices so its easy to spot
local function add_value_line(controller, text)
    local label = widgets.text(controller.page.content, {
        text = text,
        x = 8,
        width = -16,
        widthAnchor = 1,
        height = 24,
        maxLines = 0,
        font = id.Font.MUSEO_SANS_15PT_REGULAR,
        colour = theme.TEXT_PRICE,
        shadowed = true,
    })
    controller.value_lines[#controller.value_lines + 1] = {
        label = label,
        text = text,
        -- config.Font is the same font as id.Font, for measuring
        measure = config.Font.MUSEO_SANS_15PT_REGULAR,
        line_height = 22,
    }
end

-- the average kill value for the tables being shown, worked out again on every render, which
-- happens when the mode changes or live prices turn up, never per frame
local function create_kill_value(controller, sections)
    local value = core.kill_value(sections, controller.options.unit_price)

    if value.counted == 0 then
        return
    end

    local amount = formatting.price(value.total)
    local text = value.estimate and ("Estimated average kill: about " .. amount)
        or ("Average kill: " .. amount)
    add_value_line(controller, text)
end

local function create_section_button(controller, section, title)
    local button = prettyui.CollapseButton.new(controller.page.content, title, {
        expanded = section.expanded,
        colour = theme.TEXT_SOFT,
        width = 0,
        widthAnchor = 1,
        onToggle = function(button, expanded)
            widgets.hide_tooltips(controller.tooltips)
            section.expanded = expanded

            if not controller.filtering_sections then
                controller.section_state.categories[title] = expanded

                if controller.searching then
                    section.saved_expanded = expanded
                end
            end

            style_section_button(button, expanded)
            layout_sections(controller)
        end,
    })
    style_section_button(button, section.expanded)
    widgets.forward_wheel(button.root, "monster_lookup_category_wheel", controller.page)

    return button
end

local function create_text_toggle(controller, section, entries, heading)
    if #entries == 0 then
        return nil
    end

    return drop_notes.new(section.body, entries, function()
        widgets.hide_tooltips(controller.tooltips)
        section.measured_width = nil
        layout_sections(controller)
    end, controller.page, heading)
end

local function category_expanded(controller, title)
    local saved = controller.section_state.categories[title]

    if saved ~= nil then
        return saved
    end

    return controller.section_state.default_expanded ~= false
end

local function add_section(controller, data, title)
    data = wiki_notes.without_sources(data)
    local section = create_section_body(controller, data)
    section.expanded = category_expanded(controller, title)
    section.notes_controller = create_text_toggle(controller, section, section.reference_notes)
    section.explanation_controller =
        create_text_toggle(controller, section, section.explanations, "Notes")

    section.button = create_section_button(controller, section, title)
    controller.sections[#controller.sections + 1] = section

    local width = section.body.width
    section.body:Subscribe(ui.Hook.ONRESIZE, "monster_lookup_notes_resize", function()
        if section.body.width ~= width then
            width = section.body.width
            layout_sections(controller)
        end
    end)
end

local function destroy_sections(controller)
    controller.destroyed = true
    widgets.destroy_tooltips(controller.tooltips)
    controller.tooltips = {}

    if controller.toggle_all then
        controller.toggle_all:Destroy()
    end

    if controller.search then
        controller.search.destroy()
    end

    if controller.status_label then
        controller.status_label:Destroy()
    end

    for _, line in ipairs(controller.value_lines or {}) do
        line.label:Destroy()
    end

    controller.value_lines = {}

    if controller.mode_picker then
        controller.mode_picker:Destroy()
    end

    for index = #controller.sections, 1, -1 do
        local section = controller.sections[index]
        section.button:Destroy()

        if section.notes_controller then
            section.notes_controller.toggle:Destroy()
        end

        if section.explanation_controller then
            section.explanation_controller.toggle:Destroy()
        end

        section.body:Destroy()
    end

    controller.sections = {}
    if controller.toolbar then
        controller.toolbar:Destroy()
    end
end

-- dropdown for pages split into modes, picking one asks the window to render that mode
local function create_mode_picker(controller, x)
    local entries = {}

    for index, group in ipairs(controller.groups) do
        entries[#entries + 1] = { text = group.name, id = index - 1 }
    end

    controller.mode_picker = widgets.dropdown(controller.toolbar, {
        x = x,
        y = CONTENT_TOP_PADDING - 2,
        width = MODE_PICKER_WIDTH,
        height = 28,
        entries = entries,
        selected = controller.mode - 1,
        on_change = function(entry_id)
            if controller.options.on_mode_change then
                controller.options.on_mode_change(entry_id + 1)
            end
        end,
    })
end

local function create_toolbar(controller)
    -- the toolbar sits on the tab root, which doesnt scroll (prettyui scrolls the content
    -- inside it). added last so its drawn on top of the rows scrolling under it
    controller.toolbar = widgets.layer(controller.page.root, 1)
    controller.toolbar.clickthrough = false
    widgets.background(controller.toolbar, theme.ROW_ODD)
    controller.toolbar_divider = widgets.background(controller.toolbar, theme.TOOLBAR_DIVIDER)
    controller.toolbar_divider:SetSize(0, 1, 1, 0)
    controller.toolbar_divider:SetPos(0, -1, 0, 1)
    widgets.forward_wheel(controller.toolbar, "monster_lookup_toolbar_wheel", controller.page)
    controller.toggle_all = create_toolbar_button(controller, "Collapse all", 8, 112, function()
        toggle_all_sections(controller)
    end, "monster_lookup_toggle_all_wheel")
    create_status(controller)

    if controller.groups then
        create_mode_picker(controller, 132)
    end

    local query = controller.options.search_query or ""
    controller.search = drop_search.new(controller.page, query, function(new_query)
        if controller.destroyed then
            return
        end

        widgets.hide_tooltips(controller.tooltips)
        apply_search(controller, new_query)
        controller.page:SetScrollPosition(0)
        layout_sections(controller)

        if controller.options.on_search_change then
            controller.options.on_search_change(new_query)
        end
    end, controller.toolbar)
    apply_search(controller, query)
end

---@class DropTableOptions
---@field percentage_rarity boolean?
---@field price_for (fun(drop: Drop): any)? live price for a row, nil keeps drop.price
---@field unit_price (fun(item_id: integer, reference: number?): number?)? live price for one item, for the kill value
---@field status string? cache status line under the buttons
---@field problem string? refresh error, makes the status line a warning
---@field search_query string? search text to carry over from the last render
---@field on_search_change fun(query: string)?
---@field mode integer? which mode to show when the page is split into modes, defaults to 1
---@field on_mode_change fun(mode: integer)? the caller re-renders with the new mode
---@field section_state table? shared category choices for this monster across drop modes

---@param page table tab page to draw into
---@param sections DropSection[]
---@param overlay_parent table where tooltips get drawn, normally the game area
---@param options DropTableOptions?
function drop_table.render(page, sections, overlay_parent, options)
    options = options or {}
    local section_state = options.section_state or {}
    section_state.categories = section_state.categories or {}
    local controller = {
        page = page,
        options = options,
        section_state = section_state,
        overlay_parent = overlay_parent,
        groups = core.drop_modes(sections),
        sections = {},
        tooltips = {},
        value_lines = {},
        building = true,
    }

    local shown = sections

    if controller.groups then
        -- only the picked mode gets built, its titles drop the "Drops (hard mode) / " part
        controller.mode = math.min(math.max(options.mode or 1, 1), #controller.groups)
        local group = controller.groups[controller.mode]
        shown = group.sections

        for index, section in ipairs(group.sections) do
            add_section(controller, section, group.titles[index])
        end
    else
        for _, section in ipairs(sections) do
            add_section(controller, section, section.title)
        end
    end

    if #controller.sections > 0 then
        create_toolbar(controller)
        -- only the mode being shown, so normal and hard mode are never added together
        create_kill_value(controller, shown)
    end

    controller.building = false
    layout_sections(controller)

    return {
        hide_tooltips = function()
            widgets.hide_tooltips(controller.tooltips)
        end,
        destroy = function()
            destroy_sections(controller)
        end,
    }
end

return drop_table
