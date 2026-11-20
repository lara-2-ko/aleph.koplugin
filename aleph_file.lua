-- Aleph modification, 2026-11-15: small Lua data files, read and written in
-- one place.
--[[--
X-Ray's names, hits and story, and the answers background processes hand
back, are Lua tables kept as files ("return { ... }"). Each of those parts
had its own copy of the same reader and writer.

    local File = require("aleph_file")
    File.write(path, value)   -- true when written
    File.read(path)           -- the table, or nil (no file, not a table, broken)

A file is written beside its place (path .. ".part") and moved there whole,
so one half written (the device going to sleep, the process stopped) is
never read. Tables may hold strings, numbers, booleans and tables; list
items first, in order, then named and other numbered keys.
]]

local File = {}

local function dump(value, out, depth)
    local t = type(value)
    if t == "table" then
        out[#out + 1] = "{"
        local n = #value
        for i = 1, n do
            dump(value[i], out, depth + 1)
            out[#out + 1] = ","
        end
        for k, v in pairs(value) do
            local kt = type(k)
            if kt == "string" then
                out[#out + 1] = "[" .. string.format("%q", k) .. "]="
                dump(v, out, depth + 1)
                out[#out + 1] = ","
            elseif kt == "number" and not (k >= 1 and k <= n and k % 1 == 0) then
                out[#out + 1] = "[" .. tostring(k) .. "]="
                dump(v, out, depth + 1)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = depth <= 2 and "}\n" or "}"
    elseif t == "string" then
        out[#out + 1] = string.format("%q", value)
    elseif t == "number" or t == "boolean" then
        out[#out + 1] = tostring(value)
    else
        out[#out + 1] = "nil"
    end
end

-- The text of a value, as File.write writes it after "return ".
function File.text(value)
    local out = {}
    dump(value, out, 1)
    return table.concat(out)
end

function File.write(path, value)
    local f = io.open(path .. ".part", "w")
    if not f then return false end
    f:write("return ", File.text(value))
    f:close()
    return os.rename(path .. ".part", path) and true or false
end

function File.read(path)
    local fn = path and loadfile(path) or nil
    if not fn then return nil end
    local ok, value = pcall(fn)
    return ok and type(value) == "table" and value or nil
end

return File
