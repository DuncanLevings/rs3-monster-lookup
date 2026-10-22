local lu = require("luaunit")
local rarity_format = require("src/ui/drops/rarity_format")

return function()
    local suite = {}

    function suite:test_converts_fractions_ranges_and_approximate_rates()
        lu.assertEquals(rarity_format.format("1/2", true), "50%")
        lu.assertEquals(rarity_format.format("25/100; 40/100", true), "25%; 40%")
        lu.assertEquals(rarity_format.format("20/100–35/100", true), "20%–35%")
        lu.assertEquals(rarity_format.format("~1/2,819", true), "~0.0355%")
        lu.assertEquals(rarity_format.format("2/39", true), "5.13%")
        lu.assertEquals(rarity_format.format("1/100000", true), "0.001%")
        lu.assertEquals(rarity_format.format("1/1000000000", true), "<0.000001%")
        lu.assertEquals(rarity_format.format("0/100", true), "0%")
        lu.assertEquals(rarity_format.format("1/2, or 1/4", true), "50%, or 25%")
    end

    function suite:test_keeps_descriptions_invalid_rates_and_original_mode()
        for _, rate in ipairs({ "Very rare", "Always", "Unknown", "5%", "1/0", "2/1" }) do
            lu.assertEquals(rarity_format.format(rate, true), rate)
        end
        lu.assertEquals(rarity_format.format("2/39", false), "2/39")
    end

    return suite
end
