local lu = require("luaunit")
local model = require("src/data/monster_info")
local format = require("src/utils/stat_format")

return function()
    local suite = {}

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
            data.sections[1].rows[1],
            { "Life points", "200,000", "Attack style", "Unknown" }
        )
        lu.assertEquals(
            data.sections[1].rows[2],
            { "Attack speed", "4 ticks (2.4s)", "Aggressive", "Yes" }
        )
        lu.assertEquals(data.sections[1].rows[3][2], "No")
        lu.assertEquals(data.sections[2].rows[1], { "Max hit", "72", "0", "Unknown", "Unknown" })
        lu.assertEquals(
            data.sections[2].rows[2],
            { "Level", "18", "Unknown", "Unknown", "Unknown" }
        )
        lu.assertEquals(data.sections[2].rows[3], { "Accuracy", "292", "0", "Unknown", "Unknown" })
        lu.assertEquals(
            data.sections[2].header_icons,
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

        lu.assertEquals(data.sections[3].rows[1], { "1,924", "80", "None", "Hexhunter bow" })
        lu.assertEquals(data.sections[3].header_icons, { false, "defence", "weak_none", false })
        lu.assertEquals(data.sections[4].rows[1], { "Unknown", "55", "Unknown", "0" })
        lu.assertEquals(data.sections[5].rows[1], { "Not immune", "Unknown", "Immune", "Unknown" })
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

        lu.assertEquals(data.sections[2].rows[1][5], "1,000")
        lu.assertEquals(data.sections[2].rows[2][5], "99")
        lu.assertEquals(data.sections[2].rows[3][5], "3,000")
        lu.assertEquals(data.sections[4].headers[5], "Necromancy")
        lu.assertEquals(
            data.sections[6].rows[1],
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

        lu.assertEquals(data.sections[3].rows[1][4], "Terrasaur maul\nNopeNopeNope perk")
        lu.assertEquals(data.sections[3].header_icons[3], "weak_crush")
        lu.assertEquals(data.sections[1].rows[4], { "Members only", "No", "", "" })
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

    return suite
end
