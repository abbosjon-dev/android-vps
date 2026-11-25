-- bot — Lua uchun Telegram bot paketi (android-vps).
--
--   local bot = require("bot")
--   bot.token("TOKEN")
--   bot.command("start", function(ctx) ctx.reply("Salom!") end)
--   bot.run()
--
-- Bog'liqliklar: Lua 5.1+ (yoki LuaJIT) va `curl`.

local json = require("bot.json")
local http = require("bot.http")

local M = {}
M.VERSION = "0.1.0"
M.json = json

local API_BASE = os.getenv("LUABOT_API") or "https://api.telegram.org"

local function now() return os.date("%Y-%m-%d %H:%M:%S") end

local function default_log(level, msg)
  io.stderr:write(string.format("[%s] %-5s %s\n", now(), level, msg))
  io.stderr:flush()
end

local function sleep(sec)
  os.execute("sleep " .. tonumber(sec))
end

local function shallow_merge(a, b)
  local t = {}
  for k, v in pairs(a or {}) do t[k] = v end
  for k, v in pairs(b or {}) do t[k] = v end
  return t
end

-- Lokal fayl mavjudmi? (rasm/hujjatni yuklash uchun)
local function is_local_file(s)
  if type(s) ~= "string" or s:match("^https?://") then return false end
  local f = io.open(s, "rb")
  if f then f:close() return true end
  return false
end

-- Funksiyani ham `ctx.reply(x)`, ham `ctx:reply(x)` shaklida chaqirish mumkin.
local function bind(self, fn)
  return function(first, ...)
    if first == self then return fn(...) end
    return fn(first, ...)
  end
end

---------------------------------------------------------------------------
-- Klaviatura yordamchilari
---------------------------------------------------------------------------

--- Inline tugmalar: bot.inline({ { {"Ha", "yes"}, {"Yo'q", "no"} } })
-- Tugma: {matn, callback_data} yoki {text=..., url=...} kabi to'liq jadval.
function M.inline(rows)
  local kb = {}
  for i, row in ipairs(rows) do
    kb[i] = {}
    for j, b in ipairs(row) do
      if b.text then
        kb[i][j] = b
      else
        kb[i][j] = { text = b[1], callback_data = b[2] }
      end
    end
  end
  return { inline_keyboard = kb }
end

--- Oddiy klaviatura: bot.keyboard({ {"A", "B"}, {"C"} }, { resize = true })
function M.keyboard(rows, opts)
  opts = opts or {}
  local kb = {}
  for i, row in ipairs(rows) do
    kb[i] = {}
    for j, b in ipairs(row) do
      kb[i][j] = type(b) == "table" and b or { text = b }
    end
  end
  return {
    keyboard = kb,
    resize_keyboard = opts.resize ~= false,
    one_time_keyboard = opts.once or false,
  }
end

function M.remove_keyboard() return { remove_keyboard = true } end

---------------------------------------------------------------------------
-- Bot obyekti
---------------------------------------------------------------------------

--- Yangi, mustaqil bot nusxasi yaratadi.
-- @param opts.transport  test uchun: function(method, params) -> javob jadvali
-- @param opts.log        function(level, msg)
function M.new(opts)
  opts = opts or {}
  local self = {}
  local state = {
    token = os.getenv("BOT_TOKEN"),
    routes = {},        -- { match = fn(ctx) -> bool, handler = fn }
    middlewares = {},
    catch = nil,
    running = false,
    offset = nil,
    me = nil,
  }
  local log = opts.log or default_log
  self.log = log

  -- Telegram'ga so'rov --------------------------------------------------

  local function needs_multipart(params)
    for _, v in pairs(params) do
      if type(v) == "table" and v.file then return true end
    end
    return false
  end

  local function http_transport(method, params, timeout)
    if not state.token then
      error("bot.token(...) chaqirilmagan va BOT_TOKEN o'rnatilmagan", 0)
    end
    local url = API_BASE .. "/bot" .. state.token .. "/" .. method
    local body, err
    if needs_multipart(params) then
      local fields = {}
      for k, v in pairs(params) do
        if type(v) == "table" and not v.file then
          fields[k] = json.encode(v)
        else
          fields[k] = v
        end
      end
      body, err = http.post_multipart(url, fields, timeout)
    else
      body, err = http.post_json(url, json.encode(params), timeout)
    end
    if not body then return nil, err end
    local ok, res = pcall(json.decode, body)
    if not ok then
      return nil, "javobni o'qib bo'lmadi: " .. tostring(body):sub(1, 200)
    end
    return res
  end

  local transport = opts.transport or http_transport

  --- Istalgan Bot API metodini chaqirish.
  -- @return result yoki nil, xato_matni, xato_kodi
  function self.api(method, params, timeout)
    params = params or {}
    for attempt = 1, 3 do
      local res, err = transport(method, params, timeout)
      if not res then return nil, err end
      if res.ok then return res.result end
      local retry = res.parameters and res.parameters.retry_after
      if res.error_code == 429 and retry and attempt < 3 then
        log("WARN", string.format("%s: limit (429), %ds kutilmoqda", method, retry))
        sleep(retry)
      else
        return nil, res.description or "noma'lum xato", res.error_code
      end
    end
  end

  -- Fayl/URL/file_id ni avtomatik aniqlab yuborish
  local function send_media(method, field, chat_id, media, extra)
    local p = shallow_merge({ chat_id = chat_id }, extra)
    if type(media) == "table" then
      p[field] = media
    elseif is_local_file(media) then
      p[field] = { file = media }
    else
      p[field] = media
    end
    return self.api(method, p)
  end

  -- Kontekst ---------------------------------------------------------------

  local function make_context(update)
    local ctx = { update = update, bot = self, state = {}, api = self.api }

    local msg = update.message or update.edited_message
      or update.channel_post or update.edited_channel_post
    local cq = update.callback_query
    if cq then
      ctx.callback_query = cq
      ctx.data = cq.data
      msg = msg or cq.message
    end
    ctx.message = msg
    ctx.from = (cq and cq.from) or (msg and msg.from)
      or (update.inline_query and update.inline_query.from)
    ctx.chat = msg and msg.chat
    ctx.chat_id = ctx.chat and ctx.chat.id
    ctx.text = msg and (msg.text or msg.caption)

    -- update turini aniqlash (message, callback_query, ...)
    for k in pairs(update) do
      if k ~= "update_id" then ctx.update_type = k break end
    end

    -- /buyruq@BotName argumentlar
    if not cq and ctx.text and ctx.text:sub(1, 1) == "/" then
      local cmd, at, rest = ctx.text:match("^/([%w_]+)@?([%w_]*)%s*(.-)%s*$")
      if cmd then
        local mine = at == "" or not state.me
          or at:lower() == (state.me.username or ""):lower()
        if mine then
          ctx.command = cmd:lower()
          ctx.payload = rest
          ctx.args = {}
          for a in rest:gmatch("%S+") do ctx.args[#ctx.args + 1] = a end
        end
      end
    end

    ctx.reply = bind(ctx, function(text, extra)
      if not ctx.chat_id then return nil, "chat topilmadi" end
      return self.api("sendMessage",
        shallow_merge({ chat_id = ctx.chat_id, text = tostring(text) }, extra))
    end)

    ctx.reply_html = bind(ctx, function(text, extra)
      return ctx.reply(text, shallow_merge({ parse_mode = "HTML" }, extra))
    end)

    ctx.reply_markdown = bind(ctx, function(text, extra)
      return ctx.reply(text, shallow_merge({ parse_mode = "MarkdownV2" }, extra))
    end)

    ctx.reply_photo = bind(ctx, function(photo, extra)
      return send_media("sendPhoto", "photo", ctx.chat_id, photo, extra)
    end)

    ctx.reply_document = bind(ctx, function(doc, extra)
      return send_media("sendDocument", "document", ctx.chat_id, doc, extra)
    end)

    ctx.typing = bind(ctx, function(action)
      return self.api("sendChatAction",
        { chat_id = ctx.chat_id, action = action or "typing" })
    end)

    -- callback_query ga javob (tugma "soat"ini to'xtatadi)
    ctx.answer = bind(ctx, function(text, extra)
      if not cq then return nil, "callback_query emas" end
      return self.api("answerCallbackQuery",
        shallow_merge({ callback_query_id = cq.id, text = text }, extra))
    end)

    -- Tugma bosilgan xabarni tahrirlash
    ctx.edit = bind(ctx, function(text, extra)
      if not msg then return nil, "xabar topilmadi" end
      return self.api("editMessageText", shallow_merge({
        chat_id = ctx.chat_id, message_id = msg.message_id, text = tostring(text),
      }, extra))
    end)

    ctx.delete = bind(ctx, function()
      if not msg then return nil, "xabar topilmadi" end
      return self.api("deleteMessage",
        { chat_id = ctx.chat_id, message_id = msg.message_id })
    end)

    return ctx
  end

  -- Ro'yxatdan o'tkazish -------------------------------------------------

  local function add_route(match, handler, what)
    if type(handler) ~= "function" then
      error(what .. ": handler funksiya bo'lishi kerak", 3)
    end
    state.routes[#state.routes + 1] = { match = match, handler = handler }
  end

  local function as_list(x)
    if type(x) == "table" then return x end
    return { x }
  end

  --- Token o'rnatish. Berilmasa BOT_TOKEN muhit o'zgaruvchisi ishlatiladi.
  function self.token(t)
    if type(t) ~= "string" or not t:match("^%d+:[%w_%-]+$") then
      error("bot.token: noto'g'ri token formati (masalan 123456:ABC-def)", 2)
    end
    state.token = t
    return self
  end

  --- /buyruq handleri. name: "start" yoki {"start", "boshla"}
  function self.command(names, handler)
    local set = {}
    for _, n in ipairs(as_list(names)) do
      set[(tostring(n):gsub("^/", "")):lower()] = true
    end
    add_route(function(ctx) return ctx.command ~= nil and set[ctx.command] end,
      handler, "bot.command")
    return self
  end

  --- Matn bo'yicha: aniq satr yoki Lua pattern ("^salom").
  -- Topilgan qismlar ctx.matches ga yoziladi.
  function self.hears(patterns, handler)
    local list = as_list(patterns)
    add_route(function(ctx)
      if not ctx.text or ctx.callback_query then return false end
      for _, p in ipairs(list) do
        if ctx.text == p then ctx.matches = { p } return true end
        local m = { ctx.text:match(p) }
        if m[1] ~= nil then ctx.matches = m return true end
      end
      return false
    end, handler, "bot.hears")
    return self
  end

  --- Inline tugma bosilganda (callback_data bo'yicha, aniq yoki pattern).
  function self.action(patterns, handler)
    local list = as_list(patterns)
    add_route(function(ctx)
      if not ctx.data then return false end
      for _, p in ipairs(list) do
        if ctx.data == p then ctx.matches = { p } return true end
        local m = { ctx.data:match(p) }
        if m[1] ~= nil then ctx.matches = m return true end
      end
      return false
    end, handler, "bot.action")
    return self
  end

  --- Hodisa bo'yicha: "message", "text", "photo", "document", "sticker",
  -- "voice", "location", "contact", "callback_query", "edited_message", ...
  -- Hammasi uchun: "*" (yoki "update").
  function self.on(events, handler)
    local list = as_list(events)
    add_route(function(ctx)
      for _, e in ipairs(list) do
        if e == "*" or e == "update" then return true end
        if ctx.update_type == e then return true end
        if ctx.message and ctx.message[e] ~= nil and not ctx.callback_query then
          return true
        end
      end
      return false
    end, handler, "bot.on")
    return self
  end

  --- Middleware: function(ctx, next) ... next() ... end
  function self.use(fn)
    state.middlewares[#state.middlewares + 1] = fn
    return self
  end

  --- Handlerdagi xatolarni ushlash: function(err, ctx)
  function self.catch(fn)
    state.catch = fn
    return self
  end

  -- Qayta ishlash --------------------------------------------------------

  local function dispatch(ctx)
    for _, r in ipairs(state.routes) do
      if r.match(ctx) then
        r.handler(ctx)
        return true
      end
    end
    return false
  end

  --- Bitta update'ni qayta ishlash (run() ichida va testlarda ishlatiladi).
  function self.handle_update(update)
    local ctx = make_context(update)
    local i = 0
    local function nxt()
      i = i + 1
      local mw = state.middlewares[i]
      if mw then return mw(ctx, nxt) end
      return dispatch(ctx)
    end
    local ok, err = pcall(nxt)
    if not ok then
      if state.catch then
        local ok2, err2 = pcall(state.catch, err, ctx)
        if not ok2 then log("ERROR", "catch ichida xato: " .. tostring(err2)) end
      else
        log("ERROR", "handler xatosi: " .. tostring(err))
      end
    end
    return ctx
  end

  --- Botni ishga tushirish (long polling). Ctrl+C bilan to'xtaydi.
  -- opts.timeout   — long polling vaqti (soniya, standart 30)
  -- opts.drop_pending — eski xabarlarni tashlab yuborish
  -- opts.allowed_updates — {"message", "callback_query"}
  function self.run(run_opts)
    run_opts = run_opts or {}
    local poll_timeout = run_opts.timeout or 30

    local me, err
    local backoff = 1
    repeat
      local code
      me, err, code = self.api("getMe")
      if not me then
        if code == 401 then
          error("Token noto'g'ri (401 Unauthorized) — @BotFather'dan tekshiring", 0)
        end
        log("ERROR", "getMe: " .. tostring(err) .. string.format(" (%ds dan keyin qayta)", backoff))
        if run_opts.once then return nil, err end
        sleep(backoff)
        backoff = math.min(backoff * 2, 60)
      end
    until me
    state.me = me
    self.me = me

    -- Webhook o'rnatilgan bo'lsa long polling ishlamaydi.
    self.api("deleteWebhook", { drop_pending_updates = run_opts.drop_pending or false })
    log("INFO", "Bot @" .. tostring(me.username) .. " ishga tushdi")

    state.running = true
    backoff = 1
    while state.running do
      local updates, uerr = self.api("getUpdates", {
        offset = state.offset,
        timeout = poll_timeout,
        allowed_updates = run_opts.allowed_updates,
      }, poll_timeout + 15)
      if updates then
        backoff = 1
        for _, u in ipairs(updates) do
          state.offset = u.update_id + 1
          self.handle_update(u)
        end
      else
        log("WARN", "getUpdates: " .. tostring(uerr) .. string.format(" (%ds)", backoff))
        sleep(backoff)
        backoff = math.min(backoff * 2, 60)
      end
      if run_opts.once then break end
    end
    state.running = false
    return true
  end

  function self.stop() state.running = false end

  self.inline = M.inline
  self.keyboard = M.keyboard
  self.remove_keyboard = M.remove_keyboard
  self.json = json
  self.VERSION = M.VERSION
  return self
end

-- `require("bot")` darhol ishlatsa bo'ladigan standart nusxa qaytaradi,
-- `bot.new()` esa qo'shimcha mustaqil botlar yaratadi.
local default = M.new()
default.new = M.new
return default
