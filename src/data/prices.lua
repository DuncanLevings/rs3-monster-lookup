-- live GE prices from CerenMD's GE Price Library (gepl), an optional dependency
-- https://github.com/CerenMD/ge-prices-library
--
-- gepl does its own fetching and caching from prices.runescape.wiki and shares it with every
-- plugin using it, so Monster Lookup sends no price requests of its own. without gepl, or for
-- items it has no price for, the drop table keeps the GE price from the bundle/Wiki page
--
-- these are traded prices (instant buys and sells), not the Wiki's GE guide price. a drops
-- price is the unit price times the drop quantity, same as the Wiki's GE price column

local prices = {}
local SUBSCRIPTION = "monster_lookup_price_wait"
local CHECK_TICKS = 50 -- about once a second
local GIVE_UP_TICKS = 50 * 120 -- stop waiting for gepl after about two minutes
local waiting = {}
local waited = 0

local function library()
    return type(gepl) == "table" and gepl or nil
end

local function call(name, ...)
    local lib = library()

    if not lib or type(lib[name]) ~= "function" then
        return nil
    end

    -- gepl throws for item ids it doesnt know (untradeables, coins) and, in 0.2.5, from the
    -- average getters too, so every call is protected
    local ok, value = pcall(lib[name], ...)
    return ok and value or nil
end

local function positive(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function middle(high, low)
    if positive(high) and positive(low) then
        return math.floor((high + low) / 2 + 0.5)
    end

    return positive(high) and math.floor(high + 0.5) or positive(low) and math.floor(low + 0.5) or nil
end

---true once gepl is installed and has prices loaded
function prices.live()
    return call("isReady", "latest") == true
end

---unit price for an item id, nil when gepl cant give one
---@param item_id integer?
---@return integer?
function prices.unit(item_id)
    if not item_id or not library() then
        return nil
    end

    -- the hourly average is steadier, the latest trade is the fallback (and the only one that
    -- works in gepl 0.2.5)
    local average = call("getOneHourAverage", item_id)
    local price = type(average) == "table" and middle(average.avgHighPrice, average.avgLowPrice)

    if price then
        return price
    end

    local latest = call("getLatest", item_id)
    return type(latest) == "table" and middle(latest.high, latest.low) or nil
end

-- "30-40 (noted)" -> 30, 40 and "1,000" -> 1000, 1000. nil when theres no number at all
local function quantity_range(text)
    local numbers = {}

    for digits in tostring(text or ""):gmatch("%d[%d,]*") do
        numbers[#numbers + 1] = tonumber((digits:gsub(",", "")))

        if #numbers == 2 then
            break
        end
    end

    if not numbers[1] then
        return nil
    end

    return numbers[1], numbers[2] or numbers[1]
end

---live GE price for a drop row, or nil to keep the bundled one
---@param drop Drop
---@return number|{minimum: number, maximum: number}|nil
function prices.for_drop(drop)
    if drop.price == "Not sold" then
        return nil
    end

    local unit = prices.unit(drop.item_id)
    local low, high = quantity_range(drop.quantity)

    if not unit or not low then
        return nil
    end

    if high ~= low then
        return { minimum = unit * math.min(low, high), maximum = unit * math.max(low, high) }
    end

    return unit * low
end

local function stop_waiting()
    Event.Logic.Unsubscribe(SUBSCRIPTION)
    waiting, waited = {}, 0
end

---calls back once gepl has prices, if theyre still loading. a later call with the same key
---replaces the earlier callback. returns false when theres nothing to wait for (no gepl,
---or prices already live)
---@param key string
---@param callback fun()
---@return boolean waiting
function prices.when_live(key, callback)
    if not library() or prices.live() then
        return false
    end

    local first = next(waiting) == nil
    waiting[key] = callback

    if first then
        waited = 0
        Event.Logic.Subscribe(SUBSCRIPTION, function()
            waited = waited + 1

            if waited % CHECK_TICKS ~= 0 then
                return
            end

            if prices.live() then
                local callbacks = waiting
                stop_waiting()

                for _, ready in pairs(callbacks) do
                    ready()
                end
            elseif waited >= GIVE_UP_TICKS or not library() then
                stop_waiting()
            end
        end)
    end

    return true
end

function prices.stop()
    stop_waiting()
end

return prices
