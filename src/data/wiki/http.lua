-- wiki api requests, queued and cancellable
--
-- requests get sent and responses get handled from Event.Logic, not inside the native http
-- callbacks. Had a client crash during dev when follow up requests and ui work ran inside
-- the completion callback, so now the callback just stores the response and the next tick
-- deals with it. cancel() bumps the generation so anything from before gets ignored
--
-- requests can also go in a group (one lookup), cancel_group() stops just that group so
-- two lookups running side by side dont cancel each other

local clock = require("src/utils/cache_clock")
local json = require("src/utils/json")
local policy = require("src/data/wiki/request_policy")

local wiki_http = {}
local pending = {}
local queued = {}
local completed = {}
local generation = 0
local started = false
local logic_tick = 0
local request_sequence = 0
local next_send_tick = 0
local COMPLETION_SUBSCRIPTION = "monster_lookup_http_completions"
local USER_AGENT = "MonsterLookup (RuneScape plugin)"
local PERMISSION_ERROR = "Monster Lookup needs the HTTP access permission to read the "
    .. "RuneScape Wiki.\n\n"
    .. "Allow it in Monster Lookup's plugin permissions in the Plugin Hub, "
    .. "then choose View drops again."

-- still wanted: not from before a cancel(), and its group (if any) wasnt cancelled
local function current(item)
    return item.generation == generation and not (item.group and item.group.cancelled)
end

local function decode_response(entry)
    local response = entry.response
    local problem = policy.response_problem(response)

    if problem then
        return nil, problem
    end

    local result, decode_problem, detail, reason = json.decode(response.data)

    if reason == "execution_limit" then
        log(
            "Monster Lookup: client decoding time limit exceeded for Wiki response #"
                .. entry.sequence
        )
        return nil, decode_problem
    end

    if not result then
        local diagnostic = (detail or decode_problem):gsub("[%c]", " "):sub(1, 200)
        log(
            "Monster Lookup: unreadable Wiki response #"
                .. entry.sequence
                .. " ("
                .. #response.data
                .. " bytes): "
                .. diagnostic
        )
        return nil, "The Wiki sent unreadable API data. Please try again shortly.", true
    end

    if result.error then
        return nil, "The Wiki could not complete this lookup."
    end

    if result.curtimestamp then
        clock.synchronize(result.curtimestamp)
    end

    return result
end

local function finish_request(entry, response, problem)
    if entry.settled or not current(entry) then
        return
    end

    entry.settled = true
    entry.response = response
    entry.problem = problem

    if entry.request then
        pending[entry.request] = nil
    end

    -- the entry keeps its native request alive until the following logic tick
    completed[#completed + 1] = entry
end

local function cancel_native_request(request)
    -- keep a Lua caller between the protected call and the native binding.
    local ok, problem = pcall(function()
        request:Cancel()
    end)

    if not ok then
        log("Monster Lookup: client request cancellation failed: " .. tostring(problem))
    end
end

local function stop_request(entry, problem)
    finish_request(entry, nil, problem)

    if entry.request then
        cancel_native_request(entry.request)
    end
end

local function receive_response(entry, request)
    if entry.settled or not current(entry) then
        return
    end

    local problem = entry.problem
        or policy.transfer_problem(request.downloadedBytes, request.downloadTotalBytes)
    local response = {
        successful = request.successful,
        responseCode = request.responseCode,
        timedOut = request.timedOut,
        url = request.url,
        header = request.header,
        data = problem and "" or request.data,
    }

    finish_request(entry, response, problem)
end

local function track_progress(entry, request)
    if not entry.settled and current(entry) then
        entry.problem = entry.problem
            or policy.transfer_problem(request.downloadedBytes, request.downloadTotalBytes)
    end
end

local function begin_native_request(entry, path)
    local request = HTTPRequest.new(Plugin.urls.wiki, path)
    entry.request = request
    pending[request] = entry

    request:AddHeader("User-Agent", USER_AGENT)
    request:AddHeader("Accept", "application/json")
    request:Get(function(response)
        receive_response(entry, response)
    end, function(response)
        track_progress(entry, response)
    end)
end

local function send_request(job)
    if job.deadline and logic_tick >= job.deadline then
        job.on_complete(nil, policy.TIMEOUT_MESSAGE)
        return
    end

    -- check again here, the player can turn the permission off while a request is queued
    if not Plugin.HasPermission(PluginPermissions.httpAccess) then
        job.on_complete(nil, PERMISSION_ERROR)
        return
    end

    request_sequence = request_sequence + 1
    local entry = {
        generation = job.generation,
        group = job.group,
        on_complete = job.on_complete,
        sequence = request_sequence,
        path = job.path,
        attempt = job.attempt or 0,
        deadline = job.deadline or logic_tick + policy.TIMEOUT_TICKS,
    }

    local ok, problem = pcall(begin_native_request, entry, job.path)

    if not ok then
        log("Monster Lookup: client request startup failed: " .. tostring(problem))
        stop_request(
            entry,
            "The client could not start the Wiki request. Try reloading the plugin."
        )
    end
end

local function stop_expired_requests()
    local expired = {}

    for _, entry in pairs(pending) do
        if entry.problem or logic_tick >= entry.deadline then
            expired[#expired + 1] = entry
        end
    end

    for _, entry in ipairs(expired) do
        stop_request(entry, entry.problem or policy.TIMEOUT_MESSAGE)
    end
end

-- if the body was unreadable try once more after a short wait in case it was a one off
-- the retry still has to finish before the original deadline
local function queue_decode_retry(entry)
    local retry_at = logic_tick + policy.DECODE_RETRY_DELAY_TICKS

    if entry.attempt >= 1 or retry_at >= entry.deadline then
        return false
    end

    queued[#queued + 1] = {
        path = entry.path,
        on_complete = entry.on_complete,
        generation = entry.generation,
        group = entry.group,
        attempt = entry.attempt + 1,
        deadline = entry.deadline,
        not_before = retry_at,
    }
    return true
end

local function process_response(entry)
    if entry.problem then
        entry.on_complete(nil, entry.problem)
        return
    end

    local result, problem, retryable = decode_response(entry)

    if not result and retryable and queue_decode_retry(entry) then
        return
    end

    entry.on_complete(result, problem)
end

local function process_responses(responses)
    for _, entry in ipairs(responses) do
        -- an earlier callback in this loop might have cancelled it already
        if current(entry) then
            process_response(entry)
        end
    end
end

local function process_tick()
    logic_tick = logic_tick + 1
    -- take this ticks work out of the live queues. follow-up requests from callbacks
    -- wait until the next tick, so a lookup chain cannot run recursively in one tick
    local outgoing = queued
    local responses = completed
    queued = {}
    completed = {}

    stop_expired_requests()

    for _, job in ipairs(outgoing) do
        if current(job) then
            if (job.not_before and logic_tick < job.not_before) or logic_tick < next_send_tick then
                queued[#queued + 1] = job
            else
                next_send_tick = logic_tick + policy.REQUEST_INTERVAL_TICKS
                send_request(job)
            end
        end
    end

    process_responses(responses)
end

function wiki_http.start()
    if started then
        return
    end

    Event.Logic.Subscribe(COMPLETION_SUBSCRIPTION, process_tick)
    started = true
end

function wiki_http.cancel()
    generation = generation + 1
    -- detach the old queues before calling native Cancel, which may invoke a callback
    local requests = pending
    pending = {}
    queued = {}
    completed = {}

    for request, entry in pairs(requests) do
        entry.settled = true
        cancel_native_request(request)
    end
end

---a group to put one lookups requests in, see cancel_group
function wiki_http.group()
    return { cancelled = false }
end

---stops every request in the group, queued or running. requests from other groups carry on
function wiki_http.cancel_group(group)
    if not group or group.cancelled then
        return
    end

    group.cancelled = true
    local stopping = {}

    for request, entry in pairs(pending) do
        if entry.group == group then
            stopping[request] = entry
        end
    end

    -- off the pending list before the native Cancel, which may call back straight away
    for request, entry in pairs(stopping) do
        pending[request] = nil
        entry.settled = true
        cancel_native_request(request)
    end
end

function wiki_http.stop()
    wiki_http.cancel()

    if started then
        Event.Logic.Unsubscribe(COMPLETION_SUBSCRIPTION)
        started = false
    end
end

---queues a GET for a wiki api path, callback gets the decoded json or nil and a message
---thats ok to show the player
---@param path string
---@param on_complete fun(result: table?, problem: string?)
---@param group table? from wiki_http.group(), so cancel_group can stop it
function wiki_http.get(path, on_complete, group)
    if not policy.valid_path(path) then
        on_complete(nil, "This Wiki request has an invalid API address.")
        return
    end

    queued[#queued + 1] =
        { path = path, on_complete = on_complete, generation = generation, group = group }
end

return wiki_http
