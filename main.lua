-- plugin entry point

local app = require("src/app")

function PluginShutdown()
    app.stop()
end

app.start()
