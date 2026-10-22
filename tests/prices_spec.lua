local lu = require("luaunit")

-- src/data/drops/prices.lua against a fake GE Price Library, shaped like gepl 0.2.5
return function(root)
    local suite = {}

    function suite:setUp()
        local context = self
        self.ready = true
        self.latest = {}
        self.averages = {}
        self.calls = {}
        self.gepl = {
            isReady = function(endpoint)
                assert(endpoint == "latest")
                return context.ready
            end,
            getLatest = function(id)
                context.calls[#context.calls + 1] = "latest " .. id
                return assert(context.latest[id], "Price not found for itemId: " .. id)
            end,
            getOneHourAverage = function(id)
                context.calls[#context.calls + 1] = "1h " .. id
                return assert(context.averages[id], "Price not found for itemId: " .. id)
            end,
        }
        self:load(self.gepl)
    end

    function suite:load(library)
        local context = self
        self.tick = nil
        local environment = setmetatable({
            gepl = library,
            Event = {
                Logic = {
                    Subscribe = function(_, callback)
                        context.tick = callback
                    end,
                    Unsubscribe = function()
                        context.tick = nil
                    end,
                },
            },
        }, { __index = _G })
        self.prices = assert(loadfile(root .. "/src/data/drops/prices.lua", "t", environment))()
    end

    local function drop(fields)
        local row = { name = "Item", rate = "1/128", notes = "", note_marker = "" }
        for key, value in pairs(fields) do
            row[key] = value
        end
        return row
    end

    function suite:test_unit_price_is_the_middle_of_the_hourly_average_or_latest_trade()
        self.averages[4151] = { avgHighPrice = 1100, avgLowPrice = 1000 }
        self.latest[1513] = { high = 501, low = 498 }

        lu.assertEquals(self.prices.unit(4151), 1050)
        lu.assertEquals(self.prices.unit(1513), 500)
    end

    function suite:test_one_sided_or_empty_trades_still_give_a_price_when_they_can()
        self.averages[1] = { avgHighPrice = 900 }
        self.averages[2] = {}
        self.latest[2] = { low = 40 }
        self.latest[3] = {}

        lu.assertEquals(self.prices.unit(1), 900)
        lu.assertEquals(self.prices.unit(2), 40)
        lu.assertNil(self.prices.unit(3))
    end

    -- large spiky rune salvage: worth ~30k, one instant buy at 2m made the mid 1m
    function suite:test_a_one_off_trade_is_ignored_when_theres_a_saved_price_to_compare()
        self.latest[47292] = { high = 2000000, low = 29800 }

        lu.assertEquals(self.prices.unit(47292, 29882), 29800)
        lu.assertEquals(
            self.prices.for_drop(drop({
                item_id = 47292,
                quantity = "1–2",
                price = { minimum = 29882, maximum = 59764 },
            })),
            { minimum = 29800, maximum = 59600 }
        )
    end

    function suite:test_live_prices_too_far_from_the_saved_one_are_not_trusted()
        self.latest[1] = { high = 900000, low = 800000 }
        self.latest[2] = { high = 70000, low = 60000 }

        -- every live price over 3x the saved 30k, the saved price stays
        lu.assertNil(self.prices.unit(1, 30000))
        lu.assertNil(self.prices.for_drop(drop({ item_id = 1, quantity = "1", price = 30000 })))
        -- a real rise to about double still comes through
        lu.assertEquals(self.prices.unit(2, 30000), 60000)
    end

    function suite:test_without_a_saved_price_a_lopsided_buy_falls_back_to_the_sell()
        self.latest[3] = { high = 2000000, low = 29800 }
        self.latest[4] = { high = 110, low = 90 }

        lu.assertEquals(self.prices.unit(3), 29800)
        lu.assertEquals(self.prices.unit(4), 100)
    end

    function suite:test_drop_prices_scale_with_the_quantity()
        self.latest[1513] = { high = 600, low = 400 }

        lu.assertEquals(
            self.prices.for_drop(drop({ item_id = 1513, quantity = "30–40 (noted)" })),
            {
                minimum = 15000,
                maximum = 20000,
            }
        )
        lu.assertEquals(self.prices.for_drop(drop({ item_id = 1513, quantity = "1,000" })), 500000)
        lu.assertEquals(self.prices.for_drop(drop({ item_id = 1513, quantity = "3" })), 1500)
    end

    function suite:test_bundled_price_stays_when_live_price_cant_be_worked_out()
        self.latest[1513] = { high = 600, low = 400 }

        -- untradeable items make gepl throw, unparseable quantities and no item id too
        lu.assertNil(self.prices.for_drop(drop({ item_id = 995, quantity = "100" })))
        lu.assertNil(self.prices.for_drop(drop({ item_id = 1513, quantity = "Varies" })))
        lu.assertNil(self.prices.for_drop(drop({ quantity = "1" })))
        lu.assertNil(
            self.prices.for_drop(drop({ item_id = 1513, quantity = "1", price = "Not sold" }))
        )
    end

    function suite:test_without_the_library_nothing_is_live()
        self:load(nil)

        lu.assertFalse(self.prices.live())
        lu.assertNil(self.prices.unit(1513))
        lu.assertFalse(self.prices.when_live("window", function() end))
    end

    function suite:test_waits_for_prices_once_and_the_latest_callback_wins()
        self.ready = false
        local calls = {}

        lu.assertTrue(self.prices.when_live("window", function()
            calls[#calls + 1] = "first"
        end))
        lu.assertTrue(self.prices.when_live("window", function()
            calls[#calls + 1] = "second"
        end))
        for _ = 1, 50 do
            self.tick()
        end
        lu.assertEquals(calls, {})

        self.ready = true
        for _ = 1, 50 do
            self.tick()
        end

        lu.assertEquals(calls, { "second" })
        lu.assertNil(self.tick)
        lu.assertFalse(self.prices.when_live("window", function() end))
    end

    function suite:test_gives_up_waiting_after_about_two_minutes()
        self.ready = false
        self.prices.when_live("window", function() end)

        for _ = 1, 50 * 120 do
            if not self.tick then
                break
            end
            self.tick()
        end

        lu.assertNil(self.tick)
    end

    return suite
end
