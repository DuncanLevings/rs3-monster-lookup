-- The refresh chooser belongs to its settings page, including its debounce subscription.
local search = require("src/data/monster_search")
local cache = require("src/data/monster_cache")
local theme = require("src/ui/theme")
local internals = require("src/ui/prettyui_internals")

local picker = {}

function picker.new(page, on_refresh)
    local buttons = {}
    local model
    local destroyed = false
    local field, status

    local function clear_results()
        for _, button in ipairs(buttons) do
            button:Destroy()
        end
        buttons = {}
    end

    local function choose(result)
        if destroyed then
            return
        end

        local remaining = cache.manual_refresh_remaining(result.monster)

        if remaining > 0 then
            status.content = "Manual refresh available in "
                .. math.ceil(remaining / 60)
                .. " minutes."
            return
        end

        local monster = model.choose(result)

        if monster then
            clear_results()
            status.content = "Refresh requested. Search to select another saved monster."
            on_refresh(monster)
        end
    end

    local function update(results, message)
        if destroyed then
            return
        end

        clear_results()
        status.content = message

        for _, result in ipairs(results) do
            local remaining = cache.manual_refresh_remaining(result.monster)
            local label = result.label

            if remaining > 0 then
                label = label .. " (refresh in " .. math.ceil(remaining / 60) .. " min)"
            end

            buttons[#buttons + 1] = page:AddSimpleButton(label, function()
                choose(result)
            end, {
                -- SimpleButton takes a pixel width; it does not apply size anchors.
                width = math.max(1, page.content.width - 16),
                height = 30,
            })
        end
    end

    model = search.new(update, true)
    local options = internals.text_field_scroll_options(page)
    options.placeholder = "Search saved monsters..."
    options.maxLength = 80
    options.height = 32
    options.onChange = function(_, _, text)
        if not destroyed then
            model.start()
            model.set_query(text)
        end
    end
    field = page:AddTextField(options)
    status = page:AddText({
        text = "",
        height = 40,
        maxLines = 2,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        colour = theme.TEXT_MUTED,
        shadowed = false,
    })
    model.start()

    return {
        destroy = function()
            if destroyed then
                return
            end

            destroyed = true
            model.stop()
            clear_results()
            field:Destroy()
            status:Destroy()
        end,
    }
end

return picker
