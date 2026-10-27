-- tests load the embedded library through the same module paths as the runtime.
local loader = {}
local plugin_root = debug
    .getinfo(1, "S").source
    :sub(2)
    :match("^(.*)[/\\]tests[/\\]support[/\\][^/\\]+$") or "."

function loader.new()
    local modules = {}
    local environment = setmetatable({}, { __index = _G })
    local function load_module(name)
        local path = name:gsub("^src/", "src/data/library/")
            :gsub("^tools/", "tests/support/core_tools/")
        if not modules[path] then
            modules[path] =
                assert(loadfile(plugin_root .. "/" .. path .. ".lua", "t", environment))()
        end
        return modules[path]
    end
    environment.require = function(name)
        if name:match("^src/data/library/") or name:match("^tests/support/core_tools/") then
            if not modules[name] then
                modules[name] =
                    assert(loadfile(plugin_root .. "/" .. name .. ".lua", "t", environment))()
            end
            return modules[name]
        end
        return load_module(name)
    end
    return { export = load_module("src/api"), load_module = load_module, root = plugin_root }
end

return loader
