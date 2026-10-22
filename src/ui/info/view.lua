-- draws the Monster info tab from the sections data/monsters/info builds
-- tables are laid out by hand so cells can grow to fit wrapped text and icons can stand in
-- for header text, the variant picker swaps the body without rebuilding the whole tab

local internals = require("src/ui/prettyui_internals")
local model = require("src/data/monsters/info")
local settings = require("src/settings")
local wiki_text = require("src/utils/wiki_text")
local text_layout = require("src/ui/text_layout")
local hover_tooltip = require("src/ui/hover_tooltip")
local stat_icons = require("src/ui/info/icons")
local theme = require("src/ui/theme")
local widgets = require("src/ui/widgets")
local monster_preview = require("src/ui/info/preview")

local monster_info_view = {}
local PADDING = 6
local ICON_SIZE = 20
local DETAILS_TITLE = "Detailed stats"
local GROUP_SETTINGS = {
    Slayer = "slayer_expanded",
    [DETAILS_TITLE] = "detailed_stats_expanded",
}

local create_layer = widgets.layer
local add_background = widgets.background

local function create_text(parent, value, options)
    options = options or {}
    options.text = text_layout.display(value)
    options.colour = options.colour or theme.TEXT
    return widgets.text(parent, options)
end

local function create_stat_icon(controller, parent, key, description)
    local resource = stat_icons.get(key)

    if not resource then
        return nil
    end

    local icon = ui.Sprite.new(parent)
    icon.sprite = resource
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    local tooltip =
        hover_tooltip.attach(controller.page, icon, controller.overlay_parent, description)
    controller.tooltips[#controller.tooltips + 1] = tooltip
    return icon
end

local function create_row(controller, parent, section, values, is_header, index)
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
                controller,
                row.root,
                value_icon,
                section.value_tooltips and section.value_tooltips[index][column]
                    or (values[column - 1] or "Value") .. ": " .. value
            )
            row.inline_icons[column] = row.icons[column] ~= nil
            row.left_icons[column] = true
        elseif is_header and section.header_icons then
            row.icons[column] =
                create_stat_icon(controller, row.root, section.header_icons[column], value)
            row.cells[column].hidden = row.icons[column] ~= nil
        elseif not is_header and not label_column and (value == "No" or value == "Yes") then
            local description = (
                section.headers and section.headers[column]
                or values[column - 1]
                or "Value"
            )
                .. ": "
                .. value
            row.icons[column] = create_stat_icon(
                controller,
                row.root,
                value == "Yes" and "yes" or "no",
                description
            )
            row.left_icons[column] = section.headers == nil
            row.cells[column].hidden = row.icons[column] ~= nil
        end
    end

    return row
end

local layout

-- The summary reads down one column beside the model. Keep the underlying data
-- sections unchanged; detailed stats and other consumers still use those tables.
local function summary_section(sections)
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
    return {
        title = "Overview",
        widths = { 0.40, 0.60 },
        labels = { true, false },
        rows = {
            { rows[1][1], rows[1][2] },
            { rows[2][1], rows[2][2] },
            { rows[1][3], rows[1][4] },
            { immune[1][1], immune[1][2] },
            { immune[2][1], immune[2][2] },
            { immune[1][3], immune[1][4] },
            { immune[2][3], immune[2][4] },
        },
        value_icons = {
            { [2] = overview.value_icons[1][2] },
            {},
            {},
            { [2] = "poison" },
            { [2] = "stun" },
            { [2] = "deflect" },
            { [2] = "drain" },
        },
    }
end

local function create_section(controller, parent, section, hide_heading)
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
            create_row(controller, block.body, section, section.headers, true, 0)
    end

    for index, values in ipairs(section.rows) do
        block.rows[#block.rows + 1] =
            create_row(controller, block.body, section, values, false, index)
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

local function create_group(controller, parent, title, sections)
    local expanded = controller.expanded[title]
    if expanded == nil then
        expanded = settings.get()[GROUP_SETTINGS[title]]
    end

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
            widgets.hide_tooltips(controller.tooltips)
            controller.expanded[title] = open
            settings.set(GROUP_SETTINGS[title], open)
            block.expanded = open
            block.body.hidden = not open
            internals.set_collapse_alpha(button, open and 0.35 or 0.55, open and 0.60 or 0.75)
            layout(controller)
        end,
    })
    internals.set_collapse_alpha(block.toggle, expanded and 0.35 or 0.55, expanded and 0.60 or 0.75)
    widgets.forward_wheel(block.toggle.root, "monster_lookup_info_header_wheel", controller.page)

    for _, section in ipairs(sections) do
        block.children[#block.children + 1] =
            create_section(controller, block.body, section, section.title == title)
    end

    return block
end

local function create_note(parent, text)
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

    for column, icon in pairs(row.icons) do
        icon:SetPos(icon.x, math.floor((height - ICON_SIZE) / 2))
    end

    row.root:SetPos(0, y)
    row.root:SetHeight(height)
    return height
end

local function layout_section(block, width, y)
    local body_height = 0

    if block.expanded then
        for _, child in ipairs(block.children or {}) do
            body_height = body_height + layout_section(child, width, body_height) + PADDING
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

local function clear_preview(controller)
    if controller.preview_tooltip then
        controller.preview_tooltip:Destroy()
        controller.preview_tooltip = nil
    end

    if controller.preview then
        monster_preview.destroy(controller.preview)
        controller.preview = nil
    end

    if controller.preview_frame then
        controller.preview_frame:Destroy()
        controller.preview_frame = nil
    end
end

local function layout_blocks(controller)
    local width = math.max(200, controller.root.width)
    local y = PADDING
    local show_preview = controller.active
        and controller.has_overview
        and width >= 620
        and not controller.preview_failed
    if not show_preview and controller.preview then
        clear_preview(controller)
    elseif show_preview and not controller.preview then
        -- A model may draw outside its own rectangle. Its parent layer provides
        -- the native clipping boundary, just like the page's scroll viewport.
        controller.preview_frame = create_layer(controller.body, 210)
        controller.preview = monster_preview.create(
            controller.preview_frame,
            controller.source_title,
            controller.info,
            controller.selection,
            function()
                if controller.preview_tooltip then
                    controller.preview_tooltip:Hide()
                end
            end
        )
        controller.preview_failed = controller.preview == nil
        if not controller.preview then
            clear_preview(controller)
        end

        if controller.preview then
            -- The preview owns its wheel gesture; the stat-tooltip helper
            -- forwards wheel input to the page, which would also scroll here.
            controller.preview_tooltip =
                prettyui.Tooltip.attach(controller.preview, controller.overlay_parent, {
                    text = monster_preview.can_turn(controller.preview)
                            and "Drag to turn the monster preview, Shift+drag to move it up or down, scroll to zoom."
                        or "Scroll to zoom the monster preview.",
                    maxWidth = 260,
                })
        end
    end

    for index, block in ipairs(controller.blocks) do
        local height

        if block.label then
            height =
                text_layout.height(block.text, width - 16, config.Font.MUSEO_SANS_11PT_REGULAR, 16)
            block.label:SetPos(8, y)
            block.label:SetSize(width - 16, height)
        else
            local overview = block.data and block.data.title == "Overview"
            local block_width = controller.preview and overview and math.floor((width - 12) * 2 / 3)
                or width
            height = layout_section(block, block_width, y)
            block.root:SetSize(block_width, height)
            if controller.preview and overview then
                local preview_height = math.max(210, math.min(280, height))
                local preview_width = width - block_width - 12
                controller.preview_frame:SetSize(preview_width, preview_height)
                controller.preview_frame:SetScrollSize(preview_width, preview_height)
                controller.preview_frame:SetPos(
                    block_width + 12,
                    y + math.max(0, math.floor((height - preview_height) / 2))
                )
                monster_preview.resize(controller.preview, preview_width, preview_height)
                controller.preview:SetPos(0, 0)
                height = math.max(height, preview_height)
            end
        end

        local next_block = controller.blocks[index + 1]
        local joined = next_block and next_block.data and next_block.data.continuation
        y = y + height + (joined and 0 or PADDING)
    end

    controller.body:SetHeight(y)
    controller.root:SetHeight(y + controller.body_y)
    controller.page:SetContentHeight(y + controller.body_y)
end

layout = function(controller)
    if controller.destroyed or controller.building then
        return
    end

    widgets.run_layout(controller, function()
        controller.measured_width = controller.root.width
        layout_blocks(controller)
    end)
end

-- tooltips live under the overlay parent, outside the body being replaced
-- destroying the body alone would leave them behind
local function destroy_tooltips(controller)
    widgets.destroy_tooltips(controller.tooltips)
    controller.tooltips = {}
end

local function replace_body(controller, info)
    destroy_tooltips(controller)
    clear_preview(controller)
    controller.info = info
    controller.has_overview = next(info) ~= nil
    controller.preview_failed = false
    if controller.body then
        for _, block in ipairs(controller.blocks) do
            if block.toggle then
                block.toggle:Destroy()
            end
        end

        controller.body:Destroy()
    end

    controller.body = create_layer(controller.root, 1)
    controller.body:SetPos(0, controller.body_y)
    controller.blocks = {}
    local data = model.build(info, controller.source_title)

    if data.variant and not controller.selector then
        controller.blocks[#controller.blocks + 1] =
            create_note(controller.body, "Variant: " .. data.variant)
    end

    if data.message then
        controller.blocks[#controller.blocks + 1] = create_note(controller.body, data.message)
    end

    local detailed, slayer = {}, {}
    local summary = summary_section(data.sections)
    if summary then
        controller.blocks[#controller.blocks + 1] =
            create_section(controller, controller.body, summary)
    end

    for _, section in ipairs(data.sections) do
        if summary and (section.title == "Overview" or section.title == "Immunities") then
            -- Already included in the single summary beside the preview.
        elseif section.title == "Slayer" or section.title == "Player-owned Slayer Dungeon" then
            slayer[#slayer + 1] = section
        elseif section.detailed then
            detailed[#detailed + 1] = section
        else
            controller.blocks[#controller.blocks + 1] =
                create_section(controller, controller.body, section)
        end
    end

    if #slayer > 0 then
        controller.blocks[#controller.blocks + 1] =
            create_group(controller, controller.body, "Slayer", slayer)
    end

    if #detailed > 0 then
        controller.blocks[#controller.blocks + 1] =
            create_group(controller, controller.body, DETAILS_TITLE, detailed)
    end

    controller.blocks[#controller.blocks + 1] = create_note(
        controller.body,
        "Source: RuneScape Wiki - "
            .. controller.source_title
            .. ". Stats apply to the selected variant."
    )
end

local function add_variant_selector(controller, variants)
    if #variants < 2 then
        return
    end

    local entries = {}

    for index, info in ipairs(variants) do
        entries[#entries + 1] = { text = model.variant_name(info, index), id = index }
    end

    create_text(controller.root, "Wiki variant", { x = 8, y = PADDING, width = 140, height = 32 })
    controller.selector = widgets.dropdown(controller.root, {
        x = 156,
        y = PADDING,
        width = -164,
        widthAnchor = 1,
        height = 32,
        entries = entries,
        selected = 1,
        on_change = function(entry_id)
            local info = variants[entry_id]

            if info then
                replace_body(controller, info)
                layout(controller)
                controller.page:SetScrollPosition(0)
            end
        end,
    })
    controller.body_y = 48
end

function monster_info_view.render(page, result, overlay_parent, selection)
    local controller = {
        page = page,
        overlay_parent = overlay_parent,
        body_y = 0,
        building = true,
        tooltips = {},
        expanded = {},
        selection = selection,
        active = false,
    }
    controller.source_title = wiki_text.plain(result.title or "Monster information")
    controller.root = create_layer(page.content, 1)
    local variants = model.variants(result)
    add_variant_selector(controller, variants)
    replace_body(controller, variants[1])

    controller.root:Subscribe(ui.Hook.ONRESIZE, "monster_lookup_info_resize", function()
        if controller.root.width ~= controller.measured_width then
            layout(controller)
        end
    end)
    controller.building = false
    layout(controller)

    return {
        set_active = function(active)
            if controller.active == active then
                return
            end

            controller.active = active
            layout(controller)
        end,
        hide_tooltips = function()
            widgets.hide_tooltips(controller.tooltips)
            if controller.preview_tooltip then
                controller.preview_tooltip:Hide()
            end
        end,
        destroy = function()
            if controller.destroyed then
                return
            end

            controller.destroyed = true
            clear_preview(controller)
            destroy_tooltips(controller)

            if controller.selector then
                controller.selector:Destroy()
            end

            controller.root:Destroy()
        end,
    }
end

return monster_info_view
