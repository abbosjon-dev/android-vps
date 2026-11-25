# android-vps

> ⚠️ Bu README **test uchun** yozilgan. Repozitoriy hozircha bo'sh — loyiha kodi hali qo'shilmagan.

## Loyiha haqida

`android-vps` — Android qurilmani VPS (virtual server) sifatida ishlatish yoki
serverda Android muhitini ishga tushirishga mo'ljallangan loyiha uchun ajratilgan repozitoriy.

## Repozitoriy holati

| Narsa | Holat |
|---|---|
| Kod | Yo'q (bo'sh repo) |
| Branchlar | `main` (shu README bilan yaratildi) |
| Testlar | Hali yo'q |

## Ishlab chiqish muhiti (o'rganilgan tizim)

Bu README yozilgan bulutli muhitning parametrlari:

| Parametr | Qiymat |
|---|---|
| OS | Ubuntu 24.04.5 LTS, x86_64 |
| CPU / RAM | 4 yadro / 15 GB |
| Git | 2.43.0 |
| Python | 3.13 |
| Node.js | 22.x |
| Java | OpenJDK 21 |
| Docker | 29.x |
| ADB / Android SDK | O'rnatilmagan |
| KVM (`/dev/kvm`) | Mavjud emas — Android emulyatori apparat tezlatkichisiz ishlaydi |

> Eslatma: KVM yo'qligi sababli bu muhitda Android emulyatori (yoki Redroid kabi
> konteynerlar) juda sekin ishlaydi yoki umuman ishlamaydi. Haqiqiy test uchun
> KVM qo'llab-quvvatlaydigan VPS yoki fizik qurilma kerak.

## Tezkor tekshiruv

```bash
git clone https://github.com/abbosjon-dev/android-vps.git
cd android-vps
cat README.md
```

## Keyingi qadamlar

- [ ] Loyiha maqsadi va arxitekturasini aniqlash
- [ ] Asosiy kodni qo'shish
- [ ] O'rnatish (install) va ishga tushirish yo'riqnomasini yozish
- [ ] Testlar va CI qo'shish
