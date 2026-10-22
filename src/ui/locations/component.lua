-- the Locations tab as a component: where a monster spawns, from the wiki, with buttons from
-- the current navigation provider (Monster Lookup's marker unless a plugin registered its
-- own, see navigation.lua), in a PrettyUI scrolling page the caller owns
--
--   local locations = locations_component.new(tab_page)
--   locations.set_monster(record)  -- a MonsterResult, eg from MonsterData.monster()
--   ...
--   locations.destroy()
--
-- theres one provider for the whole game, so using it from here moves the same marker (or
-- whatever the provider does) the standard window uses. when the provider changes every
-- locations component draws itself again with the new one

local locations_view = require("src/ui/locations/view")
local navigation = require("src/ui/locations/navigation")

local locations_component = {}

---@param page table PrettyUI scrolling page: content, SetContentHeight, SetScrollPosition, ScrollBy
function locations_component.new(page)
    local state = {}
    local self = {}

    local function clear()
        if state.controller then
            state.controller.destroy()
            state.controller = nil
        end
    end

    local function draw()
        clear()

        if state.record then
            state.controller = locations_view.render(page, state.record)
        end
    end

    ---@param record MonsterResult?
    function self.set_monster(record)
        if state.destroyed then
            return
        end

        state.record = record
        draw()
    end

    -- another plugin started or stopped doing the navigation
    local unsubscribe = navigation.subscribe(function()
        if not state.destroyed then
            draw()
        end
    end)

    function self.destroy()
        if state.destroyed then
            return
        end

        state.destroyed = true
        unsubscribe()
        clear()
    end

    return self
end

return locations_component
