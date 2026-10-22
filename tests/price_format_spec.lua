local lu = require("luaunit")
local price_format = require("src/ui/drops/price_format")

return function()
    local suite = {}

    function suite:test_small_prices_keep_thousands_separators()
        lu.assertEquals(price_format.format(15000), "15,000 gp")
        lu.assertEquals(price_format.format(99999), "99,999 gp")
        lu.assertEquals(price_format.format(0), "0 gp")
    end

    function suite:test_large_prices_use_compact_units()
        lu.assertEquals(price_format.format(100000), "100k gp")
        lu.assertEquals(price_format.format(150000), "150k gp")
        lu.assertEquals(price_format.format(150000000), "150m gp")
        lu.assertEquals(price_format.format(2500000000), "2.5b gp")
    end

    function suite:test_compact_prices_round_to_one_decimal()
        lu.assertEquals(price_format.format(150560000), "150.6m gp")
        lu.assertEquals(price_format.format(150040000), "150m gp")
    end

    function suite:test_rounding_promotes_to_the_next_unit()
        lu.assertEquals(price_format.format(999950), "1m gp")
        lu.assertEquals(price_format.format(999950000), "1b gp")
    end

    function suite:test_ranges_format_each_endpoint()
        lu.assertEquals(price_format.format({ minimum = 150000, maximum = 200000 }), "150k-200k gp")
        lu.assertEquals(
            price_format.format({ minimum = 90000, maximum = 150000 }),
            "90,000-150k gp"
        )
        lu.assertEquals(price_format.format({ minimum = 40, maximum = 120 }), "40-120 gp")
    end

    function suite:test_equal_range_endpoints_show_a_single_price()
        lu.assertEquals(price_format.format({ minimum = 150000, maximum = 150000 }), "150k gp")
    end

    function suite:test_untradeable_prices_stay_readable()
        lu.assertEquals(price_format.format("Not sold"), "Not sold")
    end

    function suite:test_invalid_prices_do_not_look_like_zero_value()
        lu.assertEquals(price_format.format(nil), "Unknown")
        lu.assertEquals(price_format.format(-1), "Unknown")
        lu.assertEquals(price_format.format(0 / 0), "Unknown")
        lu.assertEquals(price_format.format(math.huge), "Unknown")
        lu.assertEquals(price_format.format({ minimum = 50, maximum = 10 }), "Unknown")
        lu.assertEquals(price_format.format({ minimum = 50 }), "Unknown")
    end

    return suite
end
