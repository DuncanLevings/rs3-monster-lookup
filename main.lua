-- plugin entry point. what this file returns is what plugins depending on Monster Lookup
-- get (src/api.lua, PLUGIN_API.md)

local app = require("src/app")
local api = require("src/api")

function PluginShutdown()
    -- whatever other plugins left behind first, while the window they might sit in exists
    api.shutdown()
    app.stop()
end

-- the client calls this when an optional dependency (the GE Price Library) is turned on or off
function PluginDependencyUpdate(event)
    app.dependency_changed(event)
end

app.start()

return api.export
