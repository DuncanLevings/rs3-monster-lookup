local lu = require("luaunit")
local search_index = require("tools/search_index")

-- tools/search_index.lua builds drops.lua and stats.lua, src/data/drop_index.lua and
-- src/data/stat_rankings.lua read them back. these run both ends on a few made up pages
return function(root)
    local suite = {}

    local function drop(name, rate, quantity, item_id)
        return { name = name, rate = rate, quantity = quantity or "1", item_id = item_id }
    end

    local PAGES = {
        {
            title = "General Graardor",
            sections = {
                {
                    title = "Drops (normal mode) / Unique",
                    drops = { drop("Bandos chestplate", "1/384; 1/378", "1", 11724) },
                },
                {
                    title = "Drops (hard mode) / Unique",
                    drops = { drop("Bandos chestplate", "1/256") },
                },
            },
            variants = {
                { version_anchor = "Normal mode", combat_level = 624, life_points = 255000,
                  combat_experience = 2125.5, slayer_level = 1, melee_max_hit = 3000 },
                { version_anchor = "Hard mode", combat_level = 0, life_points = 500000,
                  combat_experience = 4000, special_max_hit = 9000 },
            },
        },
        {
            title = "Sergeant Steelwill",
            sections = {
                {
                    title = "Drops",
                    drops = {
                        drop("Bandos chestplate", "1/49,152"),
                        drop("Bones", "Always"),
                        drop("Nothing", "1/2"),
                        drop("Coins", "1/8", "5–10"),
                    },
                },
            },
            variants = {
                { combat_level = 96, life_points = 9000, combat_experience = 600,
                  slayer_category = { "goblins" }, slayer_level = 50, slayer_experience = 700 },
            },
        },
        {
            title = "Goblin",
            sections = {
                {
                    title = "Drops",
                    drops = {
                        drop("Bronze spear (m)", "4/128"),
                        drop("Bones", "Always", "1", 526),
                        drop("Coins", "3/128", "5–10"),
                        drop("Coins", "28/128", "5"),
                    },
                },
            },
            variants = {
                { combat_level = 2, life_points = 50, combat_experience = 5,
                  slayer_category = { "goblins" } },
            },
        },
    }

    -- "Bronze spear" on its own isnt in here, so its name has to be written out in full
    local STRINGS = {
        "1/384; 1/378", "1/256", "1/49,152", "Always", "1/2", "1/8", "5–10", "4/128",
        "3/128", "28/128", "5", "Bandos chestplate", "Bones", "Coins", "Normal mode",
        "Hard mode", "goblins",
    }

    function suite:setUp()
        local string_index = {}
        for position, text in ipairs(STRINGS) do
            string_index[text] = position - 1
        end

        local drops_source = search_index.drops(PAGES, "-- test\n", string_index)
        -- graardor is caught by its "Normal mode"/"Hard mode" variants, steelwill by category
        local stats_source = search_index.stats(PAGES, "-- test\n", string_index, {
            ["Sergeant Steelwill"] = true,
        })
        local titles = {}
        for index, page in ipairs(PAGES) do
            titles[index] = page.title
        end

        self.bundle = {
            titles = function()
                return titles
            end,
        }
        self:readers(assert(load(drops_source))(), assert(load(stats_source))())
    end

    -- fresh drop_index and stat_rankings reading these two files
    function suite:readers(drops_file, stats_file)
        self.logs = {}
        local context = self
        local modules = {
            ["src/data/bundle"] = self.bundle,
            ["src/data/bundle/strings"] = STRINGS,
            ["src/data/bundle/drops"] = drops_file,
            ["src/data/bundle/stats"] = stats_file,
        }
        local environment = setmetatable({
            log = function(message)
                context.logs[#context.logs + 1] = message
            end,
        }, { __index = _G })
        environment.require = function(path)
            if modules[path] == nil then
                modules[path] = assert(loadfile(root .. "/" .. path .. ".lua", "t", environment))()
            end
            return modules[path]
        end
        self.drops = environment.require("src/data/drop_index")
        self.stats = environment.require("src/data/stat_rankings")
    end

    local function item(drops, name)
        for position, entry in ipairs(drops.items()) do
            if entry.name == name then
                return position, entry
            end
        end
        error("missing item " .. name)
    end

    function suite:test_rates_turn_into_chances_for_sorting()
        lu.assertAlmostEquals(search_index.chance("1/128"), 1 / 128, 1e-12)
        lu.assertAlmostEquals(search_index.chance("86/1,000"), 0.086, 1e-12)
        lu.assertAlmostEquals(search_index.chance("1/384; 1/378"), 1 / 384, 1e-12)
        lu.assertAlmostEquals(search_index.chance("3 × 1/500; 1/485"), 1 / 500, 1e-12)
        lu.assertAlmostEquals(search_index.chance("5%"), 0.05, 1e-12)
        lu.assertEquals(search_index.chance("Always"), 1)
        lu.assertEquals(search_index.chance("Very rare"), 1 / 512)
        lu.assertEquals(search_index.chance("Varies"), 0)
        lu.assertEquals(search_index.chance("2/1"), 1)
    end

    function suite:test_items_are_sorted_merge_members_marks_and_skip_nothing()
        local names = {}
        for _, entry in ipairs(self.drops.items()) do
            names[#names + 1] = entry.name
        end

        lu.assertEquals(names, { "Bandos chestplate", "Bones", "Bronze spear", "Coins" })
        local _, bones = item(self.drops, "Bones")
        lu.assertEquals(bones.count, 2)
        lu.assertEquals(bones.item_id, 526)
        local _, chestplate = item(self.drops, "Bandos chestplate")
        lu.assertEquals(chestplate.item_id, 11724)
        lu.assertNil(select(2, item(self.drops, "Bronze spear")).item_id)
    end

    function suite:test_each_monster_shows_once_with_its_best_chance_first()
        local droppers = self.drops.droppers((item(self.drops, "Bandos chestplate")))

        lu.assertEquals(droppers, {
            { title = "General Graardor", rate = "1/256", quantity = "1", mode = "Hard mode" },
            { title = "Sergeant Steelwill", rate = "1/49,152", quantity = "1" },
        })

        local coins = self.drops.droppers((item(self.drops, "Coins")))
        lu.assertEquals(coins[1], { title = "Goblin", rate = "28/128", quantity = "5" })
        lu.assertEquals(coins[2], { title = "Sergeant Steelwill", rate = "1/8", quantity = "5–10" })
        lu.assertEquals(#coins, 2)
    end

    function suite:test_only_the_best_fifty_droppers_are_kept_but_all_are_counted()
        local pages = {}
        for index = 1, 60 do
            pages[index] = {
                title = "Monster " .. index,
                sections = { { title = "Drops", drops = { drop("Bones", "1/" .. index) } } },
                variants = {},
            }
        end
        local string_index = { Bones = 0 }
        for index = 1, 60 do
            string_index["1/" .. index] = index
        end

        local source, counts = search_index.drops(pages, "", string_index)
        local data = assert(load(source))()

        lu.assertEquals(counts, { items = 1, rows = 50 })
        lu.assertEquals(data.counts, "1o")
        lu.assertEquals(data.rows[1]:sub(1, 4), "1^1^")
    end

    function suite:test_separators_in_wiki_text_stop_the_build()
        local pages = {
            { title = "X", sections = { { title = "Drops", drops = { drop("Bones", "1^2") } } } },
        }
        lu.assertError(search_index.drops, pages, "", { Bones = 0, ["1^2"] = 1 })
    end

    function suite:test_top_stats_rank_variants_with_the_info_tab_names()
        local results, total = self.stats.rank(1)

        lu.assertEquals(total, 4)
        lu.assertEquals(results[1].label, "General Graardor (Hard mode) - 4,000 XP | 500,000 LP")
        lu.assertEquals(results[1].variant, "Hard mode")
        lu.assertEquals(
            results[2].label,
            "General Graardor (Normal mode) - 2,125.5 XP | combat 624 | 255,000 LP"
        )
        lu.assertEquals(results[3].title, "Sergeant Steelwill")
        lu.assertNil(results[3].variant)
    end

    function suite:test_level_caps_leave_out_unknown_levels_and_slayer_needs()
        local results = self.stats.rank(1, { max_combat = 700 })
        lu.assertEquals(#results, 3)
        lu.assertEquals(results[1].variant, "Normal mode")

        results = self.stats.rank(1, { max_slayer = 10 })
        lu.assertEquals(#results, 3)
        for _, result in ipairs(results) do
            lu.assertNotEquals(result.title, "Sergeant Steelwill")
        end
    end

    function suite:test_name_filter_matches_slayer_categories_and_other_stats_work()
        local results = self.stats.rank(1, { query = "goblins" })
        lu.assertEquals(#results, 2)
        lu.assertEquals(results[1].title, "Sergeant Steelwill")

        results = self.stats.rank(2)
        lu.assertEquals(results[1].label, "Goblin - 0.1 XP per LP | combat 2 | 50 LP")

        results = self.stats.rank(6)
        lu.assertEquals(results[1].label, "General Graardor (Hard mode) - 9,000 max hit | 500,000 LP")

        local slayer, total = self.stats.rank(3)
        lu.assertEquals(total, 1)
        lu.assertStrContains(slayer[1].label, "700 Slayer XP")
    end

    function suite:test_bosses_and_mode_fights_can_be_hidden_or_shown_on_their_own()
        local hidden = self.stats.rank(1, { bosses = "hide" })
        lu.assertEquals(#hidden, 1)
        lu.assertEquals(hidden[1].title, "Goblin")

        local only = self.stats.rank(1, { bosses = "only" })
        lu.assertEquals(#only, 3)
        for _, result in ipairs(only) do
            lu.assertNotEquals(result.title, "Goblin")
        end

        lu.assertEquals(select(2, self.stats.rank(1)), 4)
    end

    function suite:test_index_files_from_another_format_mean_no_results_and_one_log_each()
        self:readers({ format = 99 }, { format = 99, rows = {} })

        lu.assertEquals(self.drops.items(), {})
        lu.assertEquals(self.drops.items(), {})
        lu.assertEquals(self.drops.droppers(1), {})
        lu.assertEquals(select(2, self.stats.rank(1)), 0)
        lu.assertEquals(select(2, self.stats.rank(2)), 0)
        lu.assertEquals(#self.logs, 2)
    end

    return suite
end
