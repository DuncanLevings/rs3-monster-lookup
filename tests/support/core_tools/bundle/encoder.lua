-- packs plain lua values into the format src/bundle/codec.lua reads. build-time only,
-- this file isnt shipped. two passes over everything:
--   1. collect: give every table a canonical text form and count how often each one and
--      every string turns up
--   2. emit: write values out, strings as $<n> (most used strings get the shortest numbers)
--      and any table seen 2+ times as @<n>, stored once in the shared list

local encoder = {}
encoder.__index = encoder

-- put this in a list for "nothing here" so fixed-order lists can have gaps without holes
encoder.NIL = setmetatable({}, {
    __tostring = function()
        return "NIL"
    end,
})

-- a shared table costs a reference plus its own entry, not worth it for tiny ones
local MIN_SHARED_LENGTH = 16
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function base36(number)
    if number == 0 then
        return "0"
    end

    local negative = number < 0
    number = math.abs(number)
    local digits = {}

    while number > 0 do
        local digit = number % 36
        table.insert(digits, 1, DIGITS:sub(digit + 1, digit + 1))
        number = number // 36
    end

    return (negative and "-" or "") .. table.concat(digits)
end

local function is_whole(number)
    return number == number and number % 1 == 0 and math.abs(number) < 2 ^ 53
end

-- list part only covers 1..n with no gaps, everything else needs a string key
local function split_keys(value)
    local count = #value
    local keys = {}

    for key in pairs(value) do
        local listed = math.type(key) == "integer" and key >= 1 and key <= count

        if not listed then
            assert(type(key) == "string", "bundle: only string keys or a plain list are supported")
            keys[#keys + 1] = key
        end
    end

    table.sort(keys)
    return count, keys
end

function encoder.new()
    return setmetatable({
        canon = setmetatable({}, { __mode = "k" }),
        table_counts = {},
        string_counts = {},
    }, encoder)
end

function encoder:collect(value)
    local kind = type(value)

    if value == encoder.NIL then
        return "N"
    elseif kind == "string" then
        self.string_counts[value] = (self.string_counts[value] or 0) + 1
        return string.format("%q", value)
    elseif kind == "number" or kind == "boolean" then
        return tostring(value)
    end

    assert(kind == "table", "bundle: cannot pack a " .. kind)
    local count, keys = split_keys(value)
    local parts = {}

    for index = 1, count do
        parts[#parts + 1] = self:collect(value[index])
    end

    local pairs_text = {}

    for _, key in ipairs(keys) do
        pairs_text[#pairs_text + 1] = self:collect(key) .. "=" .. self:collect(value[key])
    end

    local text = "{" .. table.concat(parts, ",") .. ";" .. table.concat(pairs_text, ",") .. "}"
    self.canon[value] = text
    self.table_counts[text] = (self.table_counts[text] or 0) + 1
    return text
end

-- call once after collecting everything
function encoder:finish()
    local strings = {}

    for text in pairs(self.string_counts) do
        strings[#strings + 1] = text
    end

    table.sort(strings, function(a, b)
        local count_a, count_b = self.string_counts[a], self.string_counts[b]
        if count_a ~= count_b then
            return count_a > count_b
        end
        return a < b
    end)

    self.strings = strings
    self.string_index = {}

    for index, text in ipairs(strings) do
        self.string_index[text] = index - 1
    end

    self.shared = {}
    self.shared_index = {}
end

function encoder:emit(value)
    local kind = type(value)

    if value == encoder.NIL then
        return "N"
    elseif kind == "string" then
        return "$" .. base36(assert(self.string_index[value], "bundle: string not collected"))
    elseif kind == "boolean" then
        return value and "T" or "F"
    elseif kind == "number" then
        return is_whole(value) and base36(math.tointeger(value))
            or "#" .. string.format("%.17g", value)
    end

    local canon = assert(self.canon[value], "bundle: table not collected")

    if self.table_counts[canon] >= 2 and #canon >= MIN_SHARED_LENGTH then
        local index = self.shared_index[canon]

        if not index then
            -- reserve the number first so a nested emit cant take it
            index = #self.shared
            self.shared[index + 1] = false
            self.shared_index[canon] = index
            self.shared[index + 1] = self:emit_table(value)
        end

        return "@" .. base36(index)
    end

    return self:emit_table(value)
end

function encoder:emit_table(value)
    local count, keys = split_keys(value)
    local parts = {}

    for index = 1, count do
        parts[#parts + 1] = self:emit(value[index])
    end

    local text = "{" .. table.concat(parts, ",")

    if #keys > 0 then
        local pairs_text = {}

        for _, key in ipairs(keys) do
            pairs_text[#pairs_text + 1] = self:emit(key) .. "=" .. self:emit(value[key])
        end

        text = text .. ";" .. table.concat(pairs_text, ",")
    end

    return text .. "}"
end

encoder.base36 = base36
return encoder
