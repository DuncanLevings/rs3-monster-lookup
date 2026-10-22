local lu = require("luaunit")

return function(root)
    local suite = {}

    function suite:setUp()
        self.storage = {}
        self.bundle_match = nil
        self.max_value_bytes = nil
        self.now = 100000
        self.elapsed = 0
        self.fail_structured_key = nil
        self.time_checks = 0
        self.requests = {}
        self.results = {}
        self.monster = { npc_id = 1, name = "Goblin" }
        self.result = {
            title = "Goblin",
            info = {},
            locations = {},
            no_locations = "none",
            sections = {
                {
                    title = "Common",
                    drops = { { name = "Coins", quantity = "1", rate = "1/2", price = 1 } },
                },
            },
        }
        self:reload()
    end

    function suite:reload()
        local modules = {}
        local context = self
        local environment = setmetatable({}, { __index = _G })
        -- max_value_bytes copies the clients habit of refusing big values
        environment.PersistentDB = {
            GetStructuredData = function(_, key)
                local value = context.storage[key]
                return type(value) == "table" and value or nil
            end,
            SetStructuredData = function(_, key, value)
                if context.fail_structured_key == key then
                    return false
                end

                context.storage[key] = value
                return true
            end,
            GetString = function(_, key)
                local value = context.storage[key]
                return type(value) == "string" and value or nil
            end,
            SetString = function(_, key, value)
                if context.max_value_bytes and #value > context.max_value_bytes then
                    return false
                end

                context.storage[key] = value
                return true
            end,
            CheckExists = function(_, key)
                return context.storage[key] ~= nil
            end,
            Delete = function(_, key)
                local existed = context.storage[key] ~= nil
                context.storage[key] = nil
                return existed
            end,
        }
        context.logs = {}
        environment.log = function(message)
            context.logs[#context.logs + 1] = message
        end
        modules["src/utils/cache_clock"] = {
            elapsed = function()
                return context.elapsed or 0
            end,
            start = function() end,
            stop = function() end,
            now = function()
                return context.now
            end,
        }
        -- these tests are about the live lookup and its cache, so the bundle knows nothing
        -- unless a test sets context.bundle_match (tests/bundle_spec.lua covers the real one)
        modules["src/data/bundle"] = {
            find = function()
                return context.bundle_match
            end,
            load = function(page)
                return { title = "Bundled " .. page, info = {}, variants = {}, sections = {} },
                    "2026-10-21"
            end,
            placeholder = function(monster, kind)
                return { title = monster.name, sections = {}, no_drops = kind, placeholder = true }
            end,
        }
        modules["src/data/wiki_lookup"] = {
            synchronize_clock = function(complete)
                context.time_checks = (context.time_checks or 0) + 1
                context.now = 100000
                complete(true)
            end,
            cancel = function()
                context.cancelled = (context.cancelled or 0) + 1
            end,
            start = function() end,
            stop = function() end,
            fetch = function(monster, complete)
                context.requests[#context.requests + 1] = { monster = monster, complete = complete }
            end,
        }

        local function load_module(path)
            if not modules[path] then
                modules[path] = assert(loadfile(root .. "/" .. path .. ".lua", "t", environment))()
            end
            return modules[path]
        end

        environment.require = load_module
        self.modules = modules
        self.json = load_module("src/utils/json")
        self.cache = load_module("src/data/monster_cache")
        self.settings = load_module("src/settings")
        self.service = load_module("src/data/lookup_service")
        self.complete = function(result, problem, metadata)
            context.results[#context.results + 1] =
                { result = result, problem = problem, metadata = metadata }
        end
    end

    function suite:test_cache_survives_reload_and_returns_independent_data()
        self.cache.put(self.monster, self.result)
        self:reload()
        self.service.fetch(self.monster, self.complete)

        lu.assertEquals(#self.requests, 0)
        lu.assertFalse(self.results[1].metadata.stale)
        self.results[1].result.sections[1].drops[1].name = "Changed"
        lu.assertEquals(self.cache.get(self.monster, 60).sections[1].drops[1].name, "Coins")
    end

    function suite:test_cached_stat_variants_survive_reload()
        self.result.variants = {
            { version_anchor = "Hard mode", life_points = 450000 },
            { version_anchor = "Normal mode", life_points = 200000 },
        }
        self.cache.put(self.monster, self.result)
        self:reload()
        local saved = self.cache.get(self.monster, 60)

        lu.assertEquals(saved.variants, self.result.variants)
    end

    function suite:test_locations_survive_reload_with_independent_rows()
        self.result.locations = {
            {
                page = "Slayer Tower",
                map_issue = "ambiguous",
                name = "Lumbridge",
                levels = "2",
                requirements = "None",
                spawns = "30",
            },
        }
        self.result.no_locations = nil
        self.cache.put(self.monster, self.result)
        self:reload()
        local saved, metadata = self.cache.get(self.monster, 60)

        lu.assertEquals(saved.locations, self.result.locations)
        lu.assertFalse(metadata.stale)
        saved.locations[1].name = "Changed"
        lu.assertEquals(self.cache.get(self.monster, 60).locations[1].name, "Lumbridge")
    end

    function suite:test_older_lookups_keep_saved_drops_while_fetching_locations()
        self.result.locations = nil
        self.result.no_locations = nil
        self.cache.put(self.monster, self.result)
        self:reload()
        self.service.fetch(self.monster, self.complete)

        lu.assertEquals(self.results[1].result.sections, self.result.sections)
        lu.assertTrue(self.results[1].metadata.refreshing)
        lu.assertEquals(#self.requests, 1)
    end

    function suite:test_invalid_cached_location_records_are_discarded()
        self.result.locations = { { name = "Lumbridge", spawns = {} } }
        self.result.no_locations = nil

        lu.assertNil(self.cache.put(self.monster, self.result))
        lu.assertNil(self.cache.get(self.monster, 60))
    end

    function suite:test_expired_data_is_shown_while_refreshing_and_kept_after_failure()
        self.cache.put(self.monster, self.result)
        self.now = self.now + 14 * 86400
        self.service.fetch(self.monster, self.complete)

        lu.assertEquals(self.results[1].result, self.result)
        lu.assertTrue(self.results[1].metadata.refreshing)
        self.requests[1].complete(nil, "Wiki unavailable")

        lu.assertEquals(self.results[2].result, self.result)
        lu.assertEquals(self.results[2].problem, "Wiki unavailable")
        lu.assertFalse(self.results[2].metadata.refreshing)
        lu.assertTrue(self.results[2].metadata.stale)
        lu.assertNotNil(self.cache.get(self.monster, 60))
    end

    function suite:test_refresh_bypasses_fresh_cache_and_saves_successful_results()
        self.cache.put(self.monster, self.result)
        self.service.fetch(self.monster, self.complete, true)
        self.now = self.now + 10
        self.result.sections[1].drops[1].price = 100
        self.requests[1].complete(self.result)

        lu.assertEquals(#self.requests, 1)
        lu.assertFalse(self.results[1].metadata.stale)
        lu.assertEquals(self.results[1].metadata.saved_at, self.now)
        lu.assertEquals(self.cache.get(self.monster, 60).sections[1].drops[1].price, 100)
    end

    -- monsters missing from the bundle come from bucket rows, opening one again has to use
    -- the saved copy instead of asking the wiki every time
    function suite:test_live_bucket_results_are_saved_and_reopened_without_another_request()
        local rows = require("tests/support/dropsline_rows")
        local sections = assert(require("src/data/dropsline").sections({
            rows.drop("Coins", { ["Quantity Low"] = 5, ["Quantity High"] = 10 }),
            rows.drop("Rune bar", { ["Rarity Notes"] = { { content = "Members only." } } }),
            rows.drop("Uncut ruby", {}, { rare_drop_table = true }),
        }))
        local locations = assert(require("src/data/spawn_locations").parse({
            rows.spawn(28, 0, { 3200, 3210 }, { 3200, 3205 }),
            rows.spawn(15, 0, { 2872 }, { 5358 }),
        }))
        local live = { title = "Goblin", info = {}, sections = sections, locations = locations }

        self.service.fetch(self.monster, self.complete)
        self.requests[1].complete(live)
        self.service.fetch(self.monster, self.complete)

        lu.assertEquals(#self.requests, 1)
        lu.assertEquals(self.results[2].result, live)
        lu.assertFalse(self.results[2].metadata.stale)
        lu.assertNil(self.results[2].metadata.bundled)

        self:reload()
        self.service.fetch(self.monster, self.complete)
        lu.assertEquals(#self.requests, 1)
        lu.assertEquals(self.results[3].result.locations[2].spawn_maps[1].x, 2872)
        lu.assertNil(self.results[3].result.sections[1].drops[2].price)
    end

    function suite:test_cancelled_requests_cannot_replace_data_or_update_the_window()
        self.service.fetch(self.monster, self.complete)
        self.service.cancel()
        self.requests[1].complete(self.result)

        lu.assertEquals(#self.results, 0)
        lu.assertNil(self.cache.get(self.monster, 60))
    end

    function suite:test_removed_interval_setting_is_ignored_without_losing_other_settings()
        self.cache.put(self.monster, self.result)
        self.storage.monster_lookup_settings = {
            version = 1,
            refresh_minutes = 10080,
            percentage_rarity = true,
            menu_colour = "purple",
        }
        self:reload()
        self.now = self.now + 7 * 86400
        self.service.fetch(self.monster, self.complete)
        lu.assertEquals(#self.requests, 0)
        self.now = self.now + 7 * 86400
        self.service.fetch(self.monster, self.complete)

        lu.assertEquals(#self.requests, 1)
        lu.assertTrue(self.settings.get().percentage_rarity)
        lu.assertFalse(self.settings.set("refresh_minutes", -1))
        lu.assertFalse(self.settings.set("refresh_minutes", 0 / 0))
        lu.assertFalse(self.settings.set("percentage_rarity", "true"))
        lu.assertNil(self.settings.get().refresh_minutes)
        lu.assertEquals(self.settings.get().menu_colour, "purple")
        lu.assertFalse(self.settings.set("refresh_minutes", 20160))
    end

    function suite:test_menu_colour_defaults_to_plain_and_only_accepts_listed_colours()
        lu.assertEquals(self.settings.get().menu_colour, "default")
        lu.assertNil(self.settings.menu_colour_hex())
        lu.assertFalse(self.settings.set("menu_colour", "ff0000"))
        lu.assertTrue(self.settings.set("menu_colour", "orange"))
        self:reload()

        lu.assertEquals(self.settings.get().menu_colour, "orange")
        lu.assertEquals(self.settings.menu_colour_hex(), "e6a96b")
    end

    function suite:test_invalid_saved_data_is_ignored_and_missing_clock_never_marks_data_fresh()
        local broken = '{"title":"Goblin","info":{},"sections":[false]}'
        self.storage.monster_lookup_cache_index = {
            version = 2,
            next_slot = 4,
            entries = {
                { key = "1:Goblin", slot = 1, chunks = 1, bytes = 7, order = 1 },
                { key = "1:Goblin", slot = 2, chunks = 1, bytes = #broken, order = 2 },
                { key = "1:Goblin", slot = 3, chunks = 1, bytes = 10, order = 3 },
            },
        }
        self.storage.monster_lookup_cache_1_1 = "invalid"
        self.storage.monster_lookup_cache_2_1 = broken
        -- slot 3 has no chunk saved at all
        self:reload()
        lu.assertNil(self.cache.get(self.monster, 60))
        lu.assertNil(self.storage.monster_lookup_cache_1_1)
        lu.assertNil(self.storage.monster_lookup_cache_2_1)

        self.cache.put(self.monster, self.result)
        self.now = nil
        self:reload()
        local result, metadata = self.cache.get(self.monster, 60)
        lu.assertNotNil(result)
        lu.assertTrue(metadata.stale)
    end

    function suite:test_monsters_without_drops_are_saved_but_unexplained_empty_results_are_not()
        local duckling = { npc_id = 6112, name = "Duckling" }
        self.cache.put(
            duckling,
            { title = "Duckling", info = {}, sections = {}, no_drops = "none" }
        )
        self.cache.put(self.monster, { title = "Goblin", info = {}, sections = {} })
        self:reload()

        lu.assertEquals(self.cache.get(duckling, 60).no_drops, "none")
        lu.assertNil(self.cache.get(self.monster, 60))
    end

    function suite:test_no_stored_value_gets_near_the_client_size_limit()
        self.max_value_bytes = 65536
        self.result.info.examine = string.rep("x", 150000)

        for index = 1, 9 do
            lu.assertNotNil(self.cache.put({ npc_id = index, name = "Goblin" }, self.result))
        end

        self:reload()

        for index = 1, 9 do
            lu.assertNotNil(self.cache.get({ npc_id = index, name = "Goblin" }, 60))
        end

        lu.assertEquals(self.logs, {})
    end

    function suite:test_failed_saves_are_kept_for_the_session_and_only_logged_once()
        self.max_value_bytes = 10

        self.cache.put(self.monster, self.result)
        self.cache.put({ npc_id = 2, name = "Imp" }, self.result)

        lu.assertNotNil(self.cache.get(self.monster, 60))
        lu.assertEquals(#self.logs, 1)
        self:reload()
        lu.assertNil(self.cache.get(self.monster, 60))
    end

    function suite:test_old_single_key_cache_is_removed()
        self.storage.monster_lookup_cache = { version = 1, entries = {} }
        self:reload()

        lu.assertNil(self.cache.get(self.monster, 60))
        lu.assertNil(self.storage.monster_lookup_cache)
    end

    function suite:test_replacing_or_evicting_an_entry_deletes_its_saved_chunks()
        self.cache.put(self.monster, self.result)
        self.cache.put(self.monster, self.result)

        local chunk_keys = {}
        for key in pairs(self.storage) do
            if key:match("^monster_lookup_cache_%d+_%d+$") then
                chunk_keys[#chunk_keys + 1] = key
            end
        end

        lu.assertEquals(#chunk_keys, 1)
    end

    function suite:test_saved_payloads_are_only_decoded_when_opened()
        self.cache.put(self.monster, self.result)
        self.cache.put({ npc_id = 2, name = "Imp" }, self.result)
        self:reload()
        local decoded = 0
        local real_decode = self.json.decode
        self.json.decode = function(...)
            decoded = decoded + 1
            return real_decode(...)
        end

        lu.assertNotNil(self.cache.get(self.monster, 60))
        lu.assertEquals(decoded, 1)
    end

    function suite:test_a_decode_time_limit_keeps_the_saved_entry()
        self.cache.put(self.monster, self.result)
        self:reload()
        local real_decode = self.json.decode
        self.json.decode = function()
            return nil, "time limit", "detail", "execution_limit"
        end

        lu.assertNil(self.cache.get(self.monster, 60))

        self.json.decode = real_decode
        lu.assertNotNil(self.cache.get(self.monster, 60))
    end

    function suite:test_cache_evicts_oldest_entries_and_rejects_oversized_results()
        for index = 1, 1001 do
            self.cache.put({ npc_id = index, name = "Goblin" }, self.result)
        end

        lu.assertNil(self.cache.get(self.monster, 60))
        lu.assertNotNil(self.cache.get({ npc_id = 1001, name = "Goblin" }, 60))
        self.result.info.examine = string.rep("x", 250001)
        self.cache.put(self.monster, self.result)
        lu.assertNil(self.cache.get(self.monster, 60))
    end

    function suite:test_bundled_monsters_need_no_request_and_are_not_cached()
        self.bundle_match = { kind = "bundled", page = 7 }

        self.service.fetch(self.monster, self.complete)
        self.service.fetch(self.monster, self.complete, true)

        lu.assertEquals(#self.requests, 0)
        lu.assertEquals(self.results[1].result.title, "Bundled 7")
        lu.assertEquals(
            self.results[1].metadata,
            { bundled = true, built = "2026-10-21", stale = false }
        )
        lu.assertEquals(self.results[2].result.title, "Bundled 7")
        lu.assertNil(self.cache.get(self.monster, 60))
    end

    function suite:test_known_no_drop_and_not_covered_monsters_get_a_placeholder()
        self.bundle_match = { kind = "not_covered" }
        self.service.fetch({ npc_id = 15824, name = "Bandit" }, self.complete)
        self.bundle_match = { kind = "no_drops" }
        self.service.fetch({ npc_id = 6112, name = "Duckling" }, self.complete)

        lu.assertEquals(#self.requests, 0)
        lu.assertEquals(self.results[1].result.no_drops, "not_covered")
        lu.assertEquals(self.results[2].result.no_drops, "no_drops")
        lu.assertTrue(self.results[2].result.placeholder)
    end

    function suite:test_monsters_the_bundle_doesnt_know_still_use_the_wiki()
        self.service.fetch(self.monster, self.complete)

        lu.assertEquals(#self.requests, 1)
    end

    function suite:test_uncached_failure_does_not_create_an_entry()
        self.service.fetch(self.monster, self.complete)
        self.requests[1].complete(nil, "Permission required")

        lu.assertNil(self.results[1].result)
        lu.assertEquals(self.results[1].problem, "Permission required")
        lu.assertNil(self.cache.get(self.monster, 60))
    end

    function suite:test_clockless_clients_cache_within_the_session_and_revalidate_after_reload()
        self.now = nil
        self.cache.put(self.monster, self.result)
        self.elapsed = 10
        self.service.fetch(self.monster, self.complete)
        lu.assertEquals(#self.requests, 0)

        self.elapsed = 14 * 86400
        self.service.fetch(self.monster, self.complete)
        lu.assertEquals(#self.requests, 1)

        self:reload()
        local _, metadata = self.cache.get(self.monster, 60)
        lu.assertTrue(metadata.stale)
    end

    function suite:test_two_week_expiry_uses_each_entry_age_without_deleting_saved_data()
        self.cache.put(self.monster, self.result)
        self.now = self.now + 13 * 86400
        self.cache.put({ npc_id = 2, name = "Goblin" }, self.result)
        self.now = self.now + 86400 - 1
        local _, metadata = self.cache.get(self.monster, 20160)
        lu.assertFalse(metadata.stale)

        self.now = self.now + 1
        local saved, expired = self.cache.get(self.monster, 20160)
        local _, recent = self.cache.get({ npc_id = 2, name = "Goblin" }, 20160)
        lu.assertEquals(saved, self.result)
        lu.assertTrue(expired.stale)
        lu.assertFalse(recent.stale)
    end

    function suite:test_large_cache_index_is_paged_and_survives_reload()
        for index = 1, 1000 do
            self.cache.put({ npc_id = index, name = "Goblin " .. index }, self.result)
        end

        self:reload()
        local real_decode = self.json.decode
        self.json.decode = function()
            error("Listing the cache must not decode payloads")
        end
        lu.assertEquals(#self.cache.list(), 1000)
        self.json.decode = real_decode
        lu.assertNotNil(self.cache.get({ npc_id = 1, name = "Goblin 1" }, 10080))
        lu.assertNotNil(self.cache.get({ npc_id = 1000, name = "Goblin 1000" }, 10080))

        for key, value in pairs(self.storage) do
            if key:match("^monster_lookup_cache_index_[ab]_%d+$") then
                lu.assertTrue(#self.json.encode(value) < 60000)
            end
        end
    end

    function suite:test_failed_index_commit_preserves_the_previously_saved_payload()
        self.cache.put(self.monster, self.result)
        self.fail_structured_key = "monster_lookup_cache_index"
        local updated = self.json.decode(self.json.encode(self.result))
        updated.sections[1].drops[1].price = 999
        self.cache.put(self.monster, updated)
        lu.assertEquals(self.cache.get(self.monster, 10080).sections[1].drops[1].price, 999)
        self:reload()
        lu.assertEquals(self.cache.get(self.monster, 10080).sections[1].drops[1].price, 1)
    end

    function suite:test_same_name_cache_selections_keep_their_npc_ids()
        self.cache.put({ npc_id = 2, name = "Guard" }, self.result)
        self.cache.put({ npc_id = 1, name = "Guard" }, self.result)
        lu.assertEquals(self.cache.list(), {
            { npc_id = 1, name = "Guard" },
            { npc_id = 2, name = "Guard" },
        })
    end

    function suite:test_repeated_selection_follows_one_request_and_updates_only_the_latest_view()
        self.service.fetch(self.monster, self.complete)
        local latest = {}

        for _ = 1, 20 do
            self.service.fetch(self.monster, function(result)
                latest[#latest + 1] = result
            end, true)
        end

        lu.assertEquals(#self.requests, 1)
        self.requests[1].complete(self.result)
        lu.assertEquals(#self.results, 0)
        lu.assertEquals(latest, { self.result })
    end

    function suite:test_failed_refresh_has_a_cooldown_even_for_manual_requests()
        self.cache.put(self.monster, self.result)
        self.service.fetch(self.monster, self.complete, true)
        self.requests[1].complete(nil, "Wiki unavailable")

        for _ = 1, 10 do
            self.service.fetch(self.monster, self.complete, true)
        end

        lu.assertEquals(#self.requests, 1)
        lu.assertStrContains(self.results[#self.results].problem, "wait a minute")
        self.elapsed, self.now = 60, self.now + 60
        self.service.fetch(self.monster, self.complete, true)
        lu.assertEquals(#self.requests, 1)
        lu.assertStrContains(self.results[#self.results].problem, "59 minutes")
        self.elapsed, self.now = 3600, self.now + 3540
        self.service.fetch(self.monster, self.complete, true)
        lu.assertEquals(#self.requests, 2)
    end

    function suite:test_clockless_reload_checks_time_once_then_reuses_fresh_saved_entries()
        self.cache.put(self.monster, self.result)
        self.cache.put({ npc_id = 2, name = "Guard" }, self.result)
        self:reload()
        self.now = nil
        self.service.fetch(self.monster, self.complete)
        self.service.fetch({ npc_id = 2, name = "Guard" }, self.complete)

        lu.assertEquals(self.time_checks, 1)
        lu.assertEquals(#self.requests, 0)
        lu.assertFalse(self.results[#self.results].metadata.stale)
    end

    function suite:test_old_index_migrates_without_refetching_or_losing_entries()
        local payload = self.json.encode(self.result)
        self.storage.monster_lookup_cache_index = {
            version = 2,
            next_slot = 8,
            entries = {
                {
                    key = "1:Goblin",
                    slot = 7,
                    chunks = 1,
                    bytes = #payload,
                    order = 1,
                    saved_at = self.now,
                },
            },
        }
        self.storage.monster_lookup_cache_7_1 = payload
        self:reload()
        self.service.fetch(self.monster, self.complete)
        lu.assertEquals(#self.requests, 0)
        self.cache.put({ npc_id = 2, name = "Guard" }, self.result)
        self:reload()
        lu.assertEquals(#self.cache.list(), 2)
        lu.assertEquals(self.cache.get(self.monster, 10080), self.result)
    end

    function suite:test_failed_index_page_write_keeps_the_previous_bank_readable()
        self.cache.put(self.monster, self.result)
        self.fail_structured_key = "monster_lookup_cache_index_b_1"
        self.cache.put({ npc_id = 2, name = "Guard" }, self.result)
        self:reload()
        lu.assertEquals(self.cache.list(), { self.monster })
        lu.assertEquals(self.cache.get(self.monster, 10080), self.result)
    end

    function suite:test_time_sync_failure_keeps_saved_data_and_backs_off_across_monsters()
        self.cache.put(self.monster, self.result)
        self.cache.put({ npc_id = 2, name = "Guard" }, self.result)
        self:reload()
        self.now = nil
        local pending
        self.modules["src/data/wiki_lookup"].synchronize_clock = function(complete)
            self.time_checks = self.time_checks + 1
            pending = complete
        end
        self.service.fetch(self.monster, self.complete)
        pending(false, "Wiki unavailable")
        self.service.fetch({ npc_id = 2, name = "Guard" }, self.complete)
        lu.assertEquals(self.time_checks, 1)
        lu.assertEquals(#self.requests, 0)
        lu.assertEquals(self.results[#self.results].result, self.result)
        lu.assertStrContains(self.results[#self.results].problem, "wait a minute")
    end

    function suite:test_page_search_cache_is_persistent_and_separate_from_same_name_npcs()
        local page = { name = "Goblin", wiki_title = "Goblin" }
        self.cache.put(page, self.result)
        local npc_result = self.json.decode(self.json.encode(self.result))
        npc_result.info.life_points = 500
        self.cache.put(self.monster, npc_result)
        self:reload()
        self.service.fetch(page, self.complete)
        lu.assertEquals(#self.requests, 0)
        lu.assertEquals(self.results[1].result.info, {})
        lu.assertEquals(self.cache.get(self.monster, 20160).info.life_points, 500)
        lu.assertEquals(self.cache.list(), { self.monster, page })
    end

    function suite:test_saved_search_summaries_are_indexed_without_decoding_payloads()
        self.result.title = "Bloodveld (God Wars Dungeon)"
        self.result.info = { version_anchor = "Normal", combat_level = 52 }
        self.cache.put({ name = "Bloodveld", npc_id = 6215 }, self.result)
        self:reload()
        local decoded = 0
        local decode = self.json.decode
        self.json.decode = function(...)
            decoded = decoded + 1
            return decode(...)
        end
        local choices = self.cache.list(true)
        lu.assertEquals(
            choices[1].summary,
            { title = "Bloodveld (God Wars Dungeon)", variant = "Normal", level = 52 }
        )
        lu.assertEquals(decoded, 0)
        lu.assertEquals(self.cache.describe(choices[1]), choices[1].summary)
        lu.assertEquals(decoded, 0)
    end

    function suite:test_older_indexes_resolve_display_names_only_when_requested()
        self.cache.put(self.monster, self.result)
        for key, value in pairs(self.storage) do
            if key:match("^monster_lookup_cache_index_[ab]_%d+$") then
                for _, entry in ipairs(value) do
                    entry.summary = nil
                end
            end
        end
        self:reload()
        local decoded = 0
        local decode = self.json.decode
        self.json.decode = function(...)
            decoded = decoded + 1
            return decode(...)
        end
        lu.assertNil(self.cache.list(true)[1].summary)
        lu.assertEquals(decoded, 0)
        lu.assertEquals(self.cache.describe(self.monster).title, "Goblin")
        lu.assertEquals(decoded, 1)
        lu.assertEquals(self.cache.describe(self.monster).title, "Goblin")
        lu.assertEquals(decoded, 1)
    end

    function suite:test_enrage_metadata_survives_cache_roundtrip_and_rejects_invalid_thresholds()
        local section = self.result.sections[1]
        section.drop_mode, section.drop_switch, section.drop_threshold = "100%", 1, 100
        self.cache.put(self.monster, self.result)
        self:reload()
        lu.assertEquals(self.cache.get(self.monster, 20160).sections[1].drop_mode, "100%")
        section.drop_threshold = "bad"
        lu.assertNil(self.cache.put({ name = "Other", npc_id = 2 }, self.result))
    end

    function suite:test_manual_cooldown_survives_success_reload_and_expires_after_an_hour()
        self.cache.put(self.monster, self.result)
        self.service.fetch(self.monster, self.complete, true)
        self.requests[1].complete(self.result)
        self:reload()
        self.now = self.now + 1800
        lu.assertEquals(self.cache.manual_refresh_remaining(self.monster), 1800)
        self.service.fetch(self.monster, self.complete, true)
        lu.assertEquals(#self.requests, 1)
        self.now = self.now + 1800
        self.service.fetch(self.monster, self.complete, true)
        lu.assertEquals(#self.requests, 2)
    end

    function suite:test_cancelled_manual_refresh_erases_payloads_and_keeps_family_cooldown()
        self.cache.put(self.monster, self.result)
        local other = { name = "Guard", npc_id = 2 }
        local other_result = self.json.decode(self.json.encode(self.result))
        other_result.title = "Guard"
        self.cache.put(other, other_result)
        self.service.fetch(self.monster, self.complete, true)
        self.service.cancel()
        self:reload()
        self.service.fetch(self.monster, self.complete, true)
        lu.assertEquals(#self.requests, 1)
        self.service.fetch(other, self.complete, true)
        lu.assertEquals(#self.requests, 2)
        self.service.fetch(self.monster, self.complete)
        lu.assertEquals(#self.requests, 3)
        lu.assertNil(self.cache.get(self.monster, 60))
        self.requests[3].complete(self.result)
        lu.assertNotNil(self.cache.get(self.monster, 60))
    end

    function suite:test_clockless_manual_attempt_is_limited_in_session_and_checks_time_after_reload()
        self.now = nil
        self.cache.put(self.monster, self.result)
        lu.assertEquals(self.cache.begin_manual_refresh(self.monster), 0)
        self.elapsed = 600
        lu.assertEquals(self.cache.begin_manual_refresh(self.monster), 3000)
    end

    function suite:test_info_section_preferences_persist_independently_and_validate_saved_values()
        lu.assertTrue(self.settings.get().slayer_expanded)
        lu.assertFalse(self.settings.get().detailed_stats_expanded)
        self.settings.set("slayer_expanded", false)
        self.settings.set("detailed_stats_expanded", true)
        self.settings.set("menu_colour", "purple")
        self:reload()
        lu.assertFalse(self.settings.get().slayer_expanded)
        lu.assertTrue(self.settings.get().detailed_stats_expanded)
        lu.assertEquals(self.settings.get().menu_colour, "purple")
        lu.assertFalse(self.settings.set("slayer_expanded", "false"))
        self.storage.monster_lookup_settings.slayer_expanded = "broken"
        self:reload()
        lu.assertTrue(self.settings.get().slayer_expanded)
        lu.assertTrue(self.settings.get().detailed_stats_expanded)
    end

    function suite:test_optional_map_metadata_survives_reload_without_changing_legacy_entries()
        self.result.locations = {
            {
                name = "Varrock",
                levels = "10",
                requirements = "None",
                spawns = "3",
                map = { id = 28, plane = 1, x = 3225, z = 3439 },
            },
        }
        self.result.no_locations = nil
        self.cache.put(self.monster, self.result)
        self:reload()
        lu.assertEquals(
            self.cache.get(self.monster, 60).locations[1].map,
            self.result.locations[1].map
        )
        self.result.locations[1].map.plane = 9
        lu.assertNil(self.cache.put(self.monster, self.result))
        lu.assertEquals(self.cache.get(self.monster, 60).locations[1].map.plane, 1)
    end

    function suite:test_manual_refresh_erases_all_matching_variants_and_fetches_only_the_selection()
        local variants = {
            { name = "General Graardor", npc_id = 6260 },
            { name = "General Graardor", npc_id = 6261 },
            { name = "General Graardor (Hard mode)", wiki_title = "General Graardor (Hard mode)" },
        }
        for _, monster in ipairs(variants) do
            local result = self.json.decode(self.json.encode(self.result))
            result.title = monster.wiki_title or monster.name
            self.cache.put(monster, result)
        end
        local unrelated = { name = "General Graardor guard", npc_id = 99 }
        local other_result = self.json.decode(self.json.encode(self.result))
        other_result.title = unrelated.name
        self.cache.put(unrelated, other_result)
        self.service.fetch(variants[1], self.complete, true)
        lu.assertEquals(#self.requests, 1)
        lu.assertEquals(self.requests[1].monster, variants[1])
        lu.assertEquals(#self.results, 0) -- Settings waits for completion, not a cached preview.
        for _, monster in ipairs(variants) do
            lu.assertNil(self.cache.get(monster, 20160))
            lu.assertEquals(self.cache.manual_refresh_remaining(monster), 3600)
        end
        lu.assertNotNil(self.cache.get(unrelated, 20160))
        lu.assertEquals(self.cache.manual_refresh_remaining(unrelated), 0)
        local updated = self.json.decode(self.json.encode(self.result))
        updated.title = "General Graardor"
        self.requests[1].complete(updated)
        self:reload()
        lu.assertNotNil(self.cache.get(variants[1], 20160))
        lu.assertNil(self.cache.get(variants[2], 20160))
        lu.assertNil(self.cache.get(variants[3], 20160))
        lu.assertEquals(#self.cache.list(), 2)
        lu.assertEquals(self.cache.manual_refresh_remaining(variants[3]), 3600)
    end

    function suite:test_family_erasure_deletes_payload_chunks_without_decoding_other_variants()
        self.cache.put(self.monster, self.result)
        local page = { name = "Goblin (Lumbridge)", wiki_title = "Goblin (Lumbridge)" }
        self.cache.put(page, self.result)
        local decoded = 0
        local decode = self.json.decode
        self.json.decode = function(...)
            decoded = decoded + 1
            return decode(...)
        end
        self.cache.begin_manual_refresh(self.monster)
        lu.assertEquals(self.cache.invalidate_family(self.monster), 2)
        lu.assertEquals(decoded, 0)
        for key, value in pairs(self.storage) do
            if key:match("^monster_lookup_cache_%d+_%d+$") then
                lu.fail("Invalidated payload still stored at " .. key .. ": " .. type(value))
            end
        end
        self:reload()
        lu.assertEquals(self.cache.list(), {})
        lu.assertNil(self.cache.get(page, 20160))
        lu.assertEquals(self.cache.manual_refresh_remaining(page), 3600)
    end

    function suite:test_failed_group_refresh_does_not_restore_erased_variants_after_reload()
        self.cache.put(self.monster, self.result)
        local other = { name = "Goblin (Lumbridge)", wiki_title = "Goblin (Lumbridge)" }
        self.cache.put(other, self.result)
        self.service.fetch(self.monster, self.complete, true)
        self.requests[1].complete(nil, "Wiki unavailable")
        lu.assertNil(self.results[#self.results].result)
        self:reload()
        lu.assertNil(self.cache.get(self.monster, 20160))
        lu.assertNil(self.cache.get(other, 20160))
        lu.assertEquals(self.cache.manual_refresh_remaining(other), 3600)
        self.now = nil
        self.service.fetch(other, self.complete, true)
        lu.assertEquals(self.time_checks, 1)
        lu.assertEquals(#self.requests, 1)
    end

    function suite:test_settings_refresh_completion_survives_a_foreground_view_joining_it()
        self.cache.put(self.monster, self.result)
        local settings_messages, window_messages = {}, {}
        self.service.fetch(self.monster, function(result, problem)
            settings_messages[#settings_messages + 1] = { result = result, problem = problem }
        end, true)
        self.service.fetch(self.monster, function(result)
            window_messages[#window_messages + 1] = result
        end)
        self.requests[1].complete(self.result)
        lu.assertEquals(#self.requests, 1)
        lu.assertEquals(settings_messages[1].result, self.result)
        lu.assertEquals(window_messages, { self.result })
    end

    function suite:test_superseding_a_settings_refresh_reports_cancellation_and_ignores_its_result()
        self.cache.put(self.monster, self.result)
        self.service.fetch(self.monster, self.complete, true)
        self.service.fetch({ name = "Guard", npc_id = 2 }, function() end)
        lu.assertEquals(self.results[1].problem, "Refresh cancelled.")
        self.requests[1].complete(self.result)
        lu.assertNil(self.cache.get(self.monster, 20160))
    end

    function suite:test_spawn_maps_survive_cache_roundtrip_and_invalid_arrays_are_rejected()
        self.result.no_locations = nil
        self.result.locations = {
            {
                name = "Polypore Dungeon",
                page = "Polypore Dungeon",
                levels = "105",
                requirements = "None",
                spawns = "44",
                spawn_maps = { { id = 41, plane = 0, x = 3411, z = 9687 } },
            },
        }
        lu.assertNotNil(self.cache.put(self.monster, self.result))
        lu.assertEquals(
            self.cache.get(self.monster, 60).locations[1].spawn_maps,
            self.result.locations[1].spawn_maps
        )
        self.result.locations[1].spawn_maps[2] = { id = 41, plane = 0, x = 1.5, z = 9687 }
        lu.assertNil(self.cache.put(self.monster, self.result))
        self.result.locations[1].spawn_maps = { [2] = { id = 41, plane = 0, x = 3411, z = 9687 } }
        lu.assertNil(self.cache.put(self.monster, self.result))
    end

    return suite
end
