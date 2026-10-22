local fixture = {}

function fixture.new(root, saved)
    local context = {
        parent = { width = 1280, height = 800, xyGlobal = { x = 0, y = 0 } },
        saved = saved,
        windows = {},
        texts = {},
        panels = 0,
        section_buttons = {},
        simple_buttons = {},
        radio_controls = {},
        checkbox_controls = {},
        settings_views = {},
        dropdowns = {},
        combos = {},
        text_fields = {},
        nodes = {},
        tooltips = {},
        text_measurements = {},
        models = {},
        logs = {},
    }
    local environment = setmetatable({}, { __index = _G })
    local modules = {}

    local function load_module(path)
        if modules[path] == nil then
            modules[path] = assert(loadfile(root .. "/" .. path .. ".lua", "t", environment))()
        end

        return modules[path]
    end

    local function native_component(parent)
        local node =
            { parent = parent, width = 840, height = 40, x = 0, y = 0, xyGlobal = { x = 0, y = 0 } }
        local hidden = false
        node.position_updates = 0
        node.visibility_updates = 0
        setmetatable(node, {
            __index = function(_, key)
                if key == "hidden" then
                    return hidden
                elseif key == "visible" then
                    return not hidden
                end
            end,
            __newindex = function(component, key, value)
                if key == "visible" then
                    error("Component.visible is read-only; write hidden instead")
                elseif key == "hidden" then
                    hidden = value
                    component.visibility_updates = component.visibility_updates + 1
                else
                    rawset(component, key, value)
                end
            end,
        })

        function node:SetPos(x, y, x_anchor, y_anchor)
            self.position_updates = self.position_updates + 1
            self.x = x
            self.y = y
            self.x_anchor = x_anchor
            self.y_anchor = y_anchor
        end

        function node:SetSize(width, height, width_anchor, height_anchor)
            self.width_anchor = width_anchor
            self.height_anchor = height_anchor
            self.width = width + (width_anchor or 0) * (parent and parent.width or 840)
            self.height = height + (height_anchor or 0) * (parent and parent.height or 520)
        end

        function node:SetHeight(height)
            self.height = height
        end
        function node:SetScrollSize(width, height)
            self.scroll_width, self.scroll_height = width, height
        end

        function node:Destroy()
            self.destroyed = true
        end

        node.hooks = {}
        node.listeners = {}

        function node:Subscribe(hook, id, handler)
            local listeners = self.listeners[hook]

            if not listeners then
                listeners = { order = {}, handlers = {} }
                self.listeners[hook] = listeners
            end

            if not listeners.handlers[id] then
                listeners.order[#listeners.order + 1] = id
            end

            listeners.handlers[id] = handler
            self.hooks[hook] = function(...)
                for _, listener_id in ipairs(listeners.order) do
                    if listeners.handlers[listener_id](...) == false then
                        return false
                    end
                end

                return true
            end
        end

        function node:SetAssociatedObject(item_id)
            self.item_id = item_id
        end

        context.nodes[#context.nodes + 1] = node
        return node
    end

    function context:find_node_with_hook(hook, id)
        for _, node in ipairs(self.nodes) do
            local listeners = node.listeners[hook]

            if not node.destroyed and listeners and listeners.handlers[id] then
                return node
            end
        end
    end

    local function create_text(parent, options)
        assert(options.lineSpacing == nil, "this client build rejects Text.lineSpacing writes")

        local text = native_component(parent)
        text.content = options.text
        text.options = options
        context.texts[#context.texts + 1] = text
        return text
    end

    local function container()
        local content = native_component(nil)
        content.width, content.height = 800, 360
        local root_layer = native_component(nil)
        local viewport = native_component(root_layer)
        content.parent = viewport
        local host = { root = root_layer, content = content, viewport = viewport, scrollY = 0 }

        function host:AddText(options)
            local text = native_component(self.content)
            text.content = type(options) == "table" and options.text or options
            context.texts[#context.texts + 1] = text
            return text
        end

        host.AddTitle = host.AddText

        function host:AddComboBox(options)
            context.combos[#context.combos + 1] = options
            return {}
        end

        function host:AddTextField(options)
            return environment.prettyui.TextField.new(self.content, options)
        end

        function host:AddSimpleButton(text, action, options)
            options = options or {}
            local button = {
                text = text,
                action = action,
                root = native_component(self.content),
                options = options,
            }
            button.root:SetSize(options.width or #text * 8 + 24, options.height or 24)
            function button:Destroy()
                self.root:Destroy()
            end
            context.simple_buttons[#context.simple_buttons + 1] = button
            return button
        end

        function host:AddRadioButton(entries, options)
            context.radio_controls[#context.radio_controls + 1] =
                { entries = entries, options = options }
            return {}
        end

        function host:AddCheckboxButton(entries, options)
            context.checkbox_controls[#context.checkbox_controls + 1] =
                { entries = entries, options = options }
            return {}
        end

        function host:AddPanel()
            context.panels = context.panels + 1
            return container()
        end

        function host:AddItemSlot()
            return {}
        end

        function host:SetScrollPosition(value)
            self.scroll_position = value
            self.scrollY = value
            self.viewport.scroll_y = value
        end

        function host:ScrollBy(delta)
            self:SetScrollPosition((self.scroll_position or 0) + delta)
        end

        function host:SetContentHeight(height)
            self.content_height = height

            if context.on_content_height then
                context.on_content_height(self, height)
            end
        end

        function host:AddTabs(entries, options)
            local tabs = {
                pages = {},
                entries = entries,
                active = 1,
                root = native_component(self.content),
            }
            for index in ipairs(entries) do
                tabs.pages[index] = container()
            end
            tabs.root.y = 140
            context.tabs = tabs

            function tabs:GetPage(index)
                return self.pages[index]
            end

            function tabs:SetActive(index, notify)
                self.active = index

                if notify ~= false and options.onChange then
                    options.onChange(self, index)
                end
            end

            return tabs
        end

        return host
    end

    environment.require = load_module
    environment.log = function(message)
        context.logs[#context.logs + 1] = message
    end
    -- context.saved is the full windows geometry, anything else goes in context.storage
    context.storage = {}
    environment.PersistentDB = {
        GetStructuredData = function(_, key)
            if key == "monster_lookup_window" then
                return context.saved
            end

            return context.storage[key]
        end,
        SetStructuredData = function(_, key, value)
            if key == "monster_lookup_window" then
                context.saved = value
            else
                context.storage[key] = value
            end

            return true
        end,
    }
    function environment.PersistentDB:CheckExists(key)
        return context.storage[key] ~= nil
    end

    function environment.PersistentDB:Delete(key)
        context.storage[key] = nil
    end

    function environment.PersistentDB:GetString(key)
        return context.storage[key]
    end

    function environment.PersistentDB:SetString(key, value)
        context.storage[key] = value
        return true
    end

    context.cache = load_module("src/data/monster_cache")
    environment.config = {
        Font = {
            MUSEO_SANS_15PT_REGULAR = {
                GetStringLineCount = function(_, text, width)
                    context.text_measurements[#context.text_measurements + 1] =
                        { text = text, width = width }
                    local lines = 0

                    for line in (text .. "<br>"):gmatch("(.-)<br>") do
                        lines = lines + math.max(1, math.ceil(#line * 8 / width))
                    end

                    return lines
                end,
            },
        },
        Obj = {
            FromID = function(item_id)
                return { id = item_id }
            end,
        },
    }
    environment.id = { Component = { TOPLEVEL_V2__GAME_AREA = 1 } }
    environment.id.Font = { MUSEO_SANS_15PT_REGULAR = 30, MUSEO_SANS_11PT_REGULAR = 11 }
    environment.id.StyleSheet = { DROPDOWN_DEFAULT = "dropdown" }
    environment.config.Font.MUSEO_SANS_11PT_REGULAR =
        environment.config.Font.MUSEO_SANS_15PT_REGULAR
    environment.ui = {
        Interfaces = {
            GetComponent = function(_, component_id)
                context.requested_parent_id = component_id
                return context.parent
            end,
        },
        Layer = { new = native_component },
        Rectangle = { new = native_component },
        Sprite = { new = native_component },
        ModelType = { NPC_MODEL = 6 },
        Model = {
            new = function(parent)
                if context.model_error then
                    error("Model creation unavailable")
                end
                local node = native_component(parent)
                local base = getmetatable(node)
                local offset = { x = 0, y = 0, z = 0, vector_kind = "integer" }
                setmetatable(node, {
                    __index = function(component, key)
                        if key == "worldOffset" then
                            return offset
                        end
                        return base.__index(component, key)
                    end,
                    __newindex = function(component, key, value)
                        if key == "worldOffset" then
                            assert(
                                value.vector_kind == "integer",
                                "Model worldOffset requires an integer vector"
                            )
                            offset = value
                        elseif key == "rotation" then
                            error("Model rotation requires a native integer vector")
                        else
                            base.__newindex(component, key, value)
                        end
                    end,
                })
                function node:SetModel(kind, npc_id)
                    self.model_type, self.npc_id = kind, npc_id
                end
                function node:SetTransform(position, rotation, scale, duration)
                    self.transform = {
                        position = position,
                        rotation = rotation,
                        scale = scale,
                        duration = duration,
                    }
                end
                context.models[#context.models + 1] = node
                return node
            end,
        },
        -- native dropdown list, dropdown:pick(id) acts like the player choosing an entry
        List = {
            new = function(parent)
                local list = native_component(parent)
                list.entries = {}
                list.selection_flags = {}

                function list:Add(label, entry_id)
                    self.entries[#self.entries + 1] = { text = label, id = entry_id }
                    self.selection_flags[entry_id] = true
                    return true
                end

                function list:SetEntrySelected(entry_id, selected)
                    self.selection_flags[entry_id] = selected

                    if selected then
                        self.selected = entry_id
                    end
                end

                function list:pick(entry_id)
                    self.selected = entry_id
                    self.hooks[6](self, entry_id, 1)
                end

                context.dropdowns[#context.dropdowns + 1] = list
                return list
            end,
        },
        SelectionChangeEvent = { DESELECTED = 0, SELECTED = 1 },
        AlignMode = { TOPLEFT = 0, CENTRE = 1, BOTTOMRIGHT = 2 },
        Hook = {
            ONSCROLLWHEEL = 1,
            ONRESIZE = 2,
            ONMOUSEOVER = 3,
            ONCLICK = 4,
            ONMOUSELEAVE = 5,
            ONSELECTIONCHANGED = 6,
        },
    }
    environment.Plugin = { resources = {} }
    environment.Vector3 = {
        new = function(x, y, z)
            return { x = x, y = y, z = z }
        end,
    }
    for _, key in ipairs({
        "no",
        "yes",
        "melee",
        "ranged",
        "magic",
        "necromancy",
        "special",
        "defence",
        "poison",
        "deflect",
        "stun",
        "drain",
        "weak_air",
        "weak_water",
        "weak_earth",
        "weak_fire",
        "weak_none",
        "weak_crush",
        "weak_slash",
        "weak_stab",
    }) do
        environment.Plugin.resources["stat_" .. key] = "test:" .. key
    end
    context.logic = {}
    function context:tick(count)
        for _ = 1, count or 1 do
            for _, callback in pairs(self.logic) do
                callback()
            end
        end
    end
    environment.Event = {
        Logic = {
            Subscribe = function(key, callback)
                context.logic[key] = callback
            end,
            Unsubscribe = function(key)
                context.logic[key] = nil
            end,
        },
        ContentLayerReady = {
            Subscribe = function(_, callback)
                context.on_content_ready = callback
            end,
            Unsubscribe = function()
                context.on_content_ready = nil
            end,
        },
        SettingsLayerReady = {
            Subscribe = function(_, callback)
                context.on_settings_ready = callback
            end,
            Unsubscribe = function()
                context.on_settings_ready = nil
            end,
        },
    }
    environment.prettyui = {
        TextField = {
            new = function(parent, options)
                local field =
                    { root = native_component(parent), options = options, text = options.text }

                function field:GetText()
                    return self.text
                end

                function field:SetText(value, notify)
                    self.text = value

                    if notify then
                        options.onChange(self, 0, value)
                    end
                end

                function field:Destroy()
                    self.root:Destroy()
                end

                context.text_fields[#context.text_fields + 1] = field
                return field
            end,
        },
        SimpleView = {
            new = function(parent, options)
                local view = container()
                view.root = native_component(parent)
                view.options = options

                function view:Destroy()
                    self.root:Destroy()
                end

                context.settings_views[#context.settings_views + 1] = view
                return view
            end,
        },
        Text = { new = create_text, title = create_text },
        Tooltip = {
            attach = function(component, parent, options)
                local popup = native_component(options.parent or parent)
                popup:SetSize(300, 80)
                popup.hidden = true
                local tooltip = {
                    component = component,
                    parent = options.parent or parent,
                    options = options,
                    root = popup,
                }

                function tooltip:Show()
                    self.root.hidden = false
                    self.hidden = false
                end

                function tooltip:Hide()
                    self.root.hidden = true
                    self.hidden = true
                end

                component:Subscribe(3, "prettyui_tooltip", function()
                    tooltip:Show()
                    return true
                end)

                function tooltip:Destroy()
                    self.destroyed = true
                end

                context.tooltips[#context.tooltips + 1] = tooltip
                return tooltip
            end,
        },
        SimpleButton = {
            new = function(parent, text, action, options)
                local button = { root = native_component(parent), content = { content = text } }
                button.root:SetPos(options.x, options.y)
                button.root:SetSize(options.width or #text * 8 + 24, options.height or 24)
                button.action = action

                function button:Destroy()
                    self.root:Destroy()
                end
                function button:SetDisabled(value)
                    self.disabled = value
                end
                button.disabled = options.disabled == true
                button.options = options

                context.simple_buttons[#context.simple_buttons + 1] = button
                return button
            end,
        },
        CollapseButton = {
            new = function(parent, title, options)
                local button = {
                    title = title,
                    root = native_component(parent),
                    left = native_component(parent),
                    middle = native_component(parent),
                    right = native_component(parent),
                    expanded = options.expanded,
                }

                function button:Destroy()
                    self.root:Destroy()
                end

                function button:SetExpanded(expanded)
                    self.expanded = expanded
                    options.onToggle(self, expanded)
                end

                context.section_buttons[#context.section_buttons + 1] = button
                return button
            end,
        },
        Window = {
            new = function(parent, options)
                local window = container()
                window.parent = parent
                window.root =
                    { x = options.x, y = options.y, width = options.width, height = options.height }
                window.options = options
                window.destroy_count = 0

                function window:Show()
                    self.visible = true
                end

                function window:SetTitle(title)
                    self.title = title
                end

                function window:Close()
                    options.onClose(self)
                    self.visible = false
                end

                function window:Destroy()
                    self.destroy_count = self.destroy_count + 1
                end

                context.windows[#context.windows + 1] = window
                return window
            end,
        },
    }
    context.environment = environment
    context.load_module = load_module
    context.stub_module = function(path, value)
        modules[path] = value
    end
    context.subject = load_module("src/ui/monster_window")
    context.settings_panel = load_module("src/ui/settings_panel")
    context.info_view = load_module("src/ui/monster_info_view")
    context.sample =
        { title = "Goblin", info = {}, sections = load_module("tests/support/sample_drops") }
    context.geometry = load_module("src/ui/window_state")
    return context
end

return fixture
