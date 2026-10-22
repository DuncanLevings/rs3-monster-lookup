-- small helpers for numbers in text

local number_format = {}

-- adds thousands commas to an already formatted number without changing its sign,
-- precision or suffix, "12345.5k" -> "12,345.5k"
function number_format.group(text)
    local sign, whole, rest = text:match("^(-?)(%d+)(.*)$")

    if not whole then
        return text
    end

    local grouped = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. grouped .. rest
end

-- "1 monster", "3 monsters"
function number_format.plural(count, word)
    return count .. " " .. word .. (count == 1 and "" or "s")
end

return number_format
