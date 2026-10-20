-- player settings, saved in PersistentDB

local settings = {}
local STORAGE_KEY = "monster_lookup_settings"
local intervals = { [15] = true, [60] = true, [360] = true, [1440] = true }
local values

local function load()
    if values then
        return values
    end

    local saved = PersistentDB:GetStructuredData(STORAGE_KEY)
    saved = type(saved) == "table" and saved.version == 1 and saved or {}
    values = {
        version = 1,
        refresh_minutes = intervals[saved.refresh_minutes] and saved.refresh_minutes or 60,
        percentage_rarity = saved.percentage_rarity == true,
    }

    return values
end

function settings.get()
    local current = load()
    return {
        refresh_minutes = current.refresh_minutes,
        percentage_rarity = current.percentage_rarity,
    }
end

function settings.set(key, value)
    if key == "refresh_minutes" and not intervals[value] then
        return false
    elseif key == "percentage_rarity" and type(value) ~= "boolean" then
        return false
    elseif key ~= "refresh_minutes" and key ~= "percentage_rarity" then
        return false
    end

    load()[key] = value
    local saved = PersistentDB:SetStructuredData(STORAGE_KEY, values)

    if not saved then
        log("Monster Lookup: settings could not be saved for the next session")
    end

    return true
end

return settings
