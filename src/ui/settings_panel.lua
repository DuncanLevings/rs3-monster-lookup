-- settings page shown from the cog in Plugin Hub > Manage
-- the client clears the layer each time its opened so the view is rebuilt every time

local settings = require("src/settings")

local settings_panel = {}
local SUBSCRIPTION = "monster_lookup_hub_settings"
local view

local function destroy_view()
    if view then
        view:Destroy()
        view = nil
    end
end

local function add_controls(page, on_change)
    local current = settings.get()
    page:AddTitle("Wiki refresh interval")
    page:AddText(
        "Refresh saved Wiki data when you next open a monster after this interval. "
            .. "Prices update with the rest of the page."
    )
    page:AddRadioButton({
        { text = "15 minutes", value = 15 },
        { text = "1 hour", value = 60 },
        { text = "6 hours", value = 360 },
        { text = "24 hours", value = 1440 },
    }, {
        selectedValue = current.refresh_minutes,
        onChange = function(_, value)
            settings.set("refresh_minutes", value)
        end,
    })

    page:AddTitle("Drop rarity")
    page:AddCheckboxButton({
        {
            text = "Show rarity as a percentage",
            value = "percentage",
            selected = current.percentage_rarity,
        },
    }, {
        onChange = function(_, _, _, selected)
            if settings.set("percentage_rarity", selected) then
                on_change()
            end
        end,
    })
    page:AddText(
        "Converts numeric drop rates, including ranges. Descriptions such as Very rare and "
            .. "conditional notes stay as shown on the Wiki."
    )
end

---@param on_change fun() called when a setting changes that the open window needs to redraw for
function settings_panel.start(on_change)
    Event.SettingsLayerReady.Subscribe(SUBSCRIPTION, function(event)
        destroy_view()
        view = prettyui.SimpleView.new(event.component, {
            width = 0,
            height = 0,
            widthAnchor = 1,
            heightAnchor = 1,
        })
        add_controls(view, on_change)
    end)
end

function settings_panel.stop()
    Event.SettingsLayerReady.Unsubscribe(SUBSCRIPTION)
    destroy_view()
end

return settings_panel
