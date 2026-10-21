-- checks decoded API records before the lookup uses them

local json = require("src/utils/json")

local response = {}

-- ipairs alone would silently skip holes or object keys in a malformed record list
local function is_array(value)
    if type(value) ~= "table" then
        return false
    end

    local count = 0

    for key in pairs(value) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
            return false
        end

        count = count + 1
    end

    return count == #value
end

function response.bucket(value)
    if type(value) ~= "table" or not is_array(value.bucket) then
        return nil, "The Wiki returned an invalid list of records. Please try again."
    end

    return value.bucket
end

-- the bucket embeds infobox data as another JSON string inside the API response
-- missing stats are allowed, but broken stats must not become a cacheable empty result
function response.monster_info(value)
    if value == nil then
        return {}
    end

    local info, problem = json.decode(value)

    if not info then
        return nil, "The Wiki monster stats could not be read. " .. problem
    end

    for key in pairs(info) do
        if type(key) ~= "string" then
            return nil, "The Wiki returned an invalid monster stats record. Please try again."
        end
    end

    return info
end

function response.page_text(value)
    if
        type(value) ~= "table"
        or type(value.parse) ~= "table"
        or type(value.parse.text) ~= "string"
    then
        return nil, "The Wiki returned an invalid monster page. Please try again."
    end

    return value.parse.text
end

local function item_id(value)
    if type(value) ~= "number" and type(value) ~= "string" then
        return nil
    end

    local number = tonumber(value)
    return number and number >= 0 and number < math.huge and number % 1 == 0 and number or nil
end

function response.item_ids(value)
    local rows, problem = response.bucket(value)

    if not rows then
        return nil, problem
    end

    local ids = {}

    for _, item in ipairs(rows) do
        if type(item) ~= "table" or type(item.page_name) ~= "string" or item.page_name == "" then
            return nil, "The Wiki returned an invalid item record."
        end

        if item.item_id ~= nil then
            if not is_array(item.item_id) then
                return nil, "The Wiki returned an invalid item ID list."
            end

            -- a Wiki item can have several game IDs; one representative ID is enough for its icon
            if #item.item_id > 0 then
                local resolved = item_id(item.item_id[1])

                if not resolved then
                    return nil, "The Wiki returned an invalid item ID."
                end

                ids[item.page_name] = resolved
            end
        end
    end

    return ids
end

return response
