-- bot/http.lua — `curl` orqali HTTPS so'rovlar.
-- Termux'da: `pkg install curl`. Tashqi Lua kutubxonasi kerak emas.

local http = {}

-- Shell uchun xavfsiz qo'shtirnoq: 'abc' -> 'abc', a'b -> 'a'\''b'
local function q(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end
http.quote = q

http.curl = os.getenv("LUABOT_CURL") or "curl"

local function run(cmd)
  local p, err = io.popen(cmd, "r")
  if not p then return nil, "popen xatosi: " .. tostring(err) end
  local out = p:read("*a")
  local ok, _, code = p:close()
  -- Lua 5.1 da close() faqat true qaytaradi; bo'sh javob — xato belgisi.
  if ok == nil or ok == false then
    return nil, "curl xatosi (kod " .. tostring(code) .. "): " .. (out or "")
  end
  if out == nil or out == "" then
    return nil, "curl bo'sh javob qaytardi (tarmoq yo'qmi?)"
  end
  return out
end

--- JSON tanali POST so'rov.
-- @param url     to'liq URL
-- @param body    JSON satr (yoki nil)
-- @param timeout soniyalarda umumiy kutish vaqti
function http.post_json(url, body, timeout)
  local tmp = os.tmpname()
  local f, err = io.open(tmp, "wb")
  if not f then return nil, "vaqtinchalik fayl ochilmadi: " .. tostring(err) end
  f:write(body or "{}")
  f:close()
  local cmd = table.concat({
    http.curl, "-sS",
    "--max-time", tostring(timeout or 30),
    "-X", "POST",
    "-H", q("Content-Type: application/json"),
    "--data-binary", q("@" .. tmp),
    q(url), "2>&1",
  }, " ")
  local out, rerr = run(cmd)
  os.remove(tmp)
  return out, rerr
end

--- multipart/form-data so'rov (fayl yuborish uchun).
-- @param fields { key = "matn", photo = { file = "/yo'l/rasm.jpg" } }
function http.post_multipart(url, fields, timeout)
  local parts = { http.curl, "-sS", "--max-time", tostring(timeout or 120) }
  for k, v in pairs(fields) do
    if type(v) == "table" and v.file then
      parts[#parts + 1] = "-F"
      parts[#parts + 1] = q(k .. "=@" .. v.file)
    else
      parts[#parts + 1] = "--form-string"
      parts[#parts + 1] = q(k .. "=" .. tostring(v))
    end
  end
  parts[#parts + 1] = q(url)
  parts[#parts + 1] = "2>&1"
  return run(table.concat(parts, " "))
end

return http
