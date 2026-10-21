-- player settings, saved in PersistentDB

local settings = {}
local STORAGE_KEY = "monster_lookup_settings"
local INTERVALS = { [15] = true, [60] = true, [360] = true, [1440] = true }

-- choices for the View drops menu text. default has no colour so it looks like every other
-- menu option, the rest are toned down so they dont fight with npc names and combat levels
settings.MENU_COLOURS = {
    { id = "default", name = "Default" },
    { id = "cyan", name = "Cyan", hex = "8fd3d3" },
    { id = "purple", name = "Purple", hex = "b9a3e3" },
    { id = "orange", name = "Orange", hex = "e6a96b" },
}

local function is_menu_colour(value)
    for _, colour in ipairs(settings.MENU_COLOURS) do
        if colour.id == value then
            return true
        end
    end

    return false
end

-- one check per setting, also decides which keys settings.set accepts
local VALID = {
    refresh_minutes = function(value)
        return INTERVALS[value] == true
    end,
    percentage_rarity = function(value)
        return type(value) == "boolean"
    end,
    menu_colour = is_menu_colour,
}

local DEFAULTS = { refresh_minutes = 60, percentage_rarity = false, menu_colour = "default" }

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

function settings.get()
    local current = load()
    return {
        refresh_minutes = current.refresh_minutes,
        percentage_rarity = current.percentage_rarity,
        menu_colour = current.menu_colour,
    }
end

-- hex for the current View drops colour, nil for the default
function settings.menu_colour_hex()
    local selected = load().menu_colour

    for _, colour in ipairs(settings.MENU_COLOURS) do
        if colour.id == selected then
            return colour.hex
        end
    end
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
