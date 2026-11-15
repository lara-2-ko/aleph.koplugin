-- Aleph modification, 2026-11-11: receiving the Goodreads sign-in cookie from
-- a computer's browser.
--[[--
The Goodreads plugin by advokatb (goodreads.koplugin, 0.5.0) signs in to
goodreads.com with the cookies of a browser where the reader is signed in,
pasted by hand into its menu. They expire after a few weeks, and pasting a
long cookie on an e-reader is hard.

Settings > Library > Goodreads sign-in (shown only when that plugin is installed) opens a small
screen that listens on the local network for a few minutes, with the
device's address and a four-digit code. The "Aleph Goodreads cookie"
extension for Chrome, Edge or Firefox (aleph-goodreads-cookie.zip, next to
Aleph's release) reads the browser's goodreads.com cookies and sends them there with
the code. Aleph saves them in the Goodreads plugin's settings, as its own
"Session cookies" menu does, and stops listening.

The cookies travel over the local network without encryption: the screen
says so. Five wrong codes, ten minutes or closing the screen stop it. On a
Kindle the firewall is opened for the port while it listens and closed
again after (as KOReader's HTTP inspector does).

The request:  POST /goodreads-cookie, body {"code": "1234", "cookie": "a=b; c=d"}
The answer:   {"ok": true} or {"ok": false, "error": "code" | "cookie" | ...}
              GET / answers {"aleph": "goodreads-cookie"} (the extension's test)
]]

local _ = require("gettext")
local logger = require("logger")
local try = require("aleph_try").call

local GR = {}

GR.PORT = 8769
GR.PORTS_TRIED = 5
GR.MAX_TRIES = 5
GR.MINUTES = 10
GR.MAX_BODY = 65536

-- ------------------------------------------------------------ the plugin
-- advokatb's plugin: named "goodreads", with a settings object that keeps
-- the cookie under "session_cookie" (other Goodreads plugins differ).
local function isTheOne(p)
    if type(p) ~= "table" then return false end
    local s = p.settings
    return type(s) == "table" and type(s.setCookie) == "function" and type(s.getCookie) == "function"
        and s.KEY_COOKIE == "session_cookie"
end
GR.isTheOne = isTheOne

local function hosts(ui)
    local ok, list = pcall(function() return require("aleph_plugins").hosts(ui) end)
    return ok and list or (ui and { ui } or {})
end

-- Every running instance of the plugin (the file browser's and the reader's).
function GR.instances(ui)
    local out, seen = {}, {}
    local function add(p)
        if isTheOne(p) and not seen[p] then seen[p] = true; out[#out + 1] = p end
    end
    for _i, h in ipairs(hosts(ui)) do
        try(function() add(rawget(h, "goodreads") or h.goodreads) end)
    end
    try(function() add(require("pluginloader"):getPluginInstance("goodreads")) end)
    return out
end

function GR.plugin(ui) return GR.instances(ui)[1] end
function GR.available(ui) return GR.plugin(ui) ~= nil end

-- Drops jwt_token (it expires in minutes; the plugin strips it too) and
-- blank parts. Returns the cookie and how many name=value pairs it holds.
function GR.clean(cookie)
    if type(cookie) ~= "string" then return "", 0 end
    local parts = {}
    for part in cookie:gmatch("[^;]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        local name = part:match("^([^=]+)=")
        if name and name ~= "jwt_token" and not part:find("[\r\n]") then parts[#parts + 1] = part end
    end
    return table.concat(parts, "; "), #parts
end

-- Saves `cookie` in the plugin, as its "Session cookies" menu does.
function GR.save(ui, cookie)
    local list = GR.instances(ui)
    if #list == 0 then return false end
    for _i, p in ipairs(list) do
        try(function() p.settings:setCookie(cookie) end)
        try(function() if p.settings.clearSessionCache then p.settings:clearSessionCache() end end)
    end
    try(function()
        local Api = package.loaded["goodreads_api"]
        local backend = Api and Api._get_backend and Api:_get_backend()
        if backend and backend.reset_csrf_token then backend:reset_csrf_token() end
    end)
    try(function() if list[1].onCookiesSaved then list[1]:onCookiesSaved() end end)
    logger.info("Aleph: Goodreads cookie received and saved")
    return true
end

-- ------------------------------------------------------------- requests
local function decode(s)
    local ok, v = pcall(function() return require("rapidjson").decode(s) end)
    if ok and type(v) == "table" then return v end
    ok, v = pcall(function() return require("json").decode(s) end)
    if ok and type(v) == "table" then return v end
    return nil
end

local function encode(t)
    local parts = {}
    for k, v in pairs(t) do
        local val = type(v) == "string" and ('"' .. v:gsub('[%c"\\]', "") .. '"') or tostring(v)
        parts[#parts + 1] = '"' .. k .. '":' .. val
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end
GR.encode = encode

-- The request line and headers (names in lower case).
function GR.parseHead(lines)
    local method, path = (lines[1] or ""):match("^(%u+)%s+(%S+)")
    local headers = {}
    for i = 2, #lines do
        local k, v = lines[i]:match("^([^:]+):%s*(.-)%s*$")
        if k then headers[k:lower()] = v end
    end
    return method, path, headers
end

-- What to answer: status, body table. state: { code, tries, done } and
-- on_cookie(cookie) (true when saved). Pure, for tests.
function GR.answer(state, method, path, body)
    path = (path or ""):match("^[^?]*")
    if method == "OPTIONS" then return 204, nil end
    -- A page of the e-reader's own, for browsers that will not let the
    -- extension reach the local network: the extension opens it in a tab
    -- and sends from inside it, as the page itself (same origin).
    if method == "GET" and path == "/aleph" then return 200, GR.PAGE end
    if method == "GET" and (path == "/" or path == "/goodreads-cookie") then
        return 200, { aleph = "goodreads-cookie", ok = true }
    end
    if method ~= "POST" or path ~= "/goodreads-cookie" then return 404, { ok = false, error = "not-found" } end
    if state.done then return 410, { ok = false, error = "closed" } end
    local req = decode(body or "")
    if not req then return 400, { ok = false, error = "bad-request" } end
    if tostring(req.code or "") ~= state.code then
        state.tries = (state.tries or 0) + 1
        return 403, { ok = false, error = "code", left = math.max(0, GR.MAX_TRIES - state.tries) }
    end
    local cookie, n = GR.clean(req.cookie)
    if n == 0 or #cookie > 32768 then return 400, { ok = false, error = "cookie" } end
    if not state.on_cookie(cookie, n) then return 500, { ok = false, error = "save" } end
    state.done = true
    return 200, { ok = true }
end

local REASONS = { [200] = "OK", [204] = "No Content", [400] = "Bad Request", [403] = "Forbidden",
    [404] = "Not Found", [410] = "Gone", [413] = "Payload Too Large", [500] = "Internal Server Error" }

GR.PAGE = [[<!doctype html><html><head><meta charset="utf-8"><title>Aleph</title></head>
<body style="font:16px system-ui,sans-serif;padding:24px">Aleph is receiving the Goodreads cookie&hellip; This tab closes by itself.</body></html>]]

function GR.response(status, body)
    local html = type(body) == "string"
    local text = html and body or (body and encode(body) or "")
    return table.concat({
        "HTTP/1.1 " .. status .. " " .. (REASONS[status] or "OK"),
        html and "Content-Type: text/html; charset=utf-8" or "Content-Type: application/json",
        "Cache-Control: no-store",
        "Access-Control-Allow-Origin: *",
        "Access-Control-Allow-Methods: GET, POST, OPTIONS",
        "Access-Control-Allow-Headers: Content-Type",
        "Access-Control-Allow-Private-Network: true",
        "Content-Length: " .. #text,
        "Connection: close",
        "", text,
    }, "\r\n")
end

-- --------------------------------------------------------------- server
-- The device's address on the local network: the one a packet to the
-- outside would leave from (nothing is sent).
function GR.localIp()
    local ip
    try(function()
        local socket = require("socket")
        local u = socket.udp()
        u:setpeername("192.0.2.1", 9)
        ip = u:getsockname()
        u:close()
    end)
    if ip == "0.0.0.0" or ip == "127.0.0.1" then ip = nil end
    return ip
end

local function firewall(port, open)
    local ok, Device = pcall(require, "device")
    if not (ok and Device:isKindle()) then return end
    local flag = open and "-A" or "-D"
    local a = os.execute(string.format("iptables %s INPUT -p tcp --dport %d -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT", flag, port))
    local b = os.execute(string.format("iptables %s OUTPUT -p tcp --sport %d -m conntrack --ctstate ESTABLISHED -j ACCEPT", flag, port))
    logger.info("Aleph: Goodreads cookie: Kindle firewall", flag, port, tostring(a), tostring(b))
end

local Server = {}
Server.__index = Server

-- Listens on the first free port from GR.PORT. Returns the server or nil, why.
function GR.listen(state)
    local socket = require("socket")
    local last
    for port = GR.PORT, GR.PORT + GR.PORTS_TRIED - 1 do
        local srv, err = socket.bind("*", port)
        if srv then
            srv:settimeout(0)
            firewall(port, true)
            logger.info("Aleph: Goodreads cookie: listening on", GR.localIp(), port)
            return setmetatable({ server = srv, port = port, state = state }, Server)
        end
        last = err
    end
    return nil, last
end

local function readRequest(client)
    client:settimeout(1, "t")
    local lines = {}
    while #lines < 100 do
        local line = client:receive("*l")
        if not line then return nil end
        if line == "" then break end
        lines[#lines + 1] = line
    end
    local method, path, headers = GR.parseHead(lines)
    local len = tonumber(headers["content-length"] or 0) or 0
    if len > GR.MAX_BODY then return method, path, nil, true end
    local body = ""
    if len > 0 then body = client:receive(len) or "" end
    return method, path, body
end

-- Called by KOReader's main loop (UIManager:insertZMQ). Returns nothing: a
-- value would be taken for an input event.
function Server:waitEvent()
    if not self.server then return end
    local client = self.server:accept()
    if not client then return end
    local ok, err = pcall(function()
        local method, path, body, too_big = readRequest(client)
        logger.info("Aleph: Goodreads cookie: request", tostring(method), tostring(path), "from", tostring((client:getpeername())))
        local status, answer
        if too_big then status, answer = 413, { ok = false, error = "too-big" }
        elseif not method then return
        else status, answer = GR.answer(self.state, method, path, body) end
        client:send(GR.response(status, answer))
        if self.state.after then self.state.after(status, answer) end
    end)
    pcall(function() client:close() end)
    if not ok then logger.warn("Aleph: Goodreads cookie request failed:", err) end
end

function Server:stop()
    if not self.server then return end
    pcall(function() self.server:close() end)
    self.server = nil
    firewall(self.port, false)
end

-- --------------------------------------------------------------- screen
local function code4()
    math.randomseed(os.time() + math.floor((os.clock() * 1e6) % 1e6))
    return string.format("%04d", math.random(0, 9999))
end
GR.code4 = code4

-- Opens the screen; turns Wi-Fi on first when it is off.
function GR.open(ui)
    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:isConnected() then return GR.show(ui) end
    NetworkMgr:runWhenConnected(function() GR.show(ui) end)
end

function GR.show(ui)
    local UIManager = require("ui/uimanager")
    local Geom = require("ui/geometry")
    local T = require("ffi/util").template
    local BoardMetrics = require("aleph_board_metrics")
    local BoardUI = require("aleph_board_ui")
    local MenuUI = require("aleph_menu_ui")
    local Panel = require("aleph_panel")
    local INK, px, floor = BoardMetrics.INK, BoardMetrics.px, math.floor

    local panel, server, timer
    local state = { code = code4(), tries = 0 }
    local status = "wait" -- wait | saved | tries | timeout | error
    local note

    local function stop()
        if timer then UIManager:unschedule(timer); timer = nil end
        if server then UIManager:removeZMQ(server); server:stop(); server = nil end
    end

    state.on_cookie = function(cookie) return GR.save(ui, cookie) end
    state.after = function(code, answer)
        if answer and answer.ok and code == 200 and state.done then
            status = "saved"
            stop()
        elseif answer and answer.error == "code" then
            if state.tries >= GR.MAX_TRIES then status = "tries"; stop() end
            note = T(_("A wrong code was sent (%1 tries left)."), math.max(0, GR.MAX_TRIES - state.tries))
        elseif answer and answer.error == "cookie" then
            note = _("What arrived was not a cookie. Sign in to goodreads.com in that browser and send again.")
        elseif not (answer and answer.ok == false) then
            -- The extension's check, or the address opened in a browser:
            -- the network path works.
            note = T(_("A computer reached this e-reader at %1. Waiting for the cookie…"), os.date("%H:%M"))
        end
        if panel and not panel.closed then panel:refresh() end
    end

    local ip = GR.localIp()
    local err
    server, err = GR.listen(state)
    if server then
        UIManager:insertZMQ(server)
        timer = function()
            timer = nil
            if status == "wait" then status = "timeout"; stop(); if panel and not panel.closed then panel:refresh() end end
        end
        UIManager:scheduleIn(GR.MINUTES * 60, timer)
    else
        status = "error"
        note = tostring(err or "")
    end

    local function statusText()
        if status == "saved" then return _("Cookie received and saved. The Goodreads plugin is signed in again.") end
        if status == "tries" then return _("Too many wrong codes: stopped listening. Open this screen again for a new code.") end
        if status == "timeout" then return T(_("Stopped listening after %1 minutes. Open this screen again to try once more."), GR.MINUTES) end
        if status == "error" then return T(_("Could not listen on the network: %1"), note) end
        return T(_("Waiting… (listens for %1 minutes)"), GR.MINUTES)
    end

    panel = Panel:new{
        dismiss = false,
        build = function(p, sw, sh)
            local w = math.min(px(500), sw - 2 * px(16))
            local pad = px(18)
            local iw = w - 2 * pad
            local address = (ip or "?") .. ":" .. (server and server.port or GR.PORT)
            local listening = status == "wait"
            local items = {
                BoardUI.text(_("Receive Goodreads cookie"), { s = 19, b = true, w = iw }),
                BoardUI.space(nil, px(10)),
                BoardUI.text(_("On your computer, sign in to goodreads.com, then open the Aleph Goodreads cookie extension and enter:"),
                    { s = 15, col = INK.g2, w = iw, lines = 4 }),
                BoardUI.space(nil, px(12)),
            }
            if listening then
                items[#items + 1] = BoardUI.text(_("Address"), { s = 13, col = INK.g4, w = iw })
                items[#items + 1] = BoardUI.text(address, { s = 24, b = true, w = iw, data = true })
                items[#items + 1] = BoardUI.space(nil, px(8))
                items[#items + 1] = BoardUI.text(_("Code"), { s = 13, col = INK.g4, w = iw })
                items[#items + 1] = BoardUI.text(state.code, { s = 30, b = true, w = iw, data = true })
                items[#items + 1] = BoardUI.space(nil, px(12))
                if not ip then
                    items[#items + 1] = BoardUI.text(_("The address could not be found: check that Wi-Fi is connected."), { s = 14, col = INK.g2, w = iw, lines = 3 })
                    items[#items + 1] = BoardUI.space(nil, px(8))
                end
            end
            items[#items + 1] = BoardUI.text(statusText(), { s = 15, b = status == "saved", w = iw, lines = 4, data = status == "error" })
            if note and listening then
                items[#items + 1] = BoardUI.space(nil, px(6))
                items[#items + 1] = BoardUI.text(note, { s = 14, col = INK.g2, w = iw, lines = 3 })
            end
            if listening then
                items[#items + 1] = BoardUI.space(nil, px(10))
                items[#items + 1] = BoardUI.text(_("The computer must be on the same network. The cookie crosses it unencrypted, so use this on a network you trust. Keep this screen open until it arrives."),
                    { s = 13, col = INK.g4, w = iw, lines = 5 })
            end
            items[#items + 1] = BoardUI.space(nil, px(18))
            items[#items + 1] = MenuUI.pill(listening and _("Stop") or _("Close"),
                { kind = listening and "outline" or "dark", w = iw, h = 48, s = 16, action = { kind = "close" } })
            local content = BoardUI.vstack({ w = w, pad = pad }, items)
            local border = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * border
            local widget = BoardUI.box({ w = w, h = ph, radius = px(16), bg = INK.white, border = border, border_col = INK.g6 }, content)
            local x, y = floor((sw - w) / 2), math.max(px(8), floor((sh - ph) / 2))
            p.panel_rect = Geom:new{ x = x, y = y, w = w, h = ph }
            return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
        end,
        on_action = function(p, action)
            if action.kind == "close" then p:close() end
        end,
    }
    -- However it closes, it stops listening.
    local base_close = panel.onCloseWidget
    panel.onCloseWidget = function(self, ...)
        stop()
        return base_close(self, ...)
    end
    panel:show()
    return panel, state
end

return GR
