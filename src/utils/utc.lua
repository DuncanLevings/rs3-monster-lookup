-- MediaWiki returns UTC timestamps; os.time is unavailable in some client sandboxes.
-- Convert explicitly rather than interpreting UTC fields in the player's local timezone.
local utc = {}
local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function leap(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

function utc.parse(value)
    if type(value) ~= "string" then
        return nil
    end

    local year, month, day, hour, minute, second =
        value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)

    if
        not year
        or year < 1970
        or year > 2200
        or month < 1
        or month > 12
        or day < 1
        or day > MONTH_DAYS[month] + (month == 2 and leap(year) and 1 or 0)
        or hour > 23
        or minute > 59
        or second > 59
    then
        return nil
    end

    local previous = year - 1
    local days = (year - 1970) * 365
        + math.floor(previous / 4)
        - math.floor(1969 / 4)
        - math.floor(previous / 100)
        + math.floor(1969 / 100)
        + math.floor(previous / 400)
        - math.floor(1969 / 400)

    for index = 1, month - 1 do
        days = days + MONTH_DAYS[index] + (index == 2 and leap(year) and 1 or 0)
    end

    return ((days + day - 1) * 24 + hour) * 3600 + minute * 60 + second
end

return utc
