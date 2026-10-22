-- a stand in for src/data/core (the static data plugins export) in tests: the real export,
-- with whatever a test wants different swapped in. a new table every time, so one test
-- changing it cant leak into another
--
--   modules["src/data/core"] = core_stub({ coverage = function() return { status = "unknown" } end })

local real = assert(MonsterDataCore, "test runner must load Monster Data Core first")

return function(overrides)
    local stub = {}

    for key, value in pairs(real) do
        stub[key] = value
    end

    for key, value in pairs(overrides or {}) do
        stub[key] = value
    end

    return stub
end
