-- reads one infobox_monster bucket row's json into its values, for the bundle build. the
-- Monster Lookup plugin has the same check for its live lookups (src/data/wiki/response.lua)
-- missing stats are allowed, but broken stats must not end up in the bundle

local json = require("src/data/library/utils/json")

local infobox = {}

function infobox.monster_info(value)
    if value == nil then
        return {}
    end

    local info, problem = json.decode(value)

    if not info then
        return nil, "The Wiki monster stats could not be read. " .. problem
    end

    for key in pairs(info) do
        if type(key) ~= "string" then
            return nil, "The Wiki returned an invalid monster stats record."
        end
    end

    return info
end

return infobox
