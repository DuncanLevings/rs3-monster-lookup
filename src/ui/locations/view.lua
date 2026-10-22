-- the Locations tab: where the monster spawns, from the wiki, with a Mark (or Entrance)
-- button per row for the in game marker (src/game/locations/marker.lua). rows grow to fit
-- wrapped requirement text

local text_layout = require("src/ui/common/text_layout")
local wiki_text = require("src/utils/wiki_text")
local widgets = require("src/ui/common/widgets")
local theme = require("src/ui/common/theme")
local marker = require("src/game/locations/marker")
local internals = require("src/ui/common/prettyui_internals")
local clock = require("src/utils/cache_clock")

local locations_view = {}
local next_feedback_id = 0
local FEEDBACK_TICKS = 3 * clock.TICKS_PER_SECOND
local COLUMNS = {
    { key = "name", title = "Location", width = 0.30 },
    { key = "levels", title = "Levels", width = 0.10 },
    { key = "requirements", title = "Access requirements", width = 0.32 },
    { key = "spawns", title = "Spawns", width = 0.10 },
    { key = "map", title = "Map", width = 0.18 },
}

local function create_text(parent, value, small, notice)
    local label = widgets.text(parent, {
        text = text_layout.display(value),
        height = 24,
        maxLines = 0,
        font = small and id.Font.MUSEO_SANS_11PT_REGULAR or id.Font.MUSEO_SANS_15PT_REGULAR,
        colour = notice and theme.TEXT_WARNING or small and theme.TEXT_MUTED or theme.TEXT,
        shadowed = not small,
    })
    return label
end

local function stop_feedback(controller)
    if controller.feedback_row then
        Event.Logic.Unsubscribe(controller.feedback_id)
    end

    controller.feedback_row, controller.feedback_text, controller.feedback_ticks = nil, nil, nil
end

local function show_feedback(controller, row)
    controller.feedback_row = row
    controller.feedback_text = "Marked: "
        .. controller.source_title
        .. " - "
        .. wiki_text.plain(row.location.name or "Location")
        .. " - open the world map to see it."
    controller.feedback_ticks = FEEDBACK_TICKS
    Event.Logic.Subscribe(controller.feedback_id, function()
        if controller.destroyed then
            return
        end

        controller.feedback_ticks = controller.feedback_ticks - 1
        if controller.feedback_ticks == 0 then
            stop_feedback(controller)
            controller.update_status()
        end
    end)
end

local function create_row(controller, location, index)
    local row = {
        root = widgets.layer(controller.root, 30),
        cells = {},
        location = location,
        normal_colour = location and theme.row_colour(index) or theme.COLUMN_HEADER,
    }
    row.background = widgets.background(row.root, row.normal_colour)

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
        local action, tooltip, reason = marker.action(location)
        row.action = action
        row.marked_label = "Marked"
        -- entrance already fits the marked label; keep its normal compact width.
        local fitted_label = #action >= #row.marked_label and action or row.marked_label
        row.button = prettyui.SimpleButton.new(row.root, fitted_label, function()
            if controller.destroyed then
                return
            end
            stop_feedback(controller)
            controller.marking = true
            local ok, problem = marker.mark(location, controller.source_title)
            controller.marking = false
            controller.problem = not ok and problem or nil
            if ok then
                show_feedback(controller, row)
            end

            controller.update_status()
        end, { height = 24, disabled = reason ~= nil, tooltip = tooltip })
        internals.set_button_text(row.button, action)
        widgets.forward_wheel(
            row.button.root,
            "monster_lookup_location_mark_wheel",
            controller.page
        )
    end

    return row
end

local function layout_row(row, width, y, map_width)
    local height = 30
    local x = 0

    for index, cell in ipairs(row.cells) do
        local cell_width = index == #COLUMNS and map_width
            or math.floor((width - map_width) * cell.width / (1 - COLUMNS[5].width))
        height = math.max(height, text_layout.height(cell.value, cell_width - 16))
        cell.label:SetPos(x + 8, 4)
        cell.label:SetSize(cell_width - 16, height)
        x = x + cell_width
    end

    for _, cell in ipairs(row.cells) do
        cell.label:SetHeight(height - 4)
    end

    if row.button then
        row.button.root:SetPos(width - map_width + 8, math.floor((height - 24) / 2))
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
                    controller.status_attention and config.Font.MUSEO_SANS_15PT_REGULAR
                        or config.Font.MUSEO_SANS_11PT_REGULAR,
                    controller.status_attention and 20 or 16
                )
            )
            controller.marker_status:SetPos(8, 4)
            controller.marker_status:SetSize(status_width, status_height)
            controller.clear_button.root:SetPos(-clear_width - 8, 4, 1, 0)
            controller.toolbar:SetHeight(status_height + 8)
            y = y + status_height + 12
        end

        -- every row gets the same button width, so "Entrance" still fits on small screens
        -- and the columns stay lined up
        local map_width = math.max(96, math.floor(width * COLUMNS[5].width))

        for _, row in ipairs(controller.rows) do
            if row.button then
                map_width = math.max(map_width, row.button.root.width + 16)
            end
        end

        for _, row in ipairs(controller.rows) do
            y = y + layout_row(row, width, y, map_width)
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

    controller.source_title = wiki_text.plain(result.title)
    next_feedback_id = next_feedback_id + 1
    controller.feedback_id = "monster_lookup_location_feedback_" .. next_feedback_id
    controller.update_status = function()
        if controller.destroyed or not controller.marker_status then
            return
        end

        local matched = false

        for _, row in ipairs(controller.rows) do
            if row.button then
                local marked = not matched
                    and marker.is_target(row.location, controller.source_title)
                matched = matched or marked
                if row.marked ~= marked then
                    row.marked = marked
                    row.background.rgba = marked and theme.ROW_MARKED or row.normal_colour
                    internals.set_button_text(row.button, marked and row.marked_label or row.action)
                end
            end
        end

        local status_text, attention = marker.status()
        status_text = controller.problem or controller.feedback_text or status_text
        attention = controller.problem ~= nil or controller.feedback_row ~= nil or attention == true
        controller.clear_button:SetDisabled(not marker.has_target())
        if controller.status_text == status_text and controller.status_attention == attention then
            return
        end

        controller.status_text, controller.status_attention = status_text, attention
        controller.status_normal.hidden = controller.status_attention
        controller.status_notice.hidden = not controller.status_attention
        controller.marker_status = controller.status_attention and controller.status_notice
            or controller.status_normal
        controller.marker_status.content = text_layout.display(controller.status_text)
        controller.measured_width = nil
        layout(controller)
    end

    if #rows > 0 then
        controller.toolbar = widgets.layer(controller.root, 1)
        controller.status_normal = create_text(controller.toolbar, "", true)
        controller.status_notice = create_text(controller.toolbar, "", false, true)
        controller.marker_status = controller.status_normal
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
            if controller.feedback_row then
                local _, attention = marker.status()
                if
                    attention
                    or not marker.is_target(
                        controller.feedback_row.location,
                        controller.source_title
                    )
                then
                    stop_feedback(controller)
                end
            end

            if not controller.marking then
                controller.update_status()
            end
        end)
        controller.update_status()
        controller.rows[1] = create_row(controller, nil, 0)

        for index, location in ipairs(rows) do
            controller.rows[#controller.rows + 1] = create_row(controller, location, index)
        end

        controller.note = "Source: RuneScape Wiki - "
            .. wiki_text.plain(result.title)
            .. ". Check levels and access requirements. Dungeon markers continue in mapped areas; unsupported routes pause with instructions."
    else
        controller.note = empty_message(result)
    end

    controller.footer = create_text(controller.root, controller.note, true)
    controller.root:Subscribe(ui.Hook.ONRESIZE, "monster_lookup_locations_resize", function()
        layout(controller)
    end)
    controller.building = false
    controller.update_status()
    layout(controller)

    return {
        destroy = function()
            if controller.destroyed then
                return
            end

            controller.destroyed = true
            stop_feedback(controller)
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
