# Vaultie 2.0 — Enable Banking integracija (work flow)

> **Tikslas:** vartotojas prijungia savo LT banką → app'as automatiškai randa
> pasikartojančius mokėjimus → importuoja juos kaip `Subscription`. Funkcija =
> **Pro**. Pirma versija (2.0) = **MVP** (be AI įžvalgų — tos ateina 2.1).

## Sprendimai (2026-07-07)

| Klausimas | Sprendimas |
|-----------|-----------|
| Backend | **Firebase Cloud Functions (Python)** — tas pats Firebase projektas kaip Auth |
| Apimtis (2.0) | **MVP**: prijungti + rasti + importuoti recurring. AI (dublikatai/sutaupymai) → 2.1 |
| AI variklis | Aptikimas = **taisyklės** (ne AI, pigu/tikslu). Claude įžvalgos → 2.1 |
| Enable Banking | `application_id` = `324f8a3b-8d09-4f98-a9bb-50120f8eb082`; raktas turimas |

## Kodėl reikia backend'o

Enable Banking kiekvieną užklausą pasirašo **RS256 JWT** su RSA privačiu raktu.
Tas raktas **niekada negali būti telefone** (bet kas jį ištrauktų → prieiga prie
banko duomenų → GDPR pažeidimas + Apple atmestų). Todėl:

```
Telefonas  →  Cloud Function (laiko raktą)  →  Enable Banking  →  Bankas
```

## Įrodyta (Faza 0 — DONE)

PoC `~/banksync-test/banksync.py` jau veikia ir įrodė visą srautą:

1. JWT auth — `kid`=application_id, `iss`=enablebanking.com, `aud`=api.enablebanking.com
2. `GET /aspsps?country=LT` — bankų sąrašas
3. `POST /auth` → grąžina banko autorizacijos URL
4. `POST /sessions` su `code` → sesija + sąskaitos
5. `GET /accounts/{uid}/transactions` → transakcijos
6. Recurring aptikimas: grupuoti DBIT pagal (gavėjas, apvalinta suma), ≥2 kartai = recurring; kadencija iš datų tarpų

> ⚠️ LT sandbox sąskaitos rodo balansus, bet dažnai **neturi transakcijų istorijos**.
> Aptikimą testuojam ant demo duomenų arba realaus banko.

---

## Srautas žmogui (kuo paprastesnis — 5 žingsniai)

1. Dashboard/Settings → **„Prijungti banką"** (Pro).
2. Pasirenka banką (Swedbank, SEB, Luminor, Revolut…).
3. Nukreipiamas į **banko puslapį** → prisijungia (mes nematome slaptažodžio).
4. Grįžta į app'ą (deep link).
5. **„Radome šiuos pasikartojančius mokėjimus"** → pažymi → **Pridėti**.

---

## Fazės (checklistas)

### Faza 0 — Enable Banking setup ✅ DONE
- [x] Registracija, `application_id`, privatus raktas
- [x] Veikiantis PoC (auth → banks → auth → session → transactions → recurring)

### Faza 1 — Backend (Firebase Cloud Functions, Python) — kodas parašytas
- [x] Inicijuoti `functions/` (Python, gen2) + `firebase.json` funkcijų blokas + `.firebaserc`
- [x] Portuoti PoC JWT/HTTP logiką iš `banksync.py` → `functions/enable_banking.py`
- [x] Recurring variklis `functions/recurring.py` (+ testas `test_recurring.py`, praeina ✓)
- [x] Endpointai `functions/main.py` (callable, visi tikrina Firebase Auth token'ą):
  - [x] `list_banks(country)` → bankų sąrašas UI'ui
  - [x] `start_bank_auth(aspspName)` → grąžina banko autorizacijos URL + state
  - [x] `finish_bank_auth(code)` → sesija → transakcijos → recurring aptikimas → **tik kandidatai**
- [x] **Neišsaugoti** žalių banko transakcijų (apdorojama atmintyje, grąžinami tik kandidatai)
- [x] Raktas įkeltas kaip secret (`ENABLE_BANKING_PRIVATE_KEY` v1), Blaze įjungtas
- [x] **DEPLOY'INTA** ✅ — visos 3 funkcijos gyvos `europe-west1`, python312, callable
- [ ] (Nice-to-have) tikrinti Pro entitlement serveryje

#### Deploy (komandos, kurias paleidi TU)
```bash
# 1) Įjungti Blaze planą (jei dar ne): Firebase Console → Upgrade → Blaze
# 2) Prisijungti prie Firebase CLI (interaktyvu):
firebase login
# 3) Įkelti privatų raktą kaip secret (skaito iš .pem, į git nepatenka):
firebase functions:secrets:set ENABLE_BANKING_PRIVATE_KEY < ~/Desktop/324f8a3b-8d09-4f98-a9bb-50120f8eb082.pem
# 4) Deploy'inti tik funkcijas:
firebase deploy --only functions
```
> Cloud Functions Python runtime = 3.12. Lokalus python3 = 3.9 → deploy'as buildina
> cloud'e, bet emuliatoriui/lokaliam testui reikėtų `brew install python@3.12`.

#### ⚠️ Deploy gotcha šitoje mašinoje (macOS 26 / Darwin 25)
Homebrew Python 3.12 `pyexpat` linkuoja į naują `libexpat` simbolį, kurio nėra
sisteminėje `/usr/lib/libexpat.1.dylib` → lūžta `pip` ir `firebase deploy` (venv
discovery). **Kiekvienam deploy'ui reikia** nurodyti brew expat:
```bash
brew install expat python@3.12          # vienkartinis
DYLD_LIBRARY_PATH=/opt/homebrew/opt/expat/lib firebase deploy --only functions
```
venv sukurtas su `python3.12 -m venv --without-pip venv` + `get-pip.py` (nes
`ensurepip` irgi lūžta dėl to paties expat).

### Faza 2 — Recurring aptikimo variklis
- [ ] Portuoti algoritmą iš `banksync.py` (`step_recurring`, `guess_cadence`)
- [ ] Kiekvienam kandidatui: pavadinimas, vid. suma, kadencija → `BillingCycle`, kita data
- [ ] Mapinti į `Subscription` (name, cost, billingCycle, category, nextBillingDate, logoDomain spėjimas iš gavėjo)
- [ ] Unit testai su `DEMO_TRANSACTIONS` iš PoC

### Faza 3 — App UI (Flutter) — parašyta
- [x] `cloud_functions` + `app_links` paketai pridėti
- [x] `BankingService` (`lib/services/banking_service.dart`) — 3 callable + kandidatų mapinimas į `Subscription`, region `europe-west1`
- [x] „Prijungti banką" kortelė Dashboard Overview (Pro gating: premium → flow, kitaip → paywall)
- [x] Bankų pasirinkimo ekranas `bank_connect_screen.dart` (iš `list_banks`)
- [x] Deep-link callback per **https tiltą** (custom scheme kaip redirect nepriimamas):
  - [x] EB redirect = `https://vaultie-1a2c4.web.app/banking/callback` (Firebase Hosting)
  - [x] tilto puslapis `public/banking/callback/index.html` → `vaultie://banking/callback?code=&state=`
  - [x] custom scheme registruotas (iOS `CFBundleURLTypes`, Android intent-filter)
  - [x] Flutter `app_links` gaudymas connect ekrane
  - [x] `BankingService` siunčia `redirectUrl`; backend validuoja prieš registruotus
- [x] Importo ekranas `bank_import_screen.dart`: kandidatai su checkbox'ais → „Pridėti pažymėtus"
- [x] Pridėti → `Subscription` Hive box'e + suplanuotos notifikacijos
- [ ] **← LIEKA (Faza 6 prereq):** sukurti NAUJĄ Enable Banking app su redirect
  `https://vaultie-1a2c4.web.app/banking/callback` (seno redirect keisti negalima),
  atnaujinti `APP_ID`/raktą backend'e; tada end-to-end sandbox testas

### Faza 4 — Pro gating ✅
- [x] „Prijungti banką" už `PurchaseService.isPremium` (Pro gate atstatytas po test bypass)
- [x] Paywall tekstas: banko funkcija kaip pirma (flagship) 2.0 savybė

### Faza 5 — Privacy / Legal / Apple review
- [x] Atnaujinta in-app `legal_screen.dart`: dedikuota „Bank connection (Open Banking)" sekcija (LT/EN), Enable Banking kaip PSD2 procesorius, žalios operacijos nesaugomos, sutikimas atšaukiamas; Terms atnaujinti
- [x] Atnaujinta hostinama `docs/privacy.html` (LT/EN): nauja 6 sekcija Open Banking, Enable Banking trečiosiose šalyse, ištrynimo skiltis
- [ ] App Privacy „nutrition label" App Store Connect: **Financial Info** (tavo žingsnis skydelyje)
- [ ] `APP_REVIEW_NOTES.md`: kaip reviewer'iui pasiekti banko srautą
- [ ] Patikrinti Apple 3.1.1 / finansų kategorijos reikalavimus
- [ ] Įsitikinti, kad App Store Privacy URL rodo į atnaujintą puslapį (GitHub Pages iš `main/docs`)

### Faza 6 — Testai
- [x] Recurring aptikimas ant demo duomenų (unit — `test_recurring.py`)
- [x] Sandbox end-to-end iki consent: `list_banks` + `start_bank_auth` per app'ą veikia (Mock ASPSP consent friction — magic-link sesija sim'e)
- [ ] Pilnas Mock ASPSP import (reikia test duomenų skydelyje) — arba realus bankas produkcijoje
- [ ] Realus LT bankas (SEB/Swedbank) — **reikia Enable Banking PRODUKCIJOS** (verslo onboarding)
- [ ] Edge case'ai: 0 transakcijų, rate limit (429), kelios sąskaitos, kintama suma

### ⚠️ Blokuoja gyvą paleidimą
- **Enable Banking PRODUKCIJA** (`environment: SANDBOX` → production): verslo/KYC verifikacija + sutartis. Tik tada atsiranda visi realūs bankai (SEB ir kt.). App scoped 29 EU šalims.

---

## Techniniai sprendimai, kuriuos dar reikia užfiksuoti

- **Deep link / redirect:** rekomenduoju hosted https callback (Firebase Hosting/
  GitHub Pages), kuris pagauna `?code=` ir peradresuoja į `vaultie://bank-callback`.
  Reikia užregistruoti šį URL Enable Banking valdymo skydelyje (dabar PoC naudoja
  `https://localhost:3000/`).
- **Žalios transakcijos:** neišsaugom — tik grąžinam recurring kandidatus. Mažiau
  GDPR rizikos, paprastesnė privacy politika.
- **Consent galiojimas:** Enable Banking sesija galioja ribotą laiką (PoC — 10 d.).
  MVP: vienkartinis importas. Auto-sync (periodinis) → vėlesnė versija.
