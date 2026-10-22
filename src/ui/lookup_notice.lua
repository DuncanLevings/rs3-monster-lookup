-- message box at the top of the Drops tab, red when a lookup fails with no saved data to fall
-- back on, or a plain one when theres just nothing to show. resizes to fit as the window does

local text_layout = require("src/ui/common/text_layout")
local theme = require("src/ui/common/theme")
local widgets = require("src/ui/common/widgets")

local lookup_notice = {}
local INSET = 14
local TITLE_HEIGHT = 28

local function create_label(parent, y, colour)
    local label = widgets.text(parent, {
        text = "",
        x = INSET,
        y = y,
        width = -INSET * 2,
        widthAnchor = 1,
        height = TITLE_HEIGHT,
        colour = colour,
    })

    return label
end

local function resize_notice(notice)
    -- the resizing below can set off our ONRESIZE hook again (say the page scrollbar appears
    -- and the width changes), this stops it re-entering halfway through
    if notice.resizing then
        return
    end

    notice.resizing = true

    local height = text_layout.height(notice.message, notice.root.width - INSET * 2)
    notice.body:SetSize(-INSET * 2, height, 1, 0)
    notice.root:SetSize(0, height + TITLE_HEIGHT + INSET * 2, 1, 0)
    notice.page:SetContentHeight(notice.root.height + 24)
    notice.resizing = false
end

function lookup_notice.new(page)
    local root = widgets.layer(page.content, 1)
    root:SetPos(0, 12)
    root.hidden = true

    local notice = {
        root = root,
        page = page,
        background = widgets.background(root, theme.ERROR_BACKGROUND),
        title = create_label(root, INSET, theme.ERROR_TITLE),
        body = create_label(root, INSET + TITLE_HEIGHT, theme.TEXT),
        message = "",
    }
    local width = root.width

    root:Subscribe(ui.Hook.ONRESIZE, "monster_lookup_error_resize", function()
        if root.width ~= width then
            width = root.width

            if not root.hidden then
                resize_notice(notice)
            end
        end
    end)

    return notice
end

-- "error" is the red failure box, "info" is a plain brown box for things that arent really
-- a problem, like a monster that has no drops
local TONES = {
    error = { background = theme.ERROR_BACKGROUND, title = theme.ERROR_TITLE },
    info = { background = theme.HEADER, title = theme.TEXT_WARNING },
}

---@param message string
---@param title string? defaults to "Couldn't load drops"
---@param tone "error"|"info"|nil defaults to "error"
function lookup_notice.show(notice, message, title, tone)
    local colours = TONES[tone or "error"]
    notice.background.rgba = colours.background
    notice.title.rgba = colours.title
    notice.message = message
    notice.title.content = title or "Couldn't load drops"
    notice.body.content = text_layout.display(message)
    notice.root.hidden = false

    resize_notice(notice)
end

function lookup_notice.hide(notice)
    notice.root.hidden = true
end

return lookup_notice
