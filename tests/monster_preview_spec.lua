local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

-- the orbiting preview on the Monster info tab, against stand ins for ui.ModelGroup and
-- ui.ModelCamera. the plain zoom only preview is covered in tests/monster_window_spec.lua
return function(root)
    local suite = {}
    local ONHOLD, ONRELEASE = 7, 8

    local function camera_stub()
        local camera = { fov = 90 }
        function camera:SetFOV(fov)
            self.fov = fov
        end
        function camera:SetPosition(position)
            self.position = position
        end
        function camera:SetLookAt(target)
            self.lookAt = target
        end
        function camera:SetClipPlanes(near, far)
            self.nearPlane, self.farPlane = near, far
        end
        return camera
    end

    local function copy(camera)
        local result = camera_stub()
        for key, value in pairs(camera) do
            if type(value) ~= "function" then
                result[key] = value
            end
        end
        return result
    end

    -- keeps = true holds on to the camera it was given, otherwise it keeps a copy, the docs
    -- dont say which so the preview has to cope with both
    local function install_model_groups(context, keeps)
        context.groups = {}
        local ui = context.environment.ui
        ui.Hook.ONHOLD, ui.Hook.ONRELEASE = ONHOLD, ONRELEASE
        ui.ModelCameraTransition = { NONE = 0, FADE = 1, CROSSFADE = 2 }
        ui.ModelCamera = { new = camera_stub }
        ui.ModelGroup = {
            new = function(parent)
                if context.group_error then
                    error("Model group creation unavailable")
                end
                local group = {
                    parent = parent,
                    width = 300,
                    height = 210,
                    x = 0,
                    y = 0,
                    hooks = {},
                    cameras = {},
                    next_camera = 0,
                    added = 0,
                }
                function group:SetSize(width, height)
                    self.width, self.height = width, height
                end
                function group:SetPos(x, y)
                    self.x, self.y = x, y
                end
                function group:Subscribe(hook, _, callback)
                    self.hooks[hook] = callback
                end
                function group:Destroy()
                    self.destroyed = true
                end
                function group:AddCamera(camera)
                    -- no argument adds a default camera, like the docs say
                    camera = camera or camera_stub()
                    local index = self.next_camera
                    self.next_camera = index + 1
                    self.added = self.added + 1
                    self.cameras[index] = keeps and camera or copy(camera)
                    return index
                end
                function group:SwitchCamera(index)
                    self.active = index
                    return self.cameras[index] ~= nil
                end
                function group:DeleteCamera(index)
                    self.cameras[index] = nil
                end
                function group:GetCamera(index)
                    return self.cameras[index] and copy(self.cameras[index])
                end
                setmetatable(group, {
                    __index = function(self, key)
                        if key == "activeCamera" then
                            local camera = rawget(self, "cameras")[rawget(self, "active")]
                            return camera and copy(camera)
                        end
                    end,
                })
                context.groups[#context.groups + 1] = group
                return group
            end,
        }
        context.environment.config.NPC = {
            FromID = function(npc_id)
                if npc_id == 1 then
                    return { visibleCombatLevel = 2, gridSize = 1, overlayHeight = 200 }
                end
            end,
        }
        context.stub_module("src/data/bundle/reader", {
            npc_ids = function()
                return { 1 }
            end,
        })
    end

    local function open_info(context)
        context.subject.open({ name = "Goblin", npc_id = 1 })
        context.subject.show_result({ title = "Goblin", sections = {}, info = { combat_level = 2 } })
        context.tabs:SetActive(2)
        return context.groups[#context.groups]
    end

    local function active_camera(group)
        return group.cameras[group.active]
    end

    -- how far the camera is from what its looking at, the orbit radius
    local function distance(camera)
        local p, t = camera.position, camera.lookAt
        return math.sqrt((p.x - t.x) ^ 2 + (p.y - t.y) ^ 2 + (p.z - t.z) ^ 2)
    end

    function suite:setUp()
        self.context = fixture.new(root)
    end

    function suite:tearDown()
        self.context.subject.destroy()
    end

    function suite:test_the_model_sits_centred_in_its_own_scene_with_the_camera_in_front()
        install_model_groups(self.context, true)
        local group = assert(open_info(self.context))
        local model = self.context.models[1]

        lu.assertIs(model.parent, group)
        lu.assertTrue(model.clickthrough)
        lu.assertFalse(group.clickthrough)
        lu.assertEquals(model.npc_id, 1)
        lu.assertEquals(model.animID, -1)
        -- the plain previews offset with y flipped, y is up inside a model group
        -- the model stays put, the camera aims at the plain previews centre point instead
        lu.assertEquals(model.transform.position, { x = 0, y = 0, z = 0 })
        -- drawn smaller to match the plain renderer, see SCENE_SCALE
        lu.assertAlmostEquals(model.transform.scale.x, 1 / 1.75, 1e-9)
        lu.assertEquals(model.transform.scale.x, model.transform.scale.y)

        local camera = active_camera(group)
        lu.assertEquals(camera.fov, 40)
        lu.assertTrue(camera.useLookAt)
        lu.assertEquals(camera.lookAt, { x = 0, y = 70, z = 0 })
        lu.assertAlmostEquals(camera.position.x, 0, 1e-9)
        lu.assertAlmostEquals(camera.position.y, 70, 1e-9)
        lu.assertTrue(camera.position.z < 0)
        lu.assertEquals(group.width, model.width)

        local tooltip = self.context.tooltips[#self.context.tooltips]
        lu.assertStrContains(tooltip.options.text, "Drag to turn")
    end

    -- no overlay height, so 256 per tile is only a guess and the model may be taller
    function suite:test_a_guessed_height_centres_on_its_middle_for_headroom()
        install_model_groups(self.context, true)
        self.context.environment.config.NPC.FromID = function(npc_id)
            if npc_id == 1 then
                return { visibleCombatLevel = 2, gridSize = 1, overlayHeight = -1 }
            end
        end
        local group = open_info(self.context)
        local camera = active_camera(group)
        local focal = group.width / 2 / math.tan(math.rad(20))

        -- the middle of the 256 guess, plus the one tile lift of 15% of the box
        lu.assertEquals(self.context.models[1].transform.position, { x = 0, y = 0, z = 0 })
        lu.assertAlmostEquals(
            (camera.lookAt.y - 128) / (distance(camera) / focal),
            0.15 * group.height,
            1e-6
        )
    end

    -- a 3 tile monster with a guessed height is moved down a fifth of the box, so a taller
    -- than guessed model loses its legs off the bottom rather than its head off the top
    function suite:test_bigger_guessed_monsters_are_moved_down_a_share_of_the_box()
        install_model_groups(self.context, true)
        self.context.environment.config.NPC.FromID = function(npc_id)
            if npc_id == 1 then
                return { visibleCombatLevel = 2, gridSize = 3, overlayHeight = -1 }
            end
        end
        local group = open_info(self.context)
        local camera = active_camera(group)
        local focal = group.width / 2 / math.tan(math.rad(20))
        local units_per_pixel = distance(camera) / focal

        -- guessed height 768, so 384 is its middle, then a fifth of the box on top
        lu.assertAlmostEquals((camera.lookAt.y - 384) / units_per_pixel, 0.2 * group.height, 1e-6)
    end

    -- 4 tiles and up are mostly long low beasts like dragons, the guess is already too tall
    function suite:test_four_tile_and_bigger_guessed_monsters_are_not_moved_down()
        install_model_groups(self.context, true)
        self.context.environment.config.NPC.FromID = function(npc_id)
            if npc_id == 1 then
                return { visibleCombatLevel = 2, gridSize = 4, overlayHeight = -1 }
            end
        end
        local group = open_info(self.context)

        lu.assertAlmostEquals(active_camera(group).lookAt.y, 512, 1e-9)
    end

    -- a dragon sized monster with a real overlay height is low and long, not tall
    function suite:test_big_monsters_with_a_real_height_are_not_moved_down()
        install_model_groups(self.context, true)
        self.context.environment.config.NPC.FromID = function(npc_id)
            if npc_id == 1 then
                return { visibleCombatLevel = 2, gridSize = 4, overlayHeight = 300 }
            end
        end
        local group = open_info(self.context)

        -- the plain previews 35% of the real height, nothing added
        lu.assertAlmostEquals(active_camera(group).lookAt.y, 300 * 0.35, 1e-9)
    end

    -- dharok and most monsters have no overlay height of their own, the game then uses their
    -- animation sets, which is a real height so they frame like any other known height
    function suite:test_the_animation_sets_height_is_used_when_the_npc_has_none()
        install_model_groups(self.context, true)
        self.context.environment.config.NPC.FromID = function(npc_id)
            if npc_id == 1 then
                return {
                    visibleCombatLevel = 2,
                    gridSize = 1,
                    overlayHeight = -1,
                    bas = { overlayHeight = 400 },
                }
            end
        end
        local group = open_info(self.context)

        -- 35% of the real height, no tile guess and no lift
        lu.assertAlmostEquals(active_camera(group).lookAt.y, 400 * 0.35, 1e-9)
        lu.assertEquals(self.context.models[1].transform.scale.x, 1 / 1.75)
    end

    function suite:test_dragging_turns_and_tilts_without_changing_the_distance()
        install_model_groups(self.context, true)
        local group = open_info(self.context)
        local camera = active_camera(group)
        local start = distance(camera)

        group.hooks[4](group, 100, 50)
        group.hooks[ONHOLD](group, 140, 50)
        lu.assertTrue(camera.position.x > 0)
        lu.assertAlmostEquals(distance(camera), start, 1e-6)

        -- tilting stops at the limit however far the mouse goes
        group.hooks[ONHOLD](group, 140, 5000)
        local high = camera.position.y
        group.hooks[ONHOLD](group, 140, 9000)
        lu.assertAlmostEquals(camera.position.y, high, 1e-6)
        lu.assertAlmostEquals(math.abs(high - camera.lookAt.y) / start, math.sin(0.6), 1e-6)

        -- after letting go, holding elsewhere does nothing until the next click
        group.hooks[ONRELEASE](group, 140, 9000)
        local position = camera.position
        group.hooks[ONHOLD](group, 900, 900)
        lu.assertIs(camera.position, position)

        -- the next drag carries on from where the last one left it
        group.hooks[4](group, 0, 0)
        group.hooks[ONHOLD](group, 0, 0)
        lu.assertAlmostEquals(camera.position.y, high, 1e-6)
        lu.assertEquals(group.added, 1)
    end

    function suite:test_a_group_that_keeps_copies_gets_a_fresh_camera_for_each_move()
        install_model_groups(self.context, false)
        local group = open_info(self.context)
        local first = group.active
        local added = group.added

        group.hooks[4](group, 100, 50)
        group.hooks[ONHOLD](group, 160, 50)

        lu.assertEquals(group.added, added + 1)
        lu.assertNotEquals(group.active, first)
        lu.assertNil(group.cameras[first])
        lu.assertTrue(active_camera(group).position.x > 0)
        local count = 0
        for _ in pairs(group.cameras) do
            count = count + 1
        end
        lu.assertEquals(count, 1)
    end

    function suite:test_zoom_moves_the_camera_back_up_to_twice_as_far_and_never_scrolls_the_page()
        install_model_groups(self.context, true)
        local group = open_info(self.context)
        local camera = active_camera(group)
        local near = distance(camera)
        local page = self.context.tabs.pages[2]
        local scroll = page.scroll_position

        lu.assertFalse(group.hooks[1](group, 1))
        lu.assertTrue(distance(camera) > near)
        for _ = 1, 200 do
            group.hooks[1](group, 1)
        end
        lu.assertAlmostEquals(distance(camera), near * 2, 1e-6)
        for _ = 1, 200 do
            group.hooks[1](group, -1)
        end
        lu.assertAlmostEquals(distance(camera), near, 1e-6)
        lu.assertEquals(page.scroll_position, scroll)
    end

    -- drawn size is the old previews: 256 / its view distance pixels per unit. the camera fov
    -- spans the width, so for it thats (width / 2 / tan(20 degrees)) / camera distance
    function suite:test_the_scene_draws_the_model_the_same_size_as_the_plain_preview()
        local function drawn_scale(group)
            local focal = group.width / 2 / math.tan(math.rad(20))
            return focal / distance(active_camera(group))
        end
        local function plain_scale(width, height)
            -- goblin is 128 wide and 200 tall (its overlay height), 128 deep
            local aspect = math.max(0.5, width / height)
            local extent = math.max(200, 128 / aspect)
            return 256 / (extent * 256 / (height * 0.72) + 64)
        end

        install_model_groups(self.context, true)
        local group = open_info(self.context)
        lu.assertAlmostEquals(drawn_scale(group), plain_scale(group.width, group.height), 1e-9)

        local body = self.context:find_node_with_hook(2, "monster_lookup_info_resize")
        body.width = 1000
        body.hooks[2](body)
        lu.assertTrue(group.width > 300)
        lu.assertAlmostEquals(drawn_scale(group), plain_scale(group.width, group.height), 1e-9)
    end

    local function reject_model_transforms(context)
        local ui = context.environment.ui
        local make_model = ui.Model.new
        ui.Model.new = function(parent)
            local model = make_model(parent)
            -- replaces the fixtures working one, like this client turning float vectors down
            rawset(model, "SetTransform", function()
                error("SetTransform requires a native integer vector")
            end)
            return model
        end
    end

    -- the transform only scales now, centring is the cameras job, so losing it costs the
    -- size match and nothing else
    function suite:test_a_rejected_transform_still_leaves_a_centred_turnable_scene()
        install_model_groups(self.context, true)
        reject_model_transforms(self.context)

        local group = assert(open_info(self.context))
        lu.assertIs(self.context.models[1].parent, group)
        lu.assertEquals(active_camera(group).lookAt.y, 70)
        lu.assertStrContains(
            table.concat(self.context.logs, "\n"),
            "preview skipped model transform"
        )

        group.hooks[4](group, 100, 50)
        group.hooks[ONHOLD](group, 140, 50)
        lu.assertTrue(active_camera(group).position.x > 0)
    end

    -- what the live client does: ui.ModelGroup but no ui.ModelCamera constructor in lua
    -- what the live client has: no ui.ModelCamera, a ui.ModelCameraInfo instead. this one is
    -- a plain record with fields and no setter methods, the preview has to cope with that
    function suite:test_a_model_camera_info_record_works_in_place_of_the_documented_camera()
        install_model_groups(self.context, false)
        local ui = self.context.environment.ui
        ui.ModelCamera = nil
        ui.ModelCameraInfo = {
            new = function()
                return { fov = 90 }
            end,
        }

        local group = assert(open_info(self.context))
        local camera = active_camera(group)
        lu.assertEquals(camera.fov, 40)
        lu.assertTrue(camera.useLookAt)
        lu.assertEquals(camera.lookAt, { x = 0, y = 70, z = 0 })
        lu.assertTrue(camera.position.z < 0)
        lu.assertEquals(camera.nearPlane, 10)

        group.hooks[4](group, 100, 50)
        group.hooks[ONHOLD](group, 140, 50)
        lu.assertTrue(active_camera(group).position.x > 0)
        local tooltip = self.context.tooltips[#self.context.tooltips]
        lu.assertStrContains(tooltip.options.text, "Drag to turn")
    end

    function suite:test_no_camera_type_at_all_keeps_the_plain_preview()
        install_model_groups(self.context, true)
        self.context.environment.ui.ModelCamera = nil
        open_info(self.context)

        lu.assertEquals(#self.context.groups, 0)
        lu.assertTrue(self.context.models[1].viewDistance > 0)
        lu.assertEquals(#self.context.logs, 0)
    end

    function suite:test_shift_drag_slides_the_view_and_keeps_the_new_centre_while_turning()
        install_model_groups(self.context, true)
        local shift = false
        self.context.environment.Keyboard = {
            IsAvailable = function()
                return true
            end,
            IsShiftDown = function()
                return shift
            end,
        }
        local group = open_info(self.context)
        local camera = active_camera(group)
        local start = distance(camera)

        shift = true
        group.hooks[4](group, 100, 50)
        group.hooks[ONHOLD](group, 300, 90)
        -- dragging down raises the target, so the model follows the mouse down
        lu.assertTrue(camera.lookAt.y > 70)
        lu.assertAlmostEquals(camera.position.x, 0, 1e-9)
        lu.assertAlmostEquals(distance(camera), start, 1e-6)
        group.hooks[ONRELEASE](group, 300, 90)

        -- without shift it turns again, round the new centre
        shift = false
        local raised = camera.lookAt.y
        group.hooks[4](group, 100, 50)
        group.hooks[ONHOLD](group, 140, 50)
        lu.assertTrue(camera.position.x > 0)
        lu.assertEquals(camera.lookAt.y, raised)
    end

    function suite:test_repeated_optional_feature_failures_are_only_logged_once()
        install_model_groups(self.context, true)
        reject_model_transforms(self.context)
        local preview = self.context.load_module("src/ui/info/preview")
        local info = { combat_level = 2 }

        local first = preview.create(self.context.parent, "Goblin", info)
        preview.destroy(first)
        local second = preview.create(self.context.parent, "Goblin", info)
        preview.destroy(second)

        local warnings = 0
        for _, message in ipairs(self.context.logs) do
            if message:find("preview skipped model transform", 1, true) then
                warnings = warnings + 1
            end
        end

        lu.assertEquals(warnings, 1)
    end

    local function live_npcs(context, entities)
        context.environment.NPCList = {
            ByUID = function(uid)
                return { entities[uid] }
            end,
            ByConfigID = function(npc_id)
                for _, entity in pairs(entities) do
                    if entity.configID == npc_id then
                        return { entity }
                    end
                end
                return {}
            end,
        }
    end

    function suite:test_a_live_npc_is_framed_by_its_real_size_and_remembered()
        install_model_groups(self.context, true)
        live_npcs(self.context, {
            [77] = { configID = 1, aabb = { width = 100, height = 600, length = 100 } },
        })
        self.context.subject.open({ name = "Goblin", npc_id = 1, entity_uid = 77 })
        self.context.subject.show_result({
            title = "Goblin",
            sections = {},
            info = { combat_level = 2 },
        })
        self.context.tabs:SetActive(2)
        local group = self.context.groups[1]
        local camera = active_camera(group)

        -- true size, centred on its real middle
        lu.assertEquals(self.context.models[1].transform.scale, { x = 1, y = 1, z = 1 })
        lu.assertEquals(camera.lookAt.y, 300)
        -- 600 tall filling 80% of the box: drawn height = 600 * focal / distance
        local focal = group.width / 2 / math.tan(math.rad(20))
        local across = math.sqrt(100 ^ 2 + 100 ^ 2)
        lu.assertAlmostEquals(
            600 * focal / (distance(camera) - across / 2),
            0.8 * group.height,
            1e-6
        )

        -- opened again later with nothing loaded nearby, it still knows the size
        self.context.environment.NPCList = nil
        self.context.tabs:SetActive(3)
        self.context.tabs:SetActive(2)
        lu.assertEquals(active_camera(self.context.groups[2]).lookAt.y, 300)
    end

    function suite:test_any_loaded_npc_with_the_same_id_is_measured_when_the_clicked_one_isnt()
        install_model_groups(self.context, true)
        live_npcs(self.context, {
            [5] = { configID = 99, aabb = { width = 1, height = 1, length = 1 } },
            [6] = { configID = 1, aabb = { width = 128, height = 200, length = 128 } },
        })
        self.context.subject.open({ name = "Goblin", npc_id = 1, entity_uid = 5 })
        self.context.subject.show_result({
            title = "Goblin",
            sections = {},
            info = { combat_level = 2 },
        })
        self.context.tabs:SetActive(2)

        lu.assertEquals(active_camera(self.context.groups[1]).lookAt.y, 100)
    end

    function suite:test_a_shift_drag_centre_is_kept_for_the_session_when_not_measured()
        install_model_groups(self.context, true)
        local shift = true
        self.context.environment.Keyboard = {
            IsAvailable = function()
                return true
            end,
            IsShiftDown = function()
                return shift
            end,
        }
        local group = open_info(self.context)
        group.hooks[4](group, 100, 50)
        group.hooks[ONHOLD](group, 100, 120)
        group.hooks[ONRELEASE](group, 100, 120)
        local chosen = active_camera(group).lookAt.y

        self.context.tabs:SetActive(3)
        self.context.tabs:SetActive(2)
        lu.assertAlmostEquals(active_camera(self.context.groups[2]).lookAt.y, chosen, 1e-9)
    end

    function suite:test_a_failed_scene_falls_back_to_the_plain_zoom_preview()
        install_model_groups(self.context, true)
        self.context.group_error = true
        open_info(self.context)

        local model = self.context.models[1]
        lu.assertNotNil(model)
        lu.assertTrue(model.viewDistance > 0)
        lu.assertEquals(#self.context.groups, 0)
        local logged = table.concat(self.context.logs, "\n")
        lu.assertStrContains(logged, "orbit preview failed")
        local tooltip = self.context.tooltips[#self.context.tooltips]
        lu.assertEquals(tooltip.options.text, "Scroll to zoom the monster preview.")
    end

    function suite:test_closing_the_tab_releases_the_scene()
        install_model_groups(self.context, true)
        local group = open_info(self.context)
        self.context.tabs:SetActive(3)
        lu.assertTrue(group.destroyed)
    end

    return suite
end
