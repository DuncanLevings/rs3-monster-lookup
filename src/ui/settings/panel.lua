-- the Search/Customize pages, mounted in two places that can be open at once: the cog in
-- Plugin Hub > Manage and the ribbon content panel. the client clears each layer when its
-- opened, so each mount rebuilds its own view every time

local settings = require("src/settings")
local plugin_pages = require("src/ui/settings/pages")

local settings_panel = {}
local HUB_SUBSCRIPTION = "monster_lookup_hub_settings"
local RIBBON_SUBSCRIPTION = "monster_lookup_content"
local views = {}

local function destroy_view(name)
    if views[name] then
        views[name]:Destroy()
        views[name] = nil
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

---@param open_search fun() opens the monster search window
---@param on_change fun() redraws the open lookup after a display setting changed
function settings_panel.start(open_search, on_change)
    local function mount(name)
        return function(event)
            destroy_view(name)
            views[name] = plugin_pages.new(event.component, open_search, function(page)
                add_controls(page, on_change)
            end)
        end
    end

    Event.SettingsLayerReady.Subscribe(HUB_SUBSCRIPTION, mount("hub"))
    Event.ContentLayerReady.Subscribe(RIBBON_SUBSCRIPTION, mount("ribbon"))
end

-- the ribbon panel belongs to the game session, so logout drops it
function settings_panel.destroy_ribbon()
    destroy_view("ribbon")
end

function settings_panel.stop()
    Event.SettingsLayerReady.Unsubscribe(HUB_SUBSCRIPTION)
    Event.ContentLayerReady.Unsubscribe(RIBBON_SUBSCRIPTION)
    destroy_view("hub")
    destroy_view("ribbon")
end

return settings_panel
