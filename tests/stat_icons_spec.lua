local lu = require("luaunit")

return function(root)
    local suite = {}

    local function load_icons(resources)
        local messages = {}
        local environment = setmetatable({
            Plugin = { resources = resources },
            log = function(message)
                messages[#messages + 1] = message
            end,
        }, { __index = _G })
        local icons = assert(loadfile(root .. "/src/ui/info/icons.lua", "t", environment))()
        return icons, messages
    end

    function suite:test_resources_resolve_by_file_name_without_extension()
        local melee, ranged = {}, {}
        local icons = load_icons({ stat_melee = melee, stat_ranged = ranged })

        lu.assertIs(icons.get("melee"), melee)
        lu.assertIs(icons.get("ranged"), ranged)
    end

    function suite:test_missing_resources_keep_text_fallback_and_report_once()
        local icons, messages = load_icons({})

        lu.assertNil(icons.get(false))
        lu.assertNil(icons.get("melee"))
        lu.assertNil(icons.get("ranged"))
        lu.assertEquals(#messages, 1)
        lu.assertStrContains(messages[1], "stat_melee was not found")
    end

    return suite
end
