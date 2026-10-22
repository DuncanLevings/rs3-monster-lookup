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
        lu.assertStrContains(self.logs[1], "Expected format 4")
    end

    function suite:test_search_names_match_the_bundled_titles()
        local names = assert(loadfile(root .. "/src/data/monsters/names.lua"))()
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

    -- drop rows leave out what can be worked out, see shapes.DERIVED
    function suite:test_left_out_drop_fields_are_worked_out_like_the_wiki_writes_them()
        local shapes = require("src/data/bundle_shapes")
        local derive = shapes.derive
        local item = { id = 4151, unit = 30 }

        lu.assertEquals(derive.item_id({}, item), 4151)
        lu.assertEquals(derive.price({ quantity = "3" }, item), 90)
        lu.assertEquals(derive.price({ quantity = "2–4 (noted)" }, item), { minimum = 60, maximum = 120 })
        lu.assertEquals(derive.price({ quantity = "1" }, { unit = "Not sold" }), "Not sold")
        lu.assertNil(derive.price({ quantity = "Unknown" }, item))

        -- 3 significant figures, halves round up like the wiki (3.125 -> 3.13)
        lu.assertEquals(derive.chance({ rate = "4/128" }), "3.13")
        lu.assertEquals(derive.chance({ rate = "1/66.7" }), "1.5")
        lu.assertEquals(derive.chance({ rate = "3 × 1/1,500" }), "0.0667")
        lu.assertEquals(derive.chance({ rate = "Always" }), "100")
        lu.assertNil(derive.chance({ rate = "Common" }))
        lu.assertEquals(derive.rolls({ rate = "3 × 1/1,500", chance = "0.0667" }), 3)
        lu.assertNil(derive.rolls({ rate = "3 × Rare" }))

        lu.assertNil(derive.quantity_low({ quantity = "5" }))
        lu.assertEquals(derive.quantity_low({ quantity = "1,000" }), 1000)
        lu.assertEquals(derive.quantity_high({ quantity = "8–9; 16–18" }), 18)
    end

    function suite:test_items_table_reads_ids_units_and_not_sold()
        local shapes = require("src/data/bundle_shapes")
        local strings = { "Abyssal whip", "Bones", "Clue scroll" }

        -- unit x is 33 gp, - is Not sold
        local items = shapes.read_items("0:37b:x,1::-,2:a:", strings)

        lu.assertEquals(items["Abyssal whip"], { id = 4151, unit = 33 })
        lu.assertEquals(items.Bones, { unit = "Not sold" })
        lu.assertEquals(items["Clue scroll"], { id = 10 })
    end

    -- the drop search and top stats indexes that ship with the bundle
    function suite:test_shipped_search_indexes_read_back_with_real_monsters()
        local drops = require("src/data/search/drops")
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

        local stats = require("src/data/search/stats")
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
