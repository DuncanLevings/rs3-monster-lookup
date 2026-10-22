-- formatting for infobox values, which come back as numbers, strings with wiki markup in,
-- or lists of either. anything that cant be read comes out as Unknown

local wiki_text = require("src/utils/wiki_text")
local number_format = require("src/utils/number_format")

local stat_format = {}
local UNKNOWN = "Unknown"

function stat_format.number(value)
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
        return UNKNOWN
    end

    local text = string.format("%.2f", math.abs(value)):gsub("0+$", ""):gsub("%.$", "")
    return (value < 0 and "-" or "") .. number_format.group(text)
end

function stat_format.text(value)
    if type(value) == "table" then
        local parts = {}

        for _, entry in ipairs(value) do
            if type(entry) == "string" or type(entry) == "number" then
                parts[#parts + 1] = stat_format.text(entry)
            end
        end

        return #parts > 0 and table.concat(parts, ", ") or UNKNOWN
    elseif type(value) == "number" then
        return stat_format.number(value)
    elseif type(value) ~= "string" then
        return UNKNOWN
    end

    local text = wiki_text.plain(value)
    return text ~= "" and text ~= "?" and text or UNKNOWN
end

function stat_format.boolean(value, positive, negative)
    local normalized = type(value) == "string" and value:lower() or value

    if normalized == true or normalized == "true" or normalized == "yes" then
        return positive or "Yes"
    elseif normalized == false or normalized == "false" or normalized == "no" then
        return negative or "No"
    end

    return UNKNOWN
end

function stat_format.title(value)
    local title = stat_format.text(value):gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest
    end)
    return title
end

return stat_format
