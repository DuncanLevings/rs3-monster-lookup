local lu = require("luaunit")
local markup = require("tests/support/location_markup")

return function(root)
    local suite = {}
    local environment = setmetatable({}, { __index = _G })
    local modules = {}

    environment.require = function(path)
        if not modules[path] then
            modules[path] = assert(loadfile(root .. "/" .. path .. ".lua", "t", environment))()
        end
        return modules[path]
    end

    local locations = environment.require("src/data/monster_locations")

    function suite:test_standard_table_preserves_access_details_and_ignores_extra_columns()
        local rows, reason = locations.parse(markup)

        lu.assertNil(reason)
        lu.assertEquals(#rows, 3)
        lu.assertEquals(rows[1], {
            name = "Lumbridge",
            levels = "2",
            requirements = "None",
            spawns = "30",
        })
        lu.assertEquals(rows[2], {
            name = "Observatory Dungeon",
            levels = "2, 5",
            requirements = "Goblin Diplomacy and level 10 Agility",
            spawns = "33",
        })
    end

    function suite:test_floor_text_does_not_duplicate_hidden_regional_variants()
        local rows = locations.parse(markup)

        lu.assertEquals(rows[3].name, "Varrock (Floor 1)")
    end

    function suite:test_singular_heading_and_reordered_columns_are_supported()
        local rows = locations.parse([[
            <h2><span id="Location">Location</span></h2><h3>Surface</h3>
            <table><tr><th>Spawns</th><th>Requirements</th><th>Members</th><th>Level</th><th>Location</th></tr>
            <tr><td>1</td><td>None</td><td>Yes</td><td>3,000</td><td>Nodon Front</td></tr></table>
        ]])

        lu.assertEquals(rows, {
            {
                name = "Nodon Front",
                levels = "3,000",
                requirements = "None",
                spawns = "1",
            },
        })
    end

    function suite:test_table_does_not_require_a_membership_column()
        local rows = locations.parse([[
            <h2>Locations</h2><table>
            <tr><th>Location</th><th>Levels</th><th>Access requirements</th><th>Spawns</th></tr>
            <tr><td>Goblin Cave</td><td>2, 5</td><td>None</td><td>24</td></tr></table>
        ]])

        lu.assertEquals(rows, {
            { name = "Goblin Cave", levels = "2, 5", requirements = "None", spawns = "24" },
        })
    end

    function suite:test_requirement_lists_keep_line_breaks_and_skill_icon_labels()
        local requirements =
            '<ul><li>85 <img alt="Slayer" /></li><li>Complete <a>Test quest</a></li></ul>'
        local rows = locations.parse(
            markup:gsub("Goblin Diplomacy</a> and level 10 Agility", "</a>" .. requirements)
        )

        lu.assertEquals(rows[2].requirements, "85 Slayer\nComplete Test quest")
    end

    function suite:test_skill_icons_do_not_duplicate_an_existing_text_label()
        local rows = locations.parse(
            markup:gsub(
                "Goblin Diplomacy</a> and level 10 Agility",
                '</a>85 <img alt="Slayer" /> Slayer'
            )
        )

        lu.assertEquals(rows[2].requirements, "85 Slayer")
    end

    function suite:test_unrelated_tables_do_not_become_locations()
        local rows, reason = locations.parse("<h2>Drops</h2>" .. markup:match("(<table.-</table>)"))

        lu.assertEquals(rows, {})
        lu.assertEquals(reason, "none")
    end

    function suite:test_location_section_ends_at_the_next_peer_heading()
        local rows, reason = locations.parse(
            "<h2>Locations</h2><p>Somewhere.</p><h2>Drops</h2>"
                .. markup:match("(<table.-</table>)")
        )

        lu.assertEquals(rows, {})
        lu.assertEquals(reason, "unreadable")
    end

    function suite:test_merged_cells_reject_the_table_instead_of_shifting_columns()
        local rows, reason = locations.parse(markup:gsub("<td>2</td>", '<td rowspan="2">2</td>'))

        lu.assertEquals(rows, {})
        lu.assertEquals(reason, "unreadable")
    end

    function suite:test_missing_cells_reject_the_table_without_partial_results()
        local rows, reason =
            locations.parse(markup:gsub("<td>33</td><td>Show map</td><td>Kandarin</td>", ""))

        lu.assertEquals(rows, {})
        lu.assertEquals(reason, "unreadable")
    end

    function suite:test_wiki_text_cannot_inject_game_formatting()
        local rows = locations.parse(
            markup:gsub("Lumbridge</a>", "&lt;col=ff0000&gt;Lumbridge&lt;/col&gt;</a>")
        )

        lu.assertFalse(rows[1].name:find("[<>]") ~= nil)
    end

    function suite:test_spawn_cells_only_keep_whole_numbers()
        for _, value in ipairs({ "? <a>edit</a>", "Unknown", "12 or 15", "-", "" }) do
            local html = "<h2>Locations</h2><table><tr><th>Location</th><th>Levels</th><th>Requirements</th><th>Spawns</th></tr>"
                .. "<tr><td>Somewhere</td><td>10</td><td>None</td><td>"
                .. value
                .. "</td></tr></table>"
            lu.assertEquals(locations.parse(html)[1].spawns, "")
        end
    end

    return suite
end
