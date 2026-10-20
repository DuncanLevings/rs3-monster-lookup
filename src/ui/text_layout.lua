-- helpers for multi line text in native components

local text_layout = {}

-- native text wants <br> rather than \n
function text_layout.display(value)
    return (value:gsub("\n", "<br>"))
end

-- height a block of text needs at the given width, measured with the real font so it wraps
-- the same way the client will draw it
function text_layout.height(value, width, font, line_height)
    font = font or config.Font.MUSEO_SANS_15PT_REGULAR
    local lines = font:GetStringLineCount(text_layout.display(value), math.max(1, width))
    return math.max(1, lines) * (line_height or 22) + 8
end

return text_layout
