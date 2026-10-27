-- draws stat sections (the tables Monster Data Core stat sections builds) and collapsible groups
-- of them. used by the info components (components.lua), which the Monster info tab and
-- other plugins put together however they like
--
-- tables are laid out by hand so cells can grow to fit wrapped text and icons can stand in
-- for header text. nothing in here knows about the standard window or settings, the group
-- toggles report back through options and whoever owns the block saves what it wants
--
-- a context is shared by the blocks of one view: { page = scrolling page or nil,
-- overlay_parent = where tooltips draw, tooltips = list the view destroys }

local internals = require("src/ui/common/prettyui_internals")
local text_layout = require("src/ui/common/text_layout")
local hover_tooltip = require("src/ui/common/hover_tooltip")
local stat_icons = require("src/ui/info/icons")
local theme = require("src/ui/common/theme")
local widgets = require("src/ui/common/widgets")

local stat_blocks = {}
local PADDING = 6
local ICON_SIZE = 20

stat_blocks.PADDING = PADDING

local create_layer = widgets.layer
local add_background = widgets.background

function stat_blocks.text(parent, value, options)
    options = options or {}
    options.text = text_layout.display(value)
    options.colour = options.colour or theme.TEXT
    return widgets.text(parent, options)
end

local create_text = stat_blocks.text

local function create_stat_icon(context, parent, key, description)
    local resource = stat_icons.get(key)

    if not resource then
        return nil
    end

    local icon = ui.Sprite.new(parent)
    icon.sprite = resource
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    local tooltip = hover_tooltip.attach(context.page, icon, context.overlay_parent, description)
    context.tooltips[#context.tooltips + 1] = tooltip
    return icon
end

local function create_row(context, parent, section, values, is_header, index)
    local row = {
        root = create_layer(parent, 24),
        cells = {},
        icons = {},
        left_icons = {},
        inline_icons = {},
        values = values,
        font = is_header and config.Font.MUSEO_SANS_11PT_REGULAR
            or config.Font.MUSEO_SANS_15PT_REGULAR,
        line_height = is_header and 16 or 18,
    }
    add_background(row.root, is_header and theme.COLUMN_HEADER or theme.row_colour(index))

    for column, value in ipairs(values) do
        local label_column = section.labels and section.labels[column]
        row.cells[column] = create_text(row.root, value, {
            height = 24,
            maxLines = 0,
            font = is_header and id.Font.MUSEO_SANS_11PT_REGULAR or id.Font.MUSEO_SANS_15PT_REGULAR,
            colour = value == "No" and not label_column and theme.TEXT_NEGATIVE
                or label_column and theme.TEXT_LABEL
                or theme.TEXT,
            alignHorizontal = section.headers and not label_column and ui.AlignMode.CENTRE
                or ui.AlignMode.TOPLEFT,
        })

        local value_icon = not is_header
            and section.value_icons
            and section.value_icons[index]
            and section.value_icons[index][column]

        if value_icon then
            row.icons[column] = create_stat_icon(
                context,
                row.root,
                value_icon,
                section.value_tooltips and section.value_tooltips[index][column]
                    or (values[column - 1] or "Value") .. ": " .. value
            )
            row.inline_icons[column] = row.icons[column] ~= nil
            row.left_icons[column] = true
        elseif is_header and section.header_icons then
            row.icons[column] =
                create_stat_icon(context, row.root, section.header_icons[column], value)
            row.cells[column].hidden = row.icons[column] ~= nil
        elseif not is_header and not label_column and (value == "No" or value == "Yes") then
            local description = (
                section.headers and section.headers[column]
                or values[column - 1]
                or "Value"
            )
                .. ": "
                .. value
            row.icons[column] =
                create_stat_icon(context, row.root, value == "Yes" and "yes" or "no", description)
            row.left_icons[column] = section.headers == nil
            row.cells[column].hidden = row.icons[column] ~= nil
        end
    end

    return row
end

-- the labels the summary has, in order. pass some of them as fields to show only those
stat_blocks.SUMMARY_FIELDS = {
    "Weakness",
    "Aggressive",
    "Susceptible to",
    "Poison",
    "Stun",
    "Deflect",
    "Stat drain",
}

---the short summary that sits in one column beside the model, made from the Overview and
---Immunities sections. the sections themselves are left alone, detailed stats still shows
---them in full. nil when either section is missing (no infobox)
---@param sections table[] from Monster Data Core stat sections build()
---@param fields string[]? labels from SUMMARY_FIELDS to keep, all of them when nil
function stat_blocks.summary(sections, fields)
    local overview, immunities

    for _, section in ipairs(sections) do
        if section.title == "Overview" then
            overview = section
        end

        if section.title == "Immunities" then
            immunities = section
        end
    end

    if not overview or not immunities then
        return nil
    end

    local rows = overview.rows
    local immune = immunities.rows
    local all_rows = {
        { rows[1][1], rows[1][2] },
        { rows[2][1], rows[2][2] },
        { rows[1][3], rows[1][4] },
        { immune[1][1], immune[1][2] },
        { immune[2][1], immune[2][2] },
        { immune[1][3], immune[1][4] },
        { immune[2][3], immune[2][4] },
    }
    local all_icons = {
        { [2] = overview.value_icons[1][2] },
        {},
        {},
        { [2] = "poison" },
        { [2] = "stun" },
        { [2] = "deflect" },
        { [2] = "drain" },
    }
    local wanted

    if fields then
        wanted = {}

        for _, field in ipairs(fields) do
            wanted[field] = true
        end
    end

    local kept_rows, kept_icons = {}, {}

    for index, row in ipairs(all_rows) do
        if not wanted or wanted[row[1]] then
            kept_rows[#kept_rows + 1] = row
            kept_icons[#kept_icons + 1] = all_icons[index]
        end
    end

    return {
        title = "Overview",
        widths = { 0.40, 0.60 },
        labels = { true, false },
        rows = kept_rows,
        value_icons = kept_icons,
    }
end

---one section table. hide_heading leaves out its title bar (groups do that for a section
---with the same name as the group)
function stat_blocks.section(context, parent, section, hide_heading)
    local header_height = (hide_heading or section.title == "Overview" or section.continuation)
            and 0
        or 20
    local block = {
        root = create_layer(parent, 1),
        data = section,
        rows = {},
        expanded = true,
        header_height = header_height,
    }
    block.body = create_layer(block.root, 1)
    block.body:SetPos(0, header_height)

    if header_height > 0 then
        local heading = create_layer(block.root, header_height)
        add_background(heading, theme.HEADER)
        create_text(heading, section.title, {
            x = 8,
            height = header_height,
            width = -16,
            widthAnchor = 1,
            font = id.Font.MUSEO_SANS_11PT_REGULAR,
            colour = theme.TEXT_SOFT,
            shadowed = false,
        })
    end

    if section.headers then
        block.rows[#block.rows + 1] =
            create_row(context, block.body, section, section.headers, true, 0)
    end

    for index, values in ipairs(section.rows) do
        block.rows[#block.rows + 1] = create_row(context, block.body, section, values, false, index)
    end

    if section.note then
        block.note = create_text(block.body, section.note, {
            font = id.Font.MUSEO_SANS_11PT_REGULAR,
            colour = theme.TEXT_MUTED,
            shadowed = false,
            maxLines = 0,
        })
    end

    return block
end

local function style_toggle(button, open)
    internals.set_collapse_alpha(button, open and 0.35 or 0.55, open and 0.60 or 0.75)
end

---@class StatGroupOptions
---@field expanded boolean? starts open, defaults to true
---@field on_toggle fun(open: boolean)? after the player opened or closed it, the owner lays
---its view out again here (and saves the choice if it wants to)

---a collapsible group of sections under one title, eg Slayer or Detailed stats
---@param options StatGroupOptions?
function stat_blocks.group(context, parent, title, sections, options)
    options = options or {}
    local expanded = options.expanded ~= false
    local block = {
        root = create_layer(parent, 1),
        children = {},
        rows = {},
        expanded = expanded,
        header_height = 22,
    }
    block.body = create_layer(block.root, 1)
    block.body:SetPos(0, block.header_height)
    block.body.hidden = not expanded
    block.toggle = prettyui.CollapseButton.new(block.root, title, {
        expanded = expanded,
        colour = theme.TEXT_SOFT,
        width = 0,
        widthAnchor = 1,
        onToggle = function(button, open)
            widgets.hide_tooltips(context.tooltips)
            block.expanded = open
            block.body.hidden = not open
            style_toggle(button, open)

            if options.on_toggle then
                options.on_toggle(open)
            end
        end,
    })
    style_toggle(block.toggle, expanded)

    if context.page then
        widgets.forward_wheel(block.toggle.root, "monster_lookup_info_header_wheel", context.page)
    end

    for _, section in ipairs(sections) do
        block.children[#block.children + 1] =
            stat_blocks.section(context, block.body, section, section.title == title)
    end

    return block
end

---a line of small text, eg "Variant: Hard mode" or the source note
function stat_blocks.note(parent, text)
    return {
        text = text,
        label = create_text(parent, text, {
            font = id.Font.MUSEO_SANS_11PT_REGULAR,
            colour = theme.TEXT_LABEL,
            shadowed = false,
            height = 24,
        }),
    }
end

local function layout_row(row, widths, width, y)
    local height = 24
    local x = 0

    for column, label in ipairs(row.cells) do
        local cell_width = math.floor(width * widths[column])
        local icon = row.icons[column]

        local text_offset = row.inline_icons[column] and ICON_SIZE + 6 or 0

        if icon then
            local icon_x = row.left_icons[column] and x + 8
                or x + math.floor((cell_width - ICON_SIZE) / 2)
            icon:SetPos(icon_x, 0)
        end

        if not icon or row.inline_icons[column] then
            local lines = row.font:GetStringLineCount(
                text_layout.display(row.values[column]),
                math.max(1, cell_width - 16 - text_offset)
            )
            height = math.max(height, lines * row.line_height + 6)
        end

        label:SetPos(x + 8 + text_offset, 0)
        label:SetSize(math.max(1, cell_width - 16 - text_offset), height)
        x = x + cell_width
    end

    for _, label in ipairs(row.cells) do
        label:SetHeight(height)
    end

    for _, icon in pairs(row.icons) do
        icon:SetPos(icon.x, math.floor((height - ICON_SIZE) / 2))
    end

    row.root:SetPos(0, y)
    row.root:SetHeight(height)
    return height
end

---lays out a section or group block at y, returns its height
function stat_blocks.layout(block, width, y)
    local body_height = 0

    if block.expanded then
        for _, child in ipairs(block.children or {}) do
            body_height = body_height + stat_blocks.layout(child, width, body_height) + PADDING
        end

        for _, row in ipairs(block.rows) do
            body_height = body_height + layout_row(row, block.data.widths, width, body_height)
        end
    end

    if block.expanded and block.note then
        local height =
            text_layout.height(block.data.note, width - 16, config.Font.MUSEO_SANS_11PT_REGULAR, 16)
        block.note:SetPos(8, body_height + 4)
        block.note:SetSize(width - 16, height)
        body_height = body_height + height + 8
    end

    block.body:SetHeight(body_height)
    local height = block.header_height + body_height

    block.root:SetPos(0, y)
    block.root:SetHeight(height)
    return height
end

---lays out a note block at y, returns its height
function stat_blocks.layout_note(block, width, y)
    local height =
        text_layout.height(block.text, width - 16, config.Font.MUSEO_SANS_11PT_REGULAR, 16)
    block.label:SetPos(8, y)
    block.label:SetSize(width - 16, height)
    return height
end

return stat_blocks
