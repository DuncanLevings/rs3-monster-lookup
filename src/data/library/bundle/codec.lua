-- unpacks bundled monster data. tools/bundle/build.lua writes it, see docs/bundle-format.md
--
-- a packed value is plain ascii so it can sit in a lua string literal without escaping:
--   T / F / N      true / false / nothing (a gap in a fixed-order list, see bundle_shapes)
--   $<n>           string number n from the strings list
--   @<n>           shared table number n (stored once, used by many pages)
--   #<text>        a number that isnt a whole number, eg #12.5
--   <n> or -<n>    a whole number, base 36
--   {a,b;$k=v}     a table: list items, then ; and key=value pairs (keys are always strings)
-- all numbers after $ and @ are base 36 too

local codec = {}

local DELIMITERS = "[,;={}]"

---@param text string packed value
---@param strings string[] shared strings
---@param shared string[] packed shared tables
---@return any value fresh tables every call, callers are free to change them
function codec.decode(text, strings, shared)
    local position = 1
    local read_value

    local function read_token()
        local stop = text:find(DELIMITERS, position) or #text + 1
        local token = text:sub(position, stop - 1)
        position = stop
        return token
    end

    local function read_table()
        local result = {}
        position = position + 1 -- {
        local index = 0

        -- list part
        while true do
            local character = text:sub(position, position)

            if character == "}" or character == ";" or character == "" then
                break
            end

            index = index + 1
            result[index] = read_value()

            if text:sub(position, position) == "," then
                position = position + 1
            end
        end

        -- key=value part
        if text:sub(position, position) == ";" then
            position = position + 1

            while text:sub(position, position) ~= "}" and position <= #text do
                local key = read_value()
                assert(key ~= nil, "bundle: missing key")
                assert(text:sub(position, position) == "=", "bundle: expected = after a key")
                position = position + 1
                result[key] = read_value()

                if text:sub(position, position) == "," then
                    position = position + 1
                end
            end
        end

        assert(text:sub(position, position) == "}", "bundle: unclosed table")
        position = position + 1
        return result
    end

    read_value = function()
        local character = text:sub(position, position)

        if character == "{" then
            return read_table()
        end

        local token = read_token()
        local kind, rest = token:sub(1, 1), token:sub(2)

        if token == "T" then
            return true
        elseif token == "F" then
            return false
        elseif token == "N" then
            return nil
        elseif kind == "$" then
            return assert(strings[tonumber(rest, 36) + 1], "bundle: missing string")
        elseif kind == "@" then
            local packed = assert(shared[tonumber(rest, 36) + 1], "bundle: missing shared table")
            return codec.decode(packed, strings, shared)
        elseif kind == "#" then
            return assert(tonumber(rest), "bundle: bad number")
        end

        return assert(tonumber(token, 36), "bundle: bad value " .. token)
    end

    local value = read_value()
    assert(position > #text, "bundle: trailing data")
    return value
end

return codec
