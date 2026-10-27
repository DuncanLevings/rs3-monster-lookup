-- the few places utilizing prettyui fields that arent in its docs
--
-- kept in one file so a prettyui update only means checking here.
-- if something breaks after an update look here first.

local internals = {}

-- SimpleButton has no SetText, its label is a Text component stored in button.content
function internals.set_button_text(button, text)
    button.content.content = text
end

function internals.set_button_font(button, font)
    button.content.font = font
end

-- CollapseButton draws its bar from three sprites (left, middle, right end)
function internals.set_collapse_alpha(button, bar_alpha, end_alpha)
    button.left.alpha = bar_alpha
    button.middle.alpha = bar_alpha
    button.right.alpha = end_alpha
end

return internals
