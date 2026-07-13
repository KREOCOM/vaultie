import json, re
from collections import defaultdict, OrderedDict
from datetime import date, timedelta

SRC = '/Users/barzdyla/banksync-test/revolut_txns.json'
OUT_PATH = '/private/tmp/claude-501/-Users-barzdyla-vaultie/0613433a-79c3-47e7-b9b6-0fb1f9300d2f/scratchpad/dash_data.json'

# Real bank balances at last sync (from the Enable Banking balances endpoint —
# NOT derivable from the txn list, so anchored here).
END_EUR = 7048.86          # Revolut EUR account balance
NOK_EUR = 0.01             # Revolut NOK account in EUR
NOK_NATIVE = '0,06 kr'
CASH_EUR = 0.0

d = json.load(open(SRC))

LT_MON = {1:'Sausis',2:'Vasaris',3:'Kovas',4:'Balandis',5:'Gegužė',6:'Birželis',7:'Liepa',
          8:'Rugpjūtis',9:'Rugsėjis',10:'Spalis',11:'Lapkritis',12:'Gruodis'}
LT_GEN = {1:'Sausio',2:'Vasario',3:'Kovo',4:'Balandžio',5:'Gegužės',6:'Birželio',7:'Liepos',
          8:'Rugpjūčio',9:'Rugsėjo',10:'Spalio',11:'Lapkričio',12:'Gruodžio'}
LT_WD = ['Pirmadienis','Antradienis','Trečiadienis','Ketvirtadienis','Penktadienis','Šeštadienis','Sekmadienis']

def signed(t):
    v = float(t['transaction_amount']['amount'])
    return v if t['credit_debit_indicator'] == 'CRDT' else -v

def cname(t):
    if t['credit_debit_indicator'] == 'DBIT':
        n = (t.get('creditor') or {}).get('name')
    else:
        n = (t.get('debtor') or {}).get('name')
    return (n or (t.get('remittance_information') or [''])[0] or '—').strip()

def norm(n):
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z ]', '', n.lower())).strip()[:16]

def looks_person(n):
    parts = n.split()
    if len(parts) not in (2, 3):
        return False
    if any(k in n.lower() for k in ['uab','mb','ab','vsi','grupe','ltd','llc','oy','oü',' as ']):
        return False
    return all(p.isalpha() and (p[:1].isupper() or p.isupper()) for p in parts)

# ── salary via EXCHANGE: recurring large currency-in = salary, else conversion ──
# One salary per month (the largest EXCHANGE credit that month); only trust it as
# salary when the pattern repeats across >=3 months (else it's a one-off swap).
_exch_by_month = defaultdict(list)
for t in d:
    if t['bank_transaction_code'].get('code') == 'EXCHANGE' and signed(t) >= 300:
        _exch_by_month[t['booking_date'][:7]].append((signed(t), t['entry_reference']))
IS_EXCHANGE_SALARY = len(_exch_by_month) >= 3
SALARY_IDS = set()
if IS_EXCHANGE_SALARY:
    for mo, lst in _exch_by_month.items():
        SALARY_IDS.add(max(lst)[1])  # entry_reference of largest exchange credit that month

KNOWN_LOAN = ['mogo','general financing','sb lizing','swedbank lizing','citadele faktoring','luminor lizing']

def classify(t):
    code = t['bank_transaction_code'].get('code')
    n = cname(t); nl = n.lower(); amt = signed(t)
    # ── non-merchant flows (bank_transaction_code = reliable signal) ──
    if code == 'EXCHANGE':
        if t['entry_reference'] in SALARY_IDS:
            return ('Atlyginimas','income','income','income',False)
        return ('Valiutos keitimas','transfer','swap','transfer',False)
    if code == 'TOPUP':
        return ('Sąskaitos papildymas','transfer','swap','transfer',False)
    if code in ('CARD_REFUND','CARD_CREDIT'):
        return ('Grąžinimas','income','swap','income',False)
    if code == 'TRANSFER':
        if any(k in nl for k in KNOWN_LOAN):
            return ('Paskola, lizingas','finance','money','finance',False)
        if any(k in nl for k in ['artus','nuoma','rent','busto adm','namu prieziur']):
            return ('Būstas, nuoma','housing','house','housing',False)
        if looks_person(n):
            return ('Asmeninis pervedimas','transfer','person','transfer',False)
        return ('Pervedimas','transfer','swap','transfer',False)
    # ── CARD_PAYMENT — merchant, category via keyword (best-effort, no MCC) ──
    def has(*ks): return any(k in nl for k in ks)
    if has('circle k','viada','neste','orlen','1-2-3','123 ','lukoil','emsi','baltic petroleum'):
        if abs(amt) >= 18: return ('Kuras','fuel','fuel','fuel',True)
        return ('Užkandžiai, kava','food','coffee','food',True)
    if has('royal smoke','smoke','vyno','alko','tabak'):
        return ('Alkoholis, tabakas','food','bottle','food',False)
    if has('maxima','rimi','iki','lidl','aibe','aibė','norfa','prisma','maisto prek','parduotuv','t-market','grocer','coop marked'):
        return ('Maisto prekės','food','cart','food',False)
    if has('mcdonald','hesburger','kfc','litriukas','pocien','skoniai','duona','kavin','restoran','pizza','sushi','coffee','caffe','cili','charlie','vero','baras','bar ','pub','uzeiga','bistro','delano'):
        return ('Kavinės, restoranai','food','dining','food',False)
    if has('gympl','lemon gym','impuls','fitness','wellness','sportas','sporto'):
        return ('Sportas','fitness','health','fitness',False)
    if has('vaistin','pharm','benu','camelia','gintarine','eurovaistine','klinik','odontolog','medic','ordinacij'):
        return ('Sveikata','health','health','health',False)
    if has('netflix','spotify','youtube','hbo','disney','cinema','kinas','forum cinemas','apollo','steam','playstation','delfiplius','delfi'):
        return ('Pramogos','entertainment','fun','entertainment',False)
    if has('bolt rentals','citybee','spark','ride'):
        return ('Paspirtukai, dalinimasis','transport','scooter','transport',False)
    if has('bolt','uber','taksi','trafi'):
        return ('Taksi','transport','taxi','transport',False)
    if has('parking','stova','up202','parkin'):
        return ('Parkavimas','transport','taxi','transport',False)
    if has('savasld','draudim','insur','ergo',' if ','gjensidige','balcia'):
        return ('Draudimas','vehicle','shield','vehicle',False)
    if has('telia','bite','tele2','pillar','pildyk','ignitis','eso ','vandenys','elektros skyr'):
        return ('Ryšys, komunaliniai','housing','home','housing',False)
    if has('verslo vartai','senukai','kesko','varle','varlė','pigu','technorama','elektro','avitela','kilobaitas'):
        return ('Elektronika, prekės','shopping','monitor','shopping',False)
    if has('epaslaug','e.paslaug','vmi','sodra','mokes','regitra'):
        return ('Mokesčiai','taxes','doc','taxes',False)
    if has('artus','nuoma','rent'):
        return ('Būstas, nuoma','housing','house','housing',False)
    if has('oanda','trading212','trading 212','revolut trading','swissquote','interactive'):
        return ('Investavimas','finance','doc','finance',False)
    return ('Kita','other','swap','other',True)

# ── recurring bills/subscriptions: appear in >=3 distinct months, ~monthly cadence
#    (not a frequently-visited shop), and not a person-to-person transfer ──
name_months = defaultdict(set)
name_count = defaultdict(int)
for t in d:
    k = norm(cname(t))
    name_months[k].add(t['booking_date'][:7])
    name_count[k] += 1
# categories that are frequent spend, never "subscriptions", even if ~monthly
NON_SUB_CATS = {'Maisto prekės','Kavinės, restoranai','Užkandžiai, kava','Alkoholis, tabakas',
                'Kuras','Taksi','Paspirtukai, dalinimasis','Parkavimas','Sveikata','Elektronika, prekės'}
def is_recurring_bill(t):
    if signed(t) >= 0:                       # bills are money OUT
        return False
    n = cname(t); k = norm(n)
    mo = len(name_months[k])
    if mo < 3:                               # need repetition across months to be sure
        return False
    if name_count[k] > mo * 1.8:             # too frequent → a shop you visit, not a bill
        return False
    cat = classify(t)[0]
    if cat in NON_SUB_CATS:
        return False
    if looks_person(n):                      # P2P transfer, not a subscription
        return False
    return True

# group by month -> day (feed), merging same creditor-name same day
bydate = defaultdict(list)
for t in d:
    bydate[t['booking_date']].append(t)

months = OrderedDict()
for dt in sorted(bydate, reverse=True):
    y, m, day = map(int, dt.split('-'))
    mkey = f'{y}-{m:02d}'
    months.setdefault(mkey, {'name': LT_MON[m], 'y': y, 'm': m, 'total': 0.0, 'days': []})
    merged = OrderedDict()
    for t in bydate[dt]:
        n = cname(t); key = norm(n)
        if key not in merged:
            cat, sec, ic, col, amb = classify(t)
            badges = []
            if t.get('status') == 'PDNG': badges.append('res')
            if is_recurring_bill(t): badges.append('rec')
            merged[key] = {'nm': n, 'cat': cat, 'sec': sec, 'ic': ic, 'col': col, 'amb': amb,
                           'a': 0.0, 'count': 0, 'badges': badges, 'pos': signed(t) > 0}
        merged[key]['a'] += signed(t); merged[key]['count'] += 1
    daytot = sum(x['a'] for x in merged.values())
    wd = LT_WD[date(y, m, day).weekday()]
    months[mkey]['days'].append({'date': dt, 'label': f'{wd}, {day} d.', 'wd': wd, 'day': day,
        'total': round(daytot, 2),
        'tx': [{'nm': x['nm'], 'cat': x['cat'], 'ic': x['ic'], 'col': x['col'],
                'a': round(x['a'], 2), 'count': x['count'] if x['count'] > 1 else 0,
                'badges': x['badges'], 'amb': x['amb'], 'pos': x['pos']} for x in merged.values()]})
    months[mkey]['total'] += daytot
for mk in months: months[mk]['total'] = round(months[mk]['total'], 2)

# week = Mon..Sun of the week containing the latest date — per-day CATEGORY breakdown
SECTION = {'food':('Maistas, gėrimai','green','food'),'fuel':('Transportas','blue','car'),
 'transport':('Transportas','blue','car'),'vehicle':('Transportas','blue','car'),
 'shopping':('Apsipirkimas','teal','bag'),'housing':('Būstas, sąskaitos','olive','home'),
 'taxes':('Finansai','red','money'),'invest':('Finansai','red','money'),'finance':('Finansai','red','money'),
 'fitness':('Sveikata, sportas','orange','health'),'health':('Sveikata, sportas','orange','health'),
 'entertainment':('Pramogos','cyan','fun'),'other':('Kita','indigo','money')}
SEC_ORDER = ['Maistas, gėrimai','Transportas','Apsipirkimas','Būstas, sąskaitos','Sveikata, sportas','Pramogos','Finansai','Kita']
latest = max(bydate); ly, lm, ld = map(int, latest.split('-'))
monday = date(ly, lm, ld) - timedelta(days=date(ly, lm, ld).weekday())
week_days = []; wtot = 0.0
for i in range(7):
    dd = monday + timedelta(days=i); k = dd.isoformat()
    secagg = {}
    for t in bydate.get(k, []):
        if t['credit_debit_indicator'] != 'DBIT': continue
        col = classify(t)[3]
        if col not in SECTION: continue
        label, color, sicon = SECTION[col]
        e = secagg.setdefault(label, {'label': label, 'color': color, 'icon': sicon, 'amount': 0.0})
        e['amount'] += (-signed(t))
    cats = [secagg[l] for l in SEC_ORDER if l in secagg]
    for c in cats: c['amount'] = round(c['amount'], 2)
    total = round(sum(c['amount'] for c in cats), 2)
    week_days.append({'lbl': ['Pr','An','Tr','Kt','Pn','Št','Sk'][i], 'total': total, 'cats': cats,
                      'dlabel': f'{LT_GEN[dd.month]} {dd.day}'})
    wtot += total
week = {'total': round(wtot, 2), 'days': week_days,
        'range': f'{monday.isoformat()}..{(monday + timedelta(days=6)).isoformat()}'}

# subscriptions/bills card — from the recurring 'rec' badge (latest amount per name)
recd = {}
for mk, mv in months.items():           # months sorted desc → first seen = latest
    for dd in mv['days']:
        for tx in dd['tx']:
            if 'rec' in tx['badges'] and not tx['pos']:
                if tx['nm'] not in recd:
                    recd[tx['nm']] = abs(tx['a'])

# overall net/income/spend
netflow = round(sum(signed(t) for t in d), 2)
income = round(sum(signed(t) for t in d if t['credit_debit_indicator'] == 'CRDT'), 2)
spend = round(sum(-signed(t) for t in d if t['credit_debit_indicator'] == 'DBIT'), 2)

# ── balance: real daily cumulative shape, anchored so EUR end = END_EUR ──
allt_sorted = sorted(d, key=lambda t: t['booking_date'])
by_day_total = OrderedDict()
for t in allt_sorted:
    by_day_total[t['booking_date']] = by_day_total.get(t['booking_date'], 0.0) + signed(t)
run = 0.0; cum_by_day = OrderedDict()
for dt, tot in by_day_total.items():
    run += tot; cum_by_day[dt] = run
base = END_EUR - run
series = [{'d': dt, 'v': round(base + c, 2)} for dt, c in cum_by_day.items()]
balance = {
    'current': round(END_EUR + NOK_EUR + CASH_EUR, 2),
    'series': series,
    'accounts': [
        {'name': 'Revolut EUR', 'amount': round(END_EUR, 2), 'sub': None, 'icon': 'R'},
        {'name': 'Revolut NOK', 'amount': round(NOK_EUR, 2), 'sub': NOK_NATIVE, 'icon': 'R'},
        {'name': 'Grynieji', 'amount': CASH_EUR, 'sub': None, 'icon': 'cash'},
    ],
    'start': series[0]['d'], 'end': series[-1]['d'], 'days': len(series),
}
# dashboard mini-sparkline (recent slice, ~26 pts)
recent = [p['v'] for p in series if p['d'] >= '2026-05-13']
step = max(1, len(recent) // 26)
spark = [round(x) for x in recent[::step]][-26:]

jun = [t for t in d if t['booking_date'].startswith('2026-06')]
june_net = round(sum(signed(t) for t in jun), 2)

# ── full transaction list (for drill-downs, budgets) + merchant brand key ──
BRANDS = ['maxima','rimi','iki','lidl','aibe','aibė','norfa','circle k','viada','neste','1-2-3',
 'bolt rentals','bolt','royal smoke','mcdonald','hesburger','skoniai','senukai','kesko',
 'danutes pocien','birzu duona','biržų duona','verslo vartai','epaslaug','artus','savasld','oanda','coop marked']
def brandkey(n):
    nl = n.lower()
    for b in BRANDS:
        if b in nl: return b
    toks = [w for w in re.sub(r'[^a-zA-ZąčęėįšųūžĄČĘĖĮŠŲŪŽ ]', ' ', nl).split() if len(w) > 1][:2]
    return ' '.join(toks) or nl[:8]
SECLABEL = {'food':('Maistas, gėrimai','green'),'fuel':('Transportas','blue'),'transport':('Transportas','blue'),
 'vehicle':('Transportas','blue'),'shopping':('Apsipirkimas','teal'),'housing':('Būstas, sąskaitos','olive'),
 'taxes':('Finansai','red'),'invest':('Finansai','red'),'finance':('Finansai','red'),
 'fitness':('Sveikata, sportas','orange'),'health':('Sveikata, sportas','orange'),
 'entertainment':('Pramogos','cyan'),'other':('Kita','indigo'),
 'transfer':('Pervedimai','indigo'),'income':('Pajamos','amber')}
allt = []
for t in sorted(d, key=lambda t: t['booking_date'], reverse=True):
    cat, sec, ic, col, amb = classify(t)
    seclabel, seccolor = SECLABEL.get(col, ('Kita', 'indigo'))
    n = cname(t); y, m, day = map(int, t['booking_date'].split('-'))
    badges = ['res'] if t.get('status') == 'PDNG' else []
    if is_recurring_bill(t): badges.append('rec')
    allt.append({'nm': n, 'mkey': brandkey(n), 'd': t['booking_date'],
      'wd': LT_WD[date(y, m, day).weekday()][:3], 'md': f'{LT_GEN[m]} {day}',
      'cat': cat, 'col': col, 'ic': ic, 'sec': seclabel, 'secc': seccolor, 'a': round(signed(t), 2),
      'amb': amb, 'badges': badges, 'pos': signed(t) > 0})

BUDGETS = {'Maisto prekės': 390.0, 'Kavinės, restoranai': 150.0, 'Kuras': 220.0, 'Alkoholis, tabakas': 120.0}

OUT = {'months': list(months.values())[:2],
       'week': week,
       'subs': {'items': sorted(recd.items(), key=lambda x: -x[1]), 'total': round(sum(recd.values()), 2)},
       'spark': spark, 'june_net': june_net, 'all': allt, 'budgets': BUDGETS, 'balance': balance,
       'meta': {'count': len(d), 'range': f'{min(bydate)}..{max(bydate)}',
                'netflow': netflow, 'income': income, 'spend': spend, 'latest': latest,
                'exchange_salary': IS_EXCHANGE_SALARY, 'salary_months': len(SALARY_IDS)}}

open(OUT_PATH, 'w').write(json.dumps(OUT, ensure_ascii=False))

# ---- consistency self-test (fails loudly if aggregations don't foot) ----
def _check(month):
    rows = [t for t in allt if t['d'].startswith(month)]
    if not rows: return None
    net = round(sum(t['a'] for t in rows), 2)
    sec = defaultdict(float); day = defaultdict(float)
    for t in rows:
        sec[t['sec']] += t['a']; day[t['d']] += t['a']
    assert abs(round(sum(sec.values()), 2) - net) < 0.01, f'{month}: category sum != net'
    assert abs(round(sum(day.values()), 2) - net) < 0.01, f'{month}: day sum != net'
    return net
for _m in ['2026-05', '2026-06', '2026-07']: _check(_m)
assert abs(series[-1]['v'] - END_EUR) < 0.01, 'balance series does not end at END_EUR'
print('✓ consistency OK (category=net, day=net; balance anchored)')
print('DATA:', OUT['meta']['range'], '| txns', OUT['meta']['count'],
      '| exchange_salary', IS_EXCHANGE_SALARY, '| salary_months', len(SALARY_IDS))
print('SUBSCRIPTIONS/BILLS detected:', len(recd), '→ total', OUT['subs']['total'], 'EUR/mo')
for nm, amt in sorted(recd.items(), key=lambda x: -x[1]):
    print(f'   {amt:7.2f}  {nm[:40]}')
print('INCOME (all credit):', income, '| SPEND:', spend, '| NET:', netflow)
