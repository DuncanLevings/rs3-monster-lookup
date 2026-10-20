local lu = require("luaunit")
local codec = require("src/vendor/json")

return function()
    local suite = {}

    function suite:test_strings_preserve_quotes_backslashes_controls_and_unicode()
        local source = {
            "",
            "ordinary text",
            'quotes " and backslash \\',
            "\b\f\n\r\t",
            "Wiki text: € – ×",
        }

        lu.assertEquals(codec.decode(codec.encode(source)), source)
        lu.assertEquals(codec.decode('"\\u20ac"'), "€")
        lu.assertEquals(codec.decode('"\\ud83d\\ude42"'), string.char(240, 159, 153, 130))
    end

    function suite:test_large_escaped_html_is_decoded_without_losing_or_duplicating_chunks()
        local html = string.rep('<a title="Coins">gold\\silver\n</a>', 10000)
        local source = { parse = { title = "Guard (Varrock)", text = html } }

        lu.assertEquals(codec.decode(codec.encode(source)), source)
    end

    function suite:test_invalid_escapes_control_characters_and_truncated_strings_are_rejected()
        for _, input in ipairs({
            '"\\q"',
            '"\\u123"',
            '"unterminated',
            '"ends in \\',
            '"raw\nnewline"',
            '"raw\0nul"',
        }) do
            lu.assertError(codec.decode, input)
        end
    end

    return suite
end
