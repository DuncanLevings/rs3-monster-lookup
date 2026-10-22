-- settings page shown from the cog in Plugin Hub > Manage
-- the client clears the layer each time its opened so the view is rebuilt every time

local settings = require("src/settings")
local cache = require("src/data/lookup/cache")
local core = require("src/data/core")
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

local function add_cache_refresh(page, on_refresh)
    page:AddTitle("Refresh monsters missing from local data")
    page:AddText(
        "Update saved Wiki data for monsters missing from the plugin's local data. "
            .. "Local data updates with the plugin. "
            .. "One-hour cooldown across matching variants."
    )
    local has_downloads = false

    for _, monster in ipairs(cache.list()) do
        local status = core.coverage(monster).status

        if status == "unknown" or status == "ambiguous" then
            has_downloads = true
            break
        end
    end

    if not has_downloads then
        page:AddText("No saved monsters missing from local data.")
        return
    end

    return require("src/ui/settings/picker").new(page, on_refresh)
end

---@param on_change fun() redraw display settings in the open lookup
---@param on_refresh fun(monster: MonsterSelection, on_complete: fun(ok: boolean, problem: string?))?
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
            require("src/ui/search/window").open()
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
