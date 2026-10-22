-- Button callbacks only change the desired destination. Native hints are changed
-- on Logic ticks, with a gap before replacement and fresh names for each target.
local location_map = require("src/data/location_map")
local route = require("src/game/location_route")
local clock = require("src/utils/cache_clock")
local map_symbol = require("src/game/map_symbol")

local marker = {}
local SUBSCRIPTION = "monster_lookup_location_marker"
local REPLACEMENT_GAP = 2
local CHECK_INTERVAL_TICKS = clock.TICKS_PER_SECOND
local ARRIVAL_RADIUS = 16
local ARROW_HEIGHT = 900
local desired, installed, retired, problem, ready_at, reached, completed
local changed, paused, started = false, false, false
local pause_reason
local position_bucket, cached_position
local tick, generation = 0, 0
local listeners = {}

local function available()
    return HintList ~= nil
        and type(HintList.AddArrow) == "function"
        and type(HintList.RemoveArrow) == "function"
        and type(HintList.AddPolygon) == "function"
        and type(HintList.RemovePolygon) == "function"
        and CoordGrid ~= nil
        and CoordFine ~= nil
end

local function notify()
    for callback in pairs(listeners) do
        callback()
    end
end

local function remove_hints(entry)
    if not entry or not HintList then
        return
    end

    -- Only remove registrations which the client accepted. A partial failure
    -- must not try to remove an unregistered name from the native hint list.
    if entry.arrow_added and HintList.RemoveArrow then
        entry.arrow_added = false
        -- Keep a Lua frame between pcall and the client binding. Passing the
        -- binding itself as pcall's target is shared by the reported crashes.
        pcall(function()
            HintList.RemoveArrow(entry.arrow_name)
        end)
    end
    if entry.symbol then
        map_symbol.destroy(entry.symbol)
    end
end

local function retire_current()
    if not installed then
        return
    end

    -- Retain coordinate userdata across the replacement gap as well as keeping
    -- the native registrations apart. The client may still be finishing a frame.
    retired = { entry = installed, release_at = tick + REPLACEMENT_GAP }
    remove_hints(installed)
    installed = nil
    ready_at = retired.release_at
end

local function world_ready()
    return World and World.IsAvailable() and not World.IsRegion()
end

local function same_target(a, b)
    return a and b and a.level == b.level and a.x == b.x and a.z == b.z
end

local function destination_height(target)
    if not World or type(World.GetGroundHeight) ~= "function" then
        return nil
    end
    local ok, height, loaded = pcall(function()
        local value, success =
            World.GetGroundHeight(target.level, target.x * 512 + 256, target.z * 512 + 256)
        return value, success
    end)
    if
        ok
        and loaded == true
        and type(height) == "number"
        and height == height
        and height >= 0
        and height < math.huge
    then
        return height
    end
    return nil
end

local function add_hints(entry)
    local target = entry.target
    -- The native hint treats Y as an offset above terrain. Adding the sampled
    -- floor height here lifts the arrow twice; use samples only to trigger a refresh.
    entry.ground_height = destination_height(target)
    entry.fine =
        CoordFine.new(target.level, target.x * 512 + 256, ARROW_HEIGHT, target.z * 512 + 256)
    entry.arrow_added = HintList.AddArrow({
        name = entry.arrow_name,
        coordFine = entry.fine,
        arrowID = 0,
    }) == true
    if not entry.arrow_added then
        return false
    end

    entry.symbol = map_symbol.new(entry.area_name, target, entry.map_level)
    return map_symbol.refresh(entry.symbol)
end

local function register(player_level, player_height, position)
    generation = generation + 1
    local entry = {
        target = desired.target,
        map_level = desired.map_level,
        player_level = player_level,
        player_height = player_height,
        player_position = position,
        arrow_name = "monster_lookup_location_arrow_" .. generation,
        area_name = "monster_lookup_location_area_" .. generation,
    }
    local ok, accepted = pcall(add_hints, entry)
    if not ok or not accepted then
        remove_hints(entry)
        desired = nil
        problem = "The client could not create the location marker."
        if not ok then
            log("Monster Lookup location marker: " .. tostring(accepted))
        end
        return
    end

    installed = entry
end

local function supported_target(location)
    local resolution, reason = location_map.resolve(location)
    if not resolution then
        return nil, reason
    end
    if not available() then
        return nil, "Native location markers are unavailable on this client."
    end
    return resolution.target, nil, resolution
end

function marker.action(location)
    local _, reason, resolution = supported_target(location)
    return resolution and resolution.kind == "entrance" and "Entrance" or "Mark",
        reason or (resolution and resolution.tooltip),
        reason
end

function marker.reason(location)
    local _, reason = supported_target(location)
    return reason
end

-- compare the selected goal, not the current dungeon waypoint or native hint.
local function same_selection(location, source_title, resolution)
    if not desired or not resolution then
        return false
    end
    local same_interior = (not desired.goal.interior and not resolution.interior)
        or same_target(desired.goal.interior, resolution.interior)
    local selection = (source_title or desired.source) .. " - " .. (location.name or "Location")
    return desired.selection == selection
        and desired.goal.interior_map == resolution.interior_map
        and same_target(desired.goal.target, resolution.target)
        and same_interior == true
end

function marker.is_target(location, source_title)
    return same_selection(location, source_title, location_map.resolve(location))
end

function marker.mark(location, source_title)
    local target, reason, resolution = supported_target(location)
    if not target or not resolution then
        return false, reason
    end
    if not world_ready() then
        return false, "Location markers are available outside instances while logged in."
    end

    local label = source_title .. " - " .. resolution.label
    local selection = source_title .. " - " .. (location.name or "Location")
    if not same_selection(location, source_title, resolution) then
        desired = {
            goal = resolution,
            selection = selection,
            source = source_title,
            target = target,
            label = label,
            map_level = 0,
            -- Allow the next periodic position snapshot to replace a cached
            -- snapshot from the preceding selection before automatic completion.
            confirm_after = tick + CHECK_INTERVAL_TICKS,
        }
        changed = true
    end

    problem, paused, reached, completed = nil, false, nil, nil
    notify()
    return true
end

function marker.clear()
    desired, problem, ready_at, reached, completed = nil, nil, nil, nil, nil
    changed, paused, pause_reason = true, false, nil
    notify()
end

function marker.status()
    if problem then
        return problem
    end
    if reached then
        return "Arrived: " .. reached .. ". Marker cleared."
    end
    if completed then
        return completed
    end
    if desired then
        if paused and pause_reason then
            return "Paused: " .. pause_reason .. ".\nDestination: " .. desired.selection, true
        end
        local prefix = paused and "Paused inside an instance or while the world loads: "
            or installed and same_target(installed.target, desired.target) and "Marked: "
            or "Updating marker: "
        return prefix .. desired.label, paused
    end
    return available() and "Select Mark, then open and pan the game map to the destination."
        or "Native location markers are unavailable on this client."
end

function marker.has_target()
    return desired ~= nil
end

function marker.subscribe(callback)
    listeners[callback] = true
    return function()
        listeners[callback] = nil
    end
end

local function player_position()
    local bucket = math.floor(tick / CHECK_INTERVAL_TICKS)
    if position_bucket == bucket then
        return cached_position
    end
    position_bucket, cached_position = bucket, nil
    if not Player or not Player.IsAvailable() then
        return nil
    end
    local player = Player.GetEntity()
    local position = player and player.coordGrid
    if position then
        -- Retain a value snapshot, not entity userdata that can move between checks.
        cached_position = { level = position.level, x = position.x, z = position.z }
    end
    return cached_position
end

local function near_destination(target, position)
    local dx, dz = position.x - target.x, position.z - target.z
    local nearby = position.level == target.level
        and dx * dx + dz * dz <= ARRIVAL_RADIUS * ARRIVAL_RADIUS
    return nearby, position.level, not nearby and destination_height(position) or nil
end

local function pause_navigation(reason)
    retire_current()
    ready_at = nil
    if not paused or pause_reason ~= reason then
        paused, pause_reason = true, reason
        notify()
    end
end

local function update()
    tick = tick + 1
    if retired and tick >= retired.release_at then
        retired = nil
    end

    local requested = changed
    if changed then
        changed = false
        retire_current()
        if not desired then
            ready_at = nil
            return
        end
    end

    if not desired then
        return
    end
    -- nothing can be installed during the native replacement gap. wait before
    -- routing or sampling terrain, then validate the destination when it ends.
    if ready_at and tick < ready_at then
        return
    end
    if not requested and not ready_at and tick % CHECK_INTERVAL_TICKS ~= 0 then
        return
    end

    if not world_ready() then
        position_bucket, cached_position = nil, nil
        pause_navigation(nil)
        return
    end

    local position_ok, position = pcall(player_position)
    if not position_ok then
        position = nil
    end
    local routed, step, reason, outcome = pcall(route.next, desired.goal, position)
    if
        routed
        and not step
        and outcome == "interior_unavailable"
        and tick >= desired.confirm_after
    then
        completed = "Dungeon entered. Interior guidance unavailable; marker cleared."
        desired, problem, ready_at, reached = nil, nil, nil, nil
        paused, pause_reason = false, nil
        -- Use the same tick-owned removal path as normal arrival and replacement.
        retire_current()
        notify()
        return
    end
    if not routed or not step then
        pause_navigation(routed and reason or "Navigation is temporarily unavailable")
        return
    end
    local label = desired.source .. " - " .. step.label
    local status_changed = paused or desired.label ~= label
    paused, pause_reason, desired.label = false, nil, label
    desired.target, desired.map_level = step.target, step.map_level
    if
        installed
        and (
            not same_target(installed.target, desired.target)
            or installed.map_level ~= desired.map_level
        )
    then
        retire_current()
        notify()
        return
    end
    if status_changed then
        notify()
    end
    local ok, nearby, player_level, player_height =
        pcall(near_destination, desired.target, position)
    if not ok then
        player_level, player_height = nil, nil
    end
    if ok and nearby and step.final then
        reached = desired.label
        desired, problem = nil, nil
        paused = false
        retire_current()
        ready_at = nil
        notify()
        return
    end

    if installed then
        local height = destination_height(installed.target)
        local terrain_changed = height ~= nil and height ~= installed.ground_height
        local floor_changed = player_level ~= nil and player_level ~= installed.player_level
        -- moving onto a slope changes ground height without changing floors.
        -- only a height change at the same tile means its terrain reference changed.
        local elevation_changed = same_target(installed.player_position, position)
            and player_height ~= nil
            and player_height ~= installed.player_height
        if terrain_changed or floor_changed or elevation_changed then
            -- Native hints can retain their original terrain reference. Re-register
            -- on loading or climbing, without adding absolute height to the offset.
            retire_current()
            notify()
            return
        end
        installed.player_position = position
        if player_height ~= nil then
            installed.player_height = player_height
        end
        local refreshed, visible = pcall(map_symbol.refresh, installed.symbol)
        local next_problem = not (refreshed and visible)
                and "The map symbol could not update. The navigation arrow is still active."
            or nil
        if problem ~= next_problem then
            problem = next_problem
            notify()
        end
        return
    end
    ready_at, paused = nil, false
    if available() then
        register(player_level, player_height, position)
    else
        desired = nil
        problem = "Native location markers are unavailable on this client."
    end
    notify()
end

function marker.start()
    if started then
        return
    end
    started = true
    Event.Logic.Subscribe(SUBSCRIPTION, update)
end

function marker.stop()
    Event.Logic.Unsubscribe(SUBSCRIPTION)
    started = false
    -- Shutdown must release accepted hints before the plugin's callbacks disappear.
    remove_hints(installed)
    installed, desired, retired, problem, ready_at, reached, completed =
        nil, nil, nil, nil, nil, nil, nil
    changed, paused, tick, pause_reason = false, false, 0, nil
    position_bucket, cached_position = nil, nil
    notify()
end

return marker
