-- the Mark / Entrance buttons on the Locations tab. marking a location shows a native
-- arrow over the spot in game and an X on the world map, and walks you there a step at a
-- time when its inside a dungeon (route.lua picks each step)
--
-- how it fits together:
--   - the buttons only ever change desired, what the player asked for
--   - everything touching the clients hint list happens on Logic ticks in update(), never
--     straight from a button callback
--   - installed is what the client is showing right now. replacing it retires the old one
--     and waits REPLACEMENT_GAP ticks before adding the new one, and every new arrow gets a
--     fresh name, the client didnt cope with reusing a name straight away
--   - listeners (the Locations tab) get told whenever status() would say something new

local location_map = require("src/data/locations/resolve")
local route = require("src/game/locations/route")
local clock = require("src/utils/cache_clock")
local map_symbol = require("src/game/locations/symbol")

local marker = {}
local SUBSCRIPTION = "monster_lookup_location_marker"
-- ticks between removing a hint and adding its replacement
local REPLACEMENT_GAP = 2
-- the player position and terrain are only checked this often
local CHECK_INTERVAL_TICKS = clock.TICKS_PER_SECOND
-- within this many tiles of the last step counts as arrived
local ARRIVAL_RADIUS = 16
-- how high above the ground the arrow floats
local ARROW_HEIGHT = 900
local UNAVAILABLE = "Native location markers are unavailable on this client."

-- what the player asked for: the goal, its label and the current step towards it
local desired
-- the hints the client is showing now, nil when none
local installed
-- the last installed hints, kept alive until the replacement gap is over
local retired
-- an error to show instead of the normal status
local problem
-- tick the next hints can go in, nil when theres no gap to wait out
local ready_at
-- label of the destination just reached, for the "Arrived" status
local reached
-- status to show after the marker cleared itself for another reason
local completed
-- desired was changed by a button, the next tick has to swap the hints
local changed = false
-- inside an instance or while the world loads, no hints until thats over
local paused = false
local pause_reason
local started = false
-- the player position is read once per CHECK_INTERVAL_TICKS, these hold that reading
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

-- "Goblin - Lumbridge", what the player picked. stays the same while the steps change
local function selection_name(source_title, location)
    return source_title .. " - " .. (location.name or "Location")
end

local function remove_hints(entry)
    if not entry or not HintList then
        return
    end

    -- only remove what the client actually accepted, if adding failed part way theres
    -- nothing registered under that name to remove
    if entry.arrow_added and HintList.RemoveArrow then
        entry.arrow_added = false

        -- wrapped in a function, passing the client call straight to pcall is what the
        -- reported crashes had in common
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

    -- the old entry (and its coordinate objects) is kept through the gap as well, the client
    -- might still be finishing a frame with them
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

-- ground height at a tile, nil when that part of the map isnt loaded
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

    -- the arrows height is already above the ground, adding the ground height lifted it
    -- twice. the height is only saved to notice when the terrain changes (see update)
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
            log("Monster Lookup: location marker failed. " .. tostring(accepted))
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
        return nil, UNAVAILABLE
    end

    return resolution.target, nil, resolution
end

---the button text for a location, its tooltip, and why it cant be marked if it cant
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

-- compares what was picked, not the dungeon step its on or the hints showing right now
local function same_selection(location, source_title, resolution)
    if not desired or not resolution then
        return false
    end

    local same_interior = (not desired.goal.interior and not resolution.interior)
        or same_target(desired.goal.interior, resolution.interior)
    local selection = selection_name(source_title or desired.source, location)

    return desired.selection == selection
        and desired.goal.interior_map == resolution.interior_map
        and same_target(desired.goal.target, resolution.target)
        and same_interior == true
end

function marker.is_target(location, source_title)
    return same_selection(location, source_title, location_map.resolve(location))
end

---asks for a location to be marked, the hints follow on the next tick
---@return boolean marked
---@return string? reason why it couldnt be
function marker.mark(location, source_title)
    local target, reason, resolution = supported_target(location)

    if not target or not resolution then
        return false, reason
    end

    if not world_ready() then
        return false, "Location markers are available outside instances while logged in."
    end

    if not same_selection(location, source_title, resolution) then
        desired = {
            goal = resolution,
            selection = selection_name(source_title, location),
            source = source_title,
            target = target,
            label = source_title .. " - " .. resolution.label,
            map_level = 0,
            -- arriving isnt checked until the next position reading, the one saved might
            -- still be from before this was picked
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

---what the Locations tab shows above the list
---@return string text
---@return boolean? attention true when it needs the player to notice (paused)
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
        or UNAVAILABLE
end

function marker.has_target()
    return desired ~= nil
end

---calls back whenever the status changes, returns a function that stops it
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
        -- copy the numbers out, the client object can change under us between checks
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

-- the route got into the dungeon but cant guide you any further inside, so the marker
-- clears itself and says why
local function finish_at_interior()
    log("Monster Lookup: marker cleared, no guidance inside " .. desired.selection)
    completed = "Dungeon entered. Interior guidance unavailable; marker cleared."
    desired, problem, ready_at, reached = nil, nil, nil, nil
    paused, pause_reason = false, nil
    -- removed the same way as arriving or replacing, on this tick
    retire_current()
    notify()
end

local function arrive()
    reached = desired.label
    desired, problem = nil, nil
    paused = false
    retire_current()
    ready_at = nil
    notify()
end

-- for hints already showing. true when they have to be put in again (the next tick does),
-- else keeps the map X up to date
local function needs_reinstall(position, player_level, player_height)
    local height = destination_height(installed.target)
    local terrain_changed = height ~= nil and height ~= installed.ground_height
    local floor_changed = player_level ~= nil and player_level ~= installed.player_level
    -- walking onto a slope changes the ground height without changing floor, only a height
    -- change on the same tile means the ground the arrow is measured from changed
    local elevation_changed = same_target(installed.player_position, position)
        and player_height ~= nil
        and player_height ~= installed.player_height

    if terrain_changed or floor_changed or elevation_changed then
        -- the client can keep measuring a hint from the ground it was added on, so after
        -- loading in or climbing its put in again
        return true
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

    return false
end

-- runs every tick: swaps hints after a button press, follows the route a step at a time,
-- notices arriving, and puts hints back in when the ground under them changes
local function update()
    tick = tick + 1

    if retired and tick >= retired.release_at then
        retired = nil
    end

    -- a button changed desired, take down whats showing first
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

    -- nothing goes in during the replacement gap, so dont route or read terrain until its
    -- over. the destination gets checked again then
    if ready_at and tick < ready_at then
        return
    end

    -- otherwise only once a second, unless a button just asked for something
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

    -- which step of the route to point at now
    local routed, step, reason, outcome = pcall(route.next, desired.goal, position)

    if
        routed
        and not step
        and outcome == "interior_unavailable"
        and tick >= desired.confirm_after
    then
        finish_at_interior()
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

    -- moved on to another step, the hints for the old one come down first
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
        arrive()
        return
    end

    if installed then
        if needs_reinstall(position, player_level, player_height) then
            retire_current()
            notify()
        end

        return
    end

    -- nothing showing yet (first tick, or the gap just ended), put the hints in
    ready_at, paused = nil, false

    if available() then
        register(player_level, player_height, position)
    else
        desired = nil
        problem = UNAVAILABLE
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
    -- the hints have to go before the plugin does, the client would keep showing them
    remove_hints(installed)
    installed, desired, retired, problem, ready_at, reached, completed =
        nil, nil, nil, nil, nil, nil, nil
    changed, paused, tick, pause_reason = false, false, 0, nil
    position_bucket, cached_position = nil, nil
    notify()
end

return marker
