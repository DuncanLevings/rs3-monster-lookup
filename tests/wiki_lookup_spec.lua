local lu = require("luaunit")
local fixture = require("tests/support/wiki_fixture")
local markup = require("tests/support/wiki_markup")

return function(root)
    local suite = {}

    function suite:setUp()
        self.context = fixture.new(root)
        self.results = {}
        self.context.lookup.fetch({ npc_id = 1, name = "Goblin" }, function(result, problem)
            self.results[#self.results + 1] = { result = result, problem = problem }
        end)
        self.context:tick()
    end

    function suite:tearDown()
        self.context.lookup.stop()
    end

    local function respond_with_monster(context, info)
        context:respond(1, { bucket = { { page_name = "Goblin", json = info } } })
    end

    function suite:test_malformed_monster_lists_fail_once_without_name_fallback()
        self.context:respond(1, { bucket = 123 })
        self.context:tick(1100)

        lu.assertEquals(#self.results, 1)
        lu.assertNil(self.results[1].result)
        lu.assertStrContains(self.results[1].problem, "invalid list")
        lu.assertEquals(#self.context.requests, 1)
    end

    function suite:test_object_shaped_bucket_is_not_treated_as_an_empty_result()
        self.context:respond(1, { bucket = { unexpected = true } })

        lu.assertEquals(#self.results, 1)
        lu.assertStrContains(self.results[1].problem, "invalid list")
        lu.assertEquals(#self.context.requests, 1)
    end

    function suite:test_invalid_record_is_reported_instead_of_treated_as_ambiguity()
        self.context:respond(1, { bucket = { { page_name = "Goblin" }, false } })

        lu.assertEquals(#self.results, 1)
        lu.assertStrContains(self.results[1].problem, "invalid monster record")
    end

    function suite:test_unexpected_page_type_completes_with_an_error()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, { parse = 123 })
        self.context:tick(1100)

        lu.assertEquals(#self.results, 1)
        lu.assertNil(self.results[1].result)
        lu.assertStrContains(self.results[1].problem, "invalid monster page")
    end

    function suite:test_unexpected_page_text_type_completes_with_an_error()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, { parse = { text = false } })

        lu.assertEquals(#self.results, 1)
        lu.assertStrContains(self.results[1].problem, "invalid monster page")
    end

    function suite:test_broken_infobox_json_is_not_successful_empty_stats()
        respond_with_monster(self.context, "broken JSON")

        lu.assertEquals(#self.results, 1)
        lu.assertNil(self.results[1].result)
        lu.assertStrContains(self.results[1].problem, "monster stats could not be read")
        lu.assertEquals(#self.context.requests, 1)
    end

    function suite:test_wrong_infobox_type_is_rejected()
        respond_with_monster(self.context, 42)

        lu.assertEquals(#self.results, 1)
        lu.assertNil(self.results[1].result)
        lu.assertStrContains(self.results[1].problem, "monster stats could not be read")
    end

    function suite:test_invalid_later_variant_does_not_return_partial_stats()
        self.context:respond(1, {
            bucket = {
                { page_name = "Goblin", json = '{"life_points":100}' },
                { page_name = "Goblin", json = "[1,2]" },
            },
        })

        lu.assertEquals(#self.results, 1)
        lu.assertNil(self.results[1].result)
        lu.assertStrContains(self.results[1].problem, "invalid monster stats record")
    end

    function suite:test_failed_icon_request_keeps_parsed_drops_and_stats()
        respond_with_monster(self.context, '{"life_points":100}')
        self.context:respond(2, { parse = { text = markup } })
        self.context:respond(3, "", { successful = false, responseCode = 503 })

        lu.assertEquals(#self.results, 1)
        local result = self.results[1].result
        lu.assertNotNil(result)
        lu.assertEquals(result.info.life_points, 100)
        lu.assertEquals(#result.sections, 2)
        lu.assertNil(self.results[1].problem)
        lu.assertNil(result.sections[1].drops[1].item_id)
        lu.assertStrContains(table.concat(self.context.logs, "\n"), "some item icons")
    end

    function suite:test_unexpected_item_bucket_type_keeps_usable_result()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, { parse = { text = markup } })
        self.context:respond(3, { bucket = 123 })

        lu.assertEquals(#self.results, 1)
        lu.assertEquals(#self.results[1].result.sections, 2)
        lu.assertNil(self.results[1].problem)
    end

    function suite:test_invalid_item_record_uses_placeholder_instead_of_raising()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, { parse = { text = markup } })
        self.context:respond(3, { bucket = { false } })

        lu.assertEquals(#self.results, 1)
        lu.assertNotNil(self.results[1].result)
        lu.assertNil(self.results[1].problem)
    end

    function suite:test_non_numeric_item_ids_do_not_reach_the_sprite_api()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, { parse = { text = markup } })
        self.context:respond(3, { bucket = { { page_name = "Bones", item_id = { {} } } } })

        lu.assertEquals(#self.results, 1)
        lu.assertNotNil(self.results[1].result)
        lu.assertNil(self.results[1].result.sections[1].drops[2].item_id)
    end

    function suite:test_later_icon_batch_failure_keeps_ids_from_earlier_batches()
        local rows = {}

        for index = 1, 45 do
            local name = "Item " .. index
            rows[#rows + 1] = '<tr><td data-sort-value="'
                .. name
                .. '"></td>'
                .. '<td class="item-col">'
                .. name
                .. "</td>"
                .. "<td>1</td><td>1/2</td><td>100</td></tr>"
        end

        respond_with_monster(self.context, "{}")
        self.context:respond(2, {
            parse = {
                text = '<table class="item-drops">' .. table.concat(rows) .. "</table>",
            },
        })
        self.context:respond(3, { bucket = { { page_name = "Item 1", item_id = { 526 } } } })
        self.context:respond(4, "", { successful = false, responseCode = 429 })
        self.context:tick(1100)

        lu.assertEquals(#self.results, 1)
        lu.assertEquals(#self.results[1].result.sections[1].drops, 45)
        lu.assertEquals(self.results[1].result.sections[1].drops[1].item_id, 526)
        lu.assertNil(self.results[1].result.sections[1].drops[41].item_id)
        lu.assertEquals(#self.context.requests, 4)
    end

    return suite
end
