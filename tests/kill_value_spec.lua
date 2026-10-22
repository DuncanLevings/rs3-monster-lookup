local lu = require("luaunit")
local core = require("src/data/core")
local dropsline = require("src/data/wiki/dropsline")
local rows = require("tests/support/dropsline_rows")
local drop_odds = { fill = core.fill_odds }
local kill_value = { calculate = core.kill_value }
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
        return kill_value.calculate(
            { { title = "Drops", drops = drops, notes = {}, note_ids = {} } },
            live
        )
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
