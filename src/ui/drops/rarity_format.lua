-- optional percentage view of drop rates, eg 1/128 becomes 0.7813%
-- only plain numeric fractions are touched, words like Rare stay as the wiki has them

local rarity_format = {}

local function percentage(numerator, denominator)
    local punctuation = denominator:match("[,.]+$") or ""
    denominator = denominator:gsub("[,.]+$", "")
    local top = tonumber((numerator:gsub(",", "")))
    local bottom = tonumber((denominator:gsub(",", "")))

    if not top or not bottom or bottom <= 0 or top > bottom then
        return numerator .. "/" .. denominator .. punctuation
    end

    local value = top / bottom * 100

    if value > 0 and value < 0.000001 then
        return "<0.000001%" .. punctuation
    end

    local precision = value < 0.01 and "%.6f" or value < 1 and "%.4f" or "%.2f"
    local formatted = string.format(precision, value)
    return formatted:gsub("0+$", ""):gsub("%.$", "") .. "%" .. punctuation
end

function rarity_format.format(rate, as_percentage)
    if not as_percentage then
        return rate
    end

    local result = rate:gsub("(%d[%d,]*%.?%d*)%s*/%s*(%d[%d,]*%d?%.?%d*)", percentage)
    return result
end

return rarity_format
