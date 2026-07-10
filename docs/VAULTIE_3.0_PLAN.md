# Vaultie 3.0 — Recurring Payments Tracker + Merchant DB (planas)

> **Vizija:** Vaultie nebėra „subscription tracker". Tampame **geriausiu
> recurring payments tracker'iu** su fokusuotu finansų vaizdu. NE pilnas PFM
> (ne Bilance). Wedge'as aštrus: geriausias pasikartojančių mokėjimų aptikimas,
> crowdsourced merchant DB, priminimai, švarus „ką moki kas mėnesį".

> Šis dokumentas — **nauja vizija (3.0)**, atskira nuo `VAULTIE_2.0_PLAN.md`
> (Enable Banking integracija, jau įgyvendinta).

---

## 0. Esminė nauja abstrakcija — TIPAS ant kategorijos

Iki šiol turėjome tik `category`. 3.0 prideda **`type`** dimensiją:

| `type` | Pavyzdžiai | Elgesys UI |
|--------|-----------|-----------|
| `subscription` | Netflix, Spotify, Dribbble, iCloud | Recurring · importuojama · priminimai |
| `bill` | nuoma, draudimas, Ignitis, telefonas | Recurring · importuojama · priminimai |
| `frequent` | Hesburger, Wolt, Maxima | **Niekada** recurring · tik info feed'e |

Merchant DB kiekvienam merchant'ui saugo `type + category + logo + aliases`.
Detection priskiria tipą; import UI grupuoja per **3 tipus**.

---

## 1. Architektūros apžvalga

```
 Telefonas (Flutter)                     Cloud Functions (Python)         Firestore
 ─────────────────────                   ────────────────────────         ─────────
 bank_import_screen  ── finish_bank_auth ─▶ detect_recurring              merchants/{key}
   3 grupės (sub/bill/freq)                  └─ merchant match ◀───────────  (curated + crowd)
 transactions feed   ◀── kategorizuotos txns (efemeriškai grąžinamos)
   (šifruotas Hive cache, LOKALUS)
 "patvirtink merchant'ą" ── submit_merchant ─▶ merchant_submissions ─▶ (slenkstis) ─▶ merchants
```

**Principai:**
- **Matching serveryje.** Žalias transakcijas turi tik Cloud Function (GDPR),
  tad ir merchant matching vyksta ten. Funkcija įsikelia `merchants` į atmintį
  per cold start (371 dok. = ~vienas skaitymas per instanciją).
- **Serveris be būsenos.** Niekada nepersistina žalių transakcijų.
- **Klientas kešuoja lokaliai.** Transakcijos — tik įrenginyje, šifruotos,
  ištrinamos. Feed'as tarnauja recurring misijai.

---

## 2. Firestore merchant DB schema

**Kolekcija `merchants`** (globali, viena visiems):

```jsonc
// merchants/{merchantKey}   — key = normalizuotas raktas, pvz. "netflix"
{
  "displayName": "Netflix",
  "type":        "subscription",          // subscription | bill | frequent
  "category":    "entertainment",         // app ExpenseCategory raktas
  "logoDomain":  "netflix.com",           // null jei nėra
  "aliases":     ["netflix.com", "netflix intl"],  // substring/pattern variantai
  "matchMode":   "substring",             // substring | word (trumpiems/dviprasmiams)
  "source":      "curated",               // curated | crowd
  "status":      "active",                // active | pending
  "verifiedCount": 12,                    // kiek skirtingų vartotojų patvirtino
  "createdAt":   <ts>,
  "updatedAt":   <ts>
}
```

**Kolekcija `merchant_submissions`** (crowdsource pending):
```jsonc
// merchant_submissions/{key}
{
  "displayName": "...", "type": "...", "category": "...",
  "votesByUser": { "<uidHash>": {"type":"bill","category":"utilities"} },
  "count": 2, "status": "pending", "updatedAt": <ts>
}
```

**Security rules (`firestore.rules`):**
- `merchants` — klientas `read` (jei reikės), **rašymas tik per Cloud Function**
  (admin SDK apeina rules).
- `merchant_submissions` — klientas jokios tiesioginės prieigos; viskas per
  `submit_merchant` callable.

**Schemos suderinimas su `merchant_rules.json`:** kai gausim ~371 įrašų failą
(`functions/merchants_seed.json`), `seed_merchants` jį sumapins į aukščiau
esančią schemą (laukų pervadinimas, `type`/`category` normalizavimas,
`matchMode` nustatymas trumpiems raktams).

---

## 3. GDPR sprendimai

| Klausimas | Sprendimas |
|-----------|-----------|
| Žalios transakcijos serveryje | **Niekada nesaugomos** — apdorojama atmintyje, grąžinama efemeriškai |
| Transakcijų feed'as | Klientas kešuoja **tik lokaliai** (šifruotas Hive box), vartotojo kontrolėje, ištrinama |
| Crowdsource siunta | **Tik merchant tapatybė + type + category** (viešas verslo faktas). Jokių sumų, datų, „šis vartotojas moka" |
| Uid crowdsource'e | Hash'inamas (abuse kontrolei), neišviešinamas |
| Consent | Feed'ui reikės **tęstinio** Enable Banking consent'o (SEB 180 d.) — Faza C |
| Privacy Policy | Atnaujinama **Faza C** metu (lokalus cache + crowdsourced DB) |

---

## 4. Fazių planas

### Faza A — Merchant DB į Firestore (pamatas) ← PRADEDAM

- [ ] **A1.** Įjungti Firestore projekte `vaultie-1a2c4`; `firebase.json` +
      `firestore.rules` + `firestore.indexes.json`; `.firebaserc` OK.
- [ ] **A2.** `functions/merchants_seed.json` (iš `merchant_rules.json`) +
      `seed_merchants` (vienkartinis callable/skriptas) → įrašo į `merchants`.
      **← blokuoja: reikia JSON failo.**
- [ ] **A3.** `functions/merchant_db.py` — įkelia `merchants` į atmintį
      (cache'inta per instanciją), teikia `match(name) -> (display, type,
      category, logo)`.
- [ ] **A4.** `functions/recurring.py` — whitelist keičiam į `merchant_db`;
      kandidatas gauna `type` (subscription/bill/frequent). `frequent` NĖRA
      recurring, bet grąžinamas atskirai (feed'ui / info).
- [ ] **A5.** `main.py finish_bank_auth` — grąžina kandidatus su `type`.
- [ ] **A6.** Klientas `banking_service.dart` — `RecurringCandidate` gauna
      `type` lauką.
- [ ] **A7.** `recurring_classifier.dart` — grupavimas per **3 tipus**
      (Subscriptions / Bills / Frequent spending) vietoj 5 kategorijų grupių;
      `frequent` — atskira info sekcija, neimportuojama.
- [ ] **A8.** `bank_import_screen.dart` — 3-tipų UI; frequent spending rodoma
      kaip „dažni pirkimai" (ne checkbox'ai).
- [ ] **A9.** Testai (backend `test_recurring.py` su merchant DB mock;
      klientas `recurring_classifier_test.dart`).

**Failai, kurie keičiasi Fazoje A:** `firebase.json`, `firestore.rules`,
`firestore.indexes.json`, `functions/merchants_seed.json` (naujas),
`functions/merchant_db.py` (naujas), `functions/seed_merchants.py` (naujas),
`functions/recurring.py`, `functions/main.py`,
`lib/services/banking_service.dart`, `lib/services/recurring_classifier.dart`,
`lib/screens/bank_import_screen.dart`, testai.

### Faza B — Crowdsourced learning

- [ ] **B1.** `submit_merchant` callable — rašo į `merchant_submissions`;
      kai `count ≥ N` (pvz. 3 skirtingi uid, sutampantys type/category) →
      promote į `merchants` su `source:"crowd"`, `status:"active"`.
- [ ] **B2.** Curated visada nugali crowd; abuse slenkstis + rate limit.
- [ ] **B3.** Klientas: import ekrane prie neatpažinto (`type == frequent`
      arba `category == other`) — „Kas tai? Prenumerata / Sąskaita / Dažnas
      pirkimas + kategorija" → `submit_merchant`.
- [ ] **B4.** (Nice-to-have) admin moderavimo peržiūra pending įrašams.

**Failai:** `functions/main.py` (+`submit_merchant`), `firestore.rules`,
`lib/services/banking_service.dart`, `lib/screens/bank_import_screen.dart`.

### Faza C — Feed + pilnas (fokusuotas) vaizdas — GDPR-jautru

- [ ] **C1.** Sprendimas įgyvendintas: šifruotas lokalus transakcijų Hive box.
- [ ] **C2.** `sync_transactions` (ar `finish_bank_auth` praplėtimas) — grąžina
      **kategorizuotas** transakcijas klientui (serveris nepersistina).
- [ ] **C3.** Feed ekranas — rodo **TIK recurring misijai**:
      - recurring (subscription/bill) transakcijos — **paryškintos**
      - neatpažinti merchant'ai — su „patvirtink" kvietimu
      - frequent spending — kaip **info** (ne recurring)
      - **NE** rodom visų transakcijų kaip Bilance Dashboard
- [ ] **C4.** Tęstinis Enable Banking consent + re-sync srautas.
- [ ] **C5.** Privacy Policy + `legal_screen.dart` + `docs/privacy.html` update
      (lokalus cache, crowdsourced merchant DB).

**Failai:** naujas `lib/screens/transactions_feed_screen.dart`, naujas
lokalaus cache servisas, `functions/main.py`, `lib/screens/legal_screen.dart`,
`docs/privacy.html`.

---

## 5. Feed logika (fokusas, ne PFM)

**Rodyti:**
1. Transakcijos, kurios yra recurring (subscription/bill) — **paryškintos**,
   su nuoroda į jų recurring įrašą.
2. Neatpažinti merchant'ai, kuriuos verta patvirtinti → maitina crowdsource DB.
3. Frequent spending — suvestinė info („šį mėnesį Wolt ×7"), **ne** recurring.

**NErodyti:** viso PFM (net worth, budžetai, savings club, savaitės grafikai) —
tai Bilance, ne mes.

---

## 6. Atviri klausimai / blokeriai

- **[BLOKUOJA A2]** `merchant_rules.json` (~371) → `functions/merchants_seed.json`.
- Crowdsource promotion slenkstis `N` (pradžiai siūlau 3).
- Ar klientui reikia tiesioginio `merchants` read (offline), ar užtenka
  serverio matching'o? (MVP: tik serveris.)
- Feed re-sync dažnis + Enable Banking consent tęstinumas (Faza C).

---

## 7. Statusas

- [x] Vizija + architektūra suderinta (2026-07-10)
- [x] Feed kryptis: lokalus šifruotas cache, serveris be būsenos (Faza C)
- [ ] Faza A — vyksta
- [ ] Faza B
- [ ] Faza C
