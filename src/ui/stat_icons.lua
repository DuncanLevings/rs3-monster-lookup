-- combat icons bundled in resources/
-- the client names each file without its extension so resources/stat_melee.png is
-- Plugin.resources.stat_melee

local stat_icons = {}
local reported_missing = false

---@param key string|false|nil icon name without the stat_ prefix eg "melee"
---@return any? resource the image, or nil and the caller shows text instead
function stat_icons.get(key)
    if not key then
        return nil
    end

    local resource = Plugin.resources["stat_" .. key]

    if not resource and not reported_missing then
        reported_missing = true
        log("Monster Lookup: icon resource stat_" .. key .. " was not found; showing text instead")
    end

    return resource
end

return stat_icons
