-- the standard Monster info tab: a variant picker, then the stats summary with the model
-- beside it, then the Slayer and Detailed stats groups. its put together from the same info
-- components other plugins get (components.lua), this adds what only the standard tab has:
-- the variant picker, the model, the source note and remembering which groups were open.
-- sections other plugins registered (src/ui/extensions/registry.lua) go after the groups
--
-- the variant picker swaps the body without rebuilding the whole tab

local core = require("src/data/core")
local settings = require("src/settings")
local wiki_text = require("src/utils/wiki_text")
local stat_blocks = require("src/ui/info/stat_blocks")
local components = require("src/ui/info/components")
local widgets = require("src/ui/common/widgets")
local model_viewer = require("src/ui/info/model")
local extensions = require("src/ui/extensions/registry")

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

        if entry.extension and not entry.block then
            -- an extension with nothing to show right now keeps its place, takes no room
            height = nil
        elseif entry.note then
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

local function destroy_block(block)
    if block.toggle then
        block.toggle:Destroy()
    end

    block.root:Destroy()
end

local function destroy_components(controller)
    for _, entry in ipairs(controller.blocks or {}) do
        if entry.component then
            entry.component.destroy()
        elseif entry.extension then
            -- the slot belongs to the body being replaced, a late refresh() for it does nothing
            entry.dead = true

            if entry.block then
                destroy_block(entry.block)
                entry.block = nil
            end
        end
    end
end

local build_extension

-- asks an extension for its content again, eg after its own data arrived (context.refresh)
local function refresh_extension(controller, slot)
    if controller.destroyed or slot.dead then
        return
    end

    if slot.block then
        destroy_block(slot.block)
        slot.block = nil
    end

    build_extension(controller, slot)
    layout(controller)
end

-- one extension sections group, in the slot it keeps between refreshes. nothing to show
-- leaves the slot empty, an error shows the message in it
build_extension = function(controller, slot)
    local entry = slot.extension
    local context = extensions.context(entry, controller.extension_state, function()
        refresh_extension(controller, slot)
    end)
    local ok, content = extensions.call(entry, "content", context)
    local section, problem

    if ok then
        section, problem = extensions.section(entry, content)
    else
        problem = content
    end

    if problem then
        section = { title = entry.title, widths = { 1 }, labels = { false }, rows = {}, note = problem }
    end

    if not section then
        return
    end

    slot.block = stat_blocks.group(controller.context, controller.body, entry.title, { section }, {
        expanded = controller.expanded[entry.id] ~= false,
        on_toggle = function(open)
            controller.expanded[entry.id] = open
            layout(controller)
        end,
    })
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

    local stats = components.stats(controller.body, {
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
        local in_summary = summary and (section.title == "Overview" or section.title == "Immunities")
        local in_group = section.title == "Slayer"
            or section.title == "Player-owned Slayer Dungeon"
            or section.detailed

        if not in_summary and not in_group then
            controller.blocks[#controller.blocks + 1] =
                { block = stat_blocks.section(controller.context, controller.body, section) }
        end
    end

    add_group(controller, components.slayer, "Slayer")
    add_group(controller, components.detailed_stats, DETAILS_TITLE)

    for _, entry in ipairs(extensions.list("section")) do
        local slot = { extension = entry }
        controller.blocks[#controller.blocks + 1] = slot
        build_extension(controller, slot)
    end
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

    stat_blocks.text(controller.root, "Wiki variant", { x = 8, y = PADDING, width = 140, height = 32 })
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
                -- the window moves the extension context on to this variant first, so the
                -- sections built below already see it
                if controller.on_variant then
                    controller.on_variant(variant.name)
                end

                replace_body(controller, variant.info)
                layout(controller)
                controller.page:SetScrollPosition(0)
            end
        end,
    })
    controller.body_y = 48
end

---@param options { extension_state: table?, on_variant: fun(name: string)? }? the windows
---extension selection state and what to call when the player picks another variant
function monster_info_view.render(page, result, overlay_parent, selection, options)
    options = options or {}
    local controller = {
        page = page,
        overlay_parent = overlay_parent,
        body_y = 0,
        building = true,
        expanded = {},
        selection = selection,
        active = false,
        on_variant = options.on_variant,
        -- without a window (tests, other callers) extensions see a context of their own
        extension_state = options.extension_state or { revision = 0, monster = { title = result.title } },
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
