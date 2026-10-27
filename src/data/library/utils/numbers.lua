-- checks for numbers that come from somewhere outside the plugin (saved data, the wiki, the
-- client). each one has to rule out nil, strings, NaN and infinity before anything else,
-- which is easy to forget, so its all done here

local numbers = {}

---a real number, not NaN or infinity
---@param value any
---@return boolean
function numbers.is_finite(value)
    return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

---a whole number from minimum (0 if not given) to maximum (no limit if not given)
---@param value any
---@param minimum number?
---@param maximum number?
---@return boolean
function numbers.is_whole(value, minimum, maximum)
    return numbers.is_finite(value)
        and value % 1 == 0
        and value >= (minimum or 0)
        and (maximum == nil or value <= maximum)
end

---a real number above 0
---@param value any
---@return boolean
function numbers.is_positive(value)
    return numbers.is_finite(value) and value > 0
end

return numbers
