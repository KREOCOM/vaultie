# Vaultie — testavimo eiga

Kas ką tikrina, kokia tvarka, ir ko tikėtis. Rašyta 2026-07-28.

## Kodėl šis failas egzistuoja

Keturios klaidos, rastos 2026-07-28 (žalias APPLE.COM, apverstas dienos ženklas,
negyvas SEB jungiklis, `_recKey` lūžis pabrangus) **visos buvo grynose funkcijose**
— nė vienai nereikėjo telefono. Jos praėjo todėl, kad kliente nebuvo testų.

Serveryje testai tą pačią dieną sustabdė tris kartus: `test_streams.py` pagavo,
kad 0,50 € riba surija 3,49 € pirkinį; `test_subs_review.py` pagavo, kad
`confident` valdo patekimą į sąrašą; `test_series_id_stable.py` pagavo, kad
juostos per siauros kainos pakilimui.

**Išvada: kas gali būti testu — turi būti testas. Rankos lieka tik tam, ko
automatas nepasiekia.**

---

## 1. Kas tikrinama automatiškai (be telefono)

Paleisti prieš **kiekvieną** buildą:

```bash
flutter analyze lib/                       # 0 naujų įspėjimų
flutter test                               # 40 testų
cd functions && for t in test_*.py; do ./venv/bin/python "$t" || echo "KRITO: $t"; done
```

Serverio testai neturi `pytest` — tai paprasti skriptai, grąžinantys exit kodą.

**Ką tai dengia šiandien:** serverio pusę gerai (36 testai — pasikartojantys,
pinigų ženklai, bankų formatai LT/SE/NO/DE/ES, asmenvardžiai, valiutos, srautų
tapatybė). Kliento pusę silpnai — 7 failai iš ~25 000 eilučių.

**Ko NEDENGIA:** viso, kas yra `dashboard_preview.dart` viduje (10 441 eilutė) —
dienos sumos, kalendorius, savaitės grafikas, eilučių sujungimas, jungiklių
logika. Tai taisytina iškeliant grynas funkcijas į `lib/logic/`, kur testas jas
pasiekia.

---

## 2. Rankinis patikrinimas — pirmo vartotojo kelias

Eiti iš eilės. Prie kiekvieno punkto parašyta, **ko tikėtis** — be to tai
ekskursija, ne testas.

### A. Pirmas paleidimas

- [ ] Ištrink programą ir įdiek iš naujo (švarus startas)
- [ ] Paleidi iš pagrindinio ekrano → **atsidaro, nelūžta**
- [ ] Rodomas onboarding, ne suvestinė

### B. Onboarding (3 puslapiai)

- [ ] 1 psl. — tekstas ir vaizdas vietoje, mygtukas veikia
- [ ] 2 psl. — funkcijų sąrašas
- [ ] 3 psl. — gyva suvestinės demonstracija juda pati
- [ ] Atgal mygtukas negrąžina į tuščią ekraną

### C. Paskyra

- [ ] Registracija el. paštu → gaunamas patvirtinimo laiškas
- [ ] „Tęsti su Apple" ir „Tęsti su Google"
- [ ] Neteisingas slaptažodis → aiški klaida, ne tyla
- [ ] Slaptažodžio priminimas → laiškas ateina
- [ ] **Atsijungus ir prisijungus KITU vartotoju** — įspėjimas, kad seni duomenys
      bus ištrinti (žr. `vaultie-signin-wipes-local-data`)

### D. Mokėjimas

- [ ] Paywall rodo kainas iš App Store, ne užkoduotas
- [ ] Bandomasis laikotarpis rodomas, jei jį turi ta Apple paskyra
- [ ] Pirkimas → grįžta į programą, prieiga atsidaro
- [ ] Dvigubas mygtuko paspaudimas nesukuria dviejų pirkimų
- [ ] Paywall uždarymas → atsijungia, ne pakimba

### E. Banko prijungimas

- [ ] Šalies pasirinkimas, paieška veikia
- [ ] Bankų sąrašas užsikrauna; **pasižymėk, ar kuris turi „TESTAS" ženklelį**
- [ ] Pasirinkus banką → atsidaro banko puslapis
- [ ] Sutikimas → grįžta į programą (šis grįžimas anksčiau lūždavo)
- [ ] Atšaukus sutikimą pusiaukelėje → programa nepakimba
- [ ] **Uždarius programą sutikimo metu** ir atidarius — nedingsta

### F. Sinchronizacija — čia gyvena daug klaidų

Prijungus vyksta **du** skenavimai: greitas 3 mėn. ir gilus 6 mėn. fone.

- [ ] Iš pradžių matosi dalis duomenų, po ~30 s atsinaujina
- [ ] Likutis atitinka tikrą banko likutį
- [ ] Sandorių skaičius atrodo teisingas
- [ ] **Pasikartojančių klausimas neužduodamas antrą kartą** po gilaus skenavimo
- [ ] Patrauk sąrašą žemyn → atsinaujina, nedubliuoja

### G. Pasikartojantys mokėjimai

- [ ] Peržiūros klausimas: atsakius ✗ ir ✚ — **klausimas dingsta ir negrįžta**
- [ ] Pažymėtas ✗ **neįskaičiuotas** į mėnesio sumą
- [ ] Kiekvienas jungiklis reaguoja — **ypač tie, kuriuos anksčiau išjungei**
- [ ] Tas pats teikėjas nerodomas du kartus skirtingomis sumomis
- [ ] Suma per mėnesį atitinka tai, ką realiai moki
- [ ] **Žmogaus vardas NIEKADA nepatenka į Sąskaitas ar Prenumeratas**
- [ ] Ištrynus įrašą → „Grąžinti" veikia

### H. Pradžia

- [ ] Bendras likutis teisingas
- [ ] Savaitės grafikas: stulpeliai atitinka dienas, paspaudus rodoma data
- [ ] **Dienos suma = eilučių po ja suma.** Sudėk ranka ir palygink
- [ ] Minusas, kai išleista daugiau; teigiama žalia, kai gauta daugiau
- [ ] Eilutė su `2×` ženkleliu — spalva atitinka **sumą**, ne vieną iš eilučių
- [ ] Paspaudus sandorį → detalus vaizdas
- [ ] Kategorijos keitimas, žvaigždutė, trynimas → **išlieka po sinchronizacijos**

### I. Apžvalga

- [ ] Kategorijų sumos sudeda į mėnesio sumą
- [ ] Kalendorius: dienos su pervedimais rodo pilką `↔`, ne tuščią langelį
- [ ] Pervedimai **neįskaičiuoti** į dienos sumą
- [ ] Prekybininkų sąrašas
- [ ] 6 mėn. grafikas

### J. Planavimas

- [ ] Biudžeto nustatymas → matosi mėnesio peržiūroje ir sandorio detalėje
- [ ] Viršijus biudžetą → aiškiai matoma

### K. AI pokalbis

- [ ] Pirmą kartą → **sutikimo langas**, be jo nieko nesiunčiama
- [ ] Atsakymas ateina
- [ ] **Atsakymo kalba = programos kalba**, ne klausimo ir ne duomenų
- [ ] Be interneto → aiški klaida

### L. Nustatymai

- [ ] Kalba LT↔EN: **visi 5 skirtukai**, savaitės grafiko raidės, mėnesio AI
      santrauka, datos
- [ ] Perjungus kalbą **uždaryk ir atidaryk programą** — neturi grįžti sena
- [ ] Tema šviesi/tamsi
- [ ] Valiutos keitimas → sumos perskaičiuotos, ne perrašytos kitu ženklu
- [ ] PIN nustatymas, Face ID, neteisingas PIN kelis kartus → užrakinimas
- [ ] „Pamiršai PIN" → nuveda į prisijungimą, **ne į svetimą suvestinę**
- [ ] Bankų atjungimas → duomenys dingsta, prenumerata lieka
- [ ] Paskyros trynimas → viskas dingsta, banko sutikimas atšauktas

### M. Gyvavimo ciklas

- [ ] Uždaryk visiškai ir atidaryk → duomenys vietoje, ne iš naujo kraunami
- [ ] Programų perjungiklyje **finansai uždengti**, nesimato
- [ ] Lėktuvo režimas → sena informacija rodoma, klaida aiški
- [ ] Palik fone 10 min → grįžus atsinaujina

---

## 3. Kaip įsitikinti, kad taisant vieną nesugadinai kito

Šiandien tai sulaužiau du kartus iš eilės, tad taisyklės ne teorinės:

1. **Testas prieš pataisymą.** Kiekviena tavo rasta klaida pirma virsta testu,
   kuris krenta, ir tik tada taisoma. Kitaip nežinia, ar pataisyta.
2. **Visas rinkinys, ne vienas testas.** `test_streams.py` pagavo, kad sumų
   grupavimo riba suriję vienkartinį pirkinį — to testo aš nebūčiau paleidęs.
3. **Ar krito ir anksčiau?** Prieš skelbiant „aš sulaužiau", atsukti pakeitimą
   (`git stash`) ir paleisti iš naujo. Taip paaiškėjo, kad
   `test_recurring_lifecycle` krito dar prieš mane.
4. **Ribos parenkamos testu, ne nuojauta.** 1,78× juostos ir 0,50 € riba atrodė
   protingos ir abi buvo klaidingos.
5. **Skaitymas ir rašymas turi sutapti.** Jei skaitymas priima kelis raktų
   pavidalus, rašymas privalo išvalyti visus. Būtent to nepadarius mirė SEB
   jungiklis.

---

## 4. Ką siūlau standartizuoti

**Dabar, prieš pateikimą (pigu):**
- Šis failas kaip privalomas sąrašas prieš kiekvieną pateikimą
- Dart testai keturioms šios dienos klaidoms — kad negrįžtų

**Po pateikimo (didesnis darbas, didžiausia grąža):**
- Išnešti grynas pinigų funkcijas iš `dashboard_preview.dart` (10 441 eilutė) į
  `lib/logic/`, kad testai jas pasiektų. Elgesys nesikeičia, tik pasiekiamumas.
  Tai vienintelis būdas nustoti vaikščioti tais pačiais bugais — kol logika
  užrakinta viename valdiklio faile, ji netestuojama iš principo.
- Trečias tikras duomenų rinkinys (ne Osvaldo Revolut, ne SEB pavyzdys)
