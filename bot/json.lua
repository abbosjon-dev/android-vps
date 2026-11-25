-- bot/json.lua — kichik, tashqi bog'liqliksiz JSON encoder/decoder.
-- Lua 5.1 – 5.4 va LuaJIT bilan ishlaydi.

local json = {}

-- JSON `null` qiymati uchun maxsus belgi.
json.null = setmetatable({}, { __tostring = function() return "null" end })

---------------------------------------------------------------------------
-- Encode
---------------------------------------------------------------------------

local escapes = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function escape_str(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k <= 0 or k % 1 ~= 0 then return false end
    if k > n then n = k end
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true, n
end

local encode

local function encode_table(t, seen)
  if seen[t] then error("json.encode: aylanma (circular) jadval") end
  seen[t] = true
  local out = {}
  local arr, n = is_array(t)
  if arr and n > 0 then
    for i = 1, n do out[i] = encode(t[i], seen) end
    seen[t] = nil
    return "[" .. table.concat(out, ",") .. "]"
  end
  if arr and getmetatable(t) == json.array_mt then
    seen[t] = nil
    return "[]"
  end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = t[k]
    if v == nil then v = t[tonumber(k)] end
    out[#out + 1] = escape_str(k) .. ":" .. encode(v, seen)
  end
  seen[t] = nil
  return "{" .. table.concat(out, ",") .. "}"
end

encode = function(v, seen)
  local tv = type(v)
  if v == nil or v == json.null then
    return "null"
  elseif tv == "boolean" then
    return tostring(v)
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      error("json.encode: noto'g'ri son " .. tostring(v))
    end
    if v % 1 == 0 and v >= -2^53 and v <= 2^53 then
      return string.format("%d", v)
    end
    return string.format("%.17g", v)
  elseif tv == "string" then
    return escape_str(v)
  elseif tv == "table" then
    return encode_table(v, seen or {})
  end
  error("json.encode: qo'llab-quvvatlanmaydigan tur " .. tv)
end

--- Bo'sh massivni `[]` deb kodlash uchun: json.array({})
json.array_mt = {}
function json.array(t) return setmetatable(t or {}, json.array_mt) end

function json.encode(v) return encode(v, {}) end

---------------------------------------------------------------------------
-- Decode
---------------------------------------------------------------------------

local function utf8_char(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000),
      0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(0xF0 + math.floor(cp / 0x40000),
    0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local function decode_error(str, pos, msg)
  error(string.format("json.decode: %s (pozitsiya %d)", msg, pos), 0)
end

local function skip_ws(str, pos)
  return str:find("[^ \t\r\n]", pos) or #str + 1
end

local decode_value

local function decode_string(str, pos)
  local out, i = {}, pos + 1
  while true do
    local c = str:sub(i, i)
    if c == "" then decode_error(str, i, "yopilmagan satr") end
    if c == '"' then return table.concat(out), i + 1 end
    if c == "\\" then
      local e = str:sub(i + 1, i + 1)
      local simple = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
        ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
      if simple[e] then
        out[#out + 1] = simple[e]
        i = i + 2
      elseif e == "u" then
        local hex = str:sub(i + 2, i + 5)
        local cp = tonumber(hex, 16)
        if not cp or #hex ~= 4 then decode_error(str, i, "noto'g'ri \\u") end
        i = i + 6
        if cp >= 0xD800 and cp <= 0xDBFF and str:sub(i, i + 1) == "\\u" then
          local lo = tonumber(str:sub(i + 2, i + 5), 16)
          if lo and lo >= 0xDC00 and lo <= 0xDFFF then
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
            i = i + 6
          end
        end
        out[#out + 1] = utf8_char(cp)
      else
        decode_error(str, i, "noto'g'ri escape")
      end
    else
      local j = str:find('["\\]', i) or #str + 1
      out[#out + 1] = str:sub(i, j - 1)
      i = j
    end
  end
end

local function decode_number(str, pos)
  local s, e = str:find("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
  if not s then decode_error(str, pos, "noto'g'ri son") end
  local n = tonumber(str:sub(s, e))
  if not n then decode_error(str, pos, "noto'g'ri son") end
  return n, e + 1
end

local function decode_array(str, pos)
  local arr, n = {}, 0
  pos = skip_ws(str, pos + 1)
  if str:sub(pos, pos) == "]" then return arr, pos + 1 end
  while true do
    local v
    v, pos = decode_value(str, pos)
    n = n + 1
    arr[n] = v
    pos = skip_ws(str, pos)
    local c = str:sub(pos, pos)
    if c == "]" then return arr, pos + 1 end
    if c ~= "," then decode_error(str, pos, "',' yoki ']' kutilgan") end
    pos = skip_ws(str, pos + 1)
  end
end

local function decode_object(str, pos)
  local obj = {}
  pos = skip_ws(str, pos + 1)
  if str:sub(pos, pos) == "}" then return obj, pos + 1 end
  while true do
    if str:sub(pos, pos) ~= '"' then decode_error(str, pos, "kalit kutilgan") end
    local k
    k, pos = decode_string(str, pos)
    pos = skip_ws(str, pos)
    if str:sub(pos, pos) ~= ":" then decode_error(str, pos, "':' kutilgan") end
    local v
    v, pos = decode_value(str, skip_ws(str, pos + 1))
    obj[k] = v
    pos = skip_ws(str, pos)
    local c = str:sub(pos, pos)
    if c == "}" then return obj, pos + 1 end
    if c ~= "," then decode_error(str, pos, "',' yoki '}' kutilgan") end
    pos = skip_ws(str, pos + 1)
  end
end

decode_value = function(str, pos)
  pos = skip_ws(str, pos)
  local c = str:sub(pos, pos)
  if c == "{" then return decode_object(str, pos)
  elseif c == "[" then return decode_array(str, pos)
  elseif c == '"' then return decode_string(str, pos)
  elseif c == "-" or c:match("%d") then return decode_number(str, pos)
  elseif str:sub(pos, pos + 3) == "true" then return true, pos + 4
  elseif str:sub(pos, pos + 4) == "false" then return false, pos + 5
  elseif str:sub(pos, pos + 3) == "null" then return nil, pos + 4
  end
  decode_error(str, pos, "kutilmagan belgi '" .. c .. "'")
end

function json.decode(str)
  if type(str) ~= "string" then error("json.decode: satr kutilgan", 2) end
  local v, pos = decode_value(str, 1)
  pos = skip_ws(str, pos)
  if pos <= #str then decode_error(str, pos, "ortiqcha ma'lumot") end
  return v
end

return json
