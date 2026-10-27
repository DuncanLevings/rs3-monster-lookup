local lu = require("luaunit")
local formatting = require("src/ui/drops/formatting")

return function()
    local suite = {}

    function suite:test_converts_fractions_ranges_and_approximate_rates()
        lu.assertEquals(formatting.rarity("1/2", true), "50%")
        lu.assertEquals(formatting.rarity("25/100; 40/100", true), "25%; 40%")
        lu.assertEquals(formatting.rarity("20/100–35/100", true), "20%–35%")
        lu.assertEquals(formatting.rarity("~1/2,819", true), "~0.0355%")
        lu.assertEquals(formatting.rarity("2/39", true), "5.13%")
        lu.assertEquals(formatting.rarity("1/100000", true), "0.001%")
        lu.assertEquals(formatting.rarity("1/1000000000", true), "<0.000001%")
        lu.assertEquals(formatting.rarity("0/100", true), "0%")
        lu.assertEquals(formatting.rarity("1/2, or 1/4", true), "50%, or 25%")
    end

    function suite:test_keeps_descriptions_invalid_rates_and_original_mode()
        for _, rate in ipairs({ "Very rare", "Always", "Unknown", "5%", "1/0", "2/1" }) do
            lu.assertEquals(formatting.rarity(rate, true), rate)
        end
        lu.assertEquals(formatting.rarity("2/39", false), "2/39")
    end

    return suite
end
