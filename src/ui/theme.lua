-- colours and sizes shared by the window, picked to sit close to the games own brown panels

local theme = {
    TEXT = 0xE7D7B0FF,
    TEXT_SOFT = 0xC8BDA5FF,
    TEXT_LABEL = 0xB9AD98FF,
    TEXT_MUTED = 0x9C9485FF,
    TEXT_WARNING = 0xE9BD75FF,
    TEXT_PRICE = 0xF0CD79FF,
    TEXT_NEGATIVE = 0xDE5555FF,

    HEADER = 0x493C2CFF,
    COLUMN_HEADER = 0x3B3125FF,
    RARITY_CELL = 0x4A3B28FF,
    MISSING_ICON = 0x3B3125FF,
    ROW_EVEN = 0x30281FFF,
    ROW_ODD = 0x272119FF,

    ERROR_BACKGROUND = 0x4F2724FF,
    ERROR_TITLE = 0xFFB4A4FF,

    -- same step the tab pages use natively, so forwarded scrolling feels the same
    WHEEL_STEP = 32,
}

function theme.row_colour(index)
    return index % 2 == 0 and theme.ROW_EVEN or theme.ROW_ODD
end

return theme
