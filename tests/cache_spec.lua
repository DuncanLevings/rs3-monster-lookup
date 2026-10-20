local lu = require("luaunit")

return function(root)
    local suite = {}

    function suite:setUp()
        self.storage = {}
        self.max_value_bytes = nil
        self.now = 100000
        self.requests = {}
        self.results = {}
        self.monster = { npc_id = 1, name = "Goblin" }
        self.result = {
            title = "Goblin",
            info = {},
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
        modules["src/data/wiki_lookup"] = {
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

    function suite:test_expired_data_is_shown_while_refreshing_and_kept_after_failure()
        self.cache.put(self.monster, self.result)
        self.now = self.now + 3600
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
        lu.assertFalse(self.results[2].metadata.stale)
        lu.assertEquals(self.results[2].metadata.saved_at, self.now)
        lu.assertEquals(self.cache.get(self.monster, 60).sections[1].drops[1].price, 100)
    end

    function suite:test_cancelled_requests_cannot_replace_data_or_update_the_window()
        self.service.fetch(self.monster, self.complete)
        self.service.cancel()
        self.requests[1].complete(self.result)

        lu.assertEquals(#self.results, 0)
        lu.assertNil(self.cache.get(self.monster, 60))
    end

    function suite:test_configured_interval_controls_expiration_and_settings_survive_reload()
        self.cache.put(self.monster, self.result)
        self.settings.set("refresh_minutes", 15)
        self.settings.set("percentage_rarity", true)
        self:reload()
        self.now = self.now + 900
        self.service.fetch(self.monster, self.complete)

        lu.assertEquals(#self.requests, 1)
        lu.assertTrue(self.settings.get().percentage_rarity)
        lu.assertFalse(self.settings.set("refresh_minutes", -1))
        lu.assertFalse(self.settings.set("refresh_minutes", 0 / 0))
        lu.assertFalse(self.settings.set("percentage_rarity", "true"))
        lu.assertEquals(self.settings.get().refresh_minutes, 15)
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
        self.cache.put(duckling, { title = "Duckling", info = {}, sections = {}, no_drops = "none" })
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
        for index = 1, 51 do
            self.cache.put({ npc_id = index, name = "Goblin" }, self.result)
        end

        lu.assertNil(self.cache.get(self.monster, 60))
        lu.assertNotNil(self.cache.get({ npc_id = 51, name = "Goblin" }, 60))
        self.result.info.examine = string.rep("x", 250001)
        self.cache.put(self.monster, self.result)
        lu.assertNil(self.cache.get(self.monster, 60))
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

        self.elapsed = 3600
        self.service.fetch(self.monster, self.complete)
        lu.assertEquals(#self.requests, 1)

        self:reload()
        local _, metadata = self.cache.get(self.monster, 60)
        lu.assertTrue(metadata.stale)
    end

    return suite
end
