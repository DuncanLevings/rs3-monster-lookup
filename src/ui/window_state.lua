-- remembers the window size and position between sessions
-- position is stored as a fraction of the free space so it stays on screen if the game
-- window is resized

local window_state = {}
local STORAGE_KEY = "monster_lookup_window"

local function is_finite_number(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

local function load_saved_geometry()
    local saved = PersistentDB:GetStructuredData(STORAGE_KEY)

    if type(saved) ~= "table" or saved.version ~= 1 then
        return {}
    end

    return saved
end

local function get_size_limits(parent)
    return {
        minWidth = math.min(760, parent.width),
        minHeight = math.min(360, parent.height),
        maxWidth = math.min(1200, parent.width),
        maxHeight = math.min(850, parent.height),
    }
end

local function restore_window_size(options, saved)
    local width = is_finite_number(saved.width) and saved.width or 840
    local height = is_finite_number(saved.height) and saved.height or 520

    options.width = clamp(width, options.minWidth, options.maxWidth)
    options.height = clamp(height, options.minHeight, options.maxHeight)
end

local function restore_window_position(options, saved, parent)
    local x_ratio = clamp(is_finite_number(saved.x_ratio) and saved.x_ratio or 0.5, 0, 1)
    local y_ratio = clamp(is_finite_number(saved.y_ratio) and saved.y_ratio or 0.5, 0, 1)

    options.x = math.floor((parent.width - options.width) * x_ratio + 0.5)
    options.y = math.floor((parent.height - options.height) * y_ratio + 0.5)
end

local function capture_window_geometry(window)
    local root = window.root
    local parent = window.parent
    local x_space = math.max(0, parent.width - root.width)
    local y_space = math.max(0, parent.height - root.height)

    -- relative placement stays on screen when the game size changes
    return {
        version = 1,
        width = root.width,
        height = root.height,
        x_ratio = x_space > 0 and clamp(root.x / x_space, 0, 1) or 0,
        y_ratio = y_space > 0 and clamp(root.y / y_space, 0, 1) or 0,
    }
end

function window_state.load(parent)
    local saved = load_saved_geometry()
    local options = get_size_limits(parent)

    restore_window_size(options, saved)
    restore_window_position(options, saved, parent)

    return options
end

function window_state.save(window)
    local root = window.root
    local parent = window.parent

    if not root or not parent or parent.width <= 0 or parent.height <= 0 then
        return
    end

    PersistentDB:SetStructuredData(STORAGE_KEY, capture_window_geometry(window))
end

return window_state
