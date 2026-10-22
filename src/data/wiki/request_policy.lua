-- limits and sanity checks for wiki requests and responses
-- kept separate from wiki_http so they can be tested without the http plumbing

local json = require("src/utils/json")
local clock = require("src/utils/cache_clock")

local policy = {
    MAX_BYTES = json.MAX_BYTES,
    MAX_PATH_BYTES = 8192,
    REQUEST_INTERVAL_TICKS = clock.TICKS_PER_SECOND,
    TIMEOUT_TICKS = 20 * clock.TICKS_PER_SECOND,
    DECODE_RETRY_DELAY_TICKS = 2 * clock.TICKS_PER_SECOND,
    TIMEOUT_MESSAGE = "The Wiki request timed out. Try again.",
    SIZE_MESSAGE = "The Wiki response is too large. This lookup was stopped.",
}

function policy.valid_path(path)
    return type(path) == "string"
        and #path <= policy.MAX_PATH_BYTES
        and path:match("^/api%.php%?") ~= nil
        and not path:find("[%s%c#]")
end

function policy.transfer_problem(downloaded, total)
    if
        (type(downloaded) == "number" and downloaded > policy.MAX_BYTES)
        or (type(total) == "number" and total > policy.MAX_BYTES)
    then
        return policy.SIZE_MESSAGE
    end
end

-- has to match the wiki url in plugin.json
local function valid_reported_url(url)
    return type(url) == "string" and url:match("^https://runescape%.wiki/api%.php%?") ~= nil
end

local function content_type(header)
    local found

    for value in (header or ""):lower():gmatch("content%-type:%s*([^\r\n]+)") do
        found = value:match("^([^;%s]+)")
    end

    return found
end

function policy.response_problem(response)
    if response.timedOut then
        return policy.TIMEOUT_MESSAGE
    end

    if response.url ~= nil and not valid_reported_url(response.url) then
        return "The client reported an unexpected Wiki address. This lookup was stopped."
    end

    if response.responseCode == 429 then
        return "The Wiki is limiting requests. Please wait before trying again."
    end

    if response.responseCode and response.responseCode >= 300 and response.responseCode < 400 then
        return "The Wiki redirected this request. This lookup was stopped."
    end

    if
        not response.successful
        or type(response.responseCode) ~= "number"
        or response.responseCode < 200
        or response.responseCode >= 300
    then
        return "Could not reach the RuneScape Wiki. Try again."
    end

    local mime = content_type(response.header)

    if mime and mime ~= "application/json" then
        return "The Wiki returned a page instead of API data. Try again later."
    end

    if type(response.data) ~= "string" then
        return "The Wiki response body was missing. Please try again."
    end

    if #response.data > policy.MAX_BYTES then
        return policy.SIZE_MESSAGE
    end

    if response.data:match("^%s*<") then
        return "The Wiki returned a page instead of API data. Try again later."
    end
end

return policy
