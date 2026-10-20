-- GE price text for the table. under 100k shows in full, above that its k/m/b with one
-- decimal, ranges show as low-high

local price_format = {}
local UNITS = {
    { divisor = 1000, suffix = "k" },
    { divisor = 1000000, suffix = "m" },
    { divisor = 1000000000, suffix = "b" },
}

local function is_valid_amount(amount)
    return type(amount) == "number" and amount >= 0 and amount < math.huge
end

local function add_thousands_separators(amount)
    local digits = string.format("%.0f", amount)

    return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function select_unit(amount)
    local index = 1

    for candidate = #UNITS, 1, -1 do
        if amount >= UNITS[candidate].divisor then
            index = candidate
            break
        end
    end

    return index
end

local function format_abbreviated_amount(amount)
    local index = select_unit(amount)
    local rounded = math.floor(amount / UNITS[index].divisor * 10 + 0.5) / 10

    if rounded >= 1000 and index < #UNITS then
        index = index + 1
        rounded = math.floor(amount / UNITS[index].divisor * 10 + 0.5) / 10
    end

    return string.format("%.1f", rounded):gsub("%.0$", "") .. UNITS[index].suffix
end

local function format_amount(amount)
    if amount < 100000 then
        return add_thousands_separators(amount)
    end

    return format_abbreviated_amount(amount)
end

local function format_range(range)
    if not is_valid_amount(range.minimum) or not is_valid_amount(range.maximum) then
        return "Unknown"
    end

    if range.minimum > range.maximum then
        return "Unknown"
    end

    if range.minimum == range.maximum then
        return format_amount(range.minimum) .. " gp"
    end

    return format_amount(range.minimum) .. "-" .. format_amount(range.maximum) .. " gp"
end

function price_format.format(price)
    if price == "Not sold" then
        return price
    end

    if type(price) == "table" then
        return format_range(price)
    end

    if not is_valid_amount(price) then
        return "Unknown"
    end

    return format_amount(price) .. " gp"
end

return price_format
