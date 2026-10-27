-- the extension tabs of one standard window (see registry.lua for what extensions are). the
-- window makes the tabs, this fills them and calls the extensions at the right times:
--
--   create(container)          once, when the window is made (custom tabs)
--   update(context, container) or content(context), on every new monster, variant or mode
--   activate(context) / deactivate()  when the tab is opened / left (or the window closes)
--   destroy(container)         when the window goes or the extension is disposed
--
-- a structured tab is drawn by the window like a stat table. a custom tab gets a layer of
-- its own in the tab page to put anything in, it sets that layers height and the tab scrolls
-- to fit after each update

local extensions = require("src/ui/extensions/registry")
local stat_blocks = require("src/ui/info/stat_blocks")
local widgets = require("src/ui/common/widgets")

local extension_tabs = {}
local PADDING = stat_blocks.PADDING
local next_id = 0

---@param entries table[] registry.list("tab") when the window was made, in tab order
---@param state table the windows extension selection state (see registry.context)
---@param overlay_parent table where tooltips draw
function extension_tabs.new(entries, state, overlay_parent)
    local host = { slots = {} }

    local function clear_drawing(slot)
        widgets.destroy_tooltips(slot.context.tooltips)
        slot.context.tooltips = {}

        if slot.block then
            slot.block.root:Destroy()
            slot.block = nil
        end

        if slot.note then
            slot.note.label:Destroy()
            slot.note = nil
        end
    end

    local function layout(slot)
        if slot.removed then
            return
        end

        local width = math.max(200, slot.page.content.width)

        if slot.block then
            local height = stat_blocks.layout(slot.block, width - 2 * PADDING, PADDING)
            slot.block.root:SetPos(PADDING, PADDING)
            slot.block.root:SetSize(width - 2 * PADDING, height)
            slot.page:SetContentHeight(height + 2 * PADDING)
        elseif slot.note then
            local height = stat_blocks.layout_note(slot.note, width, PADDING)
            slot.page:SetContentHeight(height + 2 * PADDING)
        elseif slot.container then
            slot.page:SetContentHeight(math.max(1, slot.container.height))
        end
    end

    local function show_message(slot, message)
        clear_drawing(slot)
        slot.note = stat_blocks.note(slot.page.content, message)
        layout(slot)
    end

    local render

    local function context_for(slot)
        return extensions.context(slot.entry, state, function()
            render(slot)
        end)
    end

    render = function(slot)
        if slot.removed then
            return
        end

        local entry = slot.entry
        local context = context_for(slot)

        if entry.create then
            if slot.failed then
                return
            end

            local ok, problem = extensions.call(entry, "update", context, slot.container)

            if not ok then
                slot.failed = true
                show_message(slot, problem)
                return
            end

            layout(slot)
            return
        end

        local ok, content = extensions.call(entry, "content", context)
        local section, problem

        if ok then
            section, problem = extensions.section(entry, content)
        else
            problem = content
        end

        clear_drawing(slot)

        if problem then
            show_message(slot, problem)
        elseif section then
            slot.block = stat_blocks.section(slot.context, slot.page.content, section, true)
            layout(slot)
        else
            slot.page:SetContentHeight(1)
        end
    end

    ---fills tab page number index (counting extension tabs from 1) for entries[index]
    function host.attach(index, page)
        local entry = entries[index]
        next_id = next_id + 1
        local slot = {
            entry = entry,
            page = page,
            context = { page = page, overlay_parent = overlay_parent, tooltips = {} },
            resize_id = "monster_lookup_extension_resize_" .. next_id,
        }
        host.slots[index] = slot

        if entry.create then
            slot.container = widgets.layer(page.content, 1)
            local ok, problem = extensions.call(entry, "create", slot.container)

            if not ok then
                slot.failed = true
                show_message(slot, problem)
            end
        end

        page.content:Subscribe(ui.Hook.ONRESIZE, slot.resize_id, function()
            if page.content.width ~= slot.measured_width then
                slot.measured_width = page.content.width
                layout(slot)
            end
        end)
    end

    ---the monster, variant or mode changed (state.revision already went up)
    function host.update()
        for _, slot in pairs(host.slots) do
            render(slot)
        end
    end

    ---the tab showing changed, index counts extension tabs from 1, nil for a built in tab
    function host.activate(index)
        local previous = host.active

        if previous == index then
            return
        end

        host.active = index
        local leaving = previous and host.slots[previous]

        if leaving and not leaving.removed then
            extensions.call(leaving.entry, "deactivate")
        end

        local opening = index and host.slots[index]

        if opening and not opening.removed then
            extensions.call(opening.entry, "activate", context_for(opening))
        end
    end

    local function tear_down(slot)
        if slot.removed then
            return
        end

        if host.active and host.slots[host.active] == slot then
            extensions.call(slot.entry, "deactivate")
        end

        clear_drawing(slot)

        if slot.container then
            extensions.call(slot.entry, "destroy", slot.container)
            slot.container:Destroy()
            slot.container = nil
        end

        slot.removed = true
    end

    ---an extension was disposed while its tab is still in the window. the tab stays until
    ---the window is made again, with a note in it
    function host.remove(entry)
        for _, slot in pairs(host.slots) do
            if slot.entry == entry and not slot.removed then
                tear_down(slot)
                slot.note = stat_blocks.note(
                    slot.page.content,
                    "The plugin that added this tab was turned off."
                )
                stat_blocks.layout_note(slot.note, math.max(200, slot.page.content.width), PADDING)
            end
        end
    end

    ---the window is going away
    function host.destroy()
        for _, slot in pairs(host.slots) do
            tear_down(slot)

            if slot.note then
                slot.note.label:Destroy()
                slot.note = nil
            end
        end

        host.slots = {}
        host.active = nil
    end

    return host
end

return extension_tabs
