-- sits between the window and the wiki lookup, decides whether saved data is good enough
-- or a new fetch is needed. saved data is shown straight away even when its due a refresh,
-- then swapped for the new result when it arrives (or kept if the refresh fails)

local identity = require("src/utils/monster_identity")
local wiki_lookup = require("src/data/wiki_lookup")
local cache = require("src/data/monster_cache")
local clock = require("src/utils/cache_clock")

local service = {}

-- bumped on every fetch and cancel so this layer never trusts a callback from an older
-- request, whatever the layers below do
local generation = 0
local active
local failures = {}
local RETRY_SECONDS = 60
local REFRESH_MINUTES = 14 * 24 * 60

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

function service.cancel()
    generation = generation + 1
    active = nil
    wiki_lookup.cancel()
end

local function finish_lookup(request, result, problem)
    if request.generation ~= generation then
        return
    end

    active = nil

    if result then
        failures[request.key] = nil
        local saved_at = cache.put(request.monster, result)
        request.on_complete(result, nil, { saved_at = saved_at, age_seconds = 0, stale = false })
    else
        remember_failure(request.key, problem or "The Wiki lookup failed.")
        request.metadata.refreshing = false
        request.on_complete(request.saved, problem, request.metadata)
    end
end

local function synchronize_for_lookup(request)
    -- Establish the current date once per client session, then recheck entry age.
    -- This avoids treating every saved lookup as expired after a plugin reload.
    wiki_lookup.synchronize_clock(function(ok, problem)
        if request.generation ~= generation then
            return
        end

        active = nil

        if ok then
            service.fetch(request.monster, request.on_complete, request.force_refresh)
        else
            remember_failure("clock", problem or "Could not check the current Wiki time.")
            request.metadata.refreshing = false
            request.on_complete(request.saved, problem, request.metadata)
        end
    end)
end

local function show_recent_failure(key, saved, metadata, on_complete)
    local failure = failures[key] or (not clock.now() and failures.clock)

    if not failure or clock.elapsed() >= failure.retry_at then
        return false
    end

    wiki_lookup.cancel()
    on_complete(
        saved,
        failure.problem .. " Please wait a minute before refreshing again.",
        metadata
    )
    return true
end

-- on_complete can run twice: saved data first, then the refresh result or failure.
-- Expiry is checked on selection, with no background refresh timer.
---@param monster MonsterSelection
---@param on_complete fun(result: MonsterResult?, problem: string?, metadata: CacheMetadata?)
---@param force_refresh boolean? skip fresh saved data, used by settings
function service.fetch(monster, on_complete, force_refresh)
    local key = identity.key(monster)

    -- A repeated click follows the request already in flight instead of restarting it.
    if active and active.key == key then
        active.on_complete = on_complete

        if active.saved then
            on_complete(active.saved, nil, active.metadata)
        end

        return
    end

    generation = generation + 1
    active = nil
    local saved, metadata = cache.get(monster, REFRESH_MINUTES)
    metadata = metadata or { stale = true }

    if saved and not metadata.stale and not force_refresh then
        wiki_lookup.cancel()
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

    if saved then
        metadata.refreshing = true
        on_complete(saved, nil, metadata)
    end

    if saved and clock.now() == nil and (force_refresh or metadata.age_seconds == nil) then
        synchronize_for_lookup(request)
    else
        if force_refresh then
            local remaining = cache.begin_manual_refresh(monster)
            if remaining > 0 then
                active = nil
                metadata.refreshing = false
                wiki_lookup.cancel()
                on_complete(
                    saved,
                    "Manual refresh available in " .. math.ceil(remaining / 60) .. " minutes.",
                    metadata
                )
                return
            end
        end
        -- fetch cancels the previous lookup itself
        wiki_lookup.fetch(monster, function(result, problem)
            finish_lookup(request, result, problem)
        end)
    end
end

function service.start()
    clock.start()
    wiki_lookup.start()
end

function service.stop()
    service.cancel()
    wiki_lookup.stop()
    clock.stop()
end

return service
