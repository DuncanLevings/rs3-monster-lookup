-- sits between the window and the wiki lookup, decides whether saved data is good enough
-- or a new fetch is needed. saved data is shown straight away even when its due a refresh,
-- then swapped for the new result when it arrives (or kept if the refresh fails)

local wiki_lookup = require("src/data/wiki_lookup")
local cache = require("src/data/monster_cache")
local settings = require("src/settings")
local clock = require("src/utils/cache_clock")

local service = {}

-- bumped on every fetch and cancel so this layer never trusts a callback from an older
-- request, whatever the layers below do
local generation = 0

function service.cancel()
    generation = generation + 1
    wiki_lookup.cancel()
end

-- on_complete can run twice: saved data first, then the refresh result or failure
-- expiry is checked when opening a monster, there is no background refresh timer
---@param monster MonsterSelection
---@param on_complete fun(result: MonsterResult?, problem: string?, metadata: CacheMetadata?)
---@param force_refresh boolean? skip fresh saved data, used by the Refresh button
function service.fetch(monster, on_complete, force_refresh)
    generation = generation + 1
    local request_generation = generation
    local saved, metadata = cache.get(monster, settings.get().refresh_minutes)
    metadata = metadata or { stale = true }

    if saved and not metadata.stale and not force_refresh then
        -- nothing new to fetch, but stop whatever the last monster was still loading
        wiki_lookup.cancel()
        on_complete(saved, nil, metadata)
        return
    end

    if saved then
        metadata.refreshing = true
        on_complete(saved, nil, metadata)
    end

    -- wiki_lookup.fetch cancels the previous lookup itself
    wiki_lookup.fetch(monster, function(result, problem)
        if request_generation ~= generation then
            return
        end

        if result then
            local saved_at = cache.put(monster, result)
            on_complete(result, nil, { saved_at = saved_at, age_seconds = 0, stale = false })
        elseif saved then
            metadata.refreshing = false
            on_complete(saved, problem, metadata)
        else
            on_complete(nil, problem)
        end
    end)
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
