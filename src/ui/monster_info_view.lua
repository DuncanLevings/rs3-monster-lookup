-- draws the Monster info tab from the sections data/monster_info builds
-- tables are laid out by hand so cells can grow to fit wrapped text and icons can stand in
-- for header text, the variant picker swaps the body without rebuilding the whole tab

local model = require("src/data/monster_info")
local wiki_text = require("src/utils/wiki_text")
local text_layout = require("src/ui/text_layout")
local hover_tooltip = require("src/ui/hover_tooltip")
local stat_icons = require("src/ui/stat_icons")
local theme = require("src/ui/theme")
local widgets = require("src/ui/widgets")

local monster_info_view = {}
local PADDING = 6
local ICON_SIZE = 20

local create_layer = widgets.layer
local add_background = widgets.background

local function create_text(parent, value, options)
    options = options or {}
    options.text = text_layout.display(value)
    options.colour = options.colour or theme.TEXT
    local label = prettyui.Text.new(parent, options)
    label.clickthrough = true
    label.enabled = false
    return label
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

        if is_header and section.header_icons then
            row.icons[column] =
                create_stat_icon(controller, row.root, section.header_icons[column], value)
            row.cells[column].hidden = row.icons[column] ~= nil
        elseif not is_header and not label_column and value == "No" then
            local description = (
                section.headers and section.headers[column]
                or values[column - 1]
                or "Value"
            ) .. ": No"
            row.icons[column] = create_stat_icon(controller, row.root, "no", description)
            row.left_icons[column] = section.headers == nil
            row.cells[column].hidden = row.icons[column] ~= nil
        end
    end

    return row
end

local function create_section(controller, parent, section)
    local block = { root = create_layer(parent, 1), data = section, rows = {} }
    local heading = create_layer(block.root, 22)
    add_background(heading, theme.HEADER)
    create_text(heading, section.title, { x = 10, width = -20, widthAnchor = 1, height = 22 })

    if section.headers then
        block.rows[#block.rows + 1] =
            create_row(controller, block.root, section, section.headers, true, 0)
    end

    for index, values in ipairs(section.rows) do
        block.rows[#block.rows + 1] =
            create_row(controller, block.root, section, values, false, index)
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

        if icon then
            icon:SetPos(
                row.left_icons[column] and x + 8 or x + math.floor((cell_width - ICON_SIZE) / 2),
                0
            )
        else
            local lines = row.font:GetStringLineCount(
                text_layout.display(row.values[column]),
                math.max(1, cell_width - 16)
            )
            height = math.max(height, lines * row.line_height + 6)
        end

        label:SetPos(x + 8, 0)
        label:SetSize(cell_width - 16, height)
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

local function layout_section(block, width, y)
    local height = 22

    for _, row in ipairs(block.rows) do
        height = height + layout_row(row, block.data.widths, width, height)
    end

    block.root:SetPos(0, y)
    block.root:SetHeight(height)
    return height
end

local function layout_blocks(controller)
    local width = math.max(200, controller.root.width)
    local y = PADDING

    for _, block in ipairs(controller.blocks) do
        local height

        if block.label then
            height =
                text_layout.height(block.text, width - 16, config.Font.MUSEO_SANS_11PT_REGULAR, 16)
            block.label:SetPos(8, y)
            block.label:SetSize(width - 16, height)
        else
            height = layout_section(block, width, y)
        end

        y = y + height + PADDING
    end

    controller.body:SetHeight(y)
    controller.root:SetHeight(y + controller.body_y)
    controller.page:SetContentHeight(y + controller.body_y)
end

local function layout(controller)
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
    if controller.body then
        controller.body:Destroy()
    end

    controller.body = create_layer(controller.root, 1)
    controller.body:SetPos(0, controller.body_y)
    controller.blocks = {}
    local data = model.build(info)

    if data.variant and not controller.selector then
        controller.blocks[#controller.blocks + 1] =
            create_note(controller.body, "Variant: " .. data.variant)
    end

    if data.message then
        controller.blocks[#controller.blocks + 1] = create_note(controller.body, data.message)
    end

    for _, section in ipairs(data.sections) do
        controller.blocks[#controller.blocks + 1] =
            create_section(controller, controller.body, section)
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

function monster_info_view.render(page, result, overlay_parent)
    local controller =
        { page = page, overlay_parent = overlay_parent, body_y = 0, building = true, tooltips = {} }
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
        hide_tooltips = function()
            widgets.hide_tooltips(controller.tooltips)
        end,
        destroy = function()
            controller.destroyed = true
            destroy_tooltips(controller)

            if controller.selector then
                controller.selector:Destroy()
            end

            controller.root:Destroy()
        end,
    }
end

return monster_info_view
