-- live GE prices from CerenMD's GE Price Library (gepl), an optional dependency
-- https://github.com/CerenMD/ge-prices-library
--
-- gepl does its own fetching and caching from prices.runescape.wiki and shares it with every
-- plugin using it, so Monster Lookup sends no price requests of its own. without gepl, or for
-- items it has no price for, the drop table keeps the GE price from the bundle/Wiki page
--
-- these are traded prices (instant buys and sells), not the Wiki's GE guide price. a drops
-- price is the unit price times the drop quantity, same as the Wiki's GE price column

local numbers = require("src/utils/numbers")

local prices = {}
local SUBSCRIPTION = "monster_lookup_price_wait"
local CHECK_TICKS = 50 -- about once a second
local GIVE_UP_TICKS = 50 * 120 -- stop waiting for gepl after about two minutes
-- how far a live price can be from the saved Wiki one before its treated as a one-off trade
-- (someone instant buying a single salvage for 2m made it look worth 1m each). real prices
-- rarely move this much in the few weeks between bundle builds
local MAX_DRIFT = 3
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

local function middle(high, low)
    if numbers.is_positive(high) and numbers.is_positive(low) then
        return math.floor((high + low) / 2 + 0.5)
    end

    return numbers.is_positive(high) and math.floor(high + 0.5)
        or numbers.is_positive(low) and math.floor(low + 0.5)
        or nil
end

---true once gepl is installed and has prices loaded
function prices.live()
    return call("isReady", "latest") == true
end

-- how many times apart two prices are, either way round
local function drift(price, reference)
    return math.max(price / reference, reference / price)
end

---unit price for an item id, nil when gepl cant give one or it doesnt look real
---
---the latest trades are one buy and one sell, so a single odd trade throws them right off,
---and the steadier hourly averages throw in gepl 0.2.5. with a saved Wiki price for the item
---(reference) the live price closest to it is used, unless even that is MAX_DRIFT times away.
---without one, a buy more than twice the sell is taken as the odd trade and the sell is used,
---its also the realistic price for a drop youd be selling
---@param item_id integer?
---@param reference number? the saved Wiki unit price, to sanity check against
---@return integer?
function prices.unit(item_id, reference)
    if not item_id or not library() then
        return nil
    end

    local candidates = {}
    local average = call("getOneHourAverage", item_id)

    if type(average) == "table" then
        candidates[#candidates + 1] = middle(average.avgHighPrice, average.avgLowPrice)
    end

    local latest = call("getLatest", item_id)
    local high = type(latest) == "table" and numbers.is_positive(latest.high) and latest.high or nil
    local low = type(latest) == "table" and numbers.is_positive(latest.low) and latest.low or nil
    candidates[#candidates + 1] = middle(high, low)
    candidates[#candidates + 1] = high and math.floor(high + 0.5) or nil
    candidates[#candidates + 1] = low and math.floor(low + 0.5) or nil

    if numbers.is_positive(reference) then
        local best

        for _, price in pairs(candidates) do
            if not best or drift(price, reference) < drift(best, reference) then
                best = price
            end
        end

        return best and drift(best, reference) <= MAX_DRIFT and best or nil
    end

    if candidates[1] and type(average) == "table" then
        return candidates[1]
    end

    if high and low and high > low * 2 then
        return math.floor(low + 0.5)
    end

    return middle(high, low)
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

    local low, high = quantity_range(drop.quantity)

    if not low then
        return nil
    end

    -- the saved price is for the whole quantity, the lowest of a range
    local saved = type(drop.price) == "table" and drop.price.minimum or drop.price
    local reference = type(saved) == "number" and low > 0 and saved / low or nil
    local unit = prices.unit(drop.item_id, reference)

    if not unit then
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
                log("Monster Lookup: live GE prices didnt load, showing the saved prices")
                stop_waiting()
            end
        end)
    end

    return true
end

---stops waiting for this key, eg a drop table thats been destroyed
---@param key string
function prices.forget(key)
    if waiting[key] == nil then
        return
    end

    waiting[key] = nil

    if next(waiting) == nil then
        stop_waiting()
    end
end

function prices.stop()
    stop_waiting()
end

return prices
