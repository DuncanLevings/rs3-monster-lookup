local lu = require("luaunit")
local fixture = require("tests/support/wiki_fixture")
local markup = require("tests/support/wiki_markup")
local rows = require("tests/support/dropsline_rows")
local parser = require("tests/support/core_loader").new().load_module("tools/wiki/page")
local drop_groups = { mode_groups = MonsterDataCore.drop_modes }
local text = require("src/utils/wiki_text")
local queries = require("src/data/wiki/queries")
local url = require("src/utils/url")
local policy = require("src/data/wiki/request_policy")

local TEST_PATH = "/api.php?action=query&format=json"

return function(root)
    local suite = {}

    function suite:setUp()
        self.context = fixture.new(root)
        self.results = {}
        self.complete = function(result, problem)
            self.results[#self.results + 1] = { result = result, problem = problem }
        end
    end

    function suite:tearDown()
        self.context.lookup.stop()
    end

    function suite:test_preserves_modes_rates_quantities_and_stack_prices()
        local sections = assert(parser.parse(markup))

        lu.assertEquals(sections[1].title, "Drops (normal mode) / Common")
        lu.assertEquals(sections[2].title, "Drops (hard mode) / Unique")
        lu.assertEquals(sections[1].drops[1].rate, "2/39")
        lu.assertEquals(sections[1].drops[2].quantity, "10–20")
        lu.assertEquals(sections[1].drops[2].price, { minimum = 150000, maximum = 300000 })
        lu.assertEquals(sections[1].drops[1].price, "Not sold")
    end

    function suite:test_resolves_encoded_footnotes_and_keeps_nested_text()
        local sections = assert(parser.parse(markup))
        local section = sections[1]

        lu.assertEquals(section.notes, { "After a relic roll; (1/13) × (2/3) = 2/39." })
        lu.assertEquals(section.drops[1].note_marker, "1")
        lu.assertEquals(section.drops[2].note_marker, "1")
        lu.assertEquals(section.drops[1].notes, section.notes[1])
        lu.assertEquals(sections[2].drops[1].notes, "")
    end

    function suite:test_mod_source_citations_are_omitted_and_gameplay_notes_are_renumbered()
        local html = '<h2>Drops</h2><table class="item-drops"><tr><td data-sort-value="Bones"></td>'
            .. '<td class="item-col">Bones</td><td>1</td><td>1/10'
            .. '<a href="#cite_note-source">[1]</a><a href="#cite_note-task">[2]</a>'
            .. '<a href="#cite_note-region">[3]</a></td><td>100</td></tr></table>'
            .. '<ol><li id="cite_note-source"><span class="reference-text">Mod Sponge. Drop rates. RuneScape Discord.</span></li>'
            .. '<li id="cite_note-task"><span class="reference-text">Requires a Slayer task. Mod Timbo. Drop confirmation.</span></li>'
            .. '<li id="cite_note-region"><span class="reference-text">Only in the Wilderness.</span></li></ol>'
        local section = assert(parser.parse(html))[1]
        lu.assertEquals(section.notes, { "Requires a Slayer task.", "Only in the Wilderness." })
        lu.assertEquals(section.drops[1].note_marker, "1,2")
        lu.assertEquals(
            section.drops[1].notes,
            "Requires a Slayer task.\n\nOnly in the Wilderness."
        )
    end

    function suite:test_keeps_table_conditions_and_under_table_paragraphs()
        local section = parser.parse(markup)[1]

        -- average value lines are kept, the wiki puts them with the other table text
        lu.assertEquals(
            section.description,
            "Two rolls per kill.\n\nThe average Goblin kill is worth 2,142 coins."
                .. "\n\nOnly on a members' world."
        )
        lu.assertStrContains(section.afterword, "Luck boosts can affect these drops.")
    end

    function suite:test_rejects_invalid_or_oversize_pages_and_ignores_unrelated_tables()
        lu.assertNil(parser.parse(nil))
        lu.assertNil(parser.parse(string.rep("a", 2000001)))
        lu.assertEquals(
            parser.parse('<table class="infobox"><tr><td>Other data</td></tr></table>'),
            {}
        )
    end

    function suite:test_decodes_entities_without_allowing_game_formatting_injection()
        lu.assertEquals(text.plain("A &amp; B &#8211; &lt;col=ff0000&gt;"), "A & B – col=ff0000")
        lu.assertEquals(text.plain("<sup>[1]</sup><a>Rune scimitar</a>"), "Rune scimitar")
    end

    function suite:test_modes_are_only_split_out_when_every_table_has_one()
        local function sections(...)
            local list = {}
            for _, title in ipairs({ ... }) do
                list[#list + 1] = { title = title, drops = {} }
            end
            return list
        end

        local groups = assert(
            drop_groups.mode_groups(
                sections(
                    "Drops (normal mode) / 100%",
                    "Drops (hard mode) / 100%",
                    "Drops (hard mode) / Seeds"
                )
            )
        )

        lu.assertEquals(#groups, 2)
        lu.assertEquals(groups[1].name, "Normal mode")
        lu.assertEquals(groups[2].titles, { "100%", "Seeds" })
        lu.assertNil(drop_groups.mode_groups(sections("100%", "Tertiary / Charms")))
        lu.assertNil(drop_groups.mode_groups(sections("Tertiary / Charms", "Tertiary / Clues")))
        lu.assertNil(drop_groups.mode_groups({}))
    end

    local function enrage_switch(labels, quantities)
        local parts =
            { '<div class="switch-infobox loading"><div class="switch-infobox-triggers">' }

        for index, label in ipairs(labels) do
            parts[#parts + 1] = '<span class="trigger button" data-id="'
                .. index
                .. '">'
                .. label
                .. "</span>"
        end

        parts[#parts + 1] = "</div>"

        for index, label in ipairs(labels) do
            parts[#parts + 1] = '<div class="item" data-id="'
                .. index
                .. '"><p>Conditions for '
                .. label
                .. ".</p>"
                .. '<table class="item-drops"><tr><td data-sort-value="Bones"></td><td class="item-col">Bones</td><td>'
                .. quantities[index]
                .. "</td><td>Always</td><td>100</td></tr></table></div>"
        end

        parts[#parts + 1] = "</div>"
        return table.concat(parts)
    end

    function suite:test_enrage_switches_group_tables_and_keep_each_modes_conditions()
        local html = "<h2>Drops</h2><h3>Commons</h3><h4>Potions table</h4>"
            .. enrage_switch({ "Normal mode", "100%", "500%", "2000%+" }, { "3", "4", "5", "9" })
            .. "<h4>Supplies table</h4>"
            .. enrage_switch({ "Normal mode", "100%", "500%", "2000%+" }, { "4", "5", "6", "12" })
        local sections = assert(parser.parse(html))
        local groups = assert(drop_groups.mode_groups(sections))
        lu.assertEquals(#groups, 4)
        lu.assertEquals(groups[1].name, "Normal mode")
        lu.assertEquals(groups[4].name, "2000%+")
        lu.assertEquals(groups[2].titles, { "Commons / Potions table", "Commons / Supplies table" })
        lu.assertEquals(groups[2].sections[1].drops[1].quantity, "4")
        lu.assertEquals(groups[2].sections[2].drops[1].quantity, "5")
        lu.assertEquals(groups[1].sections[1].description, "Conditions for Normal mode.")
        lu.assertNil(groups[1].sections[1].afterword)
        lu.assertEquals(groups[2].sections[1].description, "Conditions for 100%.")
    end

    function suite:test_enrage_thresholds_preserve_shared_tables_and_skip_unavailable_normal_tables()
        local html = "<h2>Drops</h2><h3>Potions</h3>"
            .. enrage_switch({ "Normal mode", "100%", "500%" }, { "3", "4", "5" })
            .. "<h3>Supplies</h3>"
            .. enrage_switch({ "100%", "750%" }, { "10", "20" })
            .. '<h3>Tertiary</h3><table class="item-drops"><tr><td data-sort-value="Pet"></td>'
            .. '<td class="item-col">Pet</td><td>1</td><td>Rare</td><td>Not sold</td></tr></table>'
        local groups = assert(drop_groups.mode_groups(assert(parser.parse(html))))
        lu.assertEquals(#groups, 4)
        lu.assertEquals(groups[1].titles, { "Potions", "Tertiary" })
        lu.assertEquals(groups[3].name, "500%")
        lu.assertEquals(groups[3].titles, { "Potions", "Supplies", "Tertiary" })
        lu.assertEquals(groups[3].sections[2].drops[1].quantity, "10")
        lu.assertEquals(groups[4].sections[1].drops[1].quantity, "5")
        lu.assertEquals(groups[4].sections[2].drops[1].quantity, "20")
    end

    function suite:test_switches_without_enrage_labels_do_not_create_enrage_groups()
        local html = "<h2>Drops</h2><h3>Common</h3>"
            .. enrage_switch({ "Red", "Blue" }, { "1", "2" })
        local sections = assert(parser.parse(html))
        lu.assertEquals(#sections, 2)
        lu.assertNil(sections[1].drop_mode)
        lu.assertNil(drop_groups.mode_groups(sections))
    end

    function suite:test_a_mode_intro_shows_once_not_above_every_category()
        local row = '<tr><td data-sort-value="Bones"></td><td class="item-col">Bones</td>'
            .. "<td>1</td><td>Always</td><td>250</td></tr>"
        local drops = '<table class="item-drops">' .. row .. "</table>"
        local html = "<h3>Drops (normal mode)</h3>"
            .. "<p>Excluding unique drops, the average kill in normal mode is worth 21,879.</p>"
            .. "<p>Killing the three minions yields more loot.</p>"
            .. "<h4>Stone spirits</h4>"
            .. drops
            .. "<h4>Salvage</h4>"
            .. drops

        local sections = assert(parser.parse(html))

        lu.assertEquals(
            sections[1].description,
            "Excluding unique drops, the average kill in normal mode is worth 21,879."
                .. "\n\nKilling the three minions yields more loot."
        )
        lu.assertEquals(sections[2].description, "")
    end

    function suite:test_attribute_matches_whole_names_only()
        local attributes = ' data-id="wrong" id="cite_note-1" data-sort-value="Coins"'

        lu.assertEquals(text.attribute(attributes, "id"), "cite_note-1")
        lu.assertEquals(text.attribute(attributes, "data-sort-value"), "Coins")
        lu.assertEquals(text.attribute(attributes, "sort-value"), "")
    end

    function suite:test_tables_after_many_headings_keep_their_headings()
        local html = string.rep("<h3>Filler</h3><p>x</p>", 200)
            .. "<h2>Drops</h2><h3>Common</h3>"
            .. markup

        local sections = assert(parser.parse(html))

        lu.assertEquals(sections[1].title, parser.parse(markup)[1].title)
    end

    function suite:test_encodes_query_values_and_escapes_bucket_literals()
        lu.assertEquals(url.encode("A & B"), "A%20%26%20B")
        lu.assertStrContains(queries.items({ "Bones", "Gold charm" }), "bucket.Or")
        lu.assertStrContains(queries.monster("page_name", 'X";evil()'), "%5C%22")
    end

    function suite:test_fetches_the_matching_page_then_resolves_item_icons_in_a_batch()
        self.context.lookup.fetch({ npc_id = 4261, name = "Goblin" }, self.complete)
        self.context:tick()
        self.context:respond(
            1,
            { bucket = { { page_name = "Goblin", json = '{"life_points":100}' } } }
        )
        self.context:respond(2, {
            bucket = { rows.drop("Chaos relic (rare)"), rows.drop("Bones") },
        })
        self.context:respond(3, { bucket = {} })
        lu.assertStrContains(self.context.requests[4].path, "Chaos%20relic")
        lu.assertStrContains(self.context.requests[4].path, "Bones")
        self.context:respond(4, { bucket = { { page_name = "Bones", item_id = { 526 } } } })

        lu.assertEquals(#self.results, 1)

        local result = self.results[1].result

        lu.assertEquals(result.title, "Goblin")
        lu.assertEquals(result.info.life_points, 100)
        lu.assertEquals(result.sections[1].drops[2].item_id, 526)
        lu.assertNil(result.sections[1].drops[1].item_id)
        lu.assertEquals(#self.context.requests, 4)
    end

    function suite:test_tries_an_exact_name_when_the_npc_id_is_unknown()
        self.context.lookup.fetch({ npc_id = 999, name = "Goblin" }, self.complete)
        self.context:tick()
        self.context:respond(1, { bucket = {} })

        lu.assertStrContains(self.context.requests[2].path, "page_name")

        self.context:respond(2, { bucket = {} })

        lu.assertStrContains(self.results[1].problem, "No matching monster")
    end

    function suite:test_preserves_stat_variants_returned_for_the_same_npc()
        self.context.lookup.fetch({ npc_id = 28069, name = "Kerapac" }, self.complete)
        self.context:tick()
        self.context:respond(1, {
            bucket = {
                {
                    page_name = "Kerapac",
                    json = '{"version_anchor":"Hard mode","life_points":450000}',
                },
                {
                    page_name = "Kerapac",
                    json = '{"version_anchor":"Normal mode","life_points":200000}',
                },
            },
        })
        self.context:respond(2, { bucket = { rows.drop("Bones") } })
        self.context:respond(3, { bucket = {} })
        self.context:respond(4, { bucket = {} })

        lu.assertEquals(#self.results[1].result.variants, 2)
        lu.assertEquals(self.results[1].result.variants[2].life_points, 200000)
        lu.assertEquals(self.results[1].result.info.version_anchor, "Hard mode")
    end

    function suite:test_does_not_choose_between_different_pages_with_the_same_npc_id()
        self.context.lookup.fetch({ npc_id = 999, name = "Goblin" }, self.complete)
        self.context:tick()
        self.context:respond(1, { bucket = { { page_name = "Goblin" }, { page_name = "Cow" } } })

        lu.assertNil(self.results[1].result)
        lu.assertStrContains(self.results[1].problem, "several matches")
        lu.assertEquals(#self.context.requests, 1)
    end

    -- whoever started a lookup cancels it through its handle, a late response is ignored
    function suite:test_cancelled_lookups_cannot_replace_the_current_monster()
        local old = self.context.lookup.fetch({ npc_id = 1, name = "Old" }, self.complete)
        self.context:tick()
        old.cancel()
        self.context.lookup.fetch({ npc_id = 2, name = "New" }, self.complete)
        self.context:tick()
        self.context:respond(1, { bucket = { { page_name = "Old" } } })

        lu.assertTrue(self.context.requests[1].cancelled)
        lu.assertEquals(#self.context.requests, 2)
        lu.assertEquals(self.results, {})
    end

    -- two lookups started by different callers both keep going, cancelling one leaves the other
    function suite:test_lookups_run_side_by_side_and_cancel_separately()
        local first, second = {}, {}
        local a = self.context.lookup.fetch(
            { name = "First", wiki_title = "First" },
            function(result, problem)
                first[#first + 1] = { result = result, problem = problem }
            end
        )
        self.context:tick()
        self.context.lookup.fetch(
            { name = "Second", wiki_title = "Second" },
            function(result, problem)
                second[#second + 1] = { result = result, problem = problem }
            end
        )
        self.context:tick()

        lu.assertEquals(#self.context.requests, 2)
        lu.assertNil(self.context.requests[1].cancelled)

        a.cancel()
        lu.assertTrue(self.context.requests[1].cancelled)
        lu.assertNil(self.context.requests[2].cancelled)

        self.context:respond(2, { bucket = {} })
        self.context:respond(1, { bucket = {} })
        self.context:tick()

        lu.assertEquals(first, {})
        lu.assertEquals(#second, 1)
    end

    function suite:test_cancel_ignores_late_callbacks_after_shutdown()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context.http.cancel()
        self.context:respond(1, {})

        lu.assertEquals(self.results, {})
    end

    function suite:test_permission_denial_creates_no_request()
        self.context.permitted = false
        self.context.lookup.fetch({ npc_id = 1, name = "Goblin" }, self.complete)
        self.context:tick()

        lu.assertEquals(self.context.requests, {})
        lu.assertStrContains(self.results[1].problem, "permissions")
    end

    function suite:test_http_failures_and_wiki_errors_are_visible()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(1, {}, { successful = false, responseCode = 503 })
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(2, { error = "bad query" })

        lu.assertStrContains(self.results[1].problem, "Could not reach")
        lu.assertStrContains(self.results[2].problem, "could not complete")
    end

    function suite:test_timeout_and_malformed_json_are_visible()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(1, {}, { timedOut = true })
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(2, "not json")
        self.context:tick(policy.DECODE_RETRY_DELAY_TICKS)
        self.context:respond(3, "still not json")

        lu.assertStrContains(self.results[1].problem, "timed out")
        lu.assertStrContains(self.results[2].problem, "unreadable")
        self.context:tick(200)
        lu.assertEquals(#self.context.requests, 3)
        lu.assertEquals(#self.results, 2)
    end

    function suite:test_client_decode_time_limits_are_distinct_and_not_retried()
        self.context.codec.decode = function()
            error("Maximum function execution time of 1000 ms exceeded in Lua")
        end
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(1, "{}")
        self.context:tick(200)

        lu.assertEquals(#self.context.requests, 1)
        lu.assertStrContains(self.results[1].problem, "client exceeded its time limit")
        lu.assertStrContains(table.concat(self.context.logs, "\n"), "decoding time limit exceeded")
    end

    function suite:test_unreadable_api_data_is_retried_once_after_a_delay()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(1, '{"bucket":[')

        lu.assertEquals(#self.results, 0)
        self.context:tick(policy.DECODE_RETRY_DELAY_TICKS - 2)
        lu.assertEquals(#self.context.requests, 1)
        self.context:tick()
        lu.assertEquals(#self.context.requests, 2)
        lu.assertEquals(self.context.requests[2].path, self.context.requests[1].path)
        self.context:respond(2, { bucket = {} })

        lu.assertEquals(#self.results, 1)
        lu.assertEquals(self.results[1].result, { bucket = {} })
        lu.assertStrContains(table.concat(self.context.logs, "\n"), "unreadable Wiki response #1")
        self.context:tick(200)
        lu.assertEquals(#self.context.requests, 2)
    end

    function suite:test_cancelling_a_delayed_retry_prevents_another_request()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(1, "not json")
        self.context.http.cancel()
        self.context:tick(200)

        lu.assertEquals(#self.context.requests, 1)
        lu.assertEquals(#self.results, 0)
    end

    function suite:test_html_with_a_json_content_type_is_rejected_without_retrying()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(1, "<!doctype html><html>Temporary error</html>")
        self.context:tick(200)

        lu.assertEquals(#self.context.requests, 1)
        lu.assertStrContains(self.results[1].problem, "page instead of API data")
    end

    function suite:test_decode_retry_keeps_the_original_request_deadline()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:tick(850)
        self.context:respond(1, "not json")
        self.context:tick(100)
        lu.assertEquals(#self.context.requests, 2)
        self.context:tick(60)

        lu.assertTrue(self.context.requests[2].cancelled)
        lu.assertEquals(#self.results, 1)
        lu.assertStrContains(self.results[1].problem, "timed out")
    end

    function suite:test_missing_response_body_does_not_crash_the_completion_handler()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context.requests[1].callback({ successful = true, responseCode = 200 })
        self.context:tick()

        lu.assertEquals(#self.results, 1)
        lu.assertNotNil(self.results[1].problem)
    end

    function suite:test_missing_footnote_content_stays_visible_as_an_unresolved_condition()
        local sections = assert(parser.parse(markup:gsub("reference%-text", "unavailable")))

        lu.assertEquals(sections[1].drops[1].note_marker, "1")
        lu.assertStrContains(sections[1].notes[1], "could not be read")
    end

    function suite:test_pages_without_drops_still_return_the_monster()
        self.context.lookup.fetch({ npc_id = 1, name = "Duckling" }, self.complete)
        self.context:tick()
        self.context:respond(
            1,
            { bucket = { { page_name = "Duckling", json = '{"life_points":50}' } } }
        )
        self.context:respond(2, { bucket = {} })
        self.context:respond(3, { bucket = {} })

        local result = self.results[1].result
        lu.assertEquals(result.sections, {})
        lu.assertEquals(result.no_drops, "none")
        lu.assertEquals(result.no_locations, "none")
        lu.assertEquals(result.info.life_points, 50)
        lu.assertEquals(#self.context.requests, 3)
    end

    function suite:test_broken_drop_records_are_an_error_not_an_empty_drop_table()
        self.context.lookup.fetch({ npc_id = 1, name = "Goblin" }, self.complete)
        self.context:tick()
        self.context:respond(1, { bucket = { { page_name = "Goblin" } } })
        self.context:respond(2, { bucket = { rows.drop("Bones"), false } })

        lu.assertNil(self.results[1].result)
        lu.assertStrContains(self.results[1].problem, "invalid drop record")
        lu.assertEquals(#self.context.requests, 2)
    end

    function suite:test_cancelling_during_item_resolution_ignores_the_icon_response()
        self.context.lookup.fetch({ npc_id = 1, name = "Goblin" }, self.complete)
        self.context:tick()
        self.context:respond(1, { bucket = { { page_name = "Goblin" } } })
        self.context:respond(2, { bucket = { rows.drop("Bones") } })
        self.context:respond(3, { bucket = {} })

        self.context.lookup.cancel()
        self.context:respond(4, { bucket = {} })

        lu.assertTrue(self.context.requests[4].cancelled)
        lu.assertEquals(self.results, {})
    end

    function suite:test_http_completion_waits_for_the_next_logic_tick()
        self.context.manual_ticks = true
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()

        self.context:respond(1, { bucket = {} })

        lu.assertEquals(self.results, {})

        self.context:tick()

        lu.assertEquals(#self.results, 1)
    end

    function suite:test_followup_requests_are_not_started_inside_an_http_callback()
        self.context.manual_ticks = true
        self.context.lookup.fetch({ npc_id = 1, name = "Goblin" }, self.complete)
        self.context:tick()

        self.context:respond(1, { bucket = { { page_name = "Goblin" } } })

        lu.assertEquals(#self.context.requests, 1)

        self.context:tick()

        lu.assertEquals(#self.context.requests, 1)

        self.context:tick()

        lu.assertEquals(#self.context.requests, 2)
        lu.assertNil(self.context.nested_request)
    end

    function suite:test_cancel_discards_a_response_already_waiting_for_a_logic_tick()
        self.context.manual_ticks = true
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(1, {})

        self.context.http.cancel()
        self.context:tick()

        lu.assertEquals(self.results, {})
    end

    function suite:test_stop_removes_the_tick_handler_and_discards_queued_responses()
        self.context.manual_ticks = true
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(1, {})

        self.context.http.stop()
        self.context:tick()

        lu.assertNil(self.context.on_tick)
        lu.assertEquals(self.results, {})

        self.context.http.start()

        lu.assertNotNil(self.context.on_tick)
    end

    function suite:test_outgoing_requests_wait_for_a_logic_tick()
        self.context.http.get(TEST_PATH, self.complete)

        lu.assertEquals(self.context.requests, {})

        self.context:tick()

        lu.assertEquals(#self.context.requests, 1)
    end

    function suite:test_cancel_discards_requests_not_yet_sent()
        self.context.http.get(TEST_PATH, self.complete)

        self.context.http.cancel()
        self.context:tick()

        lu.assertEquals(self.context.requests, {})
    end

    function suite:test_permission_is_rechecked_before_a_queued_request_is_sent()
        self.context.http.get(TEST_PATH, self.complete)
        self.context.permitted = false

        self.context:tick()

        lu.assertEquals(self.context.requests, {})
        lu.assertStrContains(self.results[1].problem, "permissions")
    end

    function suite:test_only_bounded_api_paths_are_accepted()
        for _, path in ipairs({
            "http://runescape.wiki/api.php?action=query",
            "//other.example/api.php?action=query",
            "/api.php?x=1\r\nInjected: value",
            "/api.php?x=#fragment",
            "/api.php?x=" .. string.rep("x", policy.MAX_PATH_BYTES),
        }) do
            lu.assertFalse(policy.valid_path(path))
        end

        lu.assertTrue(policy.valid_path(TEST_PATH))
        self.context.http.get("https://other.example/api.php?x=1", self.complete)
        self.context:tick()

        lu.assertEquals(self.context.requests, {})
    end

    function suite:test_reported_response_urls_must_keep_the_exact_https_wiki_origin()
        for _, address in ipairs({
            "http://runescape.wiki/api.php?action=query",
            "https://runescape.wiki.other.example/api.php?action=query",
            "https://other.example/api.php?action=query",
        }) do
            self.context.http.get(TEST_PATH, self.complete)
            self.context:tick()
            self.context:respond(#self.context.requests, {}, {
                successful = true,
                responseCode = 200,
                url = address,
            })
        end

        for _, result in ipairs(self.results) do
            lu.assertNil(result.result)
            lu.assertStrContains(result.problem, "unexpected Wiki address")
        end
    end

    function suite:test_html_challenges_and_http_redirect_responses_are_rejected()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(1, "<html>Challenge</html>", {
            successful = true,
            responseCode = 200,
            header = "Content-Type: text/html\r\n",
        })
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(2, {}, { successful = true, responseCode = 302 })

        lu.assertStrContains(self.results[1].problem, "page instead of API data")
        lu.assertStrContains(self.results[2].problem, "redirected")
    end

    function suite:test_rate_limiting_does_not_schedule_an_automatic_retry()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:respond(1, {}, { successful = false, responseCode = 429 })
        self.context:tick()

        lu.assertStrContains(self.results[1].problem, "limiting requests")
        lu.assertEquals(#self.context.requests, 1)
    end

    function suite:test_oversize_progress_cancels_on_the_logic_tick_and_completes_once()
        self.context.complete_on_cancel = true
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()

        self.context:progress(1, policy.MAX_BYTES + 1, 0)
        lu.assertNil(self.context.requests[1].cancelled)

        self.context:tick()
        self.context:tick()

        lu.assertTrue(self.context.requests[1].cancelled)
        lu.assertEquals(#self.results, 1)
        lu.assertStrContains(self.results[1].problem, "too large")
    end

    function suite:test_announced_oversize_response_is_stopped_before_download_finishes()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:progress(1, 10, policy.MAX_BYTES + 1)
        self.context:tick()
        self.context:tick()

        lu.assertTrue(self.context.requests[1].cancelled)
        lu.assertStrContains(self.results[1].problem, "too large")
    end

    function suite:test_stalled_request_has_a_deadline_and_ignores_a_late_response()
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()

        for _ = 1, policy.TIMEOUT_TICKS + 1 do
            self.context:tick()
        end

        lu.assertTrue(self.context.requests[1].cancelled)
        lu.assertEquals(#self.results, 1)
        lu.assertStrContains(self.results[1].problem, "timed out")

        self.context:respond(1, {})

        lu.assertEquals(#self.results, 1)
    end

    function suite:test_native_request_startup_errors_leave_a_visible_failure()
        self.context.fail_start = true
        self.context.http.get(TEST_PATH, self.complete)
        self.context:tick()
        self.context:tick()

        lu.assertTrue(self.context.requests[1].cancelled)
        lu.assertEquals(#self.results, 1)
        lu.assertStrContains(self.results[1].problem, "could not start")
    end

    function suite:test_numeric_entities_decode_without_the_standard_utf8_library()
        local sandbox_text = self.context.text

        lu.assertEquals(sandbox_text.decode("cite&#95;note&#45;1"), "cite_note-1")
        lu.assertEquals(sandbox_text.decode("&#215; &#8211; &#x20AC; &#128578;"), "× – € 🙂")
        lu.assertEquals(
            sandbox_text.decode("&#55296; &#1114112; &unknown;"),
            "&#55296; &#1114112; &unknown;"
        )
    end

    function suite:test_unicode_encoder_handles_boundaries_and_rejects_invalid_codepoints()
        local unicode = self.context.unicode

        lu.assertEquals(unicode.from_codepoint(0x7F), string.char(0x7F))
        lu.assertEquals(unicode.from_codepoint(0x80), string.char(0xC2, 0x80))
        lu.assertEquals(unicode.from_codepoint(0x7FF), string.char(0xDF, 0xBF))
        lu.assertEquals(unicode.from_codepoint(0x800), string.char(0xE0, 0xA0, 0x80))
        lu.assertEquals(unicode.from_codepoint(0xFFFF), string.char(0xEF, 0xBF, 0xBF))
        lu.assertEquals(unicode.from_codepoint(0x10000), string.char(0xF0, 0x90, 0x80, 0x80))
        lu.assertEquals(unicode.from_codepoint(0x10FFFF), string.char(0xF4, 0x8F, 0xBF, 0xBF))
        lu.assertNil(unicode.from_codepoint(-1))
        lu.assertNil(unicode.from_codepoint(1.5))
        lu.assertNil(unicode.from_codepoint(0xD800))
        lu.assertNil(unicode.from_codepoint(0x110000))
        lu.assertNil(unicode.from_codepoint(nil))
    end

    function suite:test_request_pacing_survives_cancellation_and_rapid_new_selections()
        self.context.lookup.stop()
        local paced = fixture.new(root, true)
        paced.http.get(TEST_PATH, function() end)
        paced:tick()
        lu.assertEquals(#paced.requests, 1)

        for _ = 1, 20 do
            paced.http.cancel()
            paced.http.get(TEST_PATH, function() end)
            paced:tick()
        end

        lu.assertEquals(#paced.requests, 1)
        paced:tick(29)
        lu.assertEquals(#paced.requests, 1)
        paced:tick()
        lu.assertEquals(#paced.requests, 2)
        paced.lookup.stop()
    end

    return suite
end
