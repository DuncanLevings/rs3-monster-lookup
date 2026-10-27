-- entry point for the standalone plugin; Monster Data Core owns the data API.
local app = require("src/app")

function PluginShutdown()
    app.stop()
end

function PluginDependencyUpdate(event)
    app.dependency_changed(event)
end

app.start()
