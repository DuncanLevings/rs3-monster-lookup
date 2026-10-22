-- group an already formatted number without changing its sign, precision or suffix.

local number_format = {}

function number_format.group(text)
    local sign, whole, rest = text:match("^(-?)(%d+)(.*)$")

    if not whole then
        return text
    end

    local grouped = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. grouped .. rest
end

return number_format
