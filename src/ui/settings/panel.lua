-- settings page shown from the cog in Plugin Hub > Manage
-- the client clears the layer each time its opened so the view is rebuilt every time

local settings = require("src/settings")
local plugin_pages = require("src/ui/settings/pages")

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
    local colour_options = {}

    for _, colour in ipairs(settings.MENU_COLOURS) do
        colour_options[#colour_options + 1] = { text = colour.name, value = colour.id }
    end

    page:AddTitle("View drops colour")
    page:AddText("Colour of the View drops option in the right click menu.")
    page:AddRadioButton(colour_options, {
        selectedValue = current.menu_colour,
        onChange = function(_, value)
            settings.set("menu_colour", value)
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

-- the same display preferences are mounted in the hub and ribbon.
function settings_panel.populate(page, on_change)
    add_controls(page, on_change)
end

function settings_panel.start(on_change)
    Event.SettingsLayerReady.Subscribe(SUBSCRIPTION, function(event)
        destroy_view()
        view = plugin_pages.new(event.component, function()
            require("src/ui/search/window").open()
        end, function(page)
            return settings_panel.populate(page, on_change)
        end)
    end)
end

function settings_panel.stop()
    Event.SettingsLayerReady.Unsubscribe(SUBSCRIPTION)
    destroy_view()
end

return settings_panel
