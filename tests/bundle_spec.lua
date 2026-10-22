local lu = require("luaunit")

-- runs against the real src/data/bundle/ files, so a broken build shows up here too
return function(root)
    local suite = {}

    function suite:setUp()
        self.logs = {}
        self.required = {}
        self:load()
    end

    -- fresh copy of src/data/bundle.lua; require goes through so shard loads can be counted
    function suite:load(fake_index)
        local context = self
        local environment = setmetatable({
            log = function(message)
                context.logs[#context.logs + 1] = message
            end,
            require = function(name)
                context.required[#context.required + 1] = name
                if fake_index and name == "src/data/bundle/index" then
                    return fake_index
                end
                return require(name)
            end,
        }, { __index = _G })
        self.bundle = assert(loadfile(root .. "/src/data/bundle.lua", "t", environment))()
    end

    function suite:test_wiki_titles_and_npc_ids_find_the_same_bundled_page()
        local by_title = self.bundle.find({ name = "Goblin", wiki_title = "Goblin" })
        local by_npc = self.bundle.find({ npc_id = 3264, name = "Goblin" })

        lu.assertEquals(by_title.kind, "bundled")
        lu.assertEquals(by_npc, by_title)
    end

    function suite:test_a_bundled_page_unpacks_like_a_live_lookup()
        local match = self.bundle.find({ npc_id = 6260, name = "General Graardor" })
        local result, built = self.bundle.load(match.page)

        lu.assertEquals(result.title, "General Graardor")
        lu.assertEquals(result.source, "bundle")
        lu.assertTrue(type(built) == "string" and built:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil)
        lu.assertIs(result.info, result.variants[1])
        lu.assertTrue(type(result.info.life_points) == "number")
        lu.assertTrue(#result.sections > 10)

        local with_ids, rows = 0, 0
        for _, section in ipairs(result.sections) do
            for _, drop in ipairs(section.drops) do
                rows = rows + 1
                lu.assertTrue(type(drop.name) == "string" and type(drop.rate) == "string")
                lu.assertTrue(type(drop.notes) == "string")
                if drop.item_id then
                    with_ids = with_ids + 1
                end
            end
        end
        lu.assertTrue(with_ids > rows * 0.9)
    end

    function suite:test_opening_one_monster_loads_one_shard()
        local match = self.bundle.find({ name = "Goblin", wiki_title = "Goblin" })
        self.required = {}

        self.bundle.load(match.page)

        local shards = 0
        for _, name in ipairs(self.required) do
            if name:match("^src/data/bundle/shard_") then
                shards = shards + 1
            end
        end
        lu.assertEquals(shards, 1)
    end

    function suite:test_left_out_npcs_are_known_and_unknown_ones_fall_through()
        lu.assertEquals(
            self.bundle.find({ npc_id = 6112, name = "Duckling" }),
            { kind = "no_drops" }
        )
        lu.assertEquals(
            self.bundle.find({ npc_id = 15824, name = "Bandit" }),
            { kind = "not_covered" }
        )
        lu.assertNil(self.bundle.find({ npc_id = 99999999, name = "Not a real monster" }))
        lu.assertNil(self.bundle.find({ name = "Duckling", wiki_title = "Duckling" }))
    end

    function suite:test_placeholders_explain_without_stats()
        local result = self.bundle.placeholder({ name = "Duckling" }, "no_drops")

        lu.assertEquals(result.title, "Duckling")
        lu.assertEquals(result.sections, {})
        lu.assertEquals(result.no_drops, "none")
        lu.assertTrue(result.placeholder)
        lu.assertEquals(
            self.bundle.placeholder({ name = "Bandit" }, "not_covered").no_drops,
            "not_covered"
        )
    end

    function suite:test_a_bundle_from_another_format_is_ignored_and_reported_once()
        self:load({ format = 1, titles = {}, shards = "", npcs = "" })

        lu.assertNil(self.bundle.find({ name = "Goblin", wiki_title = "Goblin" }))
        lu.assertNil(self.bundle.find({ npc_id = 3264, name = "Goblin" }))
        lu.assertEquals(#self.logs, 1)
        lu.assertStrContains(self.logs[1], "Expected format 2")
    end

    function suite:test_search_names_match_the_bundled_titles()
        local names = assert(loadfile(root .. "/src/data/monster_names.lua"))()
        local titles = self.bundle.titles()
        local present = {}
        for _, title in ipairs(titles) do
            present[title] = true
        end

        lu.assertEquals(#names, #titles)
        for _, name in ipairs(names) do
            lu.assertTrue(present[name] == true)
        end
    end

    function suite:test_model_ids_come_from_the_page_index_without_loading_a_shard()
        self.required = {}
        local ids = self.bundle.npc_ids("General Graardor")
        lu.assertTrue(#ids > 0)
        lu.assertTrue(table.concat(ids, ","):find("6260", 1, true) ~= nil)
        lu.assertEquals(self.bundle.npc_ids("Nonexistent monster"), {})
        for _, name in ipairs(self.required) do
            lu.assertNil(name:match("^src/data/bundle/shard_"))
        end
    end

    -- the drop search and top stats indexes that ship with the bundle
    function suite:test_shipped_search_indexes_read_back_with_real_monsters()
        local drops = require("src/data/drop_index")
        local whip

        for position, item in ipairs(drops.items()) do
            if item.name == "Abyssal whip" then
                whip = drops.droppers(position)
            end
        end

        local titles = {}
        for _, dropper in ipairs(assert(whip)) do
            titles[dropper.title] = dropper.rate
        end
        lu.assertNotNil(titles["Abyssal demon"])
        lu.assertTrue(#drops.items() > 2000)

        local stats = require("src/data/stat_rankings")
        local results, total = stats.rank(1, { bosses = "hide", max_combat = 100 })
        lu.assertTrue(total > 1000)
        lu.assertEquals(#results, 50)

        for _, result in ipairs(stats.rank(1, { bosses = "hide" })) do
            lu.assertNotEquals(result.title, "Nex")
            lu.assertNotEquals(result.title, "General Graardor")
        end
    end

    return suite
end
