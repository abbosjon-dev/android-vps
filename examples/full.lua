-- Paketning ko'p imkoniyatlarini ko'rsatuvchi misol.
--   BOT_TOKEN=123:ABC luabot examples/full.lua
local bot = require("bot")

-- Har bir xabarni logga yozuvchi middleware
bot.use(function(ctx, next)
  local who = ctx.from and (ctx.from.username or ctx.from.first_name) or "?"
  bot.log("INFO", who .. ": " .. tostring(ctx.text or ctx.data or ctx.update_type))
  next()
end)

bot.command("start", function(ctx)
  ctx.reply("Salom, " .. ctx.from.first_name .. "! Tanlang:", {
    reply_markup = bot.inline({
      { { "👍 Yoqdi", "vote:up" }, { "👎 Yoqmadi", "vote:down" } },
      { { text = "Telegram", url = "https://telegram.org" } },
    }),
  })
end)

bot.command({ "echo", "say" }, function(ctx)
  if ctx.payload == "" then return ctx.reply("Foydalanish: /echo matn") end
  ctx.reply(ctx.payload)
end)

bot.command("menu", function(ctx)
  ctx.reply("Menyu:", { reply_markup = bot.keyboard({ { "Narxlar", "Aloqa" }, { "Yopish" } }) })
end)

bot.hears("Yopish", function(ctx)
  ctx.reply("Yopildi", { reply_markup = bot.remove_keyboard() })
end)

bot.hears("^[Ss]alom", function(ctx) ctx.reply("Va alaykum assalom!") end)

bot.action("^vote:(%a+)$", function(ctx)
  local v = ctx.matches[1]
  ctx.answer(v == "up" and "Rahmat!" or "Afsus :(")
  ctx.edit("Ovozingiz qabul qilindi: " .. v)
end)

bot.on("photo", function(ctx) ctx.reply("Chiroyli rasm 📷") end)

bot.on("text", function(ctx) ctx.reply("Siz yozdingiz: " .. ctx.text) end)

bot.catch(function(err, ctx)
  bot.log("ERROR", tostring(err))
  if ctx.chat_id then ctx.reply("Xatolik yuz berdi, keyinroq urinib ko'ring.") end
end)

bot.run({ drop_pending = true })
