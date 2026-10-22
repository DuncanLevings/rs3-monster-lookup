local lu = require("luaunit")
local loader = require("tests/support/core_loader")

return function(root)
    local suite = {}
    local function adapter(export)
        local environment = { MonsterDataCore = export, type = type, assert = assert }
        -- no module fallback: the client must have loaded the dependency already
        environment.require = function()
            error("adapter must not load private core modules")
        end
        return assert(loadfile(root .. "/src/data/core.lua", "t", environment))()
    end

    function suite:test_missing_dependency_explains_how_to_enable_it()
        local ok, problem = pcall(adapter)
        lu.assertFalse(ok)
        lu.assertStrContains(problem, "Enable monster-data-core before Monster Lookup")
    end

    function suite:test_invalid_dependency_is_rejected()
        lu.assertFalse(pcall(adapter, {}))
    end

    function suite:test_adapter_uses_the_clients_export()
        lu.assertIs(adapter(MonsterDataCore), MonsterDataCore)
    end

    function suite:test_dependency_caches_are_isolated_from_each_other_and_the_host()
        local first, second = loader.new(), loader.new()
        first.load_module("src/bundle/reader").titles = function()
            return { "fake" }
        end
        lu.assertEquals(first.export.titles(), { "fake" })
        lu.assertTrue(#second.export.titles() > 1000)
        lu.assertTrue(#MonsterDataCore.titles() > 1000)
        lu.assertNil(package.loaded["src/bundle/reader"])
    end

    return suite
end
