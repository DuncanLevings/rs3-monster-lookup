-- dropsline and coordinates bucket records for tests, shaped like what the wiki sends back
local json = require("src/vendor/json")

local rows = {}

---@param item string
---@param fields table? drop_json fields to change
---@param record table? fields on the bucket record itself eg rare_drop_table
function rows.drop(item, fields, record)
    local data = {
        ["Dropped item"] = item,
        ["Dropped from"] = "Goblin",
        ["Drop Quantity"] = "1",
        ["Quantity Low"] = 1,
        ["Quantity High"] = 1,
        ["Rarity"] = "Always",
        ["Alt Rarity"] = "",
        ["Alt Rarity Dash"] = "",
        ["Name Notes"] = "",
        ["Name NotesP"] = {},
        ["Quantity Notes"] = {},
        ["Rarity Notes"] = {},
        ["Drop GEMW"] = true,
        ["Drop Value"] = 1,
    }

    for key, value in pairs(fields or {}) do
        data[key] = value
    end

    local result = { item_name = item, drop_json = json.encode(data) }

    for key, value in pairs(record or {}) do
        result[key] = value
    end

    return result
end

function rows.spawn(mapid, plane, xs, ys)
    return { mapid = mapid, plane = plane, x = xs, y = ys }
end

return rows
