local lu = require("luaunit")
local loader = require("tests/support/core_loader")
return function(root)
    local suite = {}
    function suite:test_static_library_is_bundled_without_a_plugin_dependency()
        local loaded
        local export = {}
        local environment = {
            require = function(name)
                loaded = name
                return export
            end,
        }
        local actual = assert(loadfile(root .. "/src/data/core.lua", "t", environment))()
        lu.assertIs(actual, export)
        lu.assertEquals(loaded, "src/data/library/api")
    end
    function suite:test_static_catalogue_resolves_without_requests_or_storage()
        local library = loader.new().export
        lu.assertTrue(#library.titles() > 1000)
        local result = library.monster("Goblin")
        lu.assertNotNil(result)
        lu.assertNotNil(result.sections)
    end
    return suite
end
