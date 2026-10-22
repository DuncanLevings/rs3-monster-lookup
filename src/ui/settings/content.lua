-- ribbon content uses the same search/customize pages as the plugin hub settings.

local settings_panel = require("src/ui/settings/panel")
local plugin_pages = require("src/ui/settings/pages")

local content_panel = {}
local SUBSCRIPTION = "monster_lookup_content"
local view

function content_panel.destroy()
    if view then
        view:Destroy()
        view = nil
    end
end

function content_panel.start(open_search, on_change, on_refresh)
    Event.ContentLayerReady.Subscribe(SUBSCRIPTION, function(event)
        content_panel.destroy()
        view = plugin_pages.new(event.component, open_search, function(page)
            return settings_panel.populate(page, on_change, on_refresh)
        end)
    end)
end

function content_panel.stop()
    Event.ContentLayerReady.Unsubscribe(SUBSCRIPTION)
    content_panel.destroy()
end

return content_panel
