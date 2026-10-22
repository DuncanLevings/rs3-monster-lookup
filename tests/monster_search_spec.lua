local lu = require("luaunit")

return function(root)
    local suite = {}

    function suite:setUp()
        self.bundled = nil
        self.saved_only, self.summary_reads, self.summaries = false, nil, nil
        self.names =
            { "Goblin", "Goblin (Goblin Village)", "Guard (Varrock)", "Abyssal demon", "Duckling" }
        self.cached = { { name = "Goblin", npc_id = 1 } }
        self.updates, self.http_calls = {}, 0
        self:load()
    end

    function suite:load()
        local context = self
        local modules = {
            ["src/data/bundle/reader"] = {
                find = function(monster)
                    return context.bundled and context.bundled[monster.name]
                end,
            },
            ["src/data/monsters/names"] = self.names,
            ["src/data/lookup/cache"] = {
                list = function()
                    return context.cached
                end,
                describe = function(monster)
                    context.summary_reads = (context.summary_reads or 0) + 1
                    return context.summaries and context.summaries[monster.npc_id]
                end,
            },
            ["src/utils/cache_clock"] = { TICKS_PER_SECOND = 50 },
            -- stands in for the bundled drops.lua, see tests/search_index_spec.lua for that
            ["src/data/search/drops"] = {
                items = function()
                    return {
                        { name = "Abyssal whip", count = 2 },
                        { name = "Bones", count = 120 },
                        { name = "Big bones", count = 1 },
                    }
                end,
                droppers = function(position)
                    return ({
                        {
                            { title = "Abyssal demon (elite)", rate = "1/500", quantity = "1" },
                            { title = "Abyssal demon", rate = "1/1,024", quantity = "1" },
                        },
                        {
                            { title = "Goblin", rate = "Always", quantity = "1" },
                            {
                                title = "Kerapac",
                                rate = "Always",
                                quantity = "2",
                                mode = "Hard mode",
                            },
                        },
                    })[position] or {}
                end,
            },
        }
        self.subscribers = {}
        local environment = setmetatable({
            Event = {
                Logic = {
                    Subscribe = function(key, callback)
                        context.subscribers[key] = callback
                    end,
                    Unsubscribe = function(key)
                        context.subscribers[key] = nil
                    end,
                },
            },
            HTTPRequest = {
                new = function()
                    context.http_calls = context.http_calls + 1
                    error("Typing must never create a Wiki request")
                end,
            },
        }, { __index = _G })
        environment.require = function(path)
            if not modules[path] then
                modules[path] = assert(loadfile(root .. "/" .. path .. ".lua", "t", environment))()
            end
            return modules[path]
        end
        self.factory = environment.require("src/data/search/monsters")
        self.search = self.factory.new(function(results, message)
            context.results, context.message = results, message
            context.updates[#context.updates + 1] = { results = results, message = message }
        end, self.saved_only)
        self.search.start()
    end

    function suite:tick(count)
        for _ = 1, count or 1 do
            for _, callback in pairs(self.subscribers) do
                callback()
            end
        end
    end

    function suite:tearDown()
        self.search.stop()
        lu.assertEquals(self.http_calls, 0)
    end

    function suite:items_search()
        local context = self
        local items = self.factory.new(function(results, message)
            context.item_results, context.item_message = results, message
        end, false, "items")
        items.start()
        return items
    end

    function suite:test_item_search_lists_matching_items_with_how_many_monsters_drop_them()
        local items = self:items_search()
        lu.assertStrContains(self.item_message, "dropped items")
        items.set_query("bone")
        self:tick(12)

        lu.assertEquals(self.item_results[1].label, "Bones - 120 monsters")
        lu.assertEquals(self.item_results[2].label, "Big bones - 1 monster")
        lu.assertStrContains(self.item_message, "Select an item")

        -- picking one hands back the name for the field, the search carries on
        lu.assertEquals(items.choose(self.item_results[2]), { item = "Big bones" })
        items.set_query("big bones")
        lu.assertEquals(self.item_message, "No monsters in the saved data drop Big bones.")
        items.stop()
    end

    function suite:test_an_exact_item_name_lists_who_drops_it_straight_away()
        local items = self:items_search()
        items.set_query("BONES")

        lu.assertEquals(self.item_results[1].label, "Goblin - Always")
        lu.assertEquals(self.item_results[2].label, "Kerapac (Hard mode) - Always | x2")
        lu.assertEquals(
            self.item_message,
            "Showing the 2 best chances of the 120 monsters that drop Bones."
        )

        local selection = items.choose(self.item_results[2])
        lu.assertEquals(selection, {
            name = "Kerapac",
            wiki_title = "Kerapac",
            focus = { item = "Bones", mode = "Hard mode" },
        })
        -- the search stops once a monster is picked, like monster search does
        lu.assertNil(items.choose(self.item_results[1]))

        items.start()
        items.set_query("abyssal whip")
        lu.assertEquals(self.item_message, "2 monsters drop Abyssal whip, best chance first.")
        items.stop()
    end

    function suite:test_typing_is_debounced_and_only_the_latest_query_is_published()
        self.search.set_query("gob")
        self:tick(4)
        self.search.set_query("guard")
        self:tick(4)
        lu.assertEquals(self.results, {})
        self:tick(4)
        lu.assertEquals(#self.results, 1)
        lu.assertEquals(self.results[1].monster.wiki_title, "Guard (Varrock)")
    end

    function suite:test_short_queries_do_not_show_unrelated_results()
        self.search.set_query("go")
        self:tick(30)
        lu.assertEquals(self.results, {})
        lu.assertStrContains(self.message, "3 characters")
    end

    function suite:test_cached_npc_does_not_create_a_duplicate_page_choice()
        self.search.set_query("Goblin")
        self:tick(8)
        lu.assertEquals(self.results[1].label, "Goblin")
        lu.assertEquals(
            self.search.choose(self.results[1]),
            { name = "Goblin", wiki_title = "Goblin" }
        )
    end

    function suite:test_same_level_bloodvelds_use_their_page_names_instead_of_cached_npc_labels()
        self.names =
            { "Bloodveld", "Bloodveld (God Wars Dungeon)", "Bloodveld (Heart of Gielinor)" }
        self.cached = {
            { name = "Bloodveld", npc_id = 6215, combat_level = 52 },
            { name = "Bloodveld", npc_id = 1618, combat_level = 52 },
        }
        self:load()
        self.search.set_query("bloodveld")
        self:tick(8)
        lu.assertEquals(#self.results, 3)
        lu.assertEquals(self.results[1].label, "Bloodveld")
        lu.assertEquals(self.results[2].label, "Bloodveld (God Wars Dungeon)")
        lu.assertEquals(self.results[3].label, "Bloodveld (Heart of Gielinor)")
        lu.assertEquals(
            self.search.choose(self.results[1]),
            { name = "Bloodveld", wiki_title = "Bloodveld" }
        )
    end

    function suite:test_location_qualified_selection_retains_its_exact_page_with_cached_npcs_present()
        self.names = { "Bloodveld", "Bloodveld (God Wars Dungeon)" }
        self.cached = { { name = "Bloodveld", npc_id = 6215, combat_level = 52 } }
        self:load()
        self.search.set_query("bloodveld god wars")
        self:tick(8)
        lu.assertEquals(#self.results, 1)
        lu.assertEquals(self.search.choose(self.results[1]), {
            name = "Bloodveld (God Wars Dungeon)",
            wiki_title = "Bloodveld (God Wars Dungeon)",
        })
    end

    function suite:test_fuzzy_and_wildcard_matching_stay_local()
        self.search.set_query("abysal demon")
        self:tick(8)
        lu.assertEquals(self.results[1].monster.name, "Abyssal demon")
        self.search.set_query("abyss* dem?n")
        self:tick(8)
        lu.assertEquals(self.results[1].monster.name, "Abyssal demon")
    end

    function suite:test_stale_buttons_and_repeated_clicks_cannot_select_twice()
        self.search.set_query("goblin")
        self:tick(8)
        local old = self.results[1]
        self.search.set_query("guard")
        lu.assertNil(self.search.choose(old))
        self:tick(8)
        local current = self.results[1]
        lu.assertEquals(self.search.choose(current).wiki_title, "Guard (Varrock)")
        lu.assertNil(self.search.choose(current))
        lu.assertNil(self.on_tick)
    end

    function suite:test_large_indexes_are_processed_in_batches_and_results_are_bounded()
        self.search.stop()
        self.names = {}
        self.cached = {}
        for index = 1, 1200 do
            self.names[index] = "Monster " .. index
        end
        self:load()
        self.search.set_query("Monster 1199")
        self:tick(8)
        lu.assertEquals(self.results, {})
        self:tick(4)
        lu.assertTrue(#self.results <= 50)
        lu.assertEquals(self.results[1].monster.name, "Monster 1199")
    end

    function suite:test_stop_discards_pending_work_and_reopen_refreshes_cached_choices()
        self.search.set_query("guard")
        self.search.stop()
        local count = #self.updates
        self:tick(20)
        lu.assertEquals(#self.updates, count)
        self.cached[#self.cached + 1] = { name = "Guard (Varrock)", wiki_title = "Guard (Varrock)" }
        self.search.start()
        self:tick(8)
        lu.assertEquals(self.search.get_query(), "guard")
        lu.assertEquals(self.results[1].monster.wiki_title, "Guard (Varrock)")
    end

    function suite:test_unmatched_names_only_report_no_matches()
        self.search.set_query("new monster")
        self:tick(8)
        lu.assertEquals(self.results, {})
        lu.assertEquals(self.message, "No monsters match your search.")
    end

    function suite:test_bundled_names_find_uncached_location_variants_without_http()
        self.names = assert(loadfile(root .. "/src/data/monsters/names.lua"))()
        self.cached = {}
        self:load()
        self.search.set_query("bloodveld god wars")
        self:tick(30)
        lu.assertEquals(#self.results, 1)
        local result = self.results[1]
        lu.assertEquals(result.label, "Bloodveld (God Wars Dungeon)")
        lu.assertEquals(self.search.choose(result), {
            name = "Bloodveld (God Wars Dungeon)",
            wiki_title = "Bloodveld (God Wars Dungeon)",
        })
    end

    function suite:test_bundled_index_has_unique_titles_and_known_monsters()
        local titles = assert(loadfile(root .. "/src/data/monsters/names.lua"))()
        local seen = {}
        -- only monsters with drops are listed, see tools/fetch_wiki_data.py
        lu.assertTrue(#titles > 1000)
        local present = {}
        for _, title in ipairs(titles) do
            present[title] = true
        end
        lu.assertNil(present["Avatar of Amascut (2015 Halloween event)"])
        lu.assertNil(present["Soulless unarmoured zombie"])
        lu.assertNil(present["Duckling"])
        lu.assertNil(present["Agoroth"])
        lu.assertTrue(present["Goblin"])
        lu.assertTrue(present["Spiritual mage"])

        for _, title in ipairs(titles) do
            lu.assertFalse(seen[title] == true)
            lu.assertFalse(title:find("[%c:]") ~= nil)
            seen[title] = true
        end

        for _, title in ipairs({
            "General Graardor",
            "Abyssal demon",
            "Guard (Varrock)",
            "Bloodveld (Heart of Gielinor)",
        }) do
            lu.assertTrue(seen[title])
        end
    end

    function suite:test_cached_wiki_pages_keep_saved_ranking_when_already_in_the_name_list()
        self.names = { "Bloodveld", "Bloodveld (God Wars Dungeon)" }
        self.cached = { { name = "Bloodveld", wiki_title = "Bloodveld" } }
        self:load()
        self.search.set_query("bloodveld")
        self:tick(8)
        lu.assertTrue(self.results[1].saved)
        lu.assertEquals(#self.results, 2)
    end

    function suite:test_refresh_search_excludes_cached_monsters_now_in_the_bundle()
        self.saved_only = true
        self.cached = {
            { name = "Goblin", summary = { title = "Goblin" } },
            { name = "New goblin", summary = { title = "New goblin" } },
        }
        self.bundled = { Goblin = { kind = "bundled" } }
        self:load()
        self.search.set_query("goblin")
        self:tick(8)
        lu.assertEquals(#self.results, 1)
        lu.assertEquals(self.results[1].monster.name, "New goblin")
    end

    function suite:test_refresh_search_uses_resolved_page_names_and_original_cache_identity()
        self.saved_only = true
        self.cached = {
            {
                name = "Bloodveld",
                npc_id = 6215,
                summary = { title = "Bloodveld (God Wars Dungeon)", level = 52 },
            },
        }
        self:load()
        self.search.set_query("bloodveld god wars")
        self:tick(8)
        lu.assertEquals(#self.results, 1)
        lu.assertEquals(self.results[1].label, "Bloodveld (God Wars Dungeon)")
        lu.assertEquals(self.search.choose(self.results[1]), { name = "Bloodveld", npc_id = 6215 })
        lu.assertNil(self.summary_reads)
    end

    function suite:test_refresh_search_supports_fuzzy_and_wildcard_queries_but_excludes_unsaved_monsters()
        self.saved_only = true
        self.cached = {
            {
                name = "Bloodveld",
                npc_id = 6215,
                summary = { title = "Bloodveld (God Wars Dungeon)" },
            },
        }
        self:load()
        self.search.set_query("blodveld god wars")
        self:tick(8)
        lu.assertEquals(#self.results, 1)
        self.search.set_query("blood*god w?rs*")
        self:tick(8)
        lu.assertEquals(#self.results, 1)
        self.search.set_query("abyssal")
        self:tick(8)
        lu.assertEquals(#self.results, 0)
    end

    function suite:test_refresh_search_reads_legacy_summaries_in_bounded_batches()
        self.saved_only, self.cached, self.summaries = true, {}, {}
        for index = 1, 8 do
            self.cached[index] = { name = "Guard", npc_id = index }
            self.summaries[index] = { title = "Guard (Varrock)", variant = "Version " .. index }
        end
        self:load()
        self.search.set_query("guard")
        self:tick(8)
        lu.assertEquals(self.summary_reads, 3)
        self:tick(1)
        lu.assertEquals(self.summary_reads, 6)
        self:tick(1)
        lu.assertEquals(self.summary_reads, 8)
        lu.assertEquals(#self.results, 8)
        self.search.set_query("guard")
        self:tick(8)
        lu.assertEquals(self.summary_reads, 8)
        lu.assertEquals(self.results[1].label, "Guard (Varrock) - Version 1")
    end

    function suite:test_independent_search_models_do_not_unsubscribe_each_other()
        local results
        local second = self.factory.new(function(rows)
            results = rows
        end)
        second.start()
        second.set_query("goblin")
        self.search.stop()
        self:tick(8)
        lu.assertEquals(#results, 2)
        second.stop()
        lu.assertNil(next(self.subscribers))
    end

    function suite:test_cached_removed_pages_do_not_reappear_in_normal_search()
        self.cached = {
            {
                name = "Amascut (2015 Halloween event)",
                wiki_title = "Amascut (2015 Halloween event)",
            },
        }
        self:load()
        self.search.set_query("amascut")
        self:tick(8)
        lu.assertEquals(self.results, {})
    end

    function suite:test_empty_refresh_query_does_not_scan_and_clearing_invalidates_old_results()
        self.saved_only = true
        self.cached = { { name = "Goblin", npc_id = 1, summary = { title = "Goblin" } } }
        self:load()
        self:tick(30)
        lu.assertEquals(self.results, {})
        lu.assertNil(self.summary_reads)
        self.search.set_query("gob")
        self:tick(8)
        local old = self.results[1]
        lu.assertNotNil(old)
        self.search.set_query("  ")
        lu.assertEquals(self.results, {})
        lu.assertNil(self.search.choose(old))
        self:tick(30)
        lu.assertEquals(self.results, {})
    end

    function suite:test_first_fifty_ranked_results_are_available_without_network_requests()
        self.search.stop()
        self.names, self.cached = {}, {}
        for index = 120, 1, -1 do
            self.names[#self.names + 1] = ("Monster %03d"):format(index)
        end
        self:load()
        self.search.set_query("Monster")
        self:tick(15)
        lu.assertEquals(#self.results, 50)
        lu.assertEquals(self.results[1].monster.name, "Monster 001")
        lu.assertEquals(self.results[50].monster.name, "Monster 050")
        lu.assertEquals(self.http_calls, 0)
    end

    return suite
end
