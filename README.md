# android-vps

Android telefonni **VPS** sifatida ishlatib, unda **Lua** tilida Telegram botlar
yuritish uchun tizim. Asosiy qismi `bot` nomli Lua paketi:

```lua
local bot = require("bot")

bot.token("TOKEN")

bot.command("start", function(ctx)
    ctx.reply("Salom!")
end)

bot.command("help", function(ctx)
    ctx.reply("Yordam bo'limi")
end)

bot.run()
```

- Sof Lua (5.1–5.4, LuaJIT). Tashqi Lua kutubxonalari kerak emas.
- HTTPS so'rovlar `curl` orqali yuboriladi (Termux'da `pkg install curl`).
- Long polling ishlatiladi, shuning uchun telefonga oq (public) IP yoki domen kerak emas.
- Bot yiqilsa `luabot` uni avtomatik qayta yoqadi. Telefon qayta yoqilganda ham bot o'zi ishga tushadi (Termux:Boot).

---

## 1. Android'ga o'rnatish (Termux)

1. **Termux** va **Termux:Boot** ilovalarini **F-Droid**'dan o'rnating. Google Play'dagi versiya eskirgan.
2. Termux'da quyidagini bajaring:

```bash
pkg update
pkg install -y git
git clone https://github.com/abbosjon-dev/android-vps.git ~/android-vps
bash ~/android-vps/install.sh
```

`install.sh` `lua54`, `curl` va `git` paketlarini o'rnatadi va `luabot` buyrug'ini
`$PREFIX/bin` ga qo'shadi.

3. Android sozlamalarida Termux uchun **batareya optimizatsiyasini o'chiring**.
   Aks holda telefon fon jarayonlarini o'ldiradi.

## 2. Birinchi bot

1. @BotFather'dan token oling.
2. Botni ishga tushiring:

```bash
mkdir -p ~/bots && cd ~/bots
cp ~/android-vps/examples/basic.lua mybot.lua
export BOT_TOKEN="123456:ABC-xyz"   # yoki faylda bot.token("...")
luabot mybot.lua
```

Telegram'da botga `/start` yozing. Bot `Salom!` deb javob berishi kerak.

| Buyruq | Vazifasi |
|---|---|
| `luabot bot.lua` | Avto-restart bilan ishga tushiradi. Loglar `~/.luabot/logs/bot.log` ga yoziladi |
| `luabot --once bot.lua` | Bir marta ishga tushiradi (debug uchun) |
| `bash ~/android-vps/scripts/termux-boot.sh ~/bots/mybot.lua` | Telefon yoqilganda bot avtomatik ishga tushadi |

Termux sessiyasi yopilsa ham bot ishlashda davom etishi uchun `tmux` dan foydalaning:
`pkg install tmux`, keyin `tmux new -s bot`, keyin `luabot mybot.lua`.
Sessiyadan chiqish uchun `Ctrl+B` ni, keyin `D` ni bosing.

---

## 3. API qo'llanma

### Ro'yxatdan o'tkazish

| Funksiya | Vazifasi |
|---|---|
| `bot.token("123:ABC")` | Tokenni o'rnatadi. Chaqirilmasa `BOT_TOKEN` muhit o'zgaruvchisi olinadi |
| `bot.command("start", fn)` | `/start` buyrug'i. Bir nechta nom ham berish mumkin: `{"start", "boshla"}` |
| `bot.hears("^salom", fn)` | Matnni aniq satr yoki Lua pattern bilan solishtiradi. Topilganlar `ctx.matches` ga yoziladi |
| `bot.action("^like:(%d+)$", fn)` | Inline tugma bosilganda (`callback_data` bo'yicha) ishlaydi |
| `bot.on("photo", fn)` | Hodisalar: `text`, `photo`, `document`, `voice`, `sticker`, `location`, `contact`, `callback_query`, `edited_message`, ... Hammasi uchun `"*"` |
| `bot.use(function(ctx, next) ... next() end)` | Middleware: log yozish, ruxsatni tekshirish, ... |
| `bot.catch(function(err, ctx) end)` | Handlerlardagi xatolarni ushlaydi. Xato bo'lsa ham bot to'xtamaydi |
| `bot.run({ drop_pending = true })` | Long polling'ni boshlaydi |
| `bot.api("getChat", { chat_id = 1 })` | Istalgan [Bot API](https://core.telegram.org/bots/api) metodini chaqiradi |
| `bot.new()` | Bitta jarayonda bir nechta mustaqil bot yaratadi |

> **Tartib:** handlerlar ro'yxatdan o'tgan tartibda tekshiriladi va **birinchi mos kelgani**
> ishlaydi. Shuning uchun `bot.on("text", ...)` kabi umumiy handlerlarni oxirida yozing.

### `ctx` — kontekst

| Maydon / funksiya | Ma'nosi |
|---|---|
| `ctx.text`, `ctx.chat_id`, `ctx.from`, `ctx.chat`, `ctx.message` | Xabar ma'lumotlari |
| `ctx.command`, `ctx.args`, `ctx.payload` | `/echo bir ikki` uchun: `"echo"`, `{"bir","ikki"}`, `"bir ikki"` |
| `ctx.data`, `ctx.callback_query` | Bosilgan inline tugma |
| `ctx.matches` | `hears` yoki `action` pattern'idan topilgan qismlar |
| `ctx.state` | Middleware va handler o'rtasida ma'lumot uzatish uchun |
| `ctx.reply(text, extra)` | Javob yuboradi. `extra` = `{ parse_mode = "HTML", reply_markup = ... }` |
| `ctx.reply_html`, `ctx.reply_markdown` | Formatlangan javob |
| `ctx.reply_photo(x)`, `ctx.reply_document(x)` | `x` URL, `file_id` yoki **lokal fayl yo'li** bo'lishi mumkin (fayl avtomatik yuklanadi) |
| `ctx.answer(text)` | Tugma bosilganiga javob beradi (`answerCallbackQuery`) |
| `ctx.edit(text, extra)`, `ctx.delete()` | Xabarni tahrirlaydi yoki o'chiradi |
| `ctx.typing()` | "yozmoqda..." holatini ko'rsatadi |

`ctx.reply(...)` va `ctx:reply(...)`: ikkala shakl ham ishlaydi.
API funksiyalari `natija` qaytaradi. Xato bo'lsa `nil, xato_matni, xato_kodi` qaytadi.

### Klaviaturalar

```lua
ctx.reply("Tanlang:", { reply_markup = bot.inline({
  { {"👍", "vote:up"}, {"👎", "vote:down"} },
  { {text = "Sayt", url = "https://example.com"} },
}) })

ctx.reply("Menyu", { reply_markup = bot.keyboard({ {"Narxlar", "Aloqa"} }) })
ctx.reply("Yopildi", { reply_markup = bot.remove_keyboard() })
```

To'liq misol: [`examples/full.lua`](examples/full.lua).

---

## 4. Test qilish

```bash
lua tests/run.lua          # yoki lua5.4 tests/run.lua
```

Testlar oflayn ishlaydi, Telegram'ga ulanmaydi (transport soxta).
Ular JSON'ni, buyruqlarni, `hears`/`action`/`on` handlerlarini, middleware'ni, xatolarni ushlashni va `run()` siklini tekshiradi.

Haqiqiy so'rov yo'lini (`curl`) o'z serveringizda sinash uchun `LUABOT_API=http://127.0.0.1:8765`
muhit o'zgaruvchisi bilan API manzilini almashtiring.

| Muhit o'zgaruvchisi | Vazifasi |
|---|---|
| `BOT_TOKEN` | Bot tokeni |
| `LUABOT_API` | API manzili (standart: `https://api.telegram.org`) |
| `LUABOT_LUA` | Qaysi interpretator ishlatilsin (`lua5.4`, `luajit`, ...) |
| `LUABOT_CURL` | `curl` yo'li |
| `LUABOT_LOG_DIR` | Loglar papkasi |

## Tuzilma

```
bot/init.lua            asosiy paket (require("bot"))
bot/http.lua            curl orqali HTTPS
bot/json.lua            JSON encoder/decoder
bin/luabot              ishga tushiruvchi (avto-restart, loglar, wake-lock)
install.sh              Termux/Linux'ga o'rnatish
scripts/termux-boot.sh  telefon yoqilganda avtomatik ishga tushirish
examples/               misollar
tests/run.lua           testlar
```

## Xavfsizlik

- Tokenni kod ichida GitHub'ga yuklamang. `BOT_TOKEN` muhit o'zgaruvchisidan foydalaning.
- Token `curl` buyrug'i URL'ida bo'ladi, ya'ni telefondagi boshqa jarayonlar uni `ps` orqali ko'rishi mumkin.
  Shaxsiy telefonda bu muammo emas, lekin umumiy serverda e'tiborli bo'ling.
