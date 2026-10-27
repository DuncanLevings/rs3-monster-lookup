local lu = require("luaunit")
local loader = require("tests/support/core_loader")
return function(root)
    local suite = {}
    function suite:test_static_catalogue_resolves_without_requests_or_storage()
        local library = loader.new().export
        lu.assertTrue(#library.titles() > 1000)
        local result = library.monster("Goblin")
        lu.assertNotNil(result)
        lu.assertNotNil(result.sections)
    end
    return suite
end
