-- bounded name search over a list of entries, keeping the best few matches. it does as many
-- rows as the caller asks for per step(), so whoever shows the results decides when to run
-- it (a tick, a button) and nothing here needs a subscription
--
-- used by monster and item name search. entries can be anything with a name, the caller can
-- add a bonus per entry (saved lookups go first in the search window)

local matcher = require("src/data/library/search/matcher")

local scan = {}
scan.MAX_RESULTS = 50

-- prepared names are kept per entry table, so typing a new query doesnt prepare everything
-- again. weak so entries a caller throws away dont stay around
local prepared_names = setmetatable({}, { __mode = "k" })

local function default_prepare(entry)
    local prepared = prepared_names[entry]

    if not prepared then
        prepared = matcher.prepare(entry.name)
        prepared_names[entry] = prepared
    end

    return prepared
end

-- lower is better: the exact name, then names starting with the query, then containing it
local function rank(name, key)
    return name == key and 0
        or name:sub(1, #key) == key and 10
        or name:find(key, 1, true) and 20
        or 30
end

---@class ScanOptions
---@field prepare (fun(entry: table): table|false|nil)? prepared name for an entry, false
---skips it, nil means not ready yet so the step stops there and tries it again next time
---(defaults to matcher.prepare of entry.name, cached)
---@field bonus (fun(entry: table): number)? added to the rank, lower goes first
---@field key (fun(entry: table): string)? tie breaker, defaults to the lower case name
---@field limit integer? how many to keep, defaults to MAX_RESULTS

---@param entries table[] what to search, read in order and never changed
---@param query string
---@param options ScanOptions?
function scan.new(entries, query, options)
    options = options or {}
    local prepare = options.prepare or default_prepare
    local bonus = options.bonus
    local tie_key = options.key or function(entry)
        return entry.name:lower()
    end
    local limit = options.limit or scan.MAX_RESULTS
    local matches = matcher.compile(query)
    local key = query:lower()
    local position = 1
    local top = {}
    local search = {}

    local function insert(entry, score)
        local candidate = { entry = entry, score = score, key = tie_key(entry) }
        local at = #top + 1

        for index, current in ipairs(top) do
            if
                score < current.score or (score == current.score and candidate.key < current.key)
            then
                at = index
                break
            end
        end

        if at <= limit then
            table.insert(top, at, candidate)

            if #top > limit then
                table.remove(top)
            end
        end
    end

    ---scans up to budget more entries, true once every entry has been looked at
    ---@param budget integer
    ---@return boolean done
    function search.step(budget)
        local last = math.min(position + budget - 1, #entries)

        for index = position, last do
            local entry = entries[index]
            local prepared = prepare(entry)

            if prepared == nil then
                return false
            end

            if prepared and matches(prepared) then
                insert(entry, rank(prepared.name, key) + (bonus and bonus(entry) or 0))
            end

            position = index + 1
        end

        return position > #entries
    end

    function search.done()
        return position > #entries
    end

    ---the best matches so far, best first. the entries themselves, in a new list
    function search.results()
        local results = {}

        for index, candidate in ipairs(top) do
            results[index] = candidate.entry
        end

        return results
    end

    return search
end

return scan
