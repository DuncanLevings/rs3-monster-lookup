-- settings page shown from the cog in Plugin Hub > Manage
-- the client clears the layer each time its opened so the view is rebuilt every time

local settings = require("src/settings")
local cache = require("src/data/monster_cache")
local plugin_pages = require("src/ui/plugin_pages")

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

local function add_cache_refresh(page, on_refresh)
    page:AddTitle("Refresh a saved monster")
    page:AddText(
        "Saved data refreshes after two weeks when you next open that monster. "
            .. "Choose a saved monster to fetch its latest Wiki data sooner, including prices. Manual refresh is limited to once per hour for each saved monster."
    )
    local monsters = cache.list()

    if #monsters == 0 then
        page:AddText("No saved monsters yet. Use View drops on a monster first.")
        return
    end

    page:AddText("Search by name or location. Small typos, * and ? work here too.")
    return require("src/ui/saved_monster_picker").new(page, on_refresh)
end

---@param on_change fun() redraw display settings in the open lookup
---@param on_refresh fun(monster: MonsterSelection)? refresh only the selected saved monster
function settings_panel.populate(page, on_change, on_refresh)
    add_controls(page, on_change)
    if on_refresh then
        return add_cache_refresh(page, on_refresh)
    end
end

function settings_panel.start(on_change, on_refresh)
    Event.SettingsLayerReady.Subscribe(SUBSCRIPTION, function(event)
        destroy_view()
        view = plugin_pages.new(event.component, function()
            require("src/ui/monster_search_window").open()
        end, function(page)
            return settings_panel.populate(page, on_change, on_refresh)
        end)
    end)
end

function settings_panel.stop()
    Event.SettingsLayerReady.Unsubscribe(SUBSCRIPTION)
    destroy_view()
end

return settings_panel
