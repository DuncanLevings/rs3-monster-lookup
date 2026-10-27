local lu = require("luaunit")
local formatting = require("src/ui/drops/formatting")

return function()
    local suite = {}

    function suite:test_small_prices_keep_thousands_separators()
        lu.assertEquals(formatting.price(15000), "15,000 gp")
        lu.assertEquals(formatting.price(99999), "99,999 gp")
        lu.assertEquals(formatting.price(0), "0 gp")
    end

    function suite:test_large_prices_use_compact_units()
        lu.assertEquals(formatting.price(100000), "100k gp")
        lu.assertEquals(formatting.price(150000), "150k gp")
        lu.assertEquals(formatting.price(150000000), "150m gp")
        lu.assertEquals(formatting.price(2500000000), "2.5b gp")
    end

    function suite:test_compact_prices_round_to_one_decimal()
        lu.assertEquals(formatting.price(150560000), "150.6m gp")
        lu.assertEquals(formatting.price(150040000), "150m gp")
    end

    function suite:test_rounding_promotes_to_the_next_unit()
        lu.assertEquals(formatting.price(999950), "1m gp")
        lu.assertEquals(formatting.price(999950000), "1b gp")
    end

    function suite:test_ranges_format_each_endpoint()
        lu.assertEquals(formatting.price({ minimum = 150000, maximum = 200000 }), "150k-200k gp")
        lu.assertEquals(formatting.price({ minimum = 90000, maximum = 150000 }), "90,000-150k gp")
        lu.assertEquals(formatting.price({ minimum = 40, maximum = 120 }), "40-120 gp")
    end

    function suite:test_equal_range_endpoints_show_a_single_price()
        lu.assertEquals(formatting.price({ minimum = 150000, maximum = 150000 }), "150k gp")
    end

    function suite:test_untradeable_prices_stay_readable()
        lu.assertEquals(formatting.price("Not sold"), "Not sold")
    end

    function suite:test_invalid_prices_do_not_look_like_zero_value()
        lu.assertEquals(formatting.price(nil), "Unknown")
        lu.assertEquals(formatting.price(-1), "Unknown")
        lu.assertEquals(formatting.price(0 / 0), "Unknown")
        lu.assertEquals(formatting.price(math.huge), "Unknown")
        lu.assertEquals(formatting.price({ minimum = 50, maximum = 10 }), "Unknown")
        lu.assertEquals(formatting.price({ minimum = 50 }), "Unknown")
    end

    return suite
end
