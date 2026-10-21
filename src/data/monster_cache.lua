-- saved lookups, kept in PersistentDB between sessions
--
-- each monster is saved on its own as a json string, split over a few keys
-- (monster_lookup_cache_<slot>_<n>), and a small index key lists whats saved. the client
-- refuses values over roughly 128 KiB (not documented, but saves started failing right as
-- one big cache value reached that size), so nothing writen is allowed near that
--
-- payloads are only read and decoded when that monster is opened, decoding everything in
-- one go can hit the clients lua time limit. saved data might be from an older version or
-- just broken so everything read back is checked
--
-- if a save fails anyway the result is still kept in memory for this session

local json = require("src/utils/json")
local clock = require("src/utils/cache_clock")

---@class CacheMetadata
---@field saved_at number? os.time() when saved, nil if the client has no wall clock
---@field age_seconds number? nil when the age cant be worked out
---@field stale boolean true once the refresh interval has passed (or age is unknown)
---@field refreshing boolean? set while a refresh request is in flight

local cache = {}
local INDEX_KEY = "monster_lookup_cache_index"
-- 0.0.1 dev builds kept everything in this one key, it gets deleted on first load
local LEGACY_KEY = "monster_lookup_cache"
local CHUNK_PREFIX = "monster_lookup_cache_"
local INDEX_VERSION = 2
local CHUNK_BYTES = 60000
local MAX_ENTRIES = 50
local MAX_ENTRY_BYTES = 250000
local MAX_TOTAL_BYTES = 1500000

local entries
local next_slot = 1
local session_fetches = {}
local reported_save_failure = false

local function is_finite(value)
    return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function is_whole(value, minimum)
    return is_finite(value) and value >= minimum and value % 1 == 0
end

local function optional_string(value)
    return value == nil or type(value) == "string"
end

local function valid_drop(drop)
    return type(drop) == "table"
        and type(drop.name) == "string"
        and type(drop.quantity) == "string"
        and type(drop.rate) == "string"
        and optional_string(drop.notes)
        and optional_string(drop.note_marker)
        and (drop.item_id == nil or is_whole(drop.item_id, 0))
end

local function valid_section(section)
    if
        type(section) ~= "table"
        or type(section.title) ~= "string"
        or type(section.drops) ~= "table"
        or not optional_string(section.description)
        or not optional_string(section.afterword)
        or (section.notes ~= nil and type(section.notes) ~= "table")
    then
        return false
    end

    for _, note in ipairs(section.notes or {}) do
        if type(note) ~= "string" then
            return false
        end
    end

    for _, drop in ipairs(section.drops) do
        if not valid_drop(drop) then
            return false
        end
    end

    return true
end

local function valid_result(result)
    if
        type(result) ~= "table"
        or type(result.title) ~= "string"
        or type(result.info) ~= "table"
        or type(result.sections) ~= "table"
        or (
            result.no_drops ~= nil
            and result.no_drops ~= "none"
            and result.no_drops ~= "unreadable"
        )
    then
        return false
    end

    -- no sections is only ok when the lookup said why
    if #result.sections == 0 and result.no_drops == nil then
        return false
    end

    for _, section in ipairs(result.sections) do
        if not valid_section(section) then
            return false
        end
    end

    return true
end

-- just the cheap checks on an index row, the payload itself is checked when its opened
local function valid_entry(entry)
    return type(entry) == "table"
        and type(entry.key) == "string"
        and is_whole(entry.slot, 1)
        and is_whole(entry.chunks, 1)
        and is_whole(entry.bytes, 1)
        and entry.bytes <= MAX_ENTRY_BYTES
        and is_finite(entry.order)
        and entry.order >= 0
        and (entry.saved_at == nil or (is_finite(entry.saved_at) and entry.saved_at > 0))
end

local function chunk_key(slot, index)
    return CHUNK_PREFIX .. slot .. "_" .. index
end

local function delete_chunks(slot, count)
    for index = 1, count do
        PersistentDB:Delete(chunk_key(slot, index))
    end
end

local function report_save_failure(message)
    if not reported_save_failure then
        reported_save_failure = true
        log("Monster Lookup: " .. message)
    end
end

-- writes the payload in pieces, returns how many pieces or nil if any write failed
local function write_chunks(slot, payload)
    local count = math.max(1, math.ceil(#payload / CHUNK_BYTES))

    for index = 1, count do
        local piece = payload:sub((index - 1) * CHUNK_BYTES + 1, index * CHUNK_BYTES)

        if not PersistentDB:SetString(chunk_key(slot, index), piece) then
            delete_chunks(slot, index)
            return nil
        end
    end

    return count
end

local function read_payload(entry)
    -- not saved to disk, only kept for this session
    if entry.payload then
        return entry.payload
    end

    local pieces = {}

    for index = 1, entry.chunks do
        local piece = PersistentDB:GetString(chunk_key(entry.slot, index))

        if type(piece) ~= "string" then
            return nil
        end

        pieces[index] = piece
    end

    return table.concat(pieces)
end

local function save_index()
    local saved = {}

    for _, entry in ipairs(entries) do
        if entry.slot then
            saved[#saved + 1] = {
                key = entry.key,
                slot = entry.slot,
                chunks = entry.chunks,
                bytes = entry.bytes,
                order = entry.order,
                saved_at = entry.saved_at,
            }
        end
    end

    local index = { version = INDEX_VERSION, next_slot = next_slot, entries = saved }

    if not PersistentDB:SetStructuredData(INDEX_KEY, index) then
        report_save_failure("saved lookups could not be indexed for the next session")
    end
end

local function remove_entry(position)
    local entry = table.remove(entries, position)
    session_fetches[entry.key] = nil

    if entry.slot then
        delete_chunks(entry.slot, entry.chunks)
    end
end

-- newest first, then drop anything past the entry count or total size limits
local function trim()
    table.sort(entries, function(a, b)
        return a.order > b.order
    end)

    for position = #entries, MAX_ENTRIES + 1, -1 do
        remove_entry(position)
    end

    local bytes = 0

    for position, entry in ipairs(entries) do
        bytes = bytes + entry.bytes

        if bytes > MAX_TOTAL_BYTES then
            for remove = #entries, position, -1 do
                remove_entry(remove)
            end
            break
        end
    end
end

local function load()
    if entries then
        return
    end

    entries = {}

    if PersistentDB:CheckExists(LEGACY_KEY) then
        PersistentDB:Delete(LEGACY_KEY)
    end

    local saved = PersistentDB:GetStructuredData(INDEX_KEY)

    if
        type(saved) ~= "table"
        or saved.version ~= INDEX_VERSION
        or type(saved.entries) ~= "table"
    then
        return
    end

    next_slot = is_whole(saved.next_slot, 1) and saved.next_slot or 1
    local slots = {}

    for position, entry in ipairs(saved.entries) do
        if position > MAX_ENTRIES then
            break
        end

        if valid_entry(entry) and not slots[entry.slot] then
            slots[entry.slot] = true
            next_slot = math.max(next_slot, entry.slot + 1)
            entries[#entries + 1] = entry
        end
    end

    trim()
end

local function key_for(monster)
    return tostring(monster.npc_id) .. ":" .. monster.name
end

local function entry_age(entry, key)
    local now = clock.now()

    if now and entry.saved_at then
        return now - entry.saved_at
    end

    -- no wall clock, but it can still tell how old it is if it was fetched this session
    if session_fetches[key] then
        return clock.elapsed() - session_fetches[key]
    end
end

---@param monster MonsterSelection
---@param refresh_minutes number
---@return MonsterResult? result a fresh copy of the saved result
---@return CacheMetadata? metadata
function cache.get(monster, refresh_minutes)
    load()
    local key = key_for(monster)

    for position = #entries, 1, -1 do
        local entry = entries[position]

        if entry.key == key then
            local payload = read_payload(entry)
            local result, reason

            if payload then
                result, _, _, reason = json.decode(payload)
            end

            if valid_result(result) then
                local age = entry_age(entry, key)
                local fresh = age ~= nil and age >= 0 and age < refresh_minutes * 60

                return result, { saved_at = entry.saved_at, age_seconds = age, stale = not fresh }
            end

            -- a time limit hit says nothing about the data so keep it for next time
            if reason ~= "execution_limit" then
                remove_entry(position)
                save_index()
            end
        end
    end
end

---@param monster MonsterSelection
---@param result MonsterResult
---@return number? saved_at nil if the result wasnt kept
function cache.put(monster, result)
    load()

    if not valid_result(result) then
        return nil
    end

    local payload = json.encode(result)

    if #payload > MAX_ENTRY_BYTES then
        return nil
    end

    local key = key_for(monster)
    local order = 1

    for position = #entries, 1, -1 do
        order = math.max(order, entries[position].order + 1)

        if entries[position].key == key then
            remove_entry(position)
        end
    end

    local entry = { key = key, bytes = #payload, order = order, saved_at = clock.now() }
    local chunks = write_chunks(next_slot, payload)

    if chunks then
        entry.slot = next_slot
        entry.chunks = chunks
        next_slot = next_slot + 1
    else
        entry.payload = payload
        report_save_failure(
            "a lookup could not be saved for the next session (" .. #payload .. " bytes)"
        )
    end

    session_fetches[key] = clock.elapsed()
    entries[#entries + 1] = entry
    trim()
    save_index()

    return entry.saved_at
end

return cache
