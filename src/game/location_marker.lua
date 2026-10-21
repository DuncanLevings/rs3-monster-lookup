-- Button callbacks only change the desired destination. Native hints are changed
-- on Logic ticks, with a gap before replacement and fresh names for each target.
local location_map = require("src/data/location_map")
local clock = require("src/utils/cache_clock")
local map_symbol = require("src/game/map_symbol")

local marker = {}
local SUBSCRIPTION = "monster_lookup_location_marker"
local REPLACEMENT_GAP = 2
local CHECK_INTERVAL_TICKS = clock.TICKS_PER_SECOND
local ARRIVAL_RADIUS = 16
local ARROW_HEIGHT = 900
local desired, installed, retired, problem, ready_at, reached
local changed, paused, started = false, false, false
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

    entry.symbol = map_symbol.new(entry.area_name, target)
    return map_symbol.refresh(entry.symbol)
end

local function register(player_level, player_height)
    generation = generation + 1
    local entry = {
        target = desired.target,
        player_level = player_level,
        player_height = player_height,
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
    local target, reason = location_map.target(location)
    if not target then
        return nil, reason
    end
    if not available() then
        return nil, "Native location markers are unavailable on this client."
    end
    return target
end

function marker.reason(location)
    local _, reason = supported_target(location)
    return reason
end

function marker.mark(location, source_title)
    local target, reason = supported_target(location)
    if not target then
        return false, reason
    end
    if not world_ready() then
        return false, "Location markers are available outside instances while logged in."
    end

    local label = source_title .. " - " .. location.name
    if desired and same_target(desired.target, target) then
        desired.label = label
    else
        desired = { target = target, label = label }
        changed = true
    end

    problem, paused, reached = nil, false, nil
    notify()
    return true
end

function marker.clear()
    desired, problem, ready_at, reached = nil, nil, nil, nil
    changed, paused = true, false
    notify()
end

function marker.status()
    if problem then
        return problem
    end
    if reached then
        return "Arrived: " .. reached .. ". Marker cleared."
    end
    if desired then
        local prefix = paused and "Paused inside an instance or while the world loads: "
            or installed and same_target(installed.target, desired.target) and "Marked: "
            or "Updating marker: "
        return prefix .. desired.label
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

local function near_destination(target)
    if not Player or not Player.IsAvailable() then
        return false
    end
    local player = Player.GetEntity()
    local position = player and player.coordGrid
    if not position then
        return false
    end
    local dx, dz = position.x - target.x, position.z - target.z
    local nearby = position.level == target.level
        and dx * dx + dz * dz <= ARRIVAL_RADIUS * ARRIVAL_RADIUS
    return nearby, position.level, not nearby and destination_height(position) or nil
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
    if not requested and not ready_at and tick % CHECK_INTERVAL_TICKS ~= 0 then
        return
    end

    if not world_ready() then
        retire_current()
        ready_at = nil
        if not paused then
            paused = true
            notify()
        end
        return
    end

    local ok, nearby, player_level, player_height = pcall(near_destination, desired.target)
    if not ok then
        player_level, player_height = nil, nil
    end
    if ok and nearby then
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
        local elevation_changed = player_height ~= nil and player_height ~= installed.player_height
        if terrain_changed or floor_changed or elevation_changed then
            -- Native hints can retain their original terrain reference. Re-register
            -- on loading or climbing, without adding absolute height to the offset.
            retire_current()
            notify()
            return
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
    if ready_at and tick < ready_at then
        return
    end
    ready_at, paused = nil, false
    if available() then
        register(player_level, player_height)
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
    installed, desired, retired, problem, ready_at, reached = nil, nil, nil, nil, nil, nil
    changed, paused, tick = false, false, 0
    notify()
end

return marker
