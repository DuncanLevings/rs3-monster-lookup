-- Native hints are faked here, independently of the UI layout fixture.
local fixture = {}

function fixture.enable(context)
    local state =
        { arrows = {}, polygons = {}, adds = 0, removes = 0, ready = true, region = false }
    context.hints = state
    local environment = context.environment
    environment.HintList = {
        AddArrow = function(args)
            state.adds = state.adds + 1
            if state.throw_arrow then
                error("native arrow rejected")
            end
            if state.reject_arrow then
                return false
            end
            state.arrows[args.name] = args
            state.arrow = args
            return true
        end,
        AddPolygon = function(args)
            state.adds = state.adds + 1
            state.polygon_adds = (state.polygon_adds or 0) + 1
            if state.reject_polygon or state.polygon_adds == state.reject_polygon_number then
                return false
            end
            state.polygons[args.name] = args
            state.area = args
            return true
        end,
        RemoveArrow = function(name)
            state.removes = state.removes + 1
            state.arrows[name] = nil
            if state.arrow and state.arrow.name == name then
                state.arrow = nil
            end
        end,
        RemovePolygon = function(name)
            state.removes = state.removes + 1
            state.polygons[name] = nil
            if state.area and state.area.name == name then
                state.area = nil
            end
        end,
    }
    -- Emulate a client binding that needs a Lua caller. This guards the call
    -- shape shared by the crash reports; it does not reproduce a native crash.
    environment.pcall = function(callback, ...)
        for _, binding in pairs(environment.HintList) do
            if callback == binding then
                error("Native binding passed directly to pcall")
            end
        end
        return pcall(callback, ...)
    end
    environment.CoordGrid = {
        new = function(packed)
            return { level = (packed >> 28) & 3, x = (packed >> 14) & 0x3FFF, z = packed & 0x3FFF }
        end,
    }
    environment.CoordFine = {
        new = function(level, x, y, z)
            return { level = level, x = x, y = y, z = z }
        end,
    }
    environment.World = {
        GetGroundHeight = function(level, x, z)
            state.height_reads = (state.height_reads or 0) + 1
            state.height_query = { level = level, x = x, z = z }
            if state.throw_height then
                error("Terrain is unavailable")
            end
            return state.ground_height or -1, state.height_available == true
        end,
        IsAvailable = function()
            return state.ready
        end,
        IsRegion = function()
            return state.region
        end,
    }
    state.zoom = 100
    state.player_reads = 0
    environment.var = {
        VarClient = {
            WORLDMAP_ZOOM = setmetatable({}, {
                __index = function(_, key)
                    if key == "value" then
                        return state.zoom
                    end
                end,
            }),
        },
    }
    environment.Player = {
        IsAvailable = function()
            return state.player_ready ~= false
        end,
        GetEntity = function()
            state.player_reads = state.player_reads + 1
            return state.player and { coordGrid = state.player } or nil
        end,
    }
    return state
end

return fixture
