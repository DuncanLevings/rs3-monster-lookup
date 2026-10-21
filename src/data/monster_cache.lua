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

local identity = require("src/utils/monster_identity")
local json = require("src/utils/json")
local clock = require("src/utils/cache_clock")

---@class CacheMetadata
---@field saved_at number? UTC seconds when saved, nil for older clockless entries
---@field age_seconds number? nil when the age cant be worked out
---@field stale boolean true once the refresh interval has passed (or age is unknown)
---@field refreshing boolean? set while a refresh request is in flight

local cache = {}
local INDEX_KEY = "monster_lookup_cache_index"
-- 0.0.1 dev builds kept everything in this one key, it gets deleted on first load
local LEGACY_KEY = "monster_lookup_cache"
local CHUNK_PREFIX = "monster_lookup_cache_"
local INDEX_VERSION = 3
local INDEX_PAGE_ENTRIES = 40
local CHUNK_BYTES = 60000
local MAX_ENTRIES = 1000
local MAX_ENTRY_BYTES = 250000
local MAX_TOTAL_BYTES = 32 * 1024 * 1024

local entries
local next_slot = 1
local index_bank
local index_pages = 0
local pending_deletes = {}
local session_fetches = {}
local manual_attempts = {}
local MANUAL_REFRESH_SECONDS = 60 * 60
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

    if section.drop_mode ~= nil or section.drop_threshold ~= nil or section.drop_switch ~= nil then
        if
            type(section.drop_mode) ~= "string"
            or #section.drop_mode > 120
            or not is_whole(section.drop_threshold, -1)
            or not is_whole(section.drop_switch, 1)
        then
            return false
        end
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

local function valid_locations(result)
    -- older payloads remain usable for drops and stats, but get refreshed on first open
    if result.locations == nil then
        return result.no_locations == nil
    end

    if type(result.locations) ~= "table" then
        return false
    end

    local count = 0

    for index, location in pairs(result.locations) do
        if not is_whole(index, 1) or type(location) ~= "table" then
            return false
        end

        for _, key in ipairs({ "name", "levels", "requirements", "spawns" }) do
            if type(location[key]) ~= "string" then
                return false
            end
        end

        count = count + 1
    end

    if count ~= #result.locations then
        return false
    end

    if count > 0 then
        return result.no_locations == nil
    end

    return result.no_locations == "none" or result.no_locations == "unreadable"
end

local function valid_result(result)
    if
        type(result) ~= "table"
        or type(result.title) ~= "string"
        or type(result.info) ~= "table"
        or type(result.sections) ~= "table"
        or not valid_locations(result)
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
local function result_summary(result, monster)
    local info = type(result.info) == "table" and result.info or {}
    local variant = not monster.wiki_title and info.version_anchor or nil
    local level = info.combat_level
    return {
        title = result.title,
        variant = type(variant) == "string" and variant or nil,
        level = is_whole(level, 0) and level or nil,
    }
end

local function valid_summary(summary)
    return type(summary) == "table"
        and type(summary.title) == "string"
        and #summary.title <= 240
        and optional_string(summary.variant)
        and (summary.level == nil or is_whole(summary.level, 0))
end

local function valid_entry(entry)
    return type(entry) == "table"
        and type(entry.key) == "string"
        and #entry.key <= 512
        and is_whole(entry.slot, 1)
        and is_whole(entry.chunks, 1)
        and entry.chunks <= math.ceil(MAX_ENTRY_BYTES / CHUNK_BYTES)
        and is_whole(entry.bytes, 1)
        and entry.bytes <= MAX_ENTRY_BYTES
        and is_finite(entry.order)
        and entry.order >= 0
        and (entry.saved_at == nil or (is_finite(entry.saved_at) and entry.saved_at > 0))
        and (entry.summary == nil or valid_summary(entry.summary))
        and (
            entry.manual_refresh_at == nil
            or (is_finite(entry.manual_refresh_at) and entry.manual_refresh_at > 0)
        )
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
            -- discard the partial payload; only complete writes can be added to the index
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

local function index_page_key(bank, page)
    return INDEX_KEY .. "_" .. bank .. "_" .. page
end

local function delete_index_pages(bank, count)
    for page = 1, count do
        PersistentDB:Delete(index_page_key(bank, page))
    end
end

local function persisted_entries()
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
                summary = entry.summary,
                manual_refresh_at = entry.manual_refresh_at,
            }
        end
    end

    return saved
end

local function write_index_pages(bank, saved)
    local count = math.ceil(#saved / INDEX_PAGE_ENTRIES)

    for page = 1, count do
        local rows = {}

        for row = (page - 1) * INDEX_PAGE_ENTRIES + 1, math.min(page * INDEX_PAGE_ENTRIES, #saved) do
            rows[#rows + 1] = saved[row]
        end

        if not PersistentDB:SetStructuredData(index_page_key(bank, page), rows) then
            delete_index_pages(bank, page)
            report_save_failure("saved lookups could not be indexed for the next session")
            return
        end
    end

    return count
end

-- Publish the small header last so a failed write cannot expose a half-written index.
-- Pages stay small even with 1,000 entries; payloads are still loaded individually.
local function save_index()
    local bank = index_bank == "a" and "b" or "a"
    local count = write_index_pages(bank, persisted_entries())

    if not count then
        return
    end

    local header = { version = INDEX_VERSION, next_slot = next_slot, bank = bank, pages = count }

    if not PersistentDB:SetStructuredData(INDEX_KEY, header) then
        delete_index_pages(bank, count)
        report_save_failure("saved lookups could not be indexed for the next session")
        return
    end

    if index_bank then
        delete_index_pages(index_bank, index_pages)
    end

    index_bank, index_pages = bank, count

    -- Old payloads remain intact until the replacement index has been committed.
    for _, entry in ipairs(pending_deletes) do
        delete_chunks(entry.slot, entry.chunks)
    end

    pending_deletes = {}
    return true
end

local function remove_entry(position)
    local entry = table.remove(entries, position)
    session_fetches[entry.key] = nil

    if entry.slot then
        pending_deletes[#pending_deletes + 1] = entry
    end
end

-- newest fetch first, then drop anything past the entry count or total size limits
-- opening a saved result does not change its eviction order
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

local function read_index(saved)
    local rows = {}

    if saved.version == 2 and type(saved.entries) == "table" then
        return saved.entries
    elseif
        saved.version == INDEX_VERSION
        and (saved.bank == "a" or saved.bank == "b")
        and is_whole(saved.pages, 0)
        and saved.pages <= math.ceil(MAX_ENTRIES / INDEX_PAGE_ENTRIES)
    then
        for page = 1, saved.pages do
            local part = PersistentDB:GetStructuredData(index_page_key(saved.bank, page))

            if type(part) ~= "table" or #part > INDEX_PAGE_ENTRIES then
                return
            end

            for _, entry in ipairs(part) do
                rows[#rows + 1] = entry
            end
        end

        return rows, saved.bank, saved.pages
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

    if type(saved) ~= "table" then
        return
    end

    local rows, bank, pages = read_index(saved)

    if not rows then
        return
    end

    index_bank, index_pages = bank, pages or 0
    next_slot = is_whole(saved.next_slot, 1) and saved.next_slot or 1
    local slots = {}

    for position, entry in ipairs(rows) do
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

-- Settings only needs identities, never all the saved drop tables and stats.
function cache.list(include_summaries)
    load()
    local monsters = {}

    for _, entry in ipairs(entries) do
        local monster = identity.selection(entry.key)

        if monster then
            if include_summaries and entry.summary then
                monster.summary = {
                    title = entry.summary.title,
                    variant = entry.summary.variant,
                    level = entry.summary.level,
                }
            end

            monsters[#monsters + 1] = monster
        end
    end

    table.sort(monsters, function(a, b)
        if a.name:lower() == b.name:lower() then
            return (a.npc_id or math.huge) < (b.npc_id or math.huge)
        end

        return a.name:lower() < b.name:lower()
    end)

    return monsters
end

-- Older cache indexes lack labels. The saved picker calls this at a bounded rate,
-- rather than decoding every monster when the settings page opens.
function cache.describe(monster)
    load()
    local key = identity.key(monster)

    for _, entry in ipairs(entries) do
        if entry.key == key then
            if not entry.summary then
                local payload = read_payload(entry)
                local result = payload and json.decode(payload)

                if valid_result(result) then
                    entry.summary = result_summary(result, monster)
                end
            end

            return entry.summary
        end
    end
end

-- Record the attempt before HTTP starts: failures and cancelled lookups still count.
-- Session time covers clients without a wall clock; UTC keeps the limit across reloads.
function cache.manual_refresh_remaining(monster)
    load()
    local key = identity.key(monster)
    local remaining = 0
    if manual_attempts[key] then
        remaining = MANUAL_REFRESH_SECONDS - (clock.elapsed() - manual_attempts[key])
    end
    local now = clock.now()
    for _, entry in ipairs(entries) do
        if entry.key == key and entry.manual_refresh_at and now then
            remaining =
                math.max(remaining, MANUAL_REFRESH_SECONDS - (now - entry.manual_refresh_at))
            break
        end
    end
    return math.max(0, math.min(MANUAL_REFRESH_SECONDS, math.ceil(remaining)))
end

function cache.begin_manual_refresh(monster)
    local remaining = cache.manual_refresh_remaining(monster)
    if remaining > 0 then
        return remaining
    end
    local key = identity.key(monster)
    for _, entry in ipairs(entries) do
        if entry.key == key then
            manual_attempts[key] = clock.elapsed()
            entry.manual_refresh_at = clock.now()
            save_index()
            break
        end
    end
    return 0
end

---@param monster MonsterSelection
---@param refresh_minutes number
---@return MonsterResult? result a fresh copy of the saved result
---@return CacheMetadata? metadata
function cache.get(monster, refresh_minutes)
    load()
    local key = identity.key(monster)

    for position = #entries, 1, -1 do
        local entry = entries[position]

        if entry.key == key then
            local payload = read_payload(entry)
            local result, reason

            -- decode a fresh table so UI changes cannot mutate the saved copy
            if payload then
                result, _, _, reason = json.decode(payload)
            end

            if valid_result(result) then
                ---@cast result MonsterResult
                local age = entry_age(entry, key)
                local fresh = age ~= nil
                    and age >= 0
                    and age < refresh_minutes * 60
                    and result.locations ~= nil

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

    local key = identity.key(monster)
    local order = 1
    local manual_refresh_at

    for position = #entries, 1, -1 do
        order = math.max(order, entries[position].order + 1)

        if entries[position].key == key then
            manual_refresh_at = entries[position].manual_refresh_at
            remove_entry(position)
        end
    end

    local entry = {
        key = key,
        bytes = #payload,
        order = order,
        saved_at = clock.now(),
        manual_refresh_at = manual_refresh_at,
        summary = result_summary(result, monster),
    }
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

    if not save_index() and entry.slot then
        -- This slot was never published. Keep only the session copy if indexing failed.
        delete_chunks(entry.slot, entry.chunks)
        entry.slot, entry.chunks, entry.payload = nil, nil, payload
    end

    return entry.saved_at
end

return cache
