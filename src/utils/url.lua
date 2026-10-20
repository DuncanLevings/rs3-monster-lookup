-- building wiki api query strings

local url = {}

function url.encode(value)
    return (
        tostring(value):gsub("[^%w%-_%.~]", function(character)
            return string.format("%%%02X", string.byte(character))
        end)
    )
end

-- keys are sorted so the same query always gives the same url
function url.query(parameters)
    local keys = {}

    for key in pairs(parameters) do
        keys[#keys + 1] = key
    end

    table.sort(keys)

    local parts = {}

    for _, key in ipairs(keys) do
        parts[#parts + 1] = url.encode(key) .. "=" .. url.encode(parameters[key])
    end

    return "/api.php?" .. table.concat(parts, "&")
end

-- bucket queries are written in lua syntax on the wiki side so %q gives us a safely quoted
-- string literal (or a plain number for ids)
function url.literal(value)
    return string.format("%q", value)
end

return url
