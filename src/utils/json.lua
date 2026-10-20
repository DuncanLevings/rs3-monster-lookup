-- thin wrapper round the vendored rxi json so callers get nil + message instead of errors

local codec = require("src/vendor/json")

local json = { MAX_BYTES = 2000000 }

---@param value table
---@return string
function json.encode(value)
    return codec.encode(value)
end

---@param text string
---@return table? result
---@return string? problem message for the player
---@return string? detail raw error for the log
---@return string? reason "execution_limit" when the client stopped us for taking too long
function json.decode(text)
    if type(text) ~= "string" or #text > json.MAX_BYTES then
        return nil, "The Wiki response is too large or invalid."
    end

    local ok, result = pcall(codec.decode, text)

    -- the client kills long running lua with this message, theres no error code to check
    if not ok and tostring(result):find("Maximum function execution time", 1, true) then
        return nil,
            "The client exceeded its time limit while reading Wiki data.",
            tostring(result),
            "execution_limit"
    end

    if not ok or type(result) ~= "table" then
        return nil,
            "The Wiki returned unreadable data.",
            ok and "JSON root is not an object or array" or tostring(result)
    end

    return result
end

return json
