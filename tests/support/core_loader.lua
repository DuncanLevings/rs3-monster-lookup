-- tests load the sibling plugin in its own environment and module cache, like the client
local loader = {}
local default_root = (
    debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]tests[/\\]support[/\\][^/\\]+$") or "."
) .. "/../monster-data-core"
function loader.new(root)
    root = root or os.getenv("MONSTER_DATA_CORE_ROOT") or default_root
    local modules = {}
    local environment = setmetatable({}, {
        __index = function(_, key)
            if key ~= "MonsterDataCore" then
                return _G[key]
            end
        end,
    })
    local function load_module(name)
        if modules[name] == nil then
            local chunk, problem = loadfile(root .. "/" .. name .. ".lua", "t", environment)
            assert(
                chunk,
                "cannot load Monster Data Core from " .. root .. ": " .. tostring(problem)
            )
            modules[name] = chunk()
        end
        return modules[name]
    end
    environment.require = load_module
    return { export = load_module("main"), load_module = load_module, root = root }
end
return loader
