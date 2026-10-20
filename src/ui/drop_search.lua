-- the search box above the drop tables and its "no matches" line
-- this only owns the widgets, the actual filtering of rows lives in drop_table

local theme = require("src/ui/theme")
local widgets = require("src/ui/widgets")
local internals = require("src/ui/prettyui_internals")

local drop_search = {}
local MAX_WIDTH = 240
local MIN_WIDTH = 80
-- room left of the box for the Collapse all and Refresh buttons
local BUTTON_ROW_WIDTH = 244

---@param page table tab page the drop tables are on
---@param query string text to start with, kept when the tables are rebuilt
---@param on_change fun(query: string)
function drop_search.new(page, query, on_change)
    local search = { page = page }

    search.no_matches = prettyui.Text.new(page.content, {
        text = "No drops match your search.",
        x = 8,
        width = -16,
        widthAnchor = 1,
        height = 24,
        colour = theme.TEXT_MUTED,
    })
    search.no_matches.hidden = true
    search.no_matches.clickthrough = true
    search.no_matches.enabled = false

    local options = internals.text_field_scroll_options(page)
    options.text = query
    options.placeholder = "Search drops..."
    options.width = MAX_WIDTH
    options.height = 24
    options.maxLength = 128
    options.colour = theme.TEXT
    options.onChange = function(_, _, content)
        on_change(content)
    end

    search.field = prettyui.TextField.new(page.content, options)
    widgets.forward_wheel(search.field.root, "monster_lookup_search_wheel", page)

    function search.layout()
        local space = page.content.width - BUTTON_ROW_WIDTH
        local width = math.min(MAX_WIDTH, math.max(MIN_WIDTH, space))
        search.field.root:SetPos(-width - 8, 12, 1, 0)
        search.field.root:SetSize(width, 24)
    end

    function search.destroy()
        search.field:Destroy()
        search.no_matches:Destroy()
    end

    search.layout()
    return search
end

return drop_search
