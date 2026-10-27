-- monster stats, variant selection and model preview for the built-in info tab.

local core = require("src/data/library/api")
local settings = require("src/settings")
local wiki_text = require("src/data/library/utils/wiki_text")
local stat_blocks = require("src/ui/info/stat_blocks")
local widgets = require("src/ui/common/widgets")
local model_viewer = require("src/ui/info/model")

local monster_info_view = {}
local PADDING = stat_blocks.PADDING
local DETAILS_TITLE = "Detailed stats"
-- the player setting each group remembers its open state in
local GROUP_SETTINGS = {
    Slayer = "slayer_expanded",
    [DETAILS_TITLE] = "detailed_stats_expanded",
}

local create_layer = widgets.layer

local layout

-- the model only shows while the tab is the one showing and wide enough to fit it beside
-- the summary. the viewer itself destroys the native model whenever its not active
local function update_preview(controller, width)
    local viewer = controller.viewer

    if viewer then
        viewer.set_active(controller.active and controller.has_overview and width >= 620)
    end
end

-- the summary goes on the left two thirds with the model beside it, centred against it
local function layout_summary(controller, entry, width, y)
    local viewer = controller.viewer
    local showing = viewer and viewer.showing()
    local block_width = showing and math.floor((width - 12) * 2 / 3) or width
    local height = entry.component.layout(block_width, y)

    if showing then
        local preview_height = math.max(210, math.min(280, height))
        local preview_width = width - block_width - 12
        viewer.resize(preview_width, preview_height)
        viewer.set_position(
            block_width + 12,
            y + math.max(0, math.floor((height - preview_height) / 2))
        )
        height = math.max(height, preview_height)
    end

    return height
end

local function layout_blocks(controller)
    local width = math.max(200, controller.root.width)
    local y = PADDING
    update_preview(controller, width)

    for index, entry in ipairs(controller.blocks) do
        local height

        if entry.note then
            height = stat_blocks.layout_note(entry.note, width, y)
        elseif entry.summary then
            height = layout_summary(controller, entry, width, y)
        elseif entry.component then
            height = entry.component.layout(width, y)
        else
            height = stat_blocks.layout(entry.block, width, y)
            entry.block.root:SetSize(width, height)
        end

        if height then
            local next_entry = controller.blocks[index + 1]
            local data = next_entry and next_entry.block and next_entry.block.data
            local joined = data and data.continuation
            y = y + height + (joined and 0 or PADDING)
        end
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

-- stat icon tooltips of the plain sections, the components keep their own
local function destroy_tooltips(controller)
    widgets.destroy_tooltips(controller.context.tooltips)
    controller.context.tooltips = {}
end

local function destroy_components(controller)
    for _, entry in ipairs(controller.blocks or {}) do
        if entry.component then
            entry.component.destroy()
        end
    end
end

local function add_note(controller, text)
    controller.blocks[#controller.blocks + 1] = { note = stat_blocks.note(controller.body, text) }
end

-- a group component that opens how the player left it (this window, then their setting)
-- and remembers it when they change it
local function add_group(controller, make, title)
    local expanded = controller.expanded[title]

    if expanded == nil then
        expanded = settings.get()[GROUP_SETTINGS[title]]
    end

    local group = make(controller.body, {
        page = controller.page,
        overlay_parent = controller.overlay_parent,
        expanded = expanded,
        on_toggle = function(open)
            controller.expanded[title] = open
            settings.set(GROUP_SETTINGS[title], open)
            layout(controller)
        end,
    })
    group.set_info(controller.info, controller.source_title)

    if group.empty() then
        group.destroy()
    else
        controller.blocks[#controller.blocks + 1] = { component = group }
    end
end

local function destroy_viewer(controller)
    if controller.viewer then
        controller.viewer.destroy()
        controller.viewer = nil
    end
end

local function replace_body(controller, info)
    destroy_tooltips(controller)
    destroy_components(controller)
    destroy_viewer(controller)
    controller.info = info
    controller.has_overview = next(info) ~= nil

    if controller.body then
        controller.body:Destroy()
    end

    controller.body = create_layer(controller.root, 1)
    controller.body:SetPos(0, controller.body_y)
    controller.blocks = {}
    controller.viewer = model_viewer.new(controller.body, {
        width = 300,
        height = 210,
        overlay_parent = controller.overlay_parent,
    })
    controller.viewer.set_monster({
        title = controller.source_title,
        info = info,
        selection = controller.selection,
    })
    local data = core.stat_sections(info, controller.source_title)

    if data.variant and not controller.selector then
        add_note(controller, "Variant: " .. data.variant)
    end

    if data.message then
        add_note(controller, data.message)
    end

    local stats = stat_blocks.stats(controller.body, {
        page = controller.page,
        overlay_parent = controller.overlay_parent,
    })
    stats.set_info(info, controller.source_title)
    local summary = not stats.empty()

    if summary then
        controller.blocks[#controller.blocks + 1] = { component = stats, summary = true }
    else
        stats.destroy()
    end

    -- anything the summary and the two groups dont cover gets its own table
    for _, section in ipairs(data.sections) do
        local in_summary = summary
            and (section.title == "Overview" or section.title == "Immunities")
        local in_group = section.title == "Slayer"
            or section.title == "Player-owned Slayer Dungeon"
            or section.detailed

        if not in_summary and not in_group then
            controller.blocks[#controller.blocks + 1] =
                { block = stat_blocks.section(controller.context, controller.body, section) }
        end
    end

    add_group(controller, stat_blocks.slayer, "Slayer")
    add_group(controller, stat_blocks.detailed_stats, DETAILS_TITLE)

    add_note(
        controller,
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

    for index, variant in ipairs(variants) do
        entries[#entries + 1] = { text = variant.name, id = index }
    end

    stat_blocks.text(
        controller.root,
        "Wiki variant",
        { x = 8, y = PADDING, width = 140, height = 32 }
    )
    controller.selector = widgets.dropdown(controller.root, {
        x = 156,
        y = PADDING,
        width = -164,
        widthAnchor = 1,
        height = 32,
        entries = entries,
        selected = 1,
        on_change = function(entry_id)
            local variant = variants[entry_id]

            if variant then
                replace_body(controller, variant.info)
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
        expanded = {},
        selection = selection,
        active = false,
    }
    controller.context = { page = page, overlay_parent = overlay_parent, tooltips = {} }
    controller.source_title = wiki_text.plain(result.title or "Monster information")
    controller.root = create_layer(page.content, 1)
    local variants = core.variants(result)
    add_variant_selector(controller, variants)
    replace_body(controller, variants[1].info)

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
            widgets.hide_tooltips(controller.context.tooltips)

            for _, entry in ipairs(controller.blocks) do
                if entry.component then
                    entry.component.hide_tooltips()
                end
            end

            if controller.viewer then
                controller.viewer.hide_tooltip()
            end
        end,
        destroy = function()
            if controller.destroyed then
                return
            end

            controller.destroyed = true
            destroy_viewer(controller)
            destroy_tooltips(controller)
            destroy_components(controller)

            if controller.selector then
                controller.selector:Destroy()
            end

            controller.root:Destroy()
        end,
    }
end

return monster_info_view
