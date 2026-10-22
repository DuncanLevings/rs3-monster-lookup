local fixture = {}

function fixture.new(root, paced)
    local context = { requests = {}, permitted = true, logs = {} }
    local environment = setmetatable({}, {
        __index = function(_, key)
            if key ~= "utf8" then
                return _G[key]
            end
        end,
    })
    local modules = {}

    local function load_module(path)
        if modules[path] == nil then
            modules[path] = assert(loadfile(root .. "/" .. path .. ".lua", "t", environment))()
        end

        return modules[path]
    end

    environment.require = load_module
    environment.log = function(message)
        context.logs[#context.logs + 1] = message
    end
    environment.Event = {
        Logic = {
            Subscribe = function(_, callback)
                context.on_tick = callback
            end,
            Unsubscribe = function()
                context.on_tick = nil
            end,
        },
    }
    environment.PluginPermissions = { httpAccess = "httpAccess" }
    environment.Plugin = {
        urls = { wiki = "https://runescape.wiki" },
        HasPermission = function()
            return context.permitted
        end,
    }
    environment.HTTPRequest = {
        new = function(base, path)
            local request = { base = base, path = path, headers = {} }

            function request:AddHeader(key, value)
                self.headers[key] = value
            end

            function request:Get(callback, progress_callback)
                if context.in_http_callback then
                    context.nested_request = true
                end
                self.callback = callback
                self.progress_callback = progress_callback

                if context.fail_start then
                    error("simulated client request startup failure")
                end
            end

            function request:Cancel()
                self.cancelled = true

                if context.complete_on_cancel and self.callback then
                    self.callback({ successful = false, responseCode = 0, data = "" })
                end
            end

            context.requests[#context.requests + 1] = request
            return request
        end,
    }
    context.codec = load_module("src/vendor/json")

    function context:tick(count)
        for _ = 1, count or 1 do
            if self.on_tick then
                self.on_tick()
            end
        end
    end

    function context:respond(index, data, options)
        local response = options or { successful = true, responseCode = 200 }
        response.data = type(data) == "string" and data or self.codec.encode(data)
        response.url = response.url or self.requests[index].base .. self.requests[index].path
        response.header = response.header or "Content-Type: application/json\r\n"
        self.in_http_callback = true
        self.requests[index].callback(response)
        self.in_http_callback = false

        if not self.manual_ticks then
            self:tick()
            self:tick()
        end
    end

    function context:progress(index, downloaded, total)
        local request = self.requests[index]
        request.downloadedBytes = downloaded
        request.downloadTotalBytes = total
        request.progress_callback(request)
    end

    if not paced then
        -- Most parser/response tests use immediate follow-ups; pacing has its own timed test.
        load_module("src/data/wiki/request_policy").REQUEST_INTERVAL_TICKS = 0
    end

    context.lookup = load_module("src/data/wiki/lookup")
    context.http = load_module("src/data/wiki/http")
    context.text = load_module("src/utils/wiki_text")
    context.unicode = load_module("src/utils/unicode")
    context.lookup.start()
    return context
end

return fixture
