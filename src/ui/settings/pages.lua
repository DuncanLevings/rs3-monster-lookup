-- Each mount owns its controls: the hub and ribbon can be open at the same time.
local widgets = require("src/ui/widgets")

local plugin_pages = {}
local SEARCH_PAGE, CUSTOMIZE_PAGE = 0, 1

function plugin_pages.new(parent, open_search, populate_customize)
    local controller = {}
    local root = widgets.layer(parent, 0)
    root:SetSize(0, 0, 1, 1)
    local body = widgets.layer(root, 1)
    body:SetSize(0, -52, 1, 1)
    body:SetPos(0, 52)
    local view, custom_controls

    local function destroy_view()
        if custom_controls then
            custom_controls.destroy()
            custom_controls = nil
        end

        if view then
            view:Destroy()
            view = nil
        end
    end

    local function show_page(page)
        if controller.destroyed then
            return
        end

        destroy_view()
        view = prettyui.SimpleView.new(body, {
            width = 0,
            height = 0,
            widthAnchor = 1,
            heightAnchor = 1,
        })

        if page == SEARCH_PAGE then
            view:AddText("Find a monster by name.")
            view:AddSimpleButton("Search monsters", open_search)
        else
            custom_controls = populate_customize(view)
        end
    end

    local selector = widgets.dropdown(root, {
        x = 8,
        y = 8,
        width = -16,
        widthAnchor = 1,
        height = 32,
        entries = {
            { text = "Search", id = SEARCH_PAGE },
            { text = "Customize", id = CUSTOMIZE_PAGE },
        },
        selected = SEARCH_PAGE,
        on_change = show_page,
    })
    show_page(SEARCH_PAGE)

    function controller:Destroy()
        if self.destroyed then
            return
        end

        self.destroyed = true
        destroy_view()
        selector:Destroy()
        root:Destroy()
    end

    return controller
end

return plugin_pages
