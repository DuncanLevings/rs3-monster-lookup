local lu = require("luaunit")
local search = require("src/utils/item_search")

return function()
    local suite = {}

    local function matches(name, query)
        return search.compile(query)(search.prepare(name))
    end

    function suite:test_partial_names_are_case_insensitive()
        lu.assertTrue(matches("Rune scimitar", "RUNE SCIM"))
        lu.assertFalse(matches("Bronze arrow", "rune"))
    end

    function suite:test_words_can_be_abbreviated_or_reordered()
        lu.assertTrue(matches("Rune scimitar", "scim rn"))
        lu.assertTrue(matches("Dark animica stone spirit", "dark spirit"))
        lu.assertFalse(matches("Light animica stone spirit", "dark spirit"))
    end

    function suite:test_fuzzy_words_allow_a_single_typo()
        lu.assertTrue(matches("Rune scimitar", "scimitor"))
        lu.assertTrue(matches("Rune scimitar", "scimitarr"))
        lu.assertFalse(matches("Rune scimitar", "scixxtar"))
    end

    function suite:test_star_matches_any_number_of_characters()
        lu.assertTrue(matches("Dark animica stone spirit", "dark*spirit"))
        lu.assertTrue(matches("Rune scimitar", "rune**scim*"))
        lu.assertFalse(matches("Rune scimitar", "rune*arrow"))
    end

    function suite:test_question_mark_matches_one_character()
        lu.assertTrue(matches("Rune scimitar", "r?ne scimitar"))
        lu.assertFalse(matches("Rune scimitar", "r??ne scimitar"))
    end

    function suite:test_pattern_characters_are_literal_in_wildcards()
        lu.assertTrue(matches("Cooked meat (m)", "*(m)"))
        lu.assertFalse(matches("Cooked meat", "*(m)"))
        lu.assertFalse(matches("Coins", "*[a-z]%"))
    end

    function suite:test_empty_search_and_punctuation_normalization()
        lu.assertTrue(matches("Rune scimitar", "  "))
        lu.assertTrue(matches("Cooked undead meat (m)", "undead-meat"))
    end

    function suite:test_many_wildcards_do_not_require_recursive_backtracking()
        lu.assertFalse(matches(string.rep("a", 1000), string.rep("*a", 60) .. "b"))
    end

    return suite
end
