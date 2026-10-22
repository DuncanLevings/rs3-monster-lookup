local lu = require("luaunit")
local drop_odds = require("src/data/drop_odds")
local kill_value = require("src/data/kill_value")
local parser = require("tools/wiki_page")
local dropsline = require("src/data/dropsline")
local rows = require("tests/support/dropsline_rows")

-- the average kill value: the numbers kept on each drop (src/data/drop_odds.lua) and the sum
-- over the tables being shown (src/data/kill_value.lua)
return function()
    local suite = {}

    local function drop(fields)
        local row = { name = "Item", quantity = "1", rate = "1/2", note_marker = "", notes = "" }
        for key, value in pairs(fields) do
            row[key] = value
        end
        drop_odds.fill(row, fields.odds or row.rate)
        row.odds = nil
        return row
    end

    local function value(drops, live)
        return kill_value.calculate({ { title = "Drops", drops = drops, notes = {}, note_ids = {} } }, live)
    end

    function suite:test_quantity_bounds_cover_ranges_lists_noted_and_thousands()
        lu.assertEquals({ drop_odds.bounds("1") }, { 1, 1 })
        lu.assertEquals({ drop_odds.bounds("2–3 (noted)") }, { 2, 3 })
        lu.assertEquals({ drop_odds.bounds("2,500–3,500") }, { 2500, 3500 })
        lu.assertEquals({ drop_odds.bounds("5; 50") }, { 5, 50 })
        lu.assertEquals({ drop_odds.bounds("8–9; 16–18") }, { 8, 18 })
        lu.assertEquals({ drop_odds.bounds("N/A") }, {})
    end

    function suite:test_the_chance_rolls_and_bounds_are_kept_as_numbers_on_the_drop()
        local row = drop({ quantity = "2–3 (noted)", rate = "3 × 1/1,500", odds = "3 × 0.0667" })
        drop_odds.fill(row, "3 × 0.0667", true)

        lu.assertEquals(row.chance, "0.0667")
        lu.assertEquals(row.rolls, 3)
        lu.assertEquals(row.quantity_low, 2)
        lu.assertEquals(row.quantity_high, 3)

        local plain = drop({ quantity = "1", rate = "Always" })
        lu.assertEquals(plain.chance, "100")
        lu.assertNil(plain.rolls)
        lu.assertNil(plain.quantity_low)

        local noted = drop({ quantity = "8 (noted)", rate = "1/8" })
        lu.assertEquals(noted.quantity_low, 8)
        lu.assertNil(noted.quantity_high)
        lu.assertEquals(noted.chance, "12.5")

        -- words have no number to keep
        for _, word in ipairs({ "Common", "Rare", "Varies", "Random", "Unknown", "" }) do
            lu.assertNil(drop({ rate = word }).chance)
        end
    end

    function suite:test_fixed_quantities_are_price_times_quantity_times_chance()
        local result = value({
            drop({ name = "Bones", quantity = "1", rate = "Always", price = 200 }),
            drop({ name = "Rune bar", quantity = "2", rate = "1/4", price = 8000 }),
        })

        -- 200 + (8000 / 2 each) x 2 x 1/4
        lu.assertAlmostEquals(result.total, 200 + 4000 * 2 * 0.25, 1e-9)
        lu.assertFalse(result.estimate)
        lu.assertEquals(result.counted, 2)
    end

    function suite:test_ranges_use_the_middle_of_the_bounds_and_coins_are_one_gp()
        local result = value({
            drop({ name = "Coins", quantity = "250–500", rate = "1/2", price = { minimum = 1, maximum = 2 } }),
            drop({ name = "Magic logs", quantity = "30–40 (noted)", rate = "1/10", price = { minimum = 30000, maximum = 40000 } }),
        })

        -- coins: 375 x 1/2, logs: 1000 each x 35 x 1/10
        lu.assertAlmostEquals(result.total, 375 * 0.5 + 1000 * 35 * 0.1, 1e-6)
    end

    function suite:test_multiple_rolls_multiply_the_value()
        local once = drop({ name = "Gem", rate = "1/100", price = 10000 })
        local thrice = drop({ name = "Gem", rate = "3 × 1/100", price = 10000 })
        drop_odds.fill(thrice, "3 × 1", true)

        lu.assertEquals(thrice.rolls, 3)
        lu.assertAlmostEquals(value({ thrice }).total, value({ once }).total * 3, 1e-9)
    end

    function suite:test_live_unit_prices_win_and_saved_ones_fill_in()
        local rows_ = {
            drop({ name = "Rune bar", quantity = "2", rate = "Always", price = 8000, item_id = 2363 }),
            drop({ name = "Bones", quantity = "1", rate = "Always", price = 100, item_id = 526 }),
        }
        local result = value(rows_, function(item_id)
            return ({ [2363] = 5000 })[item_id]
        end)

        -- rune bars live at 5000 each, bones keep their saved 100
        lu.assertAlmostEquals(result.total, 5000 * 2 + 100, 1e-9)
    end

    function suite:test_missing_prices_and_unknown_chances_are_left_out_and_make_an_estimate()
        local result = value({
            drop({ name = "Bones", rate = "Always", price = 100 }),
            drop({ name = "Mystery", rate = "1/2" }),
            drop({ name = "Shiny", rate = "Rare", price = 9000000 }),
            drop({ name = "Thing", quantity = "N/A", rate = "1/2", price = 50 }),
        })

        lu.assertEquals(result.total, 100)
        lu.assertTrue(result.estimate)
        lu.assertEquals(result.no_price, 1)
        lu.assertEquals(result.unknown_chance, 1)
        lu.assertEquals(result.unknown_quantity, 1)
    end

    function suite:test_conditional_always_drops_are_left_out_unless_theyre_worthless_anyway()
        local result = value({
            drop({ name = "Binding contract", rate = "Always", price = 34000, note_marker = "1" }),
            drop({ name = "Goblin skull", rate = "Always", price = "Not sold", note_marker = "2" }),
            drop({ name = "Bronze spear", rate = "1/2", price = 100, note_marker = "3" }),
        })

        -- the contract would swamp the total, the skull is 0 either way, the spear has a real
        -- rate so it counts like the wiki counts it
        lu.assertEquals(result.total, 50)
        lu.assertEquals(result.conditional, 1)
        lu.assertEquals(result.untradeable, 1)
        lu.assertTrue(result.estimate)
    end

    function suite:test_nothing_and_untradeables_count_as_zero_without_making_an_estimate()
        local result = value({
            drop({ name = "Nothing", rate = "1/2" }),
            drop({ name = "Gold charm", rate = "1/10", price = "Not sold" }),
        })

        lu.assertEquals(result.total, 0)
        lu.assertFalse(result.estimate)
    end

    function suite:test_only_the_wikis_average_sentences_are_hidden()
        local text = "Two rolls per kill. The average Goblin kill is worth 2,142 coins.\n\n"
            .. "Excluding unique drops, the average kill is worth 21,879.\n\nCharms need members."

        lu.assertEquals(kill_value.without_wiki_averages(text), "Two rolls per kill.\n\nCharms need members.")
        -- untouched when theres nothing to take out, spacing and all
        local plain = "Line one.  Line two.\n\nMore 2.5k text"
        lu.assertEquals(kill_value.without_wiki_averages(plain), plain)
        lu.assertNil(kill_value.without_wiki_averages(nil))
    end

    function suite:test_the_page_parser_keeps_the_wikis_percent_and_rolls()
        local html = '<table class="item-drops"><tr><td data-sort-value="Abyssal whip"></td>'
            .. '<td class="item-col">Abyssal whip</td><td data-sort-value="1">1</td>'
            .. '<td data-sort-value="500"><span data-drop-percent="3 &#215; 0.0667">3 × 1/1,500</span>'
            .. '<span>; </span><span data-drop-percent="0.0674">1/1,484</span></td>'
            .. "<td>2,000,000</td></tr>"
            .. '<tr><td data-sort-value="Coins"></td><td class="item-col">Coins</td>'
            .. "<td>2,500–3,500</td><td>Always</td><td>2,500–3,500</td></tr></table>"
        local sections = assert(parser.parse(html))
        local whip, coins = sections[1].drops[1], sections[1].drops[2]

        lu.assertEquals({ whip.chance, whip.rolls, whip.quantity_low }, { "0.0667", 3, nil })
        lu.assertEquals({ coins.chance, coins.quantity_low, coins.quantity_high }, { "100", 2500, 3500 })
    end

    function suite:test_live_bucket_rows_keep_rarity_rolls_and_bounds_too()
        local sections = assert(dropsline.sections({
            rows.drop("Coins", {
                ["Drop Quantity"] = "250–500",
                ["Quantity Low"] = 250,
                ["Quantity High"] = 500,
                ["Rarity"] = "1/43.34",
                ["Rolls"] = 2,
            }),
        }))
        local coins = sections[1].drops[1]

        lu.assertEquals(coins.chance, string.format("%.6g", 100 / 43.34))
        lu.assertEquals(coins.rolls, 2)
        lu.assertEquals({ coins.quantity_low, coins.quantity_high }, { 250, 500 })
        lu.assertAlmostEquals(value({ coins }).total, 375 / 43.34 * 2, 1e-3)
    end

    return suite
end
