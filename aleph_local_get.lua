-- Aleph modification, 2026-11-15: a question to a program on this device,
-- asked without waiting for the answer.
--[[--
The Bluetooth page turner's battery comes from HID Passthrough's daemon, a
small web server on this device (127.0.0.1). Asking it the usual way holds
KOReader until it answers: a few milliseconds as a rule, up to two seconds
when the daemon is busy, on a page turn.

    require("aleph_local_get").get("127.0.0.1", 8321, "/status", function(body, why) ... end)

sends the question and returns at once. The answer is looked for from
KOReader's own loop, 20 times a second for at most two seconds, and handed
to the function: the answer's text, or nil and why not ("refused", "took
too long", "HTTP 500"...). Only for addresses on this device: plain HTTP/1.0,
no redirects, no TLS.
]]

local Get = {}

Get.EVERY = 0.05
Get.WAIT = 2

local function parse(raw)
    local head, body = raw:match("^(.-)\r\n\r\n(.*)$")
    if not head then return nil, "no answer" end
    local code = tonumber(head:match("^HTTP/%d%.%d (%d%d%d)"))
    if code ~= 200 then return nil, "HTTP " .. tostring(code) end
    return body
end
Get.parse = parse

function Get.get(host, port, path, done, o)
    o = o or {}
    local socket = o.socket or require("socket")
    local UIManager = require("ui/uimanager")
    local s = socket.tcp()
    if not s then return done(nil, "no socket") end
    s:settimeout(0)
    local finished = false
    local function finish(body, why)
        if finished then return end
        finished = true
        pcall(s.close, s)
        local ok, err = pcall(done, body, why)
        if not ok then require("aleph_try").report("aleph_local_get.lua answer", err) end
    end
    local connected = s:connect(host, port)
    local sent = false
    local chunks = {}
    local deadline = socket.gettime() + (o.wait or Get.WAIT)
    local step
    step = function()
        if finished then return end
        if not connected then
            -- Connecting: done when the socket can be written to; asking to
            -- connect again then says how it went.
            local _r, writable = socket.select(nil, { s }, 0)
            if writable and writable[1] then
                local ok, err = s:connect(host, port)
                if ok or err == "already connected" then connected = true
                else return finish(nil, err == "connection refused" and "refused" or tostring(err)) end
            end
        end
        if connected and not sent then
            local ok, err = s:send("GET " .. path .. " HTTP/1.0\r\nHost: " .. host .. "\r\nConnection: close\r\n\r\n")
            if not ok then return finish(nil, tostring(err)) end
            sent = true
        end
        if sent then
            local data, err, partial = s:receive("*a")
            local got = data or partial
            if got and got ~= "" then chunks[#chunks + 1] = got end
            if data or err == "closed" then return finish(parse(table.concat(chunks))) end
            if err ~= "timeout" then return finish(nil, tostring(err)) end
        end
        if socket.gettime() > deadline then return finish(nil, "took too long") end
        UIManager:scheduleIn(o.every or Get.EVERY, step)
    end
    step()
end

return Get
