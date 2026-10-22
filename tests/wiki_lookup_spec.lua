local lu = require("luaunit")
local fixture = require("tests/support/wiki_fixture")
local rows = require("tests/support/dropsline_rows")

-- request order for a lookup: 1 infobox_monster, 2 dropsline, 3 coordinates, 4+ item ids
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

    local function two_drops()
        return { bucket = { rows.drop("Coins", { ["Drop Quantity"] = "5" }), rows.drop("Bones") } }
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

    function suite:test_unexpected_drop_list_type_completes_with_an_error()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, { bucket = 123 })
        self.context:tick(1100)

        lu.assertEquals(#self.results, 1)
        lu.assertNil(self.results[1].result)
        lu.assertStrContains(self.results[1].problem, "invalid list")
        lu.assertEquals(#self.context.requests, 2)
    end

    function suite:test_unreadable_drop_record_completes_with_an_error()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, { bucket = { { item_name = "Bones", drop_json = "not json" } } })

        lu.assertEquals(#self.results, 1)
        lu.assertNil(self.results[1].result)
        lu.assertStrContains(self.results[1].problem, "could not be read")
    end

    function suite:test_locations_come_from_the_coordinates_bucket()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, two_drops())
        lu.assertStrContains(self.context.requests[3].path, "coordinates")
        self.context:respond(3, {
            bucket = {
                rows.spawn(28, 0, { 3200, 3210 }, { 3200, 3205 }),
                rows.spawn(15, 0, { 2872 }, { 5358 }),
                rows.spawn(-1, 1, { 1010 }, { 5401 }),
            },
        })
        self.context:respond(4, { bucket = {} })

        local result = self.results[1].result
        lu.assertEquals(#result.locations, 2)
        lu.assertEquals(result.locations[1].name, "RuneScape Surface")
        lu.assertEquals(result.locations[1].spawns, "2")
        lu.assertEquals(result.locations[2].name, "God Wars Dungeon")
        lu.assertEquals(result.locations[2].map, { id = 15, plane = 0, x = 2872, z = 5358 })
        lu.assertNil(result.no_locations)
        lu.assertEquals(result.sections[1].drops[2].name, "Bones")
        lu.assertEquals(#self.context.requests, 4)
    end

    function suite:test_locations_are_available_when_the_monster_has_no_drops()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, { bucket = {} })
        self.context:respond(3, { bucket = { rows.spawn(28, 0, { 3200 }, { 3200 }) } })

        lu.assertEquals(self.results[1].result.no_drops, "none")
        lu.assertEquals(#self.results[1].result.locations, 1)
        lu.assertEquals(#self.context.requests, 3)
    end

    function suite:test_a_failed_spawn_request_fails_the_lookup_instead_of_saving_half_of_it()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, two_drops())
        self.context:respond(3, "", { successful = false, responseCode = 503 })
        self.context:tick(1100)

        lu.assertEquals(#self.results, 1)
        lu.assertNil(self.results[1].result)
        lu.assertNotNil(self.results[1].problem)
        lu.assertEquals(#self.context.requests, 3)
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
        self.context:respond(2, two_drops())
        self.context:respond(3, { bucket = {} })
        self.context:respond(4, "", { successful = false, responseCode = 503 })

        lu.assertEquals(#self.results, 1)
        local result = self.results[1].result
        lu.assertNotNil(result)
        lu.assertEquals(result.info.life_points, 100)
        lu.assertEquals(#result.sections[1].drops, 2)
        lu.assertNil(self.results[1].problem)
        lu.assertNil(result.sections[1].drops[1].item_id)
        lu.assertStrContains(table.concat(self.context.logs, "\n"), "some item icons")
    end

    function suite:test_unexpected_item_bucket_type_keeps_usable_result()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, two_drops())
        self.context:respond(3, { bucket = {} })
        self.context:respond(4, { bucket = 123 })

        lu.assertEquals(#self.results, 1)
        lu.assertEquals(#self.results[1].result.sections[1].drops, 2)
        lu.assertNil(self.results[1].problem)
    end

    function suite:test_invalid_item_record_uses_placeholder_instead_of_raising()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, two_drops())
        self.context:respond(3, { bucket = {} })
        self.context:respond(4, { bucket = { false } })

        lu.assertEquals(#self.results, 1)
        lu.assertNotNil(self.results[1].result)
        lu.assertNil(self.results[1].problem)
    end

    function suite:test_non_numeric_item_ids_do_not_reach_the_sprite_api()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, two_drops())
        self.context:respond(3, { bucket = {} })
        self.context:respond(4, { bucket = { { page_name = "Bones", item_id = { {} } } } })

        lu.assertEquals(#self.results, 1)
        lu.assertNotNil(self.results[1].result)
        lu.assertNil(self.results[1].result.sections[1].drops[2].item_id)
    end

    function suite:test_later_icon_batch_failure_keeps_ids_from_earlier_batches()
        local drops = {}

        for index = 1, 45 do
            drops[#drops + 1] = rows.drop("Item " .. index, { ["Rarity"] = "1/2" })
        end

        respond_with_monster(self.context, "{}")
        self.context:respond(2, { bucket = drops })
        self.context:respond(3, { bucket = {} })
        self.context:respond(4, { bucket = { { page_name = "Item 1", item_id = { 526 } } } })
        self.context:respond(5, "", { successful = false, responseCode = 429 })
        self.context:tick(1100)

        lu.assertEquals(#self.results, 1)
        lu.assertEquals(#self.results[1].result.sections[1].drops, 45)
        lu.assertEquals(self.results[1].result.sections[1].drops[1].item_id, 526)
        lu.assertNil(self.results[1].result.sections[1].drops[41].item_id)
        lu.assertEquals(#self.context.requests, 5)
    end

    function suite:test_clock_sync_uses_a_small_query_without_fetching_monster_pages()
        self.context.http.cancel()
        local done, problem
        self.context.lookup.synchronize_clock(function(ok, message)
            done, problem = ok, message
        end)
        self.context:tick()
        local request = self.context.requests[#self.context.requests]
        lu.assertStrContains(request.path, "curtimestamp=1")
        lu.assertStrContains(request.path, "action=query")
        self.context:respond(#self.context.requests, { curtimestamp = "2026-10-21T00:00:00Z" })
        lu.assertTrue(done)
        lu.assertNil(problem)
    end

    function suite:test_selected_wiki_page_is_resolved_directly_without_an_npc_id_lookup()
        self.context.lookup.cancel()
        self.context.lookup.fetch(
            { name = "Guard (Varrock)", wiki_title = "Guard (Varrock)" },
            function(result, problem)
                self.results[#self.results + 1] = { result = result, problem = problem }
            end
        )
        self.context:tick()
        local request = self.context.requests[2]
        lu.assertStrContains(request.path, "page_name")
        lu.assertStrContains(request.path, "Guard%20%28Varrock%29")
        self.context:respond(2, { bucket = {} })
        lu.assertEquals(#self.context.requests, 2)
        lu.assertStrContains(self.results[1].problem, "No matching monster")
    end

    -- the wikis plugin guidance asks for bucket or the api, not whole rendered pages
    function suite:test_every_lookup_request_is_a_bucket_query_for_the_chosen_page()
        respond_with_monster(self.context, "{}")
        self.context:respond(2, two_drops())
        self.context:respond(3, { bucket = {} })

        for _, request in ipairs(self.context.requests) do
            lu.assertStrContains(request.path, "action=bucket")
            lu.assertNotStrContains(request.path, "action=parse")
        end

        lu.assertStrContains(self.context.requests[2].path, "dropsline")
        lu.assertStrContains(self.context.requests[2].path, "%22Goblin%22")
        lu.assertStrContains(self.context.requests[4].path, "infobox_item")
    end

    return suite
end
