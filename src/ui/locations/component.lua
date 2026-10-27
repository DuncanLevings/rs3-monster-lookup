-- owns the Locations tab and its marker controls.

local locations_view = require("src/ui/locations/view")

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

    function self.destroy()
        if state.destroyed then
            return
        end

        state.destroyed = true
        clear()
    end

    return self
end

return locations_component
