-- player settings, saved in PersistentDB

local settings = {}
local STORAGE_KEY = "monster_lookup_settings"

-- choices for the View drops menu text. default has no colour so it looks like every other
-- menu option, the rest are toned down so they dont fight with npc names and combat levels
settings.MENU_COLOURS = {
    { id = "default", name = "Default" },
    { id = "cyan", name = "Cyan", hex = "8fd3d3" },
    { id = "purple", name = "Purple", hex = "b9a3e3" },
    { id = "orange", name = "Orange", hex = "e6a96b" },
}

local function find_menu_colour(id)
    for _, colour in ipairs(settings.MENU_COLOURS) do
        if colour.id == id then
            return colour
        end
    end
end

local function is_menu_colour(value)
    return find_menu_colour(value) ~= nil
end

local function is_boolean(value)
    return type(value) == "boolean"
end

-- one check per setting, also decides which keys settings.set accepts
local VALID = {
    percentage_rarity = is_boolean,
    slayer_expanded = is_boolean,
    detailed_stats_expanded = is_boolean,
    menu_colour = is_menu_colour,
}

local DEFAULTS = {
    percentage_rarity = false,
    menu_colour = "default",
    slayer_expanded = true,
    detailed_stats_expanded = false,
}

local values

local function load()
    if values then
        return values
    end

    local saved = PersistentDB:GetStructuredData(STORAGE_KEY)
    saved = type(saved) == "table" and saved.version == 1 and saved or {}
    ---@type table<string, any>
    local loaded = { version = 1 }

    -- recover each setting separately so one invalid saved value does not reset the others
    for key, valid in pairs(VALID) do
        if valid(saved[key]) then
            loaded[key] = saved[key]
        else
            loaded[key] = DEFAULTS[key]
        end
    end

    values = loaded

    return values
end

-- a copy, so callers cant change the saved values without going through settings.set
function settings.get()
    local current = load()
    local copy = {}

    for key in pairs(DEFAULTS) do
        copy[key] = current[key]
    end

    return copy
end

-- hex for the current View drops colour, nil for the default
function settings.menu_colour_hex()
    return find_menu_colour(load().menu_colour).hex
end

function settings.set(key, value)
    local valid = VALID[key]

    if not valid or not valid(value) then
        return false
    end

    -- a failed save still leaves the choice active for this session
    load()[key] = value
    local saved = PersistentDB:SetStructuredData(STORAGE_KEY, values)

    if not saved then
        log("Monster Lookup: settings could not be saved for the next session")
    end

    return true
end

return settings
