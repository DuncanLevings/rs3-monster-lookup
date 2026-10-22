-- the numbers behind a drop row: how likely it is, how many rolls a kill gets at it, and the
-- lowest and highest quantity. the page shows these as text ("3 × 1/1,500", "2–3 (noted)"),
-- the build and the live bucket lookup keep them as numbers on the drop so the kill value
-- doesnt have to read them back out of the display text
--
-- stored on a drop as:
--   chance          the wikis percent per roll as text, eg "1.56", "100" for Always. text
--                   because thats how the wiki writes it and its short in the bundle, nil
--                   when the rarity is a word (Common, Random, Varies...) or missing
--   rolls           rolls per kill, nil means 1
--   quantity_low    lowest quantity, nil when the quantity is just a number
--   quantity_high   highest quantity, nil when its the same as quantity_low

local numbers = require("src/utils/numbers")

local drop_odds = {}

-- "3 × 0.0667" -> "0.0667", 3. the wiki puts the roll count in front of the rate
local function split_rolls(value)
    local count, rest = value:match("^%s*(%d+)%s*×%s*(.-)%s*$")

    if count then
        return rest, tonumber(count)
    end

    return value:match("^%s*(.-)%s*$"), 1
end

local function percent_text(value)
    -- %.6g keeps it short and exact enough, 1/1,500 becomes 0.0666667
    return (string.format("%.6g", value))
end

---lowest and highest quantity from the quantity column, nil when it has no numbers
---("N/A", "Unknown"). a list like "5; 50" or "8–9; 16–18" goes from its smallest to its
---largest number, which is how the wikis own average drop value treats it
---@param quantity string? eg "1", "2–3 (noted)", "1,000", "5; 50"
---@return integer? low
---@return integer? high
function drop_odds.bounds(quantity)
    local low, high

    for number in
        tostring(quantity or ""):gsub("%(noted%)", ""):gsub("(%d),(%d)", "%1%2"):gmatch("%d+")
    do
        local value = assert(tonumber(number))
        low = math.min(low or value, value)
        high = math.max(high or value, value)
    end

    return low, high
end

---fills chance, rolls and the quantity bounds on a drop. the rate is either the wikis
---percent from the page ("3 × 0.0667") or a rarity fraction from the bucket ("1/128")
---@param drop Drop
---@param rate string? percent with an optional "N ×" in front, or a fraction or Always
---@param is_percent boolean? true when rate is already a percent
function drop_odds.fill(drop, rate, is_percent)
    local value, rolls = split_rolls(tostring(rate or ""))
    local chance

    if value:lower() == "always" then
        chance = "100"
    elseif is_percent then
        local number = tonumber((value:gsub(",", "")))
        chance = number and number > 0 and number <= 100 and percent_text(number) or nil
    else
        local top, bottom = value:gsub(",", ""):match("^~?(%d+%.?%d*)%s*/%s*(%d+%.?%d*)$")
        local number = top and tonumber(bottom) > 0 and tonumber(top) / tonumber(bottom) * 100
        chance = number and number > 0 and number <= 100 and percent_text(number) or nil
    end

    drop.chance = chance
    drop.rolls = chance and rolls > 1 and rolls or nil

    local low, high = drop_odds.bounds(drop.quantity)

    -- a plain number is its own bounds, only anything else needs them written down
    if low and tostring(drop.quantity) ~= tostring(low) then
        drop.quantity_low = low
        drop.quantity_high = high ~= low and high or nil
    end
end

---the chance per roll from 0 to 1, nil when its not known
---@param drop Drop
---@return number?
function drop_odds.chance(drop)
    local value = tonumber(drop.chance)
    return value and value > 0 and value <= 100 and value / 100 or nil
end

---@param drop Drop
---@return integer
function drop_odds.rolls(drop)
    return numbers.is_whole(drop.rolls) and drop.rolls > 0 and drop.rolls or 1
end

---@param drop Drop
---@return integer? low nil when the quantity isnt known
---@return integer? high
function drop_odds.quantity(drop)
    local low, high = drop.quantity_low, drop.quantity_high

    if type(low) == "number" and numbers.is_whole(low) then
        if type(high) ~= "number" or not numbers.is_whole(high) or high < low then
            high = low
        end

        return low, high
    end

    local plain = tonumber(drop.quantity)
    if numbers.is_whole(plain) then
        return plain, plain
    end
end

return drop_odds
