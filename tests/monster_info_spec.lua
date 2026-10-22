local lu = require("luaunit")
local model = require("src/data/monsters/info")
local format = require("src/utils/stat_format")

return function()
    local suite = {}

    local function section(data, title)
        for _, value in ipairs(data.sections) do
            if value.title == title then
                return value
            end
        end
        error("Missing section: " .. title)
    end

    function suite:test_combat_and_offensive_values_preserve_zeroes_and_unknowns()
        local data = model.build({
            life_points = 200000,
            attack_rate = 4,
            attack_level = 18,
            melee_accuracy = 292,
            melee_max_hit = 72,
            ranged_accuracy = 0,
            ranged_max_hit = 0,
            is_aggressive = "true",
            is_poisonous = "false",
        })

        lu.assertEquals(
            section(data, "Combat info").rows[1],
            { "Life points", "200,000", "Attack style", "Unknown" }
        )
        lu.assertEquals(
            section(data, "Combat info").rows[2],
            { "Attack speed", "4 ticks (2.4s)", "Combat XP", "Unknown" }
        )
        lu.assertEquals(section(data, "Overview").rows[2], { "Aggressive", "Yes", "", "" })
        lu.assertEquals(section(data, "Combat info").rows[3], { "Poisonous", "No", "", "" })
        lu.assertEquals(
            section(data, "Offensive stats").rows[1],
            { "Max hit", "72", "0", "Unknown", "Unknown" }
        )
        lu.assertEquals(
            section(data, "Offensive stats").rows[2],
            { "Level", "18", "Unknown", "Unknown", "Unknown" }
        )
        lu.assertEquals(
            section(data, "Offensive stats").rows[3],
            { "Accuracy", "292", "0", "Unknown", "Unknown" }
        )
        lu.assertEquals(
            section(data, "Offensive stats").header_icons,
            { false, "melee", "ranged", "magic", "necromancy" }
        )
    end

    function suite:test_defence_weakness_affinity_and_immunity_meanings_are_kept_separate()
        local data = model.build({
            armour = 1924,
            defence_level = 80,
            weakness_text = { "nothing" },
            susceptible_to = { "hexhunter" },
            melee_affinity = 55,
            magic_affinity = 0,
            susceptible_to_stun = "false",
            susceptible_to_poison = "true",
        })

        lu.assertEquals(section(data, "Defensive stats").rows[1], { "1,924", "80" })
        lu.assertEquals(section(data, "Defensive stats").header_icons, { false, "defence" })
        lu.assertEquals(
            section(data, "Base hit chance").rows[1],
            { "Unknown", "55", "Unknown", "0" }
        )
        lu.assertEquals(section(data, "Immunities").rows, {
            { "Poison", "Not immune", "Deflect", "Unknown" },
            { "Stun", "Immune", "Stat drain", "Unknown" },
        })
        lu.assertEquals(section(data, "Immunities").widths, section(data, "Overview").widths)
        lu.assertEquals(
            section(data, "Immunities").value_icons,
            { { [2] = "poison", [4] = "deflect" }, { [2] = "stun", [4] = "drain" } }
        )
        lu.assertEquals(section(data, "Immunities").value_tooltips[2][2], "Stun: Immune")
    end

    function suite:test_optional_necromancy_and_slayer_data_are_shown_when_available()
        local data = model.build({
            necromancy_level = 99,
            necromancy_accuracy = 3000,
            necromancy_max_hit = 1000,
            necromancy_affinity = 60,
            slayer_level = 90,
            slayer_experience = 1250.5,
            slayer_category = { "abyssal demons" },
            assigned_by = { "Laniakea" },
        })

        lu.assertEquals(section(data, "Offensive stats").rows[1][5], "1,000")
        lu.assertEquals(section(data, "Offensive stats").rows[2][5], "99")
        lu.assertEquals(section(data, "Offensive stats").rows[3][5], "3,000")
        lu.assertEquals(section(data, "Base hit chance").headers[5], "Necromancy")
        lu.assertEquals(
            section(data, "Slayer").rows[1],
            { "Required level", "90", "Slayer XP", "1,250.5" }
        )
    end

    function suite:test_cached_lookups_without_variant_lists_still_work()
        local info = { version_anchor = "Male", examine = "A guard." }
        lu.assertEquals(model.variants({ info = info }), { info })
        lu.assertEquals(model.variants({ info = info, variants = { false, info } }), { info })
        lu.assertEquals(model.variant_name(info, 1), "Male")
        lu.assertEquals(model.build(info).variant, "Male")
        lu.assertEquals(model.build({}).sections, {})
    end

    function suite:test_spider_susceptibilities_have_proper_names_and_separate_lines()
        local data = model.build({
            susceptible_to = { "terrasaur", "nopenopenope" },
            weakness_text = { "crush" },
            is_members_only = "No",
        })

        lu.assertEquals(section(data, "Overview").rows[1][4], "Terrasaur maul\nNopeNopeNope perk")
        lu.assertEquals(section(data, "Overview").value_icons[1][2], "weak_crush")
        lu.assertEquals(section(data, "Combat info").rows[4], { "Members only", "No", "", "" })
    end

    function suite:test_formatting_handles_missing_invalid_and_formatted_wiki_values()
        lu.assertEquals(format.number(0), "0")
        lu.assertEquals(format.number(0 / 0), "Unknown")
        lu.assertEquals(format.number(math.huge), "Unknown")
        lu.assertEquals(format.text({}), "Unknown")
        lu.assertEquals(format.text({ "[[Air spells|Air]]", "<col=red>Magic</col>" }), "Air, Magic")
        lu.assertEquals(format.boolean(false), "No")
        lu.assertEquals(format.boolean(nil), "Unknown")
    end

    function suite:test_codex_reference_preserves_non_placeable_and_variant_information()
        local abyssal = model.build({ life_points = 100 }, "Abyssal demon")
        local dungeon = section(abyssal, "Player-owned Slayer Dungeon")
        lu.assertEquals(dungeon.rows[1], { "Codex entry", "42", "Dungeon size", "Small" })
        lu.assertEquals(dungeon.rows[3][4], "Abyssal demon")
        lu.assertStrContains(dungeon.note, "2026-10-21")

        local wall = model.build({ life_points = 100 }, "Wall beast")
        lu.assertEquals(section(wall, "Player-owned Slayer Dungeon").rows[1][4], "Cannot be placed")
        local spider = model.build({ life_points = 100 }, "Giant spider")
        lu.assertStrContains(section(spider, "Player-owned Slayer Dungeon").rows[3][4], "level 8")
    end

    function suite:test_codex_never_guesses_from_part_of_a_monster_name()
        local data = model.build({ life_points = 100 }, "Giant spider (Tarn's Lair)")

        for _, value in ipairs(data.sections) do
            lu.assertNotEquals(value.title, "Player-owned Slayer Dungeon")
        end
    end

    function suite:test_common_information_is_expanded_and_detailed_stats_start_collapsed()
        local data = model.build({ life_points = 100 })
        lu.assertEquals(data.sections[1].title, "Overview")
        lu.assertTrue(section(data, "Immunities").continuation)
        lu.assertNotEquals(section(data, "Overview").detailed, false)
        lu.assertNotEquals(section(data, "Immunities").detailed, false)

        for _, title in ipairs({
            "Combat info",
            "Offensive stats",
            "Defensive stats",
            "Base hit chance",
        }) do
            lu.assertTrue(section(data, title).detailed)
        end
    end

    return suite
end
