-- plugin entry point

local app = require("src/app")

function PluginShutdown()
    app.stop()
end

-- the client calls this when an optional dependency (the GE Price Library) is turned on or off
function PluginDependencyUpdate(event)
    app.dependency_changed(event)
end

app.start()
