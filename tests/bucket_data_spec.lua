local lu = require("luaunit")
local rows = require("tests/support/dropsline_rows")
local dropsline = require("src/data/wiki/dropsline")
local spawn_locations = require("src/data/wiki/spawn_locations")
local drop_groups = require("src/data/drops/groups")

-- the readers for monsters that arent in the saved bundle, dropsline and coordinates rows
return function()
    local suite = {}

    local function titles(sections)
        local list = {}

        for _, section in ipairs(sections) do
            list[#list + 1] = section.title
        end

        return list
    end

    local function names(section)
        local list = {}

        for _, drop in ipairs(section.drops) do
            list[#list + 1] = drop.name
        end

        return list
    end

    function suite:test_modes_become_picker_groups_with_shared_and_rare_drop_table_rows()
        local sections = assert(dropsline.sections({
            rows.drop("Bones", { ["Dropped from"] = "Kerapac#Normal mode,Hard mode" }),
            rows.drop("Coins", { ["Dropped from"] = "Kerapac#Normal mode" }),
            rows.drop("Uncut ruby", { ["Dropped from"] = "Kerapac#Normal mode" }, {
                rare_drop_table = true,
            }),
            rows.drop("Rune bar", { ["Dropped from"] = "Kerapac#Hard mode" }),
            rows.drop("Clue scroll", { ["Dropped from"] = "Kerapac" }),
        }))

        lu.assertEquals(titles(sections), {
            "Normal mode / Drops",
            "Normal mode / Rare drop table",
            "Hard mode / Drops",
        })
        lu.assertEquals(names(sections[1]), { "Bones", "Coins", "Clue scroll" })
        lu.assertEquals(names(sections[3]), { "Bones", "Rune bar", "Clue scroll" })

        local groups = assert(drop_groups.mode_groups(sections))
        lu.assertEquals(groups[1].name, "Normal mode")
        lu.assertEquals(groups[1].titles, { "Drops", "Rare drop table" })
        lu.assertEquals(groups[2].name, "Hard mode")
    end

    function suite:test_a_single_mode_reads_like_a_plain_page_without_a_picker()
        local sections = assert(dropsline.sections({
            rows.drop(
                "Uncut ruby",
                { ["Dropped from"] = "Goblin#Level 2" },
                { rare_drop_table = true }
            ),
            rows.drop("Bones", { ["Dropped from"] = "Goblin#Level 2" }),
        }))

        lu.assertEquals(titles(sections), { "Drops", "Rare drop table" })
        lu.assertNil(drop_groups.mode_groups(sections))
    end

    function suite:test_rates_names_and_quantities_match_how_the_page_shows_them()
        local section = assert(dropsline.sections({
            rows.drop("Bandos helmet", { ["Rarity"] = "1/384", ["Alt Rarity"] = "1/378" }),
            rows.drop("Chargebow", {
                ["Rarity"] = "1/200",
                ["Alt Rarity"] = "Varies",
                ["Alt Rarity Dash"] = "y",
            }),
            rows.drop("Bronze dagger", {
                ["Name Notes"] = '<sub title="Free-to-play only">(f)</sub>',
                ["Drop Quantity"] = "13–19",
            }),
        }))[1]

        lu.assertEquals(section.drops[1].rate, "1/384; 1/378")
        lu.assertEquals(section.drops[2].rate, "1/200–Varies")
        lu.assertEquals(section.drops[3].name, "Bronze dagger (f)")
        lu.assertEquals(section.drops[3].wiki_name, "Bronze dagger")
        lu.assertEquals(section.drops[3].quantity, "13–19")
    end

    function suite:test_rare_drop_table_rows_use_the_bucket_item_name()
        local row = rows.drop("Loop half of a key", {}, { rare_drop_table = true })
        row.drop_json = row.drop_json:gsub('"Dropped item"', '"Dropped item from RDT"')

        local sections = assert(dropsline.sections({ row }))

        lu.assertEquals(titles(sections), { "Rare drop table" })
        lu.assertEquals(sections[1].drops[1].wiki_name, "Loop half of a key")
    end

    function suite:test_notes_are_cleaned_and_numbered_per_section()
        local shared = {
            content = "Only during the [[Rag and Bone Man]] quest. '''Mod Ash'''. 4 May 2020 {{Citation}}",
            name = "rag",
        }
        local section = assert(dropsline.sections({
            rows.drop("Goblin skull", { ["Rarity Notes"] = { shared } }),
            rows.drop("Bones"),
            rows.drop("Beer", {
                ["Rarity Notes"] = { { content = "Members only." }, shared },
            }),
        }))[1]

        lu.assertEquals(
            section.notes,
            { "Only during the Rag and Bone Man quest.", "Members only." }
        )
        lu.assertEquals(section.drops[1].note_marker, "1")
        lu.assertEquals(section.drops[2].note_marker, "")
        lu.assertEquals(section.drops[2].notes, "")
        lu.assertEquals(section.drops[3].note_marker, "2,1")
    end

    function suite:test_prices_are_left_for_the_ge_library_except_coins_and_unsold_items()
        local section = assert(dropsline.sections({
            rows.drop(
                "Coins",
                { ["Drop Quantity"] = "250–500", ["Quantity Low"] = 250, ["Quantity High"] = 500 }
            ),
            rows.drop(
                "Coins",
                { ["Drop Quantity"] = "50", ["Quantity Low"] = 50, ["Quantity High"] = 50 }
            ),
            rows.drop("Goblin book", { ["Drop GEMW"] = false }),
            rows.drop("Bandos chestplate", { ["Drop Value"] = 159000 }),
        }))[1]

        lu.assertEquals(section.drops[1].price, { minimum = 250, maximum = 500 })
        lu.assertEquals(section.drops[2].price, 50)
        lu.assertEquals(section.drops[3].price, "Not sold")
        -- the drop value is an alch value, showing it as a GE price would be wrong
        lu.assertNil(section.drops[4].price)
    end

    function suite:test_exact_repeats_from_other_level_tables_are_left_out()
        local section = assert(dropsline.sections({
            rows.drop("Bones"),
            rows.drop("Coins", { ["Drop Quantity"] = "5", ["Rarity"] = "28/128" }),
            rows.drop("Bones"),
            rows.drop("Coins", { ["Drop Quantity"] = "5", ["Rarity"] = "8/128" }),
        }))[1]

        lu.assertEquals(#section.drops, 3)
        lu.assertNil(rawget(section, "seen"))
    end

    function suite:test_no_rows_means_no_drops_and_junk_rows_are_errors()
        lu.assertEquals(dropsline.sections({}), {})

        local _, problem = dropsline.sections({ { item_name = "Bones" } })
        lu.assertStrContains(problem, "invalid drop record")

        local too_many = {}
        for index = 1, 2001 do
            too_many[index] = rows.drop("Bones")
        end
        lu.assertNil(dropsline.sections(too_many))
    end

    function suite:test_spawns_are_grouped_per_map_and_far_apart_surface_spots_get_areas()
        local locations, reason = assert(spawn_locations.parse({
            rows.spawn(28, 0, { 3200, 3230 }, { 3200, 3240 }),
            rows.spawn(15, 0, { 2872 }, { 5358 }),
            rows.spawn(28, 0, { 2800 }, { 3400 }),
            rows.spawn(15, 0, { 2862, 2872 }, { 5357, 5358 }),
            rows.spawn(-1, 3, { 1289 }, { 5047 }),
        }))

        lu.assertNil(reason)
        lu.assertEquals(#locations, 3)
        lu.assertEquals(locations[1].name, "RuneScape Surface, area 1")
        lu.assertEquals(locations[1].spawns, "2")
        lu.assertEquals(locations[2].name, "God Wars Dungeon")
        -- the repeated 2872, 5358 pin only counts once
        lu.assertEquals(locations[2].spawns, "2")
        lu.assertEquals(#locations[2].spawn_maps, 2)
        lu.assertEquals(locations[3].name, "RuneScape Surface, area 2")
        lu.assertEquals(locations[3].map, { id = 28, plane = 0, x = 2800, z = 3400 })
        lu.assertNotEquals(tostring(locations[3].map), tostring(locations[3].spawn_maps[1]))
    end

    function suite:test_no_usable_pins_means_no_locations()
        local locations, reason = spawn_locations.parse({
            rows.spawn(-1, 0, { 1010 }, { 5401 }),
            rows.spawn(28, 9, { 3200 }, { 3200 }),
            { mapid = 28 },
        })

        lu.assertEquals(locations, {})
        lu.assertEquals(reason, "none")
        lu.assertNil(spawn_locations.parse(nil))
    end

    function suite:test_unknown_maps_still_get_a_row_and_pins_are_capped()
        local xs, ys = {}, {}
        for index = 1, 200 do
            xs[index], ys[index] = index, 100
        end

        local locations = assert(spawn_locations.parse({ rows.spawn(9999, 0, xs, ys) }))

        lu.assertEquals(locations[1].name, "Wiki map 9999")
        lu.assertEquals(#locations[1].spawn_maps, 128)
        lu.assertEquals(locations[1].spawns, "128")
    end

    return suite
end
