-- sits between whatever shows a monster and the wiki lookup, decides whether saved data is
-- good enough or a new fetch is needed. saved data is shown straight away even when its due
-- a refresh, then swapped for the new result when it arrives (or kept if the refresh fails).
-- monsters in the bundled data are answered before any of that, with no request at all
--
-- every caller gets its own handle (service.new_handle). a handle follows one monster at a
-- time, picking another or cancelling only touches that handle. the wiki lookups behind them
-- are shared per monster (flights below), so two handles asking for the same monster send one
-- set of requests, and the result is saved once. service.fetch / service.cancel are a default
-- handle, what the standard window and settings use

local core = require("src/data/core")
local wiki_lookup = require("src/data/wiki/lookup")
local cache = require("src/data/lookup/cache")
local clock = require("src/utils/cache_clock")

local service = {}

local failures = {}
local RETRY_SECONDS = 60
local REFRESH_MINUTES = 14 * 24 * 60
-- every handle not yet destroyed, so stop() can cancel them all
local handles = setmetatable({}, { __mode = "k" })

local function remember_failure(key, problem)
    if problem:find("HTTP access permission", 1, true) then
        return
    end

    local now = clock.elapsed()

    for saved_key, failure in pairs(failures) do
        if now >= failure.retry_at then
            failures[saved_key] = nil
        end
    end

    failures[key] = { problem = problem, retry_at = now + RETRY_SECONDS }
end

-- what the window shows for a monster the bundle knows about but left out: no drops at all,
-- or a kind of monster Monster Lookup doesnt cover (quest, event...). no stats were bundled
local function placeholder(monster, status)
    return {
        title = monster.name,
        info = {},
        variants = {},
        sections = {},
        no_drops = status == "excluded" and "not_covered" or "none",
        locations = {},
        no_locations = "none",
        source = "bundle",
        placeholder = true,
    }
end

local function refresh_wait_message(remaining)
    return "Manual refresh available in " .. math.ceil(remaining / 60) .. " minutes."
end

-- flights: one running wiki request per key, shared by every handle waiting on it. the
-- request only gets cancelled once the last handle waiting on it leaves
local flights = {}

---@param key string
---@param start fun(done: fun(...)): { cancel: fun() }? starts the request
---@param settle fun(...): ... runs once when the request finishes, unless every waiter left
---first. saving the result goes here so a cancelled lookup never saves anything. what it
---returns goes to the waiters
---@param on_done fun(...) gets what settle returned
---@return fun() leave stop waiting, safe to call more than once or after its finished
local function join_flight(key, start, settle, on_done)
    local flight = flights[key]

    if not flight then
        flight = { waiters = {}, count = 0 }
        flights[key] = flight
    end

    local waiter = { on_done = on_done }
    flight.waiters[#flight.waiters + 1] = waiter
    flight.count = flight.count + 1

    -- the waiter goes in before the request starts, in case it finishes straight away
    if not flight.started then
        flight.started = true
        flight.request = start(function(...)
            if flight.cancelled or flight.finished then
                return
            end

            if flights[key] == flight then
                flights[key] = nil
            end

            flight.finished = true
            local results = table.pack(settle(...))

            for _, current in ipairs(flight.waiters) do
                if not current.left then
                    current.left = true
                    current.on_done(table.unpack(results, 1, results.n))
                end
            end
        end)
    end

    return function()
        if waiter.left then
            return
        end

        waiter.left = true
        flight.count = flight.count - 1

        if flight.count == 0 and not flight.finished then
            flight.cancelled = true

            if flights[key] == flight then
                flights[key] = nil
            end

            if flight.request then
                flight.request.cancel()
            end
        end
    end
end

-- the wiki lookup for one monster, saved to the cache once however many handles wait on it
local function lookup_flight(key, monster, on_done)
    return join_flight(key, function(done)
        return wiki_lookup.fetch(monster, done)
    end, function(result, problem)
        local saved_at

        if result then
            log("Monster Lookup: looked up " .. result.title .. " on the Wiki")
            failures[key] = nil
            saved_at = cache.put(monster, result)
        else
            local message = problem or "The Wiki lookup failed."
            log("Monster Lookup: Wiki lookup for " .. key .. " failed. " .. message)
            remember_failure(key, message)
        end

        return result, problem, saved_at
    end, on_done)
end

local function clock_flight(on_done)
    return join_flight("clock", function(done)
        return wiki_lookup.synchronize_clock(done)
    end, function(ok, problem)
        if not ok then
            remember_failure("clock", problem or "Could not check the current Wiki time.")
        end

        return ok, problem
    end, on_done)
end

local function complete_request(request, result, problem, metadata)
    request.on_complete(result, problem, metadata)

    if request.foreground_complete then
        request.foreground_complete(result, problem, metadata)
    end
end

local function show_recent_failure(key, saved, metadata, on_complete)
    local failure = failures[key] or (not clock.now() and failures.clock)

    if not failure or clock.elapsed() >= failure.retry_at then
        return false
    end

    on_complete(
        saved,
        failure.problem .. " Please wait a minute before refreshing again.",
        metadata
    )
    return true
end

---@class LookupHandle
---@field fetch fun(monster: MonsterSelection, on_complete: fun(result: MonsterResult?, problem: string?, metadata: CacheMetadata?), force_refresh: boolean?)
---@field cancel fun() stops this handles lookup, nobody elses
---@field destroy fun() cancel and forget the handle

---a lookup handle for one thing that shows monsters (a window, a settings page, another
---plugin). it follows one monster at a time
---@return LookupHandle
function service.new_handle()
    -- bumped on every fetch and cancel so this handle never trusts a callback from an older
    -- request, whatever the layers below do
    local generation = 0
    local active
    -- stops waiting on this handles current flight, nil when its not waiting
    local leave
    local handle = {}

    local function leave_flight()
        if leave then
            local current = leave
            leave = nil
            current()
        end
    end

    local function abandon_active()
        local previous = active
        active = nil

        if previous and previous.force_refresh then
            previous.on_complete(nil, "Refresh cancelled.", { stale = true })
        end
    end

    -- forget the current request before starting something else
    local function reset()
        generation = generation + 1
        abandon_active()
        leave_flight()
    end

    local function finish_lookup(request, result, problem, saved_at)
        if request.generation ~= generation then
            return
        end

        active, leave = nil, nil

        if result then
            complete_request(
                request,
                result,
                nil,
                { saved_at = saved_at, age_seconds = 0, stale = false }
            )
        else
            request.metadata.refreshing = false
            complete_request(request, request.saved, problem, request.metadata)
        end
    end

    local function synchronize_for_lookup(request)
        request.syncing_clock = true
        -- theres no os clock in the client, so ask the wiki the time once per session and
        -- then check the saved lookups age again. without it every saved lookup would look
        -- expired after a plugin reload
        leave = clock_flight(function(ok, problem)
            if request.generation ~= generation then
                return
            end

            active, leave = nil, nil

            if ok then
                handle.fetch(request.monster, function(result, message, metadata)
                    complete_request(request, result, message, metadata)
                end, request.force_refresh)
            else
                request.metadata.refreshing = false
                complete_request(request, request.saved, problem, request.metadata)
            end
        end)
    end

    -- on_complete can run twice: saved data first, then the refresh result or failure.
    -- whether saved data is due a refresh is only checked here when a monster is picked,
    -- theres no timer refreshing things in the background
    ---@param force_refresh boolean? skip fresh saved data, used by settings
    function handle.fetch(monster, on_complete, force_refresh)
        force_refresh = force_refresh == true

        -- bundled monsters never need the Wiki or the cache, even for a refresh: the bundle
        -- is the newest data this plugin version has. only unknown (new) monsters go further
        local status = core.coverage(monster).status
        local result

        if status == "covered" then
            result = core.monster(monster)

            if result then
                result.source = "bundle"
            end
        elseif status == "no_drops" or status == "excluded" then
            result = placeholder(monster, status)
        end

        if result then
            reset()
            on_complete(result, nil, { bundled = true, built = core.info().built, stale = false })
            return
        end

        local key = core.identity_key(monster)

        -- picking the same monster again just follows the request already running
        if active and active.key == key then
            if force_refresh and not active.force_refresh then
                -- the running lookup already gets fresh data, so turn it into the refresh
                -- instead of starting again. while its still checking the clock the fetch
                -- hasnt started, so theres nothing to promote yet
                if not active.syncing_clock then
                    local remaining = cache.begin_manual_refresh(monster)

                    if remaining > 0 then
                        on_complete(nil, refresh_wait_message(remaining), { stale = true })
                        return
                    end

                    cache.invalidate_family(monster)
                    active.saved, active.metadata = nil, { stale = true }
                end

                active.force_refresh = true
                active.on_complete = on_complete
            elseif active.force_refresh and not force_refresh then
                -- opening a monster that settings is refreshing gets the same result,
                -- settings still gets its own done message
                active.foreground_complete = on_complete
            else
                active.on_complete = on_complete
            end

            if active.saved then
                on_complete(active.saved, nil, active.metadata)
            end

            return
        end

        reset()
        local saved, metadata = cache.get(monster, REFRESH_MINUTES)
        metadata = metadata or { stale = true }

        if saved and not metadata.stale and not force_refresh then
            on_complete(saved, nil, metadata)
            return
        end

        if show_recent_failure(key, saved, metadata, on_complete) then
            return
        end

        local request = {
            key = key,
            monster = monster,
            generation = generation,
            on_complete = on_complete,
            force_refresh = force_refresh,
            saved = saved,
            metadata = metadata,
        }
        active = request

        if saved and not force_refresh then
            metadata.refreshing = true
            on_complete(saved, nil, metadata)
        end

        if
            (saved or force_refresh)
            and clock.now() == nil
            and (force_refresh or metadata.age_seconds == nil)
        then
            synchronize_for_lookup(request)
            return
        end

        if force_refresh then
            local remaining = cache.begin_manual_refresh(monster)

            if remaining > 0 then
                active = nil
                metadata.refreshing = false
                on_complete(saved, refresh_wait_message(remaining), metadata)
                return
            end

            cache.invalidate_family(monster)
            request.saved = nil
            request.metadata = { stale = true }
        end

        leave = lookup_flight(key, monster, function(result, problem, saved_at)
            finish_lookup(request, result, problem, saved_at)
        end)
    end

    function handle.cancel()
        reset()
    end

    function handle.destroy()
        reset()
        handles[handle] = nil
    end

    handles[handle] = true
    return handle
end

-- the default handle, for the standard window and settings
local default = service.new_handle()

---@param monster MonsterSelection
---@param on_complete fun(result: MonsterResult?, problem: string?, metadata: CacheMetadata?)
---@param force_refresh boolean? skip fresh saved data, used by settings
function service.fetch(monster, on_complete, force_refresh)
    default.fetch(monster, on_complete, force_refresh)
end

function service.cancel()
    default.cancel()
end

function service.start()
    clock.start()
    wiki_lookup.start()
end

-- logout and shutdown: every handle stops, then anything still queued below
function service.stop()
    for handle in pairs(handles) do
        handle.cancel()
    end

    flights = {}
    wiki_lookup.stop()
    clock.stop()
end

return service
