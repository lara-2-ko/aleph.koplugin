-- Aleph modification, 2026-11-18: who asks KOReader to redraw many times a second.
--[[--
Two crash.logs showed "not painting 1 covered widget(s)" about 16 times a
second for as long as Aleph's Home was open (37 minutes in a row once):
something kept asking KOReader to redraw a screen hidden under another.
Nothing shows on screen, but KOReader works all the time (slower, more
battery), and KOReader does not log who asks.

This watches UIManager:setDirty. It costs a counter and a comparison per
call. When the calls stay above Watch.LIMIT a second for Watch.SECONDS
seconds in a row, the next Watch.SAMPLE calls are traced: where each came
from (the first frames outside KOReader's UIManager) and for which widget.
The most frequent caller is written to crash.log once, as a warning:

  Aleph: redraw asked 16 times a second for 3 s, mostly (40 of 40) by
  plugins/x.koplugin/y.lua:123 for widget "name"; traceback: ...

Each caller is reported once a run, at most Watch.MAX_REPORTS in all.

Aleph modification, 2026-11-19 (1.2.49): a crash.log from 1.2.47 had the
same 16 lines a second with no redraw asked at all (so nothing above was
written). The line is KOReader's: it is written each time its main loop
wakes up while a full-screen window (Aleph's Home) covers another, whether
anything is drawn or not. What wakes it 16 times a second is something that
asks to be woken every 50 ms: a plugin's message queue (UIManager:insertZMQ,
looked at every 50 ms while there is one) or a task that schedules itself
again and again. So the loop's wake-ups are counted too (wrapping
UIManager:_repaint, which runs once a wake-up), and when they stay above
Watch.LIMIT a second for Watch.WAKE_SECONDS seconds, once a run:

  Aleph: KOReader wakes 16 times a second: 1 message queue (plugins/x/y.lua:12);
  tasks due next: plugins/z.lua:40 (38 of 40)
]]

local Watch = {}

Watch.LIMIT = 8               -- calls a second that count as many
Watch.SECONDS = 3             -- for this many seconds in a row
Watch.SAMPLE = 40             -- calls traced, then the report
Watch.MAX_REPORTS = 5
Watch.WAKE_SECONDS = 5        -- wake-ups: longer than a swipe or a drag lasts

local second, count, streak = 0, 0, 0
local sampling                -- { [key] = { n, where, widget, trace } } while tracing
local sampled = 0
local reported = {}
local reports = 0
local installed

local function widgetName(w)
    if w == nil then return "nil" end
    if type(w) ~= "table" then return tostring(w) end
    local name = rawget(w, "name") or w.name
    if type(name) == "string" then return name end
    local id = rawget(w, "id")
    if type(id) == "string" then return id end
    return tostring(w):gsub("^table: ", "table ")
end

-- The first frame that is not UIManager itself nor this file.
local function caller()
    for level = 3, 12 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        local src = info.short_src or "?"
        if not src:find("uimanager", 1, true) and not src:find("aleph_redraw_watch", 1, true) and src ~= "[C]" then
            return src .. ":" .. tostring(info.currentline)
        end
    end
    return "unknown"
end

function Watch.report(seconds_long, rate)
    local best
    for _k, s in pairs(sampling or {}) do
        if not best or s.n > best.n then best = s end
    end
    sampling, sampled = nil, 0
    if not best or reported[best.where] then return nil end
    reported[best.where] = true
    reports = reports + 1
    local text = string.format("redraw asked %d times a second for %d s, mostly (%d of %d) by %s for widget \"%s\"; traceback: %s",
        rate, seconds_long, best.n, Watch.SAMPLE, best.where, best.widget, best.trace)
    pcall(function() require("logger").warn("Aleph: " .. text) end)
    return text
end

-- Counts one call; `widget` is setDirty's first argument. `now` is for tests.
function Watch.count(widget, now)
    if reports >= Watch.MAX_REPORTS then return end
    now = now or os.time()
    if now ~= second then
        if now == second + 1 and count > Watch.LIMIT then streak = streak + 1 else streak = 0 end
        Watch.last_rate = count
        second, count = now, 0
        if streak >= Watch.SECONDS and not sampling then sampling, sampled = {}, 0 end
    end
    count = count + 1
    if sampling then
        local where = caller()
        local s = sampling[where]
        if not s then
            s = { n = 0, where = where, widget = widgetName(widget),
                trace = (debug.traceback("", 2) or ""):gsub("\n%s*", " | ") }
            sampling[where] = s
        end
        s.n = s.n + 1
        sampled = sampled + 1
        if sampled >= Watch.SAMPLE then
            Watch.report(streak, Watch.last_rate or count)
            streak = 0
        end
    end
end

-- ------------------------------------------------------------ wake-ups
local wake_second, wake_count, wake_streak = 0, 0, 0
local wake_samples, wake_sampled, wake_reported = nil, 0, false

local function fnWhere(fn)
    if type(fn) ~= "function" then return nil end
    local info = debug.getinfo(fn, "S")
    return info and ((info.short_src or "?") .. ":" .. tostring(info.linedefined)) or nil
end

-- Where a message queue's code is: its first own function (or its class's).
local function queueWhere(q)
    if type(q) ~= "table" then return tostring(q) end
    for _i, t in ipairs({ q, getmetatable(q) and getmetatable(q).__index or {} }) do
        if type(t) == "table" then
            for _k, v in pairs(t) do
                local w = fnWhere(v)
                if w then return w end
            end
        end
    end
    return "?"
end

function Watch.wakeReport(UIManager, rate)
    wake_reported = true
    local queues = {}
    for _i, q in ipairs(UIManager._zeromqs or {}) do queues[#queues + 1] = queueWhere(q) end
    local best, best_n, total = nil, 0, 0
    for where, n in pairs(wake_samples or {}) do
        total = total + n
        if n > best_n then best, best_n = where, n end
    end
    wake_samples, wake_sampled = nil, 0
    local text = string.format("KOReader wakes %d times a second: %d message queue(s)%s; tasks due next: %s",
        rate, #queues, #queues > 0 and (" (" .. table.concat(queues, ", ") .. ")") or "",
        best and string.format("%s (%d of %d)", best, best_n, total) or "none")
    pcall(function() require("logger").warn("Aleph: " .. text) end)
    return text
end

-- Counts one wake-up of the main loop; `now` is for tests.
function Watch.wake(UIManager, now)
    if wake_reported then return end
    now = now or os.time()
    if now ~= wake_second then
        if now == wake_second + 1 and wake_count > Watch.LIMIT then wake_streak = wake_streak + 1 else wake_streak = 0 end
        Watch.last_wake_rate = wake_count
        wake_second, wake_count = now, 0
        if wake_streak >= Watch.WAKE_SECONDS and not wake_samples then wake_samples, wake_sampled = {}, 0 end
    end
    wake_count = wake_count + 1
    if wake_samples then
        -- The task due first is what woke the loop, when one did.
        local first = UIManager._task_queue and UIManager._task_queue[1]
        local where = first and fnWhere(first.action) or "no task due"
        wake_samples[where] = (wake_samples[where] or 0) + 1
        wake_sampled = wake_sampled + 1
        if wake_sampled >= Watch.SAMPLE then Watch.wakeReport(UIManager, Watch.last_wake_rate or wake_count) end
    end
end

-- Wraps UIManager:setDirty once.
function Watch.install(UIManager)
    UIManager = UIManager or require("ui/uimanager")
    if installed or type(UIManager.setDirty) ~= "function" then return false end
    local original = UIManager.setDirty
    UIManager.setDirty = function(self, widget, ...)
        pcall(Watch.count, widget)
        return original(self, widget, ...)
    end
    if type(UIManager._repaint) == "function" then
        local repaint = UIManager._repaint
        UIManager._repaint = function(self, ...)
            pcall(Watch.wake, self)
            return repaint(self, ...)
        end
    end
    installed = true
    return true
end

-- For tests.
function Watch.reset()
    second, count, streak, sampling, sampled, reported, reports = 0, 0, 0, nil, 0, {}, 0
    wake_second, wake_count, wake_streak, wake_samples, wake_sampled, wake_reported = 0, 0, 0, nil, 0, false
end

return Watch
