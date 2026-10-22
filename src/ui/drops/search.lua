-- the search box above the drop tables and its "no matches" line
-- this only owns the widgets, the actual filtering of rows lives in drop_table

local theme = require("src/ui/theme")
local widgets = require("src/ui/widgets")
local internals = require("src/ui/prettyui_internals")

local drop_search = {}
local MAX_WIDTH = 240
local MIN_WIDTH = 80

---@param page table tab page the drop tables are on
---@param query string text to start with, kept when the tables are rebuilt
---@param on_change fun(query: string)
function drop_search.new(page, query, on_change, field_parent)
    local search = { page = page }

    search.no_matches = widgets.text(page.content, {
        text = "No drops match your search.",
        x = 8,
        width = -16,
        widthAnchor = 1,
        height = 24,
        colour = theme.TEXT_MUTED,
    })
    search.no_matches.hidden = true

    local options = field_parent and {} or internals.text_field_scroll_options(page)
    options.text = query
    options.placeholder = "Search drops..."
    options.width = MAX_WIDTH
    options.height = 24
    options.maxLength = 128
    options.colour = theme.TEXT
    options.onChange = function(_, _, content)
        on_change(content)
    end

    search.field = prettyui.TextField.new(field_parent or page.content, options)
    widgets.forward_wheel(search.field.root, "monster_lookup_search_wheel", page)

    -- left reserves space for the other toolbar controls. return the actual bottom
    -- so the caller can place status text and tables below a wrapped search field
    function search.layout(left, y)
        left = left or 236
        y = y or 12
        local space = page.content.width - left - 8

        if space < MIN_WIDTH then
            y = y + 32
            space = math.max(1, page.content.width - 16)
        end

        local width = math.min(MAX_WIDTH, space)
        search.field.root:SetPos(-width - 8, y, 1, 0)
        search.field.root:SetSize(width, 24)
        return y + 24
    end

    function search.destroy()
        search.field:Destroy()
        search.no_matches:Destroy()
    end

    search.layout()
    return search
end

return drop_search
