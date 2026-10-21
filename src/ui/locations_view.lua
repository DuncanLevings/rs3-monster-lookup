-- Wiki spawn locations with optional native markers; wrapped access notes set row height.

local text_layout = require("src/ui/text_layout")
local wiki_text = require("src/utils/wiki_text")
local widgets = require("src/ui/widgets")
local theme = require("src/ui/theme")
local marker = require("src/game/location_marker")

local locations_view = {}
local COLUMNS = {
    { key = "name", title = "Location", width = 0.30 },
    { key = "levels", title = "Levels", width = 0.10 },
    { key = "requirements", title = "Access requirements", width = 0.36 },
    { key = "spawns", title = "Spawns", width = 0.10 },
    { key = "map", title = "Map", width = 0.14 },
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

local function create_row(controller, location, index)
    local row = { root = widgets.layer(controller.root, 30), cells = {} }
    widgets.background(row.root, location and theme.row_colour(index) or theme.COLUMN_HEADER)

    for _, column in ipairs(COLUMNS) do
        local value = column.title

        if location then
            value = column.key == "map" and "" or location[column.key]
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

    if location then
        local reason = marker.reason(location)
        row.button = prettyui.SimpleButton.new(row.root, "Mark", function()
            if controller.destroyed then
                return
            end
            local ok, problem = marker.mark(location, wiki_text.plain(controller.source_title))
            controller.problem = not ok and problem or nil
            controller.update_status()
        end, { width = 54, height = 24, disabled = reason ~= nil, tooltip = reason })
        widgets.forward_wheel(
            row.button.root,
            "monster_lookup_location_mark_wheel",
            controller.page
        )
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

    if row.button then
        row.button.root:SetPos(
            width - math.floor(width * COLUMNS[5].width) + 8,
            math.floor((height - 24) / 2)
        )
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
        if controller.marker_status then
            local clear_width = controller.clear_button.root.width
            local status_width = math.max(1, width - clear_width - 24)
            local status_height = math.max(
                30,
                text_layout.height(
                    controller.status_text,
                    status_width,
                    config.Font.MUSEO_SANS_11PT_REGULAR,
                    16
                )
            )
            controller.marker_status:SetPos(8, 4)
            controller.marker_status:SetSize(status_width, status_height)
            controller.clear_button.root:SetPos(-clear_width - 8, 4, 1, 0)
            controller.toolbar:SetHeight(status_height + 8)
            y = y + status_height + 12
        end

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

    controller.source_title = result.title
    controller.update_status = function()
        if controller.destroyed or not controller.marker_status then
            return
        end
        controller.status_text = controller.problem or marker.status()
        controller.marker_status.content = controller.status_text
        controller.clear_button:SetDisabled(not marker.has_target())
        controller.measured_width = nil
        layout(controller)
    end

    if #rows > 0 then
        controller.toolbar = widgets.layer(controller.root, 1)
        controller.marker_status = create_text(controller.toolbar, "", true)
        controller.clear_button = prettyui.SimpleButton.new(
            controller.toolbar,
            "Clear marker",
            function()
                if controller.destroyed then
                    return
                end
                controller.problem = nil
                marker.clear()
            end,
            { height = 24 }
        )
        widgets.forward_wheel(
            controller.clear_button.root,
            "monster_lookup_location_clear_wheel",
            page
        )
        controller.unsubscribe = marker.subscribe(function()
            controller.problem = nil
            controller.update_status()
        end)
        controller.update_status()
        controller.rows[1] = create_row(controller, nil, 0)

        for index, location in ipairs(rows) do
            controller.rows[#controller.rows + 1] = create_row(controller, location, index)
        end

        controller.note = "Source: RuneScape Wiki - "
            .. wiki_text.plain(result.title)
            .. ". Locations cover the variants listed on that page; check levels and access requirements."
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
            if controller.unsubscribe then
                controller.unsubscribe()
            end
            if controller.clear_button then
                controller.clear_button:Destroy()
            end
            for _, row in ipairs(controller.rows) do
                if row.button then
                    row.button:Destroy()
                end
            end
            controller.root:Destroy()
        end,
    }
end

return locations_view
