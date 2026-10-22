-- the average value of one kill, worked out from the drop tables shown with live or saved
-- prices. it follows the wikis own Module:Average_drop_value, adding up for each drop
--
--   unit price x average quantity x chance per roll x rolls per kill
--
-- where the average quantity is halfway between the lowest and highest. coins are worth 1 gp
-- each, items the GE doesnt trade count as 0. the wiki puts its result in the page text, but
-- thats at the prices from when the page was saved, so the drop table shows this instead and
-- hides those sentences (see without_wiki_averages)
--
-- the sections passed in should be one mode or enrage table, what the drop table is showing,
-- so alternative tables like normal and hard mode never get added together. every table in
-- that mode counts, tertiary drops included, same as the wiki

local drop_odds = require("src/data/drops/odds")

local kill_value = {}

---@class KillValue
---@field total number gp, only from the drops that could be counted
---@field estimate boolean true when anything was left out
---@field counted integer drops in the total
---@field unknown_chance integer left out, rarity is a word like Common or Varies
---@field unknown_quantity integer left out, quantity has no numbers (N/A, Unknown)
---@field no_price integer left out, tradeable but no price live or saved
---@field untradeable integer counted as 0 gp
---@field conditional integer left out, an Always drop with a condition on it (see below)

local function is_coins(drop)
    local name = tostring(drop.wiki_name or drop.name or ""):lower()
    return name == "coins" or name:find("^coins[%s%(]") ~= nil
end

-- what one of the item is worth: live when theres a price for it, else worked back out of the
-- saved price for the whole quantity
local function unit_price(drop, low, live_unit)
    if is_coins(drop) then
        return 1
    end

    if drop.price == "Not sold" then
        return 0, true
    end

    local saved = drop.price

    if type(saved) == "table" then
        saved = saved.minimum
    end

    saved = type(saved) == "number" and saved >= 0 and low > 0 and saved / low or nil

    -- the saved price also tells the live lookup what a sane price looks like
    local live = drop.item_id and live_unit and live_unit(drop.item_id, saved)

    if type(live) == "number" and live >= 0 then
        return live
    end

    return saved
end

---@param sections DropSection[] the tables for the mode being shown
---@param live_unit (fun(item_id: integer, reference: number?): number?)? live price for one
---item, given the saved one to sanity check against. nil uses the saved prices
---@return KillValue
function kill_value.calculate(sections, live_unit)
    local result = {
        total = 0,
        estimate = false,
        counted = 0,
        unknown_chance = 0,
        unknown_quantity = 0,
        no_price = 0,
        untradeable = 0,
        conditional = 0,
    }

    for _, section in ipairs(sections or {}) do
        for _, drop in ipairs(section.drops or {}) do
            local chance = drop_odds.chance(drop)
            local low, high = drop_odds.quantity(drop)

            if drop.name == "Nothing" then
                -- a roll that gives nothing is worth nothing, not unknown
                result.counted = result.counted + 1
            elseif
                chance == 1
                and drop.note_marker
                and drop.note_marker ~= ""
                and drop.price ~= "Not sold"
            then
                -- an Always drop with a note is nearly always one that needs something first,
                -- a binding contract, a quest, one variant only. at full value every kill it
                -- swamps the rest (34k on a 4k abyssal demon), so its left out instead. an
                -- untradeable one is worth 0 either way so it isnt worth a mention, and drops
                -- with a real rate and a note are counted, like the wiki does
                result.conditional = result.conditional + 1
            elseif not chance then
                result.unknown_chance = result.unknown_chance + 1
            elseif not low then
                result.unknown_quantity = result.unknown_quantity + 1
            else
                local price, untradeable = unit_price(drop, low, live_unit)

                if not price then
                    result.no_price = result.no_price + 1
                else
                    local average = (low + high) / 2
                    result.total = result.total + price * average * chance * drop_odds.rolls(drop)
                    result.counted = result.counted + 1

                    if untradeable then
                        result.untradeable = result.untradeable + 1
                    end
                end
            end
        end
    end

    result.estimate = result.unknown_chance
            + result.unknown_quantity
            + result.no_price
            + result.conditional
        > 0
    return result
end

local function is_wiki_average(sentence)
    local lower = sentence:lower()
    return lower:find("average", 1, true) ~= nil and lower:find("worth", 1, true) ~= nil
end

---the wikis own "the average kill is worth ..." sentences, taken out of section text since
---they use the prices from when the page was saved and would disagree with the live total
---@param text string?
---@return string?
function kill_value.without_wiki_averages(text)
    -- most text has nothing to take out, leave it exactly as it was
    if type(text) ~= "string" or not is_wiki_average(text) then
        return text
    end

    local paragraphs = {}

    for paragraph in (text .. "\n\n"):gmatch("(.-)\n\n") do
        local kept = {}

        -- a sentence ends at . ! or ? and a space, so "2.5k" stays in one piece. | marks the
        -- ends, the wikis prose never has one
        for sentence in (paragraph:gsub("([%.!?])%s+", "%1|") .. "|"):gmatch("(.-)|") do
            if sentence:match("%S") and not is_wiki_average(sentence) then
                kept[#kept + 1] = sentence
            end
        end

        if #kept > 0 then
            paragraphs[#paragraphs + 1] = table.concat(kept, " ")
        end
    end

    return table.concat(paragraphs, "\n\n")
end

return kill_value
