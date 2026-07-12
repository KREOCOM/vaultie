# Vaultie — Onboarding + Recurring‑Hero Plan

Statusas: **planas, dar nestatoma.** Paremtas 4 partijų Bilance studija (onboarding 32 ekr. + jungtis 20 ekr. + pilna app 20 ekr.) ir esamu Vaultie kodu.

---

## 0. Šiaurės žvaigždė (strateginė kryptis)

**Vaultie = recurring payments tracker. Home = recurring herojus, NE transakcijų feed'as.**

| | Bilance | Vaultie |
|---|---|---|
| Esmė | Spending tracker (5 tab'ai) | Recurring tracker (lean) |
| Recurring vieta | **Užkasta** Planning tab'e, tuščias „Add recurring", rankinė | **Home ekranas #1**, auto‑aptikta |
| Prenumeratos | Išbarstytos feed'e (Anthropic, apple.com, Dribbble, Replit…) | **Surinktos: „N prenumeratų · €X/mėn"** |
| Auto‑detect | Nėra (rankinis) | ⭐ Backend jau daro (merchant DB + AI) |
| Duomenys | Google Cloud serveriuose | **Tik telefone** (GDPR — jokio serverio saugojimo) |
| Bankas | Pay‑first → connect‑after (35.99€) | **Du keliai: bankas + rankinis, be pay‑gate** |
| Bankai | 2800+ (GoCardless) | Tik SEB / Enable Banking (kol kas) |

**Ką kopijuojam iš Bilance (pakreipta į recurring):** privatumo blur (akies ikona → `****`), feed kaip **antrinis** ekranas, mėnesio wrap‑up → „prenumeratos šį mėnesį", AI report (turim Anthropic API), progress bar onboarding'e, empatijos/diagnostikos apklausa, native banko poliavimas.

**Ko NEsivaikom:** net worth / assets, pilni biudžetai, 5 sunkūs tab'ai, spending‑first feed kaip herojus.

---

## 1. Pilna seka (splash → recurring‑herojus dashboard)

Legenda: `[BŪTINA]` / `[verta]` / `[nauja]` / `[esama]` / `[enhance]`.

### A fazė — Onboarding (splash → 2 keliai)

| # | Ekranas | Būsena | Copy antraštė (LT) |
|---|---------|--------|--------------------|
| A1 | Splash | `[esama]` | „Vaultie · Išmanesni pinigų įpročiai" |
| A2 | Welcome | `[nauja]` | „Susigrąžink kontrolę nuo pamirštų prenumeratų" · CTA „Pradėti" + „Jau turiu paskyrą" |
| A3 | Empatija 1 | `[nauja]` | „Pamirštos prenumeratos tyliai valgo tavo pinigus" |
| A4 | Empatija 2 | `[verta]` | „Vidutinis žmogus permoka €X/mėn už tai, ko nebenaudoja" |
| A5 | Profilis: amžius | `[nauja]` | „Kiek tau metų?" (18‑24/25‑34/35‑44/45+) · progress bar „Tavo profilis" |
| A6 | Profilis: jausmas | `[verta]` | „Kaip jautiesi dėl finansų?" (Valdau/OK/Nerimauju/Blogai) |
| A7 | **Value** | `[nauja]` | „Pamatyk visas savo prenumeratas vienoje vietoje" (recurring mockup) |
| A8 | Tikslai | `[nauja]` | „Ką nori pasiekti?" (Sustabdyti pamirštas / Matyti recurring / Mažiau streso) · „Tavo tikslai" |
| A9 | **Value herojus** | `[BŪTINA]` | „Tavo pasikartojantys mokėjimai — surinkti automatiškai" |
| A10 | Diagnostika 1 | `[BŪTINA]` | „Ar dažnai pamiršti atšaukti prenumeratas?" Taip/Ne · „Finansų įpročiai" |
| A11 | Diagnostika 2 | `[verta]` | „Ar žinai TIKSLIAI kiek prenumeratų turi dabar?" Taip/Ne |
| A12 | Reassurance | `[verta]` | „Ačiū už atvirumą — dauguma neįvertina. Vaultie parodys tikrą skaičių" |
| A13 | **Value AI** | `[BŪTINA]` | „AI atpažįsta tavo mokėjimus" (Netflix‑stiliaus, **jau turim backend'e**) |
| A14 | Prognozė | `[verta]` | „Susitvarkysi prenumeratas per X savaičių" (SU VAULTIE vs be — grafikas) |
| A15 | Pasitikėjimas | `[verta]` | Privatumo beat: „Jokie duomenys nesaugomi serveriuose" (diferenciacija) |
| A16 | **Auth** | `[esama, perkelti]` | Google/Apple/El. paštas — **motyvacijos pike, po apklausos** |
| A17 | **2 keliai** | `[esama]` | „Prijungti SEB" (rekomend.) / „Pradėti rankiniu būdu" |

**Esminis pakeitimas vs dabar:** auth perkeltas iš pradžios (po 4 marketingo skaidrių) į **pabaigą** (po apklausos). Progress bar + sekcijos + diagnostika — visai nauja.

### B fazė — Banko srautas (native aplink Enable Banking)

Įžvalga: Bilance polius = **jų native ekranai** aplink trumpą hosted OAuth. Enable Banking hosted puslapiai baresni nei GoCardless → Vaultie turi būti **dar labiau native**.

| # | Ekranas | Native/Hosted | Būsena |
|---|---------|---------------|--------|
| B1 | „Prijunk banką" intro (read‑only, šifruota lokaliai, pašalink bet kada) | Native | `[enhance]` bank_info_screen |
| B2 | Šalies picker (LT dabar) | Native | `[nauja, nebūtina]` |
| B3 | Banko picker **+ PAIEŠKA** | Native | `[enhance]` bank_connect_screen |
| B4 | Enable Banking auth (ASWebAuthenticationSession) | **Hosted (EB)** | `[esama]` |
| B5 | Native loading | Native | `[enhance]` |
| B6 | **Native SUCCESS + konfeti** ⭐ | Native | `[nauja]` (pralenkia Bilance — jų success hosted) |
| B7 | Native sąskaitų suvestinė („SEB · 672.80€") | Native | `[nauja + backend]` (atidėta — vėliau) |
| B8 | Native „AI atpažįsta tavo mokėjimus" processing | Native | `[nauja]` |
| B9 | → Dashboard | — | `[esama]` |

### C fazė — Dashboard (recurring herojus)

Bilance dashboard = balanso kortelė + savaitės grafikas + **transakcijų feed'as**. Vaultie apverčia: **prenumeratos = herojus, feed = antrinis.**

| Blokas | Turinys | Iš Bilance? |
|--------|---------|-------------|
| **Herojus #1** | „N prenumeratų · €X/mėn" — didelis skaičius + žiedas | Vaultie unikalus |
| **Ateinantys** | Sekantys 3 nurašymai (kaip esamas `_UpcomingRenewals`) | — |
| **Šią savaitę** | Kiek prenumeratų nurašoma šią savaitę | Bilance „This week" pakreipta |
| **Prenumeratų sąrašas** | Auto‑aptiktos + rankinės, grupuotos | Vaultie esamas |
| **Banko kortelė** | SEB balansas + „Sync po X min" (jei prijungtas) | Bilance `[verta]` |
| **Privatumo blur** | Akies ikona → sumos `****` | Bilance ⭐ |
| **Feed (antrinis)** | Visos transakcijos pagal dieną — atskiras ekranas/tab | Bilance, bet ANTRINIS |
| **Mėnesio wrap‑up** | „Prenumeratos birželį" + **AI report** (Anthropic) | Bilance „June in review" pakreipta |
| **+ FAB** | Rankinis pridėjimas | Bilance/Vaultie |

---

## 2. Ekranų copy (LT / EN) — pagrindiniai

> Pilnas copy — atskiras `.arb` darbas. Čia — pagrindinių ekranų pavyzdžiai.

**A2 Welcome**
- LT: „Susigrąžink kontrolę nuo pamirštų prenumeratų" · „Pradėti" · „Jau turiu paskyrą"
- EN: „Take back control of forgotten subscriptions" · „Get started" · „I already have an account"

**A9 Value herojus**
- LT: „Tavo pasikartojantys mokėjimai — surinkti automatiškai. Nebe išbarstyti tarp šimtų transakcijų."
- EN: „Your recurring payments — gathered automatically. No longer scattered across hundreds of transactions."

**A13 AI value**
- LT: „AI atpažįsta tavo mokėjimus. Netflix, Spotify, telefonas — automatiškai priskirti."
- EN: „AI recognises your payments. Netflix, Spotify, phone — categorised automatically."

**B1 Banko intro (trust)**
- „Tik skaitymas — negalime perkelti tavo pinigų" / „Read‑only — we can never move your money"
- „Duomenys šifruoti tik tavo telefone" / „Data encrypted, on your phone only"
- „Pašalink prieigą bet kada" / „Remove access anytime"
- „Prisijungi tiesiai banke — nematome slaptažodžio" / „You sign in at the bank — we never see your password"

**B6 Success**
- LT: „Sėkmingai prijungta ✓" + konfeti
- EN: „Successfully connected ✓"

**C Herojus**
- LT: „5 prenumeratos · €63/mėn" / tuščia: „Dar neturi prenumeratų — prijunk banką arba pridėk ranka"
- EN: „5 subscriptions · €63/mo" / empty: „No subscriptions yet — connect a bank or add one"

---

## 3. Failai (kurti / keisti)

| Ekranas / sritis | Failas | Veiksmas |
|---|---|---|
| Onboarding apklausa (A2‑A15) | `lib/screens/onboarding_screen.dart` | Perdaryti: PageView 4 marketingo → welcome+empatija+profilis+value+diagnostika+prognozė; pridėti **progress bar** widget'ą + sekcijas |
| Apklausos atsakymai | `lib/onboarding_survey.dart` (naujas) + `app_prefs.dart` | Saugoti lokaliai (Hive), naudoti prognozei + dashboard copy |
| Auth pozicija | `lib/screens/onboarding_screen.dart` `_finish`, `splash_screen.dart:62‑71` | Auth po apklausos, ne prieš |
| 2 keliai | `lib/screens/onboarding_choice_screen.dart` | Esamas — connect = pagrindinis CTA, rankinis = antrinis |
| Banko intro | `lib/screens/bank_info_screen.dart` | Enhance: trust kortelė (read‑only + šifruota + pašalink) + bankų logo |
| Banko picker + paieška | `lib/screens/bank_connect_screen.dart` | Pridėti search lauką; `_Phase` +success/+accounts/+aiProcessing |
| Native success/konfeti/AI | `lib/screens/bank_connect_screen.dart` + nauji widget'ai | Nauji ekranai |
| Dashboard recurring herojus | `lib/screens/dashboard_screen.dart` | Herojus = „N prenumeratų · €X/mėn"; feed → antrinis |
| Privatumo blur | `dashboard_screen.dart` + `app_prefs.dart` | Akies toggle → sumos `****` |
| Feed (antrinis) | `lib/screens/transactions_feed_screen.dart` (naujas) | Transakcijos pagal dieną (jei rodom feed'ą) |
| Mėnesio wrap‑up + AI report | `lib/screens/monthly_review_screen.dart` (naujas) | „Prenumeratos šį mėnesį" + AI |
| Modelis | `lib/models/subscription.dart` | +`source` (bank/manual), +`bankType`; Hive adapter bump |

---

## 4. Backend pakeitimai (`functions/`)

| # | Pakeitimas | Failas | Prioritetas |
|---|---|---|---|
| 1 | `finish_bank_auth` grąžina `accounts:[{name, ibanMasked, balance, currency}]` (native suvestinei B7) | `main.py`, `banking_service.dart` | Atidėta (vėliau) |
| 2 | (Nebūtina) skaidyti `finish_bank_auth` → `create_bank_session` + `scan_transactions` (native success/suvestinė/AI atskiri) | `main.py` | Atidėta |
| 3 | AI report generavimas mėnesio wrap‑up'ui (turim Anthropic API — `ai_classifier.py` pattern) | naujas `functions/report.py` | Faze C |
| 4 | **Feed sprendimas:** ar backend grąžina VISAS transakcijas klientui (atmintyje, be DB saugojimo → telefonas saugo lokaliai)? Reikia sprendimo. | `recurring.py`/`main.py` | ⚠️ Sprendimas |

**Jau turim (nekeisti):** merchant DB (`merchant_db.py`), AI klasifikavimas (`ai_classifier.py`, Haiku 4.5), recurring detekcija (`recurring.py`), 3 secret'ai, deploy workaround.

---

## 5. Duomenų modelis

- `Subscription` (subscription.dart): pridėti `source` ('bank'|'manual'), `bankType` ('subscription'|'bill'); **bump Hive adapter** `writeByte(10)` → 12 su back‑compat default'ais.
- (Jei rodom feed'ą) naujas `Transaction` modelis — bet **tik lokaliai** (GDPR), backend negrąžina/nesaugo DB.
- Apklausos atsakymai — Hive settings box, lokaliai.

---

## 6. Fazės (statymo eiliškumas)

| Fazė | Turinys | Rizika | Svertas |
|------|---------|--------|---------|
| **1. Onboarding apklausa** | A2‑A17: welcome + empatija + apklausa + progress bar + auth perkėlimas + 2 keliai | Vidutinė | ⭐ Didžiausias konversijos (drop‑off prieš vertę) |
| **2. Recurring herojus dashboard** | C: herojus „N · €X/mėn", feed → antrinis, privatumo blur | Vidutinė | ⭐ Produkto esmė matoma |
| **3. Native banko poliavimas** | B1‑B8: paieška, success/konfeti, AI processing | Maža | Vizualus, greitas |
| **4. Mėnesio wrap‑up + AI report** | Monthly review + Anthropic report | Maža | Retention |
| **5. Sąskaitų suvestinė + backend** | B7 + backend accounts/balance | Maža | Poliavimas |

**Atviri sprendimai prieš pradedant:**
1. Paywall vieta — bankas Pro ar nemokamas? (Batch 2 paywall matytas; NEkopijuojam pay‑first)
2. Feed — rodom visas transakcijas (kaip Bilance) ar tik recurring? (GDPR: jei rodom — klientas saugo lokaliai)
3. Apklausos ilgis — 16 ekranų ar min‑viable 8?

---

## Priedas — Bilance app struktūra (nuoroda)

5 tab'ai: **Dashboard** (balansas+sparkline, „Next sync", savaitės grafikas, transakcijų feed pagal dieną su merchant grupavimu „2× apple.com", „June in review" kortelė, privatumo blur, „+"), **Overview** (spent/earned donutai, savings rate, kategorijos %/Amount, merchants, 6 mėn waterfall), **AI Chat** (asistentas), **Planning** (biudžetai + **recurring UŽKASTAS** tuščias „Add recurring"), **Account** (net worth/assets, PIN+FaceID, currency/language/theme/first‑day, export CSV, referrals, shared finances). Monthly „June in review": donutai, AI REPORT („June's Financial Snapshot 📸"), balanso sparkline, kalendoriaus heatmap, savings club, kategorijos, insights.

**Merchant vardai ateina švarūs** (Anthropic, apple.com, Dribbble, Replit, pildyk.lt); tik P2P = „Undefined"/„Nenustatyta".
