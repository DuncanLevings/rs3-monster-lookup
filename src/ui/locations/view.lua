-- the Locations tab: where the monster spawns, from the wiki. rows grow to fit wrapped
-- requirement text
--
-- the "take me there" part (a button per row, the highlighted row, the status line and its
-- stop button) is whatever navigation provider is current (navigation.lua), Monster
-- Lookup's marker unless another plugin replaced it. this file doesnt know what any of it does

local text_layout = require("src/ui/common/text_layout")
local wiki_text = require("src/utils/wiki_text")
local widgets = require("src/ui/common/widgets")
local theme = require("src/ui/common/theme")
local navigation = require("src/ui/locations/navigation")
local internals = require("src/ui/common/prettyui_internals")
local clock = require("src/utils/cache_clock")

local locations_view = {}
local next_feedback_id = 0
-- how long the providers confirmation stays in the status line after a click
local FEEDBACK_TICKS = 3 * clock.TICKS_PER_SECOND
local COLUMNS = {
    { key = "name", title = "Location", width = 0.30 },
    { key = "levels", title = "Levels", width = 0.10 },
    { key = "requirements", title = "Access requirements", width = 0.32 },
    { key = "spawns", title = "Spawns", width = 0.10 },
    -- the providers buttons, titled by it
    { key = "action", title = "", width = 0.18 },
}
local ACTION_COLUMN = #COLUMNS

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

-- the providers short confirmation, eg "Marked: ...", for a few seconds after a click
local function show_feedback(controller, row)
    local ok, text = navigation.call(
        controller.provider,
        "confirmation",
        row.location,
        controller.source_title
    )

    if not ok or type(text) ~= "string" then
        return
    end

    controller.feedback_row = row
    controller.feedback_text = text
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

local function add_action_button(controller, row, location)
    local provider = controller.provider
    local ok, action = navigation.call(provider, "action", location)

    if not ok or type(action) ~= "table" or type(action.label) ~= "string" then
        return
    end

    row.action = action.label
    row.active_label = type(action.active_label) == "string" and action.active_label or action.label
    local reason = type(action.unavailable) == "string" and action.unavailable or nil
    local tooltip = reason or (type(action.tooltip) == "string" and action.tooltip or nil)
    -- made with the longer of the two labels so swapping to the other never needs a resize
    local fitted_label = #row.action >= #row.active_label and row.action or row.active_label
    row.button = prettyui.SimpleButton.new(row.root, fitted_label, function()
        if controller.destroyed then
            return
        end

        stop_feedback(controller)
        controller.acting = true
        local called, started, problem =
            navigation.call(provider, "start", location, controller.source_title)
        controller.acting = false

        if not called then
            controller.problem = started
        else
            controller.problem = started == false and problem or nil
        end

        if called and started ~= false then
            show_feedback(controller, row)
        end

        controller.update_status()
    end, { height = 24, disabled = reason ~= nil, tooltip = tooltip })
    internals.set_button_text(row.button, row.action)
    widgets.forward_wheel(row.button.root, "monster_lookup_location_action_wheel", controller.page)
end

local function create_row(controller, location, index)
    local row = {
        root = widgets.layer(controller.root, 30),
        cells = {},
        location = location,
        normal_colour = location and theme.row_colour(index) or theme.COLUMN_HEADER,
    }
    row.background = widgets.background(row.root, row.normal_colour)

    for column_index, column in ipairs(COLUMNS) do
        if column_index ~= ACTION_COLUMN or controller.provider then
            local value = column_index == ACTION_COLUMN and controller.provider.column_title
                or column.title

            if location then
                value = column.key == "action" and "" or location[column.key]

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
    end

    if location and controller.provider then
        add_action_button(controller, row, location)
    end

    return row
end

local function layout_row(row, width, y, action_width)
    local height = 30
    local x = 0
    -- without a provider the four location columns share the whole width
    local share = action_width > 0 and (1 - COLUMNS[ACTION_COLUMN].width) or 1

    for index, cell in ipairs(row.cells) do
        local cell_width = index == ACTION_COLUMN and action_width
            or math.floor((width - action_width) * cell.width / share)
        height = math.max(height, text_layout.height(cell.value, cell_width - 16))
        cell.label:SetPos(x + 8, 4)
        cell.label:SetSize(cell_width - 16, height)
        x = x + cell_width
    end

    for _, cell in ipairs(row.cells) do
        cell.label:SetHeight(height - 4)
    end

    if row.button then
        row.button.root:SetPos(width - action_width + 8, math.floor((height - 24) / 2))
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

        if controller.status_label then
            local stop_width = controller.stop_button and controller.stop_button.root.width or 0
            local status_width = math.max(1, width - stop_width - 24)
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
            controller.status_label:SetPos(8, 4)
            controller.status_label:SetSize(status_width, status_height)

            if controller.stop_button then
                controller.stop_button.root:SetPos(-stop_width - 8, 4, 1, 0)
            end

            controller.toolbar:SetHeight(status_height + 8)
            y = y + status_height + 12
        end

        -- every row gets the same button width, so a long label still fits on small screens
        -- and the columns stay lined up
        local action_width = 0

        if controller.provider then
            action_width = math.max(96, math.floor(width * COLUMNS[ACTION_COLUMN].width))

            for _, row in ipairs(controller.rows) do
                if row.button then
                    action_width = math.max(action_width, row.button.root.width + 16)
                end
            end
        end

        for _, row in ipairs(controller.rows) do
            y = y + layout_row(row, width, y, action_width)
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

-- the status line, stop button and highlighted row, from the provider
local function update_status(controller)
    if controller.destroyed or not controller.status_label then
        return
    end

    local provider = controller.provider
    local matched = false

    for _, row in ipairs(controller.rows) do
        if row.button then
            local called, active =
                navigation.call(provider, "is_active", row.location, controller.source_title)
            active = not matched and called and active == true
            matched = matched or active

            if row.active ~= active then
                row.active = active
                row.background.rgba = active and theme.ROW_ACTIVE or row.normal_colour
                internals.set_button_text(row.button, active and row.active_label or row.action)
            end
        end
    end

    local called, status_text, attention = navigation.call(provider, "status")

    if not called then
        status_text, attention = status_text, true
    end

    status_text = controller.problem or controller.feedback_text or status_text or ""
    attention = controller.problem ~= nil or controller.feedback_row ~= nil or attention == true

    if controller.stop_button then
        local can_called, can_stop = navigation.call(provider, "can_stop")
        controller.stop_button:SetDisabled(not (can_called and can_stop == true))
    end

    if controller.status_text == status_text and controller.status_attention == attention then
        return
    end

    controller.status_text, controller.status_attention = status_text, attention
    controller.status_normal.hidden = controller.status_attention
    controller.status_notice.hidden = not controller.status_attention
    controller.status_label = controller.status_attention and controller.status_notice
        or controller.status_normal
    controller.status_label.content = text_layout.display(controller.status_text)
    controller.measured_width = nil
    layout(controller)
end

-- the bar above the table: the providers status line and stop button
local function create_toolbar(controller)
    local provider = controller.provider
    controller.toolbar = widgets.layer(controller.root, 1)
    controller.status_normal = create_text(controller.toolbar, "", true)
    controller.status_notice = create_text(controller.toolbar, "", false, true)
    controller.status_label = controller.status_normal

    if provider.stop then
        controller.stop_button = prettyui.SimpleButton.new(controller.toolbar, provider.stop_label, function()
            if controller.destroyed then
                return
            end

            controller.problem = nil
            navigation.call(provider, "stop")
        end, { height = 24 })
        widgets.forward_wheel(
            controller.stop_button.root,
            "monster_lookup_location_stop_wheel",
            controller.page
        )
    end

    local called, unsubscribe = navigation.call(provider, "subscribe", function()
        if controller.destroyed then
            return
        end

        controller.problem = nil

        -- the confirmation goes as soon as the provider has something to say or the row
        -- it was about isnt the active one any more
        if controller.feedback_row then
            local _, _, attention = navigation.call(provider, "status")
            local _, still_active = navigation.call(
                provider,
                "is_active",
                controller.feedback_row.location,
                controller.source_title
            )

            if attention or not still_active then
                stop_feedback(controller)
            end
        end

        if not controller.acting then
            controller.update_status()
        end
    end)
    controller.unsubscribe = called and type(unsubscribe) == "function" and unsubscribe or nil
end

function locations_view.render(page, result)
    local controller =
        { page = page, root = widgets.layer(page.content, 1), rows = {}, building = true }
    local rows = result.locations or {}

    controller.provider = navigation.current()
    controller.source_title = wiki_text.plain(result.title)
    next_feedback_id = next_feedback_id + 1
    controller.feedback_id = "monster_lookup_location_feedback_" .. next_feedback_id
    controller.update_status = function()
        update_status(controller)
    end

    if #rows > 0 then
        if controller.provider then
            create_toolbar(controller)
            controller.update_status()
        end

        controller.rows[1] = create_row(controller, nil, 0)

        for index, location in ipairs(rows) do
            controller.rows[#controller.rows + 1] = create_row(controller, location, index)
        end

        local note = controller.provider and controller.provider.note
        controller.note = "Source: RuneScape Wiki - "
            .. wiki_text.plain(result.title)
            .. ". Check levels and access requirements."
            .. (note and (" " .. note) or "")
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
                pcall(controller.unsubscribe)
            end

            if controller.stop_button then
                controller.stop_button:Destroy()
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
