-- Oflayn testlar: Telegram'ga ulanmaydi, transport soxtalashtiriladi.
-- Ishga tushirish: lua tests/run.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local json = require("bot.json")
local botlib = require("bot")

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1 print("  ok    " .. name)
  else failed = failed + 1 print("  FAIL  " .. name .. "\n        " .. tostring(err)) end
end
local function eq(a, b, msg)
  if a ~= b then error((msg or "") .. " kutilgan: " .. tostring(b) .. ", olingan: " .. tostring(a), 2) end
end

-- Soxta transport: chaqiruvlarni yozib boradi
local function mock()
  local calls = {}
  local responses = {}
  local function transport(method, params)
    calls[#calls + 1] = { method = method, params = params }
    local r = responses[method]
    if type(r) == "function" then return r(params) end
    return r or { ok = true, result = { message_id = #calls } }
  end
  return calls, responses, transport
end

local function msg_update(text, extra)
  local m = { message_id = 1, text = text, chat = { id = 42, type = "private" },
    from = { id = 7, first_name = "Ali" } }
  for k, v in pairs(extra or {}) do m[k] = v end
  return { update_id = 100, message = m }
end

print("json:")
test("encode/decode aylanmasi", function()
  local s = json.encode({ a = 1, b = { 1, 2, "x" }, c = true, d = "q\"\n" })
  local t = json.decode(s)
  eq(t.a, 1) eq(t.b[3], "x") eq(t.c, true) eq(t.d, "q\"\n")
end)
test("unicode \\u va surrogat", function()
  eq(json.decode('"\\u0053alom \\ud83d\\ude00"'), "Salom 😀")
  eq(json.decode('"O\'zbek"'), "O'zbek")
end)
test("null, bo'sh massiv, sonlar", function()
  local t = json.decode('{"x":null,"y":[],"z":-1.5e2,"w":123456789012}')
  eq(t.x, nil) eq(#t.y, 0) eq(t.z, -150) eq(t.w, 123456789012)
  eq(json.encode(json.array()), "[]")
  eq(json.encode(-1001234567890), "-1001234567890")
end)
test("noto'g'ri JSON xato beradi", function()
  eq(pcall(json.decode, "{bad}"), false)
end)

print("bot:")
test("token formati tekshiriladi", function()
  local b = botlib.new()
  eq(pcall(b.token, "yomon token"), false)
  b.token("123456:ABC-def_xyz")
end)

test("README dagi misol: /start va /help", function()
  local calls, _, tr = mock()
  local bot = botlib.new({ transport = tr })
  bot.token("1:A")
  bot.command("start", function(ctx) ctx.reply("Salom!") end)
  bot.command("help", function(ctx) ctx.reply("Yordam bo'limi") end)
  bot.handle_update(msg_update("/start"))
  bot.handle_update(msg_update("/help"))
  eq(#calls, 2)
  eq(calls[1].method, "sendMessage")
  eq(calls[1].params.chat_id, 42)
  eq(calls[1].params.text, "Salom!")
  eq(calls[2].params.text, "Yordam bo'limi")
end)

test("ctx:reply (ikki nuqta) ham ishlaydi", function()
  local calls, _, tr = mock()
  local bot = botlib.new({ transport = tr })
  bot.command("x", function(ctx) ctx:reply("ok") end)
  bot.handle_update(msg_update("/x"))
  eq(calls[1].params.text, "ok")
end)

test("buyruq argumentlari va @BotName", function()
  local _, _, tr = mock()
  local bot = botlib.new({ transport = tr })
  local got
  bot.command("echo", function(ctx) got = ctx end)
  bot.handle_update(msg_update("/Echo@MyBot  bir  ikki "))
  eq(got.command, "echo") eq(got.payload, "bir  ikki") eq(got.args[2], "ikki")
end)

test("hears pattern va captures", function()
  local _, _, tr = mock()
  local bot = botlib.new({ transport = tr })
  local m
  bot.hears("^salom (%w+)", function(ctx) m = ctx.matches[1] end)
  bot.handle_update(msg_update("salom dunyo"))
  eq(m, "dunyo")
end)

test("birinchi mos handler ishlaydi (buyruq > on('text'))", function()
  local _, _, tr = mock()
  local bot = botlib.new({ transport = tr })
  local hits = {}
  bot.command("start", function() hits[#hits + 1] = "cmd" end)
  bot.on("text", function() hits[#hits + 1] = "text" end)
  bot.handle_update(msg_update("/start"))
  bot.handle_update(msg_update("oddiy matn"))
  eq(table.concat(hits, ","), "cmd,text")
end)

test("on('photo') va update turi", function()
  local _, _, tr = mock()
  local bot = botlib.new({ transport = tr })
  local t
  bot.on("photo", function(ctx) t = ctx.update_type end)
  bot.handle_update(msg_update(nil, { photo = { { file_id = "f" } } }))
  eq(t, "message")
end)

test("action (inline tugma) + answer + edit", function()
  local calls, _, tr = mock()
  local bot = botlib.new({ transport = tr })
  bot.action("^like:(%d+)$", function(ctx)
    ctx.answer("Rahmat " .. ctx.matches[1])
    ctx.edit("Yoqdi!")
  end)
  bot.handle_update({ update_id = 5, callback_query = {
    id = "cq1", data = "like:9", from = { id = 7 },
    message = { message_id = 77, chat = { id = 42 } } } })
  eq(calls[1].method, "answerCallbackQuery")
  eq(calls[1].params.text, "Rahmat 9")
  eq(calls[2].method, "editMessageText")
  eq(calls[2].params.message_id, 77)
end)

test("inline klaviatura tuzilishi", function()
  local kb = botlib.inline({ { { "Ha", "yes" }, { text = "Sayt", url = "https://t.me" } } })
  eq(kb.inline_keyboard[1][1].callback_data, "yes")
  eq(kb.inline_keyboard[1][2].url, "https://t.me")
end)

test("middleware tartibi va to'xtatish", function()
  local _, _, tr = mock()
  local bot = botlib.new({ transport = tr })
  local log = {}
  bot.use(function(ctx, next) log[#log + 1] = "mw1" next() end)
  bot.use(function(ctx, next) if ctx.from.id == 7 then log[#log + 1] = "mw2" next() end end)
  bot.command("a", function() log[#log + 1] = "h" end)
  bot.handle_update(msg_update("/a"))
  eq(table.concat(log, ","), "mw1,mw2,h")
end)

test("handler xatosi botni to'xtatmaydi, catch chaqiriladi", function()
  local _, _, tr = mock()
  local bot = botlib.new({ transport = tr, log = function() end })
  local caught
  bot.command("boom", function() error("portladi") end)
  bot.catch(function(err) caught = err end)
  bot.handle_update(msg_update("/boom"))
  assert(tostring(caught):find("portladi"))
end)

test("API xatosi nil, tavsif qaytaradi", function()
  local _, res, tr = mock()
  res.sendMessage = { ok = false, error_code = 400, description = "Bad Request: chat not found" }
  local bot = botlib.new({ transport = tr })
  local r, err, code
  bot.command("s", function(ctx) r, err, code = ctx.reply("x") end)
  bot.handle_update(msg_update("/s"))
  eq(r, nil) eq(code, 400) assert(err:find("chat not found"))
end)

test("run(once): getMe, getUpdates, offset", function()
  local calls, res, tr = mock()
  res.getMe = { ok = true, result = { id = 1, username = "TestBot" } }
  res.getUpdates = { ok = true, result = { msg_update("/start") } }
  local bot = botlib.new({ transport = tr, log = function() end })
  local said
  bot.command("start", function(ctx) said = true end)
  bot.run({ once = true })
  eq(said, true)
  eq(bot.me.username, "TestBot")
  eq(calls[2].method, "deleteWebhook")
  eq(calls[3].method, "getUpdates")
end)

print(string.format("\n%d o'tdi, %d yiqildi", passed, failed))
os.exit(failed == 0 and 0 or 1)
