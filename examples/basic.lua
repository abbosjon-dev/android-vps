-- Eng oddiy bot. Ishga tushirish:
--   BOT_TOKEN=123:ABC luabot examples/basic.lua
local bot = require("bot")

-- bot.token("TOKEN")  -- yoki BOT_TOKEN muhit o'zgaruvchisi

bot.command("start", function(ctx)
  ctx.reply("Salom!")
end)

bot.command("help", function(ctx)
  ctx.reply("Yordam bo'limi")
end)

bot.run()
