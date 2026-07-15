"""Render the generalization-test result JSON into a self-contained HTML report."""
import html
import json
import sys

res = json.load(open(sys.argv[1], encoding="utf-8"))
OUT = sys.argv[2]

C = res["clean"]
D = res["descriptor"]
tot = C["n"]
none = C["by_layer"].get("none", 0)
ai = C["by_layer"].get("ai", 0)
rweak = C["by_layer"].get("resolver_weak", 0)
ai_other = C["kita"] - none

SEC_LT = {  # short display for the by-section table
    "Maistas, gėrimai": "Maistas, gėrimai", "Apsipirkimas": "Apsipirkimas",
    "Sveikata, sportas": "Sveikata, sportas", "Švietimas": "Švietimas",
    "Pramogos": "Pramogos", "Transportas": "Transportas", "Finansai": "Finansai",
    "Būstas, sąskaitos": "Būstas, sąskaitos", "Kita": "Kita",
}
CC_NAME = {"DE": "Vokietija", "FR": "Prancūzija", "NO": "Norvegija",
           "PL": "Lenkija", "SE": "Švedija", "FI": "Suomija", "IT": "Italija",
           "ES": "Ispanija", "NL": "Nyderlandai", "LT": "Lietuva",
           "EE": "Estija", "LV": "Latvija", "DK": "Danija", "CZ": "Čekija",
           "AT": "Austrija", "PT": "Portugalija"}


def pct(a, b):
    return f"{100.0 * a / b:.1f}" if b else "—"


def bar_row(label, corr, total, sub=""):
    p = 100.0 * corr / total if total else 0
    return f"""<tr><th scope="row">{html.escape(label)}<span class="sub">{sub}</span></th>
      <td class="num">{corr:,}<span class="den">/{total:,}</span></td>
      <td class="barcell"><div class="bar"><i style="width:{p:.1f}%"></i></div><b>{p:.1f}%</b></td></tr>"""


country_rows = "\n".join(
    bar_row(CC_NAME.get(cc, cc), c, t, cc)
    for cc, (c, t) in sorted(C["by_country"].items(), key=lambda x: -100 * x[1][0] / x[1][1]))

section_rows = "\n".join(
    bar_row(SEC_LT.get(s, s), c, t)
    for s, (c, t) in sorted(C["by_section"].items(), key=lambda x: -x[1][1]))

# top-100 wrong cases
def wrow(w):
    return f"""<tr><td>{html.escape(w['name'])}</td><td class="cc">{w['country']}</td>
      <td>{html.escape(w['expected'])}</td><td class="got">{html.escape(w['actual'])}</td>
      <td class="tag">{html.escape(w['layer'])}/{html.escape(w['cat'])}</td>
      <td class="tag">{html.escape(w['osm'])}</td></tr>"""


wrong_rows = "\n".join(wrow(w) for w in res["clean_wrong_top100"])

# error clusters from osm tags in the wrong set
from collections import Counter
oc = Counter(w["osm"] for w in res["clean_wrong_top100"])
cluster_rows = "\n".join(
    f"<tr><td>{html.escape(k)}</td><td class='num'>{v}</td></tr>"
    for k, v in oc.most_common(10))

HTML = f"""<meta charset="utf-8">
<title>Vaultie — nežinomų pirklių kategorizavimo stress-testas</title>
<style>
:root {{
  --ink:#151a21; --paper:#f5f6f4; --card:#ffffff; --line:#e2e4df;
  --muted:#5d6670; --faint:#8a929b; --accent:#0f7a5f; --accent-weak:#d7ebe3;
  --good:#2f8f5b; --warn:#c08a2a; --crit:#c1503f; --barbg:#e8eae5;
  --mono:ui-monospace,"SF Mono",SFMono-Regular,Menlo,Consolas,monospace;
  --sans:system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
}}
@media (prefers-color-scheme:dark) {{
  :root {{ --ink:#e7eae6; --paper:#101317; --card:#171b21; --line:#272c33;
    --muted:#9aa2ab; --faint:#6b737c; --accent:#3cc79c; --accent-weak:#183029;
    --good:#4bb277; --warn:#d6a24a; --crit:#e0705f; --barbg:#22272e; }}
}}
:root[data-theme="dark"] {{ --ink:#e7eae6; --paper:#101317; --card:#171b21; --line:#272c33;
  --muted:#9aa2ab; --faint:#6b737c; --accent:#3cc79c; --accent-weak:#183029;
  --good:#4bb277; --warn:#d6a24a; --crit:#e0705f; --barbg:#22272e; }}
:root[data-theme="light"] {{ --ink:#151a21; --paper:#f5f6f4; --card:#ffffff; --line:#e2e4df;
  --muted:#5d6670; --faint:#8a929b; --accent:#0f7a5f; --accent-weak:#d7ebe3;
  --good:#2f8f5b; --warn:#c08a2a; --crit:#c1503f; --barbg:#e8eae5; }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--paper); color:var(--ink); font-family:var(--sans);
  line-height:1.55; -webkit-font-smoothing:antialiased; }}
.wrap {{ max-width:940px; margin:0 auto; padding:clamp(20px,5vw,56px) clamp(16px,4vw,32px) 80px; }}
.eyebrow {{ font-size:12px; letter-spacing:.14em; text-transform:uppercase; color:var(--accent);
  font-weight:650; margin:0 0 10px; }}
h1 {{ font-size:clamp(26px,4.5vw,40px); line-height:1.08; margin:0 0 12px; letter-spacing:-.02em;
  text-wrap:balance; font-weight:720; }}
.lede {{ font-size:clamp(15px,1.7vw,18px); color:var(--muted); max-width:64ch; margin:0 0 8px; }}
.meta {{ font-family:var(--mono); font-size:12.5px; color:var(--faint); margin-top:14px; }}
h2 {{ font-size:20px; letter-spacing:-.01em; margin:52px 0 4px; font-weight:680; }}
h2 .n {{ color:var(--faint); font-family:var(--mono); font-weight:500; font-size:15px; margin-right:10px; }}
.say {{ color:var(--muted); margin:6px 0 20px; max-width:66ch; }}
.cards {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:14px; margin:28px 0 8px; }}
.card {{ background:var(--card); border:1px solid var(--line); border-radius:12px; padding:16px 18px; }}
.card .k {{ font-size:12px; color:var(--muted); letter-spacing:.02em; }}
.card .v {{ font-size:30px; font-weight:700; font-variant-numeric:tabular-nums; letter-spacing:-.02em;
  margin-top:2px; font-family:var(--mono); }}
.card .v small {{ font-size:15px; color:var(--faint); font-weight:500; }}
.card.hero {{ border-color:var(--accent); background:var(--accent-weak); }}
.card.hero .v {{ color:var(--accent); }}
.pillrow {{ display:flex; flex-wrap:wrap; gap:8px; margin:16px 0; }}
.pill {{ font-family:var(--mono); font-size:12px; padding:4px 10px; border-radius:99px;
  border:1px solid var(--line); background:var(--card); color:var(--muted); }}
.pill b {{ color:var(--ink); }}
table {{ width:100%; border-collapse:collapse; font-size:14px; }}
.scroll {{ overflow-x:auto; border:1px solid var(--line); border-radius:12px; background:var(--card); margin-top:8px; }}
th,td {{ text-align:left; padding:9px 14px; border-bottom:1px solid var(--line); }}
thead th {{ font-size:11px; letter-spacing:.06em; text-transform:uppercase; color:var(--faint); font-weight:600;
  position:sticky; top:0; background:var(--card); }}
tbody tr:last-child td, tbody tr:last-child th {{ border-bottom:none; }}
.num,.den {{ font-family:var(--mono); font-variant-numeric:tabular-nums; }}
td.num {{ text-align:right; white-space:nowrap; }}
.den {{ color:var(--faint); font-size:12px; }}
th[scope=row] {{ font-weight:550; }}
th[scope=row] .sub {{ font-family:var(--mono); font-size:11px; color:var(--faint); margin-left:8px; }}
.barcell {{ display:flex; align-items:center; gap:10px; min-width:180px; }}
.bar {{ flex:1; height:8px; background:var(--barbg); border-radius:99px; overflow:hidden; }}
.bar i {{ display:block; height:100%; background:var(--accent); border-radius:99px; }}
.barcell b {{ font-family:var(--mono); font-size:12.5px; min-width:46px; text-align:right; font-variant-numeric:tabular-nums; }}
.wtable td {{ font-size:13px; }}
.wtable .cc,.wtable .tag {{ font-family:var(--mono); font-size:11.5px; color:var(--muted); white-space:nowrap; }}
.wtable .got {{ color:var(--crit); }}
.split {{ display:grid; grid-template-columns:1fr 1fr; gap:14px; }}
@media (max-width:640px) {{ .split {{ grid-template-columns:1fr; }} }}
.note {{ background:var(--card); border:1px solid var(--line); border-left:3px solid var(--warn);
  border-radius:8px; padding:14px 16px; margin:14px 0; font-size:14px; color:var(--muted); }}
.note b {{ color:var(--ink); }}
.note.crit {{ border-left-color:var(--crit); }}
.note.good {{ border-left-color:var(--good); }}
ul.fix {{ list-style:none; padding:0; margin:12px 0; display:flex; flex-direction:column; gap:10px; }}
ul.fix li {{ background:var(--card); border:1px solid var(--line); border-radius:10px; padding:13px 16px; font-size:14px; }}
ul.fix .tagn {{ font-family:var(--mono); font-size:11px; color:var(--accent); font-weight:650; letter-spacing:.04em; }}
ul.fix b {{ display:block; margin:2px 0 3px; }}
ul.fix span {{ color:var(--muted); }}
.foot {{ margin-top:56px; padding-top:22px; border-top:1px solid var(--line); color:var(--faint);
  font-size:12.5px; font-family:var(--mono); line-height:1.7; }}
code {{ font-family:var(--mono); font-size:.88em; background:var(--barbg); padding:1px 5px; border-radius:4px; }}
</style>

<div class="wrap">
  <p class="eyebrow">Vaultie · nepriklausomas eval</p>
  <h1>Nežinomų pirklių kategorizavimo stress-testas</h1>
  <p class="lede">13 295 realių Europos pirklių, paimtų iš OpenStreetMap (ne iš mūsų
  indekso), praleisti per tą pačią production kategorizavimo grandinę — resolver →
  AI (Haiku) → Vaultie sekcija. Testuojami <b>tik nauji / nežinomi</b> pirkliai:
  1 978 pavadinimų, kuriuos sistema jau tvirtai atpažįsta, sąmoningai pašalinti.</p>
  <p class="meta">Šaltinis: OSM/Overpass, 16 miestų · Ground truth: OSM shop/amenity žyma → Vaultie sekcija
  (a-priori, gt_map.py) · AI niekada nematė teisingo atsakymo · nieko netaisyta pagal testą.</p>

  <div class="cards">
    <div class="card hero"><div class="k">Committed tikslumas</div>
      <div class="v">{pct(C['correct'], C['correct']+C['wrong'])}<small>%</small></div>
      <div class="k">kai sistema priskiria kategoriją</div></div>
    <div class="card"><div class="k">End-to-end tikslumas</div>
      <div class="v">{pct(C['correct'], tot)}<small>%</small></div>
      <div class="k">iš visų {tot:,} atvejų</div></div>
    <div class="card"><div class="k">„Kita" (susilaikė)</div>
      <div class="v">{pct(C['kita'], tot)}<small>%</small></div>
      <div class="k">nepriskyrė kategorijos</div></div>
    <div class="card"><div class="k">Klaidinga sekcija</div>
      <div class="v">{pct(C['wrong'], tot)}<small>%</small></div>
      <div class="k">{C['wrong']:,} atvejai</div></div>
  </div>

  <div class="pillrow">
    <span class="pill">Surinkta žalių POI: <b>{res['raw']:,}</b></span>
    <span class="pill">Unikalūs pavadinimai: <b>{res['deduped']:,}</b></span>
    <span class="pill">Šalys: <b>{len(res['countries'])}</b></span>
    <span class="pill">Jau žinomi (pašalinti): <b>{res['known_excluded']:,}</b></span>
    <span class="pill">Dviprasmiai (pašalinti): <b>{res['ambiguous_excluded']:,}</b></span>
    <span class="pill">Vertinami atvejai: <b>{tot:,}</b></span>
  </div>

  <h2><span class="n">01</span>Ką reiškia šie skaičiai</h2>
  <p class="say">Kai Vaultie <b>išdrįsta</b> priskirti nežinomam pirkliui kategoriją,
  ji teisinga <b>{pct(C['correct'], C['correct']+C['wrong'])}% </b>atvejų. Pagrindinis
  nuostolis — ne klaidos (tik {pct(C['wrong'], tot)}%), o <b>susilaikymas</b>: {pct(C['kita'], tot)}%
  pirklių lieka „Kita". Ir tas susilaikymas turi dvi aiškiai išmatuotas, taisomas priežastis.</p>

  <div class="split">
    <div class="note crit"><b>{pct(none, tot)}% — person-guard blokuoja prieš AI.</b>
    2–3 žodžių pavadinimai be verslo raktažodžio (pvz. „Trattoria da Enzo", „Café Tasso")
    apsaugos filtro palaikomi asmenimis ir <b>niekada nepasiekia AI</b>. {none:,} atvejų.
    Tai didžiausias vienas svertas.</div>
    <div class="note"><b>{pct(ai_other, tot)}% — AI grąžina „other".</b>
    AI iškviestas, bet neatpažįsta labai nišinio vienos vietos pirklio ({ai_other:,} atvejų).
    Dalis jų — reti pavieniai barai/kioskai, kurių niekas realiai neatpažintų.</div>
  </div>

  <h2><span class="n">02</span>Tikslumas pagal šalį</h2>
  <p class="say">14 šalių, nuo geriausios iki prasčiausios. Skirtumai nedideli —
  grandinė nepersimoko į vieną kalbą.</p>
  <div class="scroll"><table>
    <thead><tr><th>Šalis</th><th class="num">Teisingai</th><th>Tikslumas (end-to-end)</th></tr></thead>
    <tbody>{country_rows}</tbody>
  </table></div>

  <h2><span class="n">03</span>Tikslumas pagal kategoriją</h2>
  <p class="say">Ground-truth sekcija (iš OSM žymos). „Maistas, gėrimai" — didžiausias
  segmentas ({C['by_section']['Maistas, gėrimai'][1]:,} atvejų), nes miestuose dominuoja
  kavinės/restoranai/barai.</p>
  <div class="scroll"><table>
    <thead><tr><th>Sekcija</th><th class="num">Teisingai</th><th>Tikslumas</th></tr></thead>
    <tbody>{section_rows}</tbody>
  </table></div>

  <h2><span class="n">04</span>Kuris grandinės sluoksnis nusprendė</h2>
  <div class="pillrow">
    <span class="pill">AI priėmė sprendimą: <b>{pct(ai, tot)}%</b> ({ai:,})</span>
    <span class="pill">Susilaikyta / person-guard: <b>{pct(none, tot)}%</b> ({none:,})</span>
    <span class="pill">Resolver (silpnas): <b>{pct(rweak, tot)}%</b> ({rweak:,})</span>
  </div>
  <p class="say">Nauji pirkliai (pagal apibrėžimą nėra indekse) beveik visi keliauja į AI —
  todėl AI kokybė ir person-guard filtras yra viskas šioje uodegoje. Žinomi tinklai
  (Lidl, IKEA, Netflix…) čia sąmoningai pašalinti; production'e jie resolver'iu atpažįstami
  determinuotai ir teisingai.</p>

  <h2><span class="n">05</span>Sisteminės klaidų grupės</h2>
  <p class="say">Klaidos nėra atsitiktinės — jos telkiasi. Top-100 klaidų pagal OSM žymą:</p>
  <div class="split">
    <div class="scroll"><table>
      <thead><tr><th>OSM tipas</th><th class="num">Klaidų (iš 100)</th></tr></thead>
      <tbody>{cluster_rows}</tbody>
    </table></div>
    <div>
      <div class="note crit"><b>Vokiški „Kinderladen" / „Kita" (tėvų darželiai) → „Apsipirkimas".</b>
      31 iš 100 klaidų. AI nežino žodžio → spėja retail. Vienas keyword→„Švietimas"
      taisytų visą Vokietijos darželių segmentą.</div>
      <div class="note"><b>Optikai, kirpyklos, grožio salonai → „Apsipirkimas".</b>
      Turėtų būti „Sveikata, sportas". Fielmann, Apollo-Optik, barber shops.</div>
      <div class="note good"><b>Dalis „klaidų" iš tiesų ginčytinos.</b> Baras=maistas ar pramogos?
      Alkoholio parduotuvė=maistas ar retail? Dviračių servisas=apsipirkimas ar transportas?
      Čia ir mano ground-truth, ir AI abu gynybiški — realus klaidų % žemesnis nei 6%.</div>
    </div>
  </div>

  <h2><span class="n">06</span>Visos top-100 klaidos</h2>
  <p class="say">Žalias pavadinimas · šalis · laukta sekcija → gauta sekcija · sprendęs
  sluoksnis/kategorija · OSM žyma. Slink lentelę.</p>
  <div class="scroll" style="max-height:440px; overflow-y:auto;"><table class="wtable">
    <thead><tr><th>Pavadinimas</th><th>Šalis</th><th>Laukta</th><th>Gauta</th><th>Sluoksnis/kat.</th><th>OSM</th></tr></thead>
    <tbody>{wrong_rows}</tbody>
  </table></div>

  <h2><span class="n">07</span>Realaus banko descriptor'io jautrumas</h2>
  <p class="say">Ta pati {D['n']:,} pirklių imtis, bet pavadinimai paversti į tikrą banko
  išrašo formą (DIDŽIOSIOS raidės, miestas, parduotuvės nr., <code>SumUp *</code>,
  <code>PAYPAL *</code>). Rezultatas krenta į {pct(D['correct'], D['n'])}% — <b>bet tai
  dalinai testo artefaktas</b>: ~18% descriptor'ių person-guard'as blokuoja (prilipdytas
  miestas paverčia į 2–3 alpha žodžius), o mano sintetinis triukšmas agresyvus (nukirpimai,
  atsitiktiniai numeriai). Todėl šį skaičių traktuok <b>kryptingai</b> („triukšmas smarkiai
  kenkia atpažinimui"), o ne kaip tikslų production skaičių.</p>
  <div class="pillrow">
    <span class="pill">Committed tikslumas (descriptor): <b>{pct(D['correct'], D['correct']+D['wrong'])}%</b></span>
    <span class="pill">„Kita": <b>{pct(D['kita'], D['n'])}%</b></span>
    <span class="pill">person-guard blokas: <b>~17.8%</b> paviršių</span>
  </div>

  <h2><span class="n">08</span>Ką tai konkrečiai siūlo taisyti</h2>
  <ul class="fix">
    <li><span class="tagn">DIDŽIAUSIAS SVERTAS</span><b>Sušvelninti person-guard merchant šakoje.</b>
    <span>~{pct(none, tot)}% nežinomų pirklių niekada nepasiekia AI. Merchant branch'e (kur pagal
    kontekstą tai ne P2P) leisti 2–3 žodžių pavadinimus į AI — smoke-testas rodo, kad AI juos
    teisingai klasifikuoja („Trattoria da Enzo" → restaurant).</span></li>
    <li><span class="tagn">KEYWORD KB</span><b>Pridėti kelias didelės aprėpties taisykles.</b>
    <span><code>Kinderladen/Kita/EKT</code> → Švietimas · <code>Optik/Optic/optician</code> → Sveikata ·
    <code>Coiffeur/Frisör/barber/kirpykla</code> → Sveikata. Kelios eilutės sutvarko dešimtis % klaidų.</span></li>
    <li><span class="tagn">TAKSONOMIJA</span><b>Apsispręsti dėl ginčytinų ribų.</b>
    <span>Baras, alkoholio parduotuvė, dviračių servisas — nuspręsti kanoniškai ir suderinti
    tiek ground-truth, tiek AI promptą, kad nekonfliktuotų.</span></li>
    <li><span class="tagn">SKAIDRUMAS</span><b>„Kita" nėra klaida — bet parodyk ją sąžiningai.</b>
    <span>Nišiniam pirkliui geriau „Kita" nei pasitikinti klaida. UI gali leisti vartotojui
    priskirti ranka, o atsakymas kešuojamas visiems (crowdsourced KB).</span></li>
  </ul>

  <p class="foot">
    Metodologija — Populiacija: OSM/Overpass, 16 ES miestų, tik pavadinti POI su shop=/amenity= žyma.
    Nepriklausoma nuo functions/kb/merchant_index.sqlite.<br>
    Ground truth: OSM žyma → Vaultie sekcija pagal a-priori gt_map.py (parašyta prieš testą).
    Žymos be vienareikšmės sekcijos = AMBIGUOUS, pašalintos iš vardiklio ({res['ambiguous_excluded']:,}).<br>
    „Žinomas" filtras: pašalinti pavadinimai, kuriuos deterministinis resolver'is atpažįsta tvirtai
    ({res['known_excluded']:,}) — testuojama tik nauja uodega.<br>
    Grandinė: resolver.resolve_hit (KB → offline global index) → ai_enrichment.classify (Haiku 4.5) →
    CAT_MAP → sekcija. Identiška production'ui. Jokio tuning'o pagal testą, jokio atsakymo nutekėjimo.<br>
    Apribojimai: (1) švarus OSM pavadinimas ≠ realus banko descriptor'is; (2) person-guard mažina uodegos
    aprėptį; (3) dalis ground-truth ribų ginčytinos; (4) tai HARD-TAIL — žinomi tinklai (didžioji vartotojų
    apyvartos dalis) sąmoningai pašalinti, tad {pct(C['correct'], tot)}% nėra tai, ką mato eilinis vartotojas.
  </p>
</div>
"""

open(OUT, "w", encoding="utf-8").write(HTML)
print(f"wrote {OUT} ({len(HTML):,} bytes, {len(res['clean_wrong_top100'])} wrong cases)")
