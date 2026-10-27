-- resolves a selection through Monster Data Core. Unknown identities stay unknown.
local core = require("src/data/core")
local lookup = {}

function lookup.get(monster)
    local coverage = core.coverage(monster)
    local result = coverage.status == "covered" and core.monster(monster) or nil

    if not result and (coverage.status == "excluded" or coverage.status == "no_drops") then
        result = {
            title = monster.name,
            info = {},
            variants = {},
            sections = {},
            locations = {},
            no_drops = coverage.status == "excluded" and "not_covered" or "none",
            no_locations = "none",
            source = "bundle",
            placeholder = true,
        }
    end

    if not result then
        local problem = coverage.status == "ambiguous"
                and "This NPC matches more than one monster. Search for the specific monster name."
            or "This monster is not included in Monster Data Core. Update the data library or try searching by name."
        return nil, problem
    end

    result.source = "bundle"
    return result, nil, { bundled = true, built = core.info().built }
end

-- the library branch retains callback handles for existing consumers; static reads finish immediately.
function lookup.new_handle()
    return {
        fetch = function(monster, callback)
            callback(lookup.get(monster))
        end,
        cancel = function() end,
        destroy = function() end,
    }
end

return lookup
