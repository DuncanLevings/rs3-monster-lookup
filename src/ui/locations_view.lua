-- a compact, read-only table of Wiki spawn locations, with rows tall enough for access notes

local text_layout = require("src/ui/text_layout")
local wiki_text = require("src/utils/wiki_text")
local widgets = require("src/ui/widgets")
local theme = require("src/ui/theme")

local locations_view = {}
local COLUMNS = {
    { key = "name", title = "Location", width = 0.35 },
    { key = "levels", title = "Levels", width = 0.12 },
    { key = "requirements", title = "Access requirements", width = 0.41 },
    { key = "spawns", title = "Spawns", width = 0.12 },
}

local function create_text(parent, value, small)
    local label = prettyui.Text.new(parent, {
        text = text_layout.display(value),
        height = 24,
        maxLines = 0,
        font = small and id.Font.MUSEO_SANS_11PT_REGULAR or id.Font.MUSEO_SANS_15PT_REGULAR,
        colour = small and theme.TEXT_MUTED or theme.TEXT,
        shadowed = not small,
    })
    label.clickthrough = true
    label.enabled = false
    return label
end

local function create_row(parent, location, index)
    local row = { root = widgets.layer(parent, 30), cells = {} }
    widgets.background(row.root, location and theme.row_colour(index) or theme.COLUMN_HEADER)

    for _, column in ipairs(COLUMNS) do
        local value = column.title

        if location then
            value = location[column.key]
            if column.key == "spawns" then
                value = tostring(value or ""):match("^%s*(%d+)%s*$") or ""
            end
        end
        row.cells[#row.cells + 1] = {
            label = create_text(row.root, value),
            value = value,
            width = column.width,
        }
    end

    return row
end

local function layout_row(row, width, y)
    local height = 30
    local x = 0

    for _, cell in ipairs(row.cells) do
        local cell_width = math.floor(width * cell.width)
        height = math.max(height, text_layout.height(cell.value, cell_width - 16))
        cell.label:SetPos(x + 8, 4)
        cell.label:SetSize(cell_width - 16, height)
        x = x + cell_width
    end

    for _, cell in ipairs(row.cells) do
        cell.label:SetHeight(height - 4)
    end

    row.root:SetPos(0, y)
    row.root:SetHeight(height)
    return height
end

local function empty_message(result)
    if result.locations == nil then
        return "Locations were not included in this saved lookup. Refresh this monster in plugin settings to load them."
    elseif result.no_locations == "unreadable" then
        return "This Wiki page has a location section, but it does not contain a supported location table."
    end

    return "The Wiki page does not list a location table for this monster."
end

local function layout(controller)
    if controller.destroyed or controller.building then
        return
    end

    widgets.run_layout(controller, function()
        local width = math.max(200, controller.root.width)

        if controller.measured_width == width then
            return
        end

        controller.measured_width = width
        local y = 8

        for _, row in ipairs(controller.rows) do
            y = y + layout_row(row, width, y)
        end

        y = y + 8
        local height =
            text_layout.height(controller.note, width - 16, config.Font.MUSEO_SANS_11PT_REGULAR, 16)
        controller.footer:SetPos(8, y)
        controller.footer:SetSize(width - 16, height)
        controller.root:SetHeight(y + height + 8)
        controller.page:SetContentHeight(y + height + 8)
    end)
end

function locations_view.render(page, result)
    local controller =
        { page = page, root = widgets.layer(page.content, 1), rows = {}, building = true }
    local rows = result.locations or {}

    if #rows > 0 then
        controller.rows[1] = create_row(controller.root, nil, 0)

        for index, location in ipairs(rows) do
            controller.rows[#controller.rows + 1] = create_row(controller.root, location, index)
        end

        controller.note = "Source: RuneScape Wiki - "
            .. wiki_text.plain(result.title)
            .. ". Locations cover the variants listed on that page; check levels and access requirements. Floors are numbered from 1 (ground floor)."
    else
        controller.note = empty_message(result)
    end

    controller.footer = create_text(controller.root, controller.note, true)
    controller.root:Subscribe(ui.Hook.ONRESIZE, "monster_lookup_locations_resize", function()
        layout(controller)
    end)
    controller.building = false
    layout(controller)

    return {
        destroy = function()
            controller.destroyed = true
            controller.root:Destroy()
        end,
    }
end

return locations_view
