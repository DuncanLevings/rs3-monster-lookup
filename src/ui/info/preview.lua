-- the monster model on the Monster info tab, standing still. the bundle already knows each
-- pages npc ids so the client draws it from its own model, no images or wiki requests
--
-- when the client has model groups the model sits in its own little scene with a camera
-- that orbits it: drag to turn it round or tilt it, scroll to zoom. without them (or if the
-- scene fails to set up) its the plain model from before, zoom only

local numbers = require("src/utils/numbers")

local preview = {}
local saved_zoom = {}
-- real sizes read off live NPCs, by npc id, so a monster seen once frames right later too
local measured = {}
-- shift+drag centres the player chose, by npc id, for monsters that couldnt be measured
local saved_centre = {}
local states = setmetatable({}, { __mode = "k" })
local reported = {}

-- a missing optional feature would be missing for every monster, so each is logged once
-- per session
local function report_once(key, message)
    if not reported[key] then
        reported[key] = true
        log("Monster Lookup: " .. message)
    end
end

-- field of view for the orbit camera, narrow enough that models dont look stretched
local FOV = 40
-- radians turned per interface unit dragged, a drag across the preview is about one spin
local TURN_PER_UNIT = 0.02
-- tilt stops about 35 degrees above or below level, past that you mostly see the floor
local TILT_LIMIT = 0.6
-- model groups draw larger than the standalone renderer at the same framing.
-- this calibrated scale keeps their apparent size and origin consistent.
local SCENE_SCALE = 1 / 1.75
-- a measured models real height takes up this much of the box
local FILL = 0.8

-- how tall a monster is, from where the game draws its health bar: the npcs own overlay
-- height, else its animation sets. both are -1 for most monsters (amascut, dragons, dharok,
-- chickens), then the game works it out from the model at draw time and plugins cant see it,
-- so the tile size guess is all there is for those
local function overlay_height(npc)
    if numbers.is_positive(npc.overlayHeight) then
        return npc.overlayHeight
    end

    local ok, height = pcall(function()
        return npc.bas and npc.bas.overlayHeight
    end)

    if ok and numbers.is_positive(height) then
        return height
    end
end

local function framing(npc, size)
    local bounds = npc.hasCustomBounding and npc.customBounding
    if
        bounds
        and numbers.is_positive(bounds.width)
        and numbers.is_positive(bounds.height)
        and numbers.is_positive(bounds.length)
    then
        local centre = bounds.centre
        return {
            width = bounds.width,
            height = bounds.height,
            depth = bounds.length,
            x = -centre.x,
            y = -centre.y,
            z = -centre.z,
        }
    end

    -- the plain renderer cant tell us how big the model is, so height and footprint are
    -- guesses from the tile size. it grows with the tile size itself (not its square root)
    -- so big bosses get more room instead of being cut off
    local known = overlay_height(npc)
    local height = known or (256 * size)
    return {
        width = 128 * size,
        height = height,
        depth = 128 * size,
        x = 0,
        -- the overlay height has room above the head in it, so its middle sits too low on
        -- the body. a bit lower than half leaves some space under the feet as well
        y = height * 0.35,
        z = 0,
        -- no overlay height anywhere means the height is just a guess from the tile size
        guessed = known == nil,
    }
end

-- where the orbit scene centres a model, y up from its feet. a real overlay height or
-- custom bounds frames fine with the plain previews point (chickens look spot on). a height
-- guessed from tile size is often short of the real model (amascut came out taller than her
-- 3 tiles x 256), so those centre on the middle of the guess to leave room above the head
local function scene_centre_y(state)
    if state.guessed then
        return state.height * 0.5
    end

    return state.y
end

-- how far the legacy renderer draws pixels per unit at view distance d: LEGACY_FOCAL / d
local LEGACY_FOCAL = 256

-- view distance for the plain renderer. the orbit preview converts this same number into
-- its camera distance, so both frame a monster the same way
local function legacy_distance(state, width, height)
    -- only the previews own box counts, the variant picker and notes sit outside it
    local aspect = math.max(0.5, width / math.max(1, height))
    local extent = math.max(state.height, state.width / aspect)
    -- 0.72 was tuned by eye on Goblin and Vorago. with a focal of 512 instead both only
    -- filled half the box
    return extent * LEGACY_FOCAL / (math.max(1, height) * 0.72) + state.depth / 2
end

local function fit(component, width, height)
    local state = states[component]
    if not state then
        return
    end

    local distance = legacy_distance(state, width, height)
    state.distance = distance
    component.viewDistance = math.floor(distance * state.zoom)
end

local function valid_id(value)
    return type(value) == "number" and value >= 0 and value < 2147483647 and value % 1 == 0
end

-- the live NPCs bounding box when one is loaded nearby: the one that was clicked, else any
-- with the same id. its the models real size, the config only has a tile count to guess from
local function live_bounds(selection, npc_id)
    if not NPCList then
        return nil
    end

    local ok, bounds = pcall(function()
        local entities = {}

        if selection and selection.entity_uid then
            entities = NPCList.ByUID(selection.entity_uid) or {}
        end

        local entity = entities[1]

        if not entity or entity.configID ~= npc_id then
            entity = (NPCList.ByConfigID(npc_id) or {})[1]
        end

        local box = entity and entity.aabb

        if
            box
            and numbers.is_positive(box.width)
            and numbers.is_positive(box.height)
            and numbers.is_positive(box.length)
        then
            return { width = box.width, height = box.height, depth = box.length }
        end
    end)

    return ok and bounds or nil
end

-- zoom is a multiplier on the framed distance: 1 is the starting framing, 2 is twice as
-- far away. callers can narrow or widen that, see ModelOptions in model.lua
local DEFAULT_ZOOM_MIN, DEFAULT_ZOOM_MAX = 1, 2

local function zoom_limits(state, options)
    state.zoom_min = options.zoom_min or DEFAULT_ZOOM_MIN
    state.zoom_max = math.max(state.zoom_min, options.zoom_max or DEFAULT_ZOOM_MAX)
    state.scroll_zoom = options.scroll_zoom ~= false
end

local function clamp_zoom(state, value)
    return math.max(state.zoom_min, math.min(state.zoom_max, value))
end

---@param options table? zoom_min, zoom_max, scroll_zoom, turn (see ModelOptions in model.lua)
function preview.create(parent, title, info, selection, on_zoom, options)
    options = options or {}

    if not ui.Model or not ui.ModelType or not config.NPC then
        report_once("model_api", "preview unavailable; this client has no NPC model API.")
        return nil
    end

    local level = tonumber(info.combat_level)
    local candidates = {}
    if selection and valid_id(selection.npc_id) then
        candidates[1] = selection.npc_id
    end

    for _, npc_id in ipairs(require("src/data/core").npc_ids(title)) do
        candidates[#candidates + 1] = npc_id
    end

    -- only this pages own npc ids are checked, never a search through every npc config
    -- for the name. capped too, some pages have loads of cosmetic variants
    local chosen, size, chosen_npc

    for index = 1, math.min(#candidates, 64) do
        local npc_id = candidates[index]
        local ok, npc = pcall(function()
            return config.NPC.FromID(npc_id)
        end)
        if ok and npc and (not level or npc.visibleCombatLevel == level) then
            chosen, size = npc_id, math.max(1, npc.gridSize or 1)
            chosen_npc = npc
            break
        end
    end

    if not chosen then
        -- new or excluded monsters may have no bundled model identity; stats still work.
        return nil
    end

    measured[chosen] = live_bounds(selection, chosen) or measured[chosen]
    local scene = options.turn ~= false
        and preview.create_scene(parent, title, chosen, chosen_npc, size, on_zoom, options)

    if scene then
        return scene
    end

    local component
    local ok, problem = pcall(function()
        component = ui.Model.new(parent)
        component:SetSize(300, 210)
        component.clickthrough = false
        component.enabled = true
        component.animID = -1
        component:SetModel(ui.ModelType.NPC_MODEL, chosen)
        local state = framing(chosen_npc, size)
        state.npc_id, state.size = chosen, size
        zoom_limits(state, options)
        state.zoom = clamp_zoom(state, saved_zoom[chosen] or 1)
        states[component] = state
        fit(component, 300, 210)
        -- the docs say Vector3 but this client gives whole number vectors here, so its
        -- changed in place to keep whatever type the client uses
        local offset = component.worldOffset
        -- npcs stand on their origin, moving it below the middle of the box leaves room
        -- for the rest of the body
        offset.x, offset.y, offset.z = math.floor(state.x), math.floor(state.y), math.floor(state.z)
        component.worldOffset = offset
        -- only runs on a scroll, nothing updates per frame. the tile size gives a decent
        -- starting distance and zoom sorts out monsters that are unusually short or tall
        if state.scroll_zoom then
            component:Subscribe(
                ui.Hook.ONSCROLLWHEEL,
                "monster_lookup_preview_zoom",
                function(_, delta)
                    if on_zoom then
                        on_zoom()
                    end

                    if type(delta) == "number" and delta ~= 0 then
                        local factor = delta > 0 and 1.08 or 1 / 1.08
                        state.zoom = clamp_zoom(state, state.zoom * factor)
                        component.viewDistance = math.floor(state.distance * state.zoom)
                    end
                    saved_zoom[chosen] = state.zoom
                    return false
                end
            )
        end
    end)
    if not ok then
        report_once("model:" .. chosen, "preview failed for " .. title .. ": " .. tostring(problem))
        if component then
            states[component] = nil
            component:Destroy()
        end

        return nil
    end

    return component
end

-- extras that only make it look nicer. one failing on this client shouldnt cost the whole
-- scene, so its logged once and skipped
local function optional(name, action)
    local ok, problem = pcall(action)

    if not ok then
        report_once("optional:" .. name, "preview skipped " .. name .. ". " .. tostring(problem))
    end

    return ok
end

-- the docs call the camera type ui.ModelCamera with SetFOV/SetPosition style methods. this
-- client has it as ui.ModelCameraInfo instead, which might be a plain record, so each
-- setting uses the method when theres one and the field when there isnt
local function camera_type()
    return ui.ModelCamera or ui.ModelCameraInfo
end

local function has_method(camera, name)
    local ok, value = pcall(function()
        return camera[name]
    end)
    return ok and type(value) == "function"
end

local function set_camera(camera, method, field, value, ...)
    if has_method(camera, method) then
        camera[method](camera, value, ...)
    else
        camera[field] = value
    end
end

local function blank_camera()
    local kind = camera_type()
    return type(kind.new) == "function" and kind.new() or kind()
end

-- world units per interface unit at the models depth, so dragging and the lift below stay
-- the same on screen at any zoom
local function units_per_pixel(state)
    local focal = math.max(1, state.box_width) / 2 / math.tan(math.rad(FOV) / 2)
    return state.distance * state.zoom / focal
end

-- guessed heights need extra headroom for tall 1-3 tile monsters. larger footprints
-- tend to be long, low creatures. measured models need neither adjustment.
local LIFT_BY_TILES = { [1] = 0.15, [2] = 0.15, [3] = 0.2 }

local function lift(state)
    if state.measured or not state.guessed then
        return 0
    end

    return LIFT_BY_TILES[state.size] or 0
end

local function place_camera(camera, state)
    -- model groups use y-up, unlike the standalone model's world offset.
    local distance = state.distance * state.zoom
    local level = math.cos(state.pitch) * distance
    local raise = lift(state) * state.box_height * units_per_pixel(state)
    local target = { x = state.target.x, y = state.target.y + raise, z = state.target.z }
    local position = Vector3.new(
        target.x + math.sin(state.yaw) * level,
        target.y + math.sin(state.pitch) * distance,
        target.z - math.cos(state.yaw) * level
    )
    set_camera(camera, "SetPosition", "position", position, 0)
    set_camera(camera, "SetLookAt", "lookAt", Vector3.new(target.x, target.y, target.z), 0)
    optional("clip planes", function()
        local far = distance * 2 + state.radius * 4

        if has_method(camera, "SetClipPlanes") then
            camera:SetClipPlanes(10, far)
        else
            camera.nearPlane, camera.farPlane = 10, far
        end
    end)
end

local function new_camera(state)
    local camera = blank_camera()
    set_camera(camera, "SetFOV", "fov", FOV, 0)
    camera.useLookAt = true
    -- see through to the info tab behind, like the plain model
    optional("clear background", function()
        camera.clearColour = Vector4.new(0, 0, 0, 0)
    end)
    place_camera(camera, state)
    return camera
end

-- the docs only promise copies back from the group (GetCamera, activeCamera), so it might
-- keep the camera it was given or a copy of it. this checks once which, by nudging the
-- field of view and reading it back
local function group_keeps_camera(state)
    local ok, kept = pcall(function()
        set_camera(state.camera, "SetFOV", "fov", FOV + 1, 0)
        local active = state.group.activeCamera
        local result = active ~= nil and math.abs(active.fov - (FOV + 1)) < 0.01
        set_camera(state.camera, "SetFOV", "fov", FOV, 0)
        return result
    end)
    return ok and kept
end

-- NONE is the first value in the docs, so 0 when the client doesnt expose the enum to lua
local function no_transition()
    return ui.ModelCameraTransition and ui.ModelCameraTransition.NONE or 0
end

local function update_camera(state)
    if state.live_camera then
        place_camera(state.camera, state)
        return
    end

    -- its a copy, so swap a freshly placed camera in and drop the old one
    local camera = new_camera(state)
    local index = state.group:AddCamera(camera)
    state.group:SwitchCamera(index, no_transition(), -1, 0)
    state.group:DeleteCamera(state.camera_index)
    state.camera, state.camera_index = camera, index
end

-- the plain preview got the size right for nearly everything since its distance was
-- tuned by eye, where the box estimate on its own came out too small for amascut. so this
-- reuses that distance and swaps its scale for the cameras: the legacy renderer draws
-- LEGACY_FOCAL / d pixels per unit, a camera draws (width / 2 / tan(fov / 2)) / d. the fov
-- goes across the width on this client, measured from amascut in game (vertical would have
-- drawn her about a fifth smaller than she came out)
local function orbit_distance(state, width, height)
    local focal = math.max(1, width) / 2 / math.tan(math.rad(FOV) / 2)

    -- a real size frames itself: back far enough that the height fills FILL of the box and
    -- the footprint, which can face the camera any way round, fits across it
    if state.measured then
        local across = math.sqrt(state.width ^ 2 + state.depth ^ 2)
        local tall = state.height * focal / (FILL * math.max(1, height))
        local wide = across * focal / (FILL * math.max(1, width))
        return math.max(tall, wide) + across / 2
    end

    return legacy_distance(state, width, height) * focal / LEGACY_FOCAL
end

local function shift_down()
    local ok, down = pcall(function()
        return Keyboard.IsAvailable() and Keyboard.IsShiftDown()
    end)
    return ok and down == true
end

local function subscribe_controls(state, on_interact)
    local group = state.group

    if state.scroll_zoom then
        group:Subscribe(ui.Hook.ONSCROLLWHEEL, "monster_lookup_preview_zoom", function(_, delta)
            if on_interact then
                on_interact()
            end

            if type(delta) == "number" and delta ~= 0 then
                local factor = delta > 0 and 1.08 or 1 / 1.08
                state.zoom = clamp_zoom(state, state.zoom * factor)
                update_camera(state)
            end
            saved_zoom[state.npc_id] = state.zoom
            return false
        end)
    end

    -- older clients without these hooks still get zoom
    if not ui.Hook.ONHOLD or not ui.Hook.ONRELEASE then
        return
    end

    group:Subscribe(ui.Hook.ONCLICK, "monster_lookup_preview_turn", function(_, x, y)
        state.drag = {
            x = x,
            y = y,
            yaw = state.yaw,
            pitch = state.pitch,
            target_y = state.target.y,
        }
        return false
    end)
    group:Subscribe(ui.Hook.ONHOLD, "monster_lookup_preview_turn", function(_, x, y)
        local drag = state.drag
        if not drag or type(x) ~= "number" or type(y) ~= "number" then
            return false
        end

        if on_interact then
            on_interact()
        end

        if shift_down() then
            -- shift slides the view up and down instead, the model follows the mouse
            drag.panned = true
            state.target.y = drag.target_y + (y - drag.y) * units_per_pixel(state)
        else
            state.yaw = drag.yaw + (x - drag.x) * TURN_PER_UNIT
            state.pitch = math.max(
                -TILT_LIMIT,
                math.min(TILT_LIMIT, drag.pitch + (y - drag.y) * TURN_PER_UNIT)
            )
        end
        update_camera(state)
        return false
    end)
    group:Subscribe(ui.Hook.ONRELEASE, "monster_lookup_preview_turn", function()
        local drag = state.drag
        state.drag = nil
        if drag and drag.panned and not state.measured then
            saved_centre[state.npc_id] = state.target.y
        end

        return false
    end)
end

local function model_scale(state)
    return state.measured and 1 or SCENE_SCALE
end

---the orbiting preview, nil when the client has no model groups or the scene cant be made
function preview.create_scene(parent, title, npc_id, npc, size, on_interact, options)
    options = options or {}

    if not ui.ModelGroup or not camera_type() then
        -- a standalone model is the supported fallback on older clients.
        return nil
    end

    local group
    local ok, problem = pcall(function()
        local state = framing(npc, size)
        local real = measured[npc_id]

        if real then
            state.width, state.height, state.depth = real.width, real.height, real.depth
            state.x, state.z = 0, 0
            state.measured, state.guessed = true, false
        end

        state.npc_id, state.size = npc_id, size
        zoom_limits(state, options)
        state.zoom = clamp_zoom(state, saved_zoom[npc_id] or 1)
        state.yaw, state.pitch = 0, 0
        state.radius = math.sqrt(state.width ^ 2 + state.height ^ 2 + state.depth ^ 2) / 2
        state.box_width, state.box_height = 300, 210
        state.distance = orbit_distance(state, 300, 210)
        -- the camera aims at the models middle and circles round it, the model itself stays
        -- at the origin. moving the model with SetTransform did nothing on this client (two
        -- different centres drew amascut in the exact same spot), only its scale took
        state.target = {
            x = -state.x,
            -- the real middle when measured, else the estimate or what shift+drag picked
            y = state.measured and state.height / 2 or saved_centre[npc_id] or scene_centre_y(
                state
            ),
            z = -state.z,
        }

        group = ui.ModelGroup.new(parent)
        group:SetSize(300, 210)
        group.clickthrough = false
        group.enabled = true
        state.group = group
        state.camera = new_camera(state)
        state.camera_index = group:AddCamera(state.camera)
        group:SwitchCamera(state.camera_index, no_transition(), -1, 0)
        state.live_camera = group_keeps_camera(state)

        local model = ui.Model.new(group)
        model:SetSize(300, 210)
        -- the group takes the mouse, the model inside just draws
        model.clickthrough = true
        model.animID = -1
        model:SetModel(ui.ModelType.NPC_MODEL, npc_id)
        -- drawn at the plain previews size, see SCENE_SCALE. centring is the cameras job
        optional("model transform", function()
            model:SetTransform(
                Vector3.new(0, 0, 0),
                Vector3.new(0, 0, 0),
                -- measured models are drawn true size, the estimate needs the plain size match
                Vector3.new(model_scale(state), model_scale(state), model_scale(state)),
                0
            )
        end)
        state.model = model
        states[group] = state
        subscribe_controls(state, on_interact)
    end)

    if not ok then
        report_once(
            "scene:" .. npc_id,
            "orbit preview failed for " .. title .. ", using the plain one. " .. tostring(problem)
        )
        if group then
            states[group] = nil
            group:Destroy()
        end

        return nil
    end

    return group
end

function preview.resize(component, width, height)
    component:SetSize(width, height)
    local state = states[component]

    if state and state.group then
        state.model:SetSize(width, height)
        state.box_width, state.box_height = width, height
        state.distance = orbit_distance(state, width, height)
        update_camera(state)
        return
    end

    fit(component, width, height)
end

---true when this preview can be dragged round, not just zoomed
function preview.can_turn(component)
    local state = states[component]
    return state ~= nil and state.group ~= nil and ui.Hook.ONHOLD ~= nil
end

function preview.destroy(component)
    states[component] = nil
    component:Destroy()
end

return preview
