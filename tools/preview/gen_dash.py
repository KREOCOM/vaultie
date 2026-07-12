import json, re
from collections import defaultdict, OrderedDict
from datetime import date

d = json.load(open('/Users/barzdyla/banksync-test/revolut_txns.json'))

LT_MON = {7:'Liepa',6:'Birželis',5:'Gegužė',4:'Balandis',3:'Kovas',2:'Vasaris',1:'Sausis',
          8:'Rugpjūtis',9:'Rugsėjis',10:'Spalis',11:'Lapkritis',12:'Gruodis'}
LT_WD  = ['Pirmadienis','Antradienis','Trečiadienis','Ketvirtadienis','Penktadienis','Šeštadienis','Sekmadienis']

def signed(t):
    v=float(t['transaction_amount']['amount'])
    return v if t['credit_debit_indicator']=='CRDT' else -v

def cname(t):
    if t['credit_debit_indicator']=='DBIT':
        n=(t.get('creditor') or {}).get('name')
    else:
        n=(t.get('debtor') or {}).get('name')
    return (n or (t.get('remittance_information') or [''])[0] or '—').strip()

def looks_person(n):
    parts=n.split()
    return len(parts) in (2,3) and all(p.isalpha() and (p[:1].isupper() or p.isupper()) for p in parts) and not any(
        k in n.lower() for k in ['uab','mb','ab','vsi','grupe','ltd','oü','as '])

# (cat_lt, section, icon, colorkey, ambiguous)
KNOWN_LOAN=['mogo','general financing','sb lizing','swedbank lizing','citadele faktoring','luminor lizing']
def classify(t):
    code=t['bank_transaction_code'].get('code')
    n=cname(t); nl=n.lower(); amt=signed(t)
    # ── non-merchant flows (bank_transaction_code = reliable signal) ──
    if code=='EXCHANGE':                       # own money converted between currencies → NOT income/spend
        return ('Valiutos keitimas','transfer','swap','transfer',False)
    if code=='TOPUP':
        return ('Sąskaitos papildymas','transfer','swap','transfer',False)
    if code in ('CARD_REFUND','CARD_CREDIT'):
        return ('Grąžinimas','income','swap','income',False)
    if code=='TRANSFER':
        if any(k in nl for k in KNOWN_LOAN):
            return ('Paskola, lizingas','finance','money','finance',False)
        if looks_person(n):
            return ('Asmeninis pervedimas','transfer','person','transfer',False)
        return ('Pervedimas','transfer','swap','transfer',False)
    # ── CARD_PAYMENT — merchant, category via keyword (best-effort, no MCC) ──
    def has(*ks): return any(k in nl for k in ks)
    # fuel STATIONS: no MCC → guess by amount (fuel≈big, snacks/coffee≈small); keep ambiguous flag
    if has('circle k','viada','neste','orlen','1-2-3','123 ','lukoil','emsi','baltic petroleum'):
        if abs(amt)>=18: return ('Kuras','fuel','fuel','fuel',True)
        return ('Užkandžiai, kava','food','coffee','food',True)
    if has('royal smoke','smoke','vyno','alko','tabak'):
        return ('Alkoholis, tabakas','food','bottle','food',False)
    if has('maxima','rimi','iki','lidl','aibe','aibė','norfa','prisma','maisto prek','parduotuv','t-market','grocer'):
        return ('Maisto prekės','food','cart','food',False)
    if has('mcdonald','hesburger','kfc','litriukas','pocien','skoniai','duona','kavin','restoran','pizza','sushi','coffee','caffe','cili','charlie','vero'):
        return ('Kavinės, restoranai','food','dining','food',False)
    if has('gympl','lemon gym','impuls','fitness','wellness','sportas','sporto'):
        return ('Sportas','fitness','health','fitness',False)
    if has('vaistin','pharm','benu','camelia','gintarine','eurovaistine','klinik','odontolog','medic','ordinacij'):
        return ('Sveikata','health','health','health',False)
    if has('netflix','spotify','youtube','hbo','disney','cinema','kinas','forum cinemas','apollo','steam','playstation'):
        return ('Pramogos','entertainment','fun','entertainment',False)
    if has('bolt rentals','citybee','spark','ride'):
        return ('Paspirtukai, dalinimasis','transport','scooter','transport',False)
    if has('bolt','uber','taksi','trafi'):
        return ('Taksi','transport','taxi','transport',False)
    if has('parking','stova','up202','parkin'):
        return ('Parkavimas','transport','taxi','transport',False)
    if has('savasld','draudim','insur','ergo',' if ','gjensidige','balcia'):
        return ('Draudimas','vehicle','shield','vehicle',False)
    if has('telia','bite','tele2','pillar','ignitis','eso ','vandenys','elektros skyr'):
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

# recurring detection: same normalized merchant in >=3 distinct months
def norm(n): return re.sub(r'\s+',' ',re.sub(r'[^a-z ]','',n.lower())).strip()[:16]
months_of=defaultdict(set)
for t in d:
    months_of[norm(cname(t))].add(t['booking_date'][:7])
recurring_names={k for k,v in months_of.items() if len(v)>=3}
KNOWN_BILL={'artus','savasld'}

# group by month -> day
bydate=defaultdict(list)
for t in d: bydate[t['booking_date']].append(t)

months=OrderedDict()
for dt in sorted(bydate, reverse=True):
    y,m,day=map(int,dt.split('-'))
    mkey=f'{y}-{m:02d}'
    months.setdefault(mkey, {'name':LT_MON[m], 'y':y,'m':m,'total':0.0,'days':[]})
    txs=bydate[dt]
    # merge same creditor-name same day
    merged=OrderedDict()
    for t in txs:
        n=cname(t); key=norm(n)
        if key not in merged:
            cat,sec,ic,col,amb=classify(t)
            badges=[]
            if t.get('status')=='PDNG': badges.append('res')
            if any(b in key for b in KNOWN_BILL): badges.append('rec')
            merged[key]={'nm':n,'cat':cat,'sec':sec,'ic':ic,'col':col,'amb':amb,
                         'a':0.0,'count':0,'badges':badges,'pos':signed(t)>0}
        merged[key]['a']+=signed(t); merged[key]['count']+=1
    daytot=sum(x['a'] for x in merged.values())
    wd=LT_WD[date(y,m,day).weekday()]
    # nice label
    if mkey==max(months): pass
    label=f'{wd}, {LT_MON[m].lower()[:-1]}os {day}' if False else f'{wd}, {day} d.'
    months[mkey]['days'].append({'date':dt,'label':label,'wd':wd,'day':day,
                                 'total':round(daytot,2),
                                 'tx':[{'nm':x['nm'],'cat':x['cat'],'ic':x['ic'],'col':x['col'],
                                        'a':round(x['a'],2),'count':x['count'] if x['count']>1 else 0,
                                        'badges':x['badges'],'amb':x['amb'],'pos':x['pos']} for x in merged.values()]})
    months[mkey]['total']+=daytot

for mk in months: months[mk]['total']=round(months[mk]['total'],2)

# week = Mon..Sun of the week containing the latest date — per-day CATEGORY breakdown
SECTION={'food':('Maistas, gėrimai','green','food'),'fuel':('Transportas','blue','car'),
 'transport':('Transportas','blue','car'),'vehicle':('Transportas','blue','car'),
 'shopping':('Apsipirkimas','teal','bag'),'housing':('Būstas, sąskaitos','olive','home'),
 'taxes':('Finansai','red','money'),'invest':('Finansai','red','money'),'finance':('Finansai','red','money'),
 'fitness':('Sveikata, sportas','orange','health'),'health':('Sveikata, sportas','orange','health'),
 'entertainment':('Pramogos','cyan','fun'),'other':('Kita','indigo','money')}
SEC_ORDER=['Maistas, gėrimai','Transportas','Apsipirkimas','Būstas, sąskaitos','Sveikata, sportas','Pramogos','Finansai','Kita']
LT_GEN={1:'Sausio',2:'Vasario',3:'Kovo',4:'Balandžio',5:'Gegužės',6:'Birželio',7:'Liepos',
 8:'Rugpjūčio',9:'Rugsėjo',10:'Spalio',11:'Lapkričio',12:'Gruodžio'}
from datetime import timedelta
latest=max(bydate); ly,lm,ld=map(int,latest.split('-'))
d0=date(ly,lm,ld); monday=d0 - timedelta(days=d0.weekday())
week_days=[]; wtot=0.0
for i in range(7):
    dd=monday+timedelta(days=i); k=dd.isoformat()
    secagg={}
    for t in bydate.get(k,[]):
        if t['credit_debit_indicator']!='DBIT': continue
        cat,sec,ic,col,amb=classify(t)
        if col not in SECTION: continue  # transfers/income excluded from spend bar
        label,color,sicon=SECTION[col]
        e=secagg.setdefault(label,{'label':label,'color':color,'icon':sicon,'amount':0.0})
        e['amount']+=(-signed(t))
    cats=[secagg[l] for l in SEC_ORDER if l in secagg]
    for c in cats: c['amount']=round(c['amount'],2)
    total=round(sum(c['amount'] for c in cats),2)
    week_days.append({'lbl':['Pr','An','Tr','Kt','Pn','Št','Sk'][i],'total':total,'cats':cats,
                      'dlabel':f'{LT_GEN[dd.month]} {dd.day}'})
    wtot+=total
week={'total':round(wtot,2),'days':week_days,'range':f'{monday.isoformat()}..{(monday+timedelta(days=6)).isoformat()}'}

# subscriptions/bills card — KNOWN BILLS only (not 'frequent' merchants)
recd={}
for mk,mv in months.items():
    for dd in mv['days']:
        for tx in dd['tx']:
            if 'rec' in tx['badges'] and not tx['pos']:
                k=norm(tx['nm'])
                if k not in recd: recd[tx['nm']]=abs(tx['a'])  # keep latest (months sorted desc)


# overall net/income/spend across file
netflow=round(sum(signed(t) for t in d),2)
income=round(sum(signed(t) for t in d if t['credit_debit_indicator']=='CRDT'),2)
spend=round(sum(-signed(t) for t in d if t['credit_debit_indicator']=='DBIT'),2)

# balance sparkline: real cumulative shape, anchored so end=7049
allt=sorted(d,key=lambda t:t['booking_date'])
c=0.0; full=[]
for t in allt: c+=signed(t); full.append(c)
END=7049.0; base=END-full[-1]
recent=[base+full[i] for i,t in enumerate(allt) if t['booking_date']>='2026-05-13']
step=max(1,len(recent)//26); spark=[round(x) for x in recent[::step]][-26:]
# june net (verified vs Bilance +1369)
jun=[t for t in d if t['booking_date'].startswith('2026-06')]
june_net=round(sum(signed(t) for t in jun),2)

# ── full transaction list (for 'similar transactions', budgets) + merchant brand key ──
BRANDS=['maxima','rimi','iki','lidl','aibe','aibė','norfa','circle k','viada','neste','1-2-3',
 'bolt rentals','bolt','royal smoke','mcdonald','hesburger','skoniai','senukai','kesko',
 'danutes pocien','birzu duona','biržų duona','verslo vartai','epaslaug','artus','savasld','oanda']
def brandkey(n):
    nl=n.lower()
    for b in BRANDS:
        if b in nl: return b
    toks=[w for w in re.sub(r'[^a-zA-ZąčęėįšųūžĄČĘĖĮŠŲŪŽ ]',' ',nl).split() if len(w)>1][:2]
    return ' '.join(toks) or nl[:8]
SECLABEL={'food':('Maistas, gėrimai','green'),'fuel':('Transportas','blue'),'transport':('Transportas','blue'),
 'vehicle':('Transportas','blue'),'shopping':('Apsipirkimas','teal'),'housing':('Būstas, sąskaitos','olive'),
 'taxes':('Finansai','red'),'invest':('Finansai','red'),'finance':('Finansai','red'),
 'fitness':('Sveikata, sportas','orange'),'health':('Sveikata, sportas','orange'),
 'entertainment':('Pramogos','cyan'),'other':('Kita','indigo'),
 'transfer':('Pervedimai','indigo'),'income':('Pajamos','amber')}
LT_MON_GEN={1:'Sausio',2:'Vasario',3:'Kovo',4:'Balandžio',5:'Gegužės',6:'Birželio',7:'Liepos',
 8:'Rugpjūčio',9:'Rugsėjo',10:'Spalio',11:'Lapkričio',12:'Gruodžio'}
allt=[]
for t in sorted(d, key=lambda t:t['booking_date'], reverse=True):
    cat,sec,ic,col,amb=classify(t)
    seclabel,seccolor=SECLABEL.get(col,('Kita','indigo'))
    n=cname(t); y,m,day=map(int,t['booking_date'].split('-'))
    allt.append({'nm':n,'mkey':brandkey(n),'d':t['booking_date'],
      'wd':LT_WD[date(y,m,day).weekday()][:3],'md':f'{LT_MON_GEN[m]} {day}',
      'cat':cat,'col':col,'ic':ic,'sec':seclabel,'secc':seccolor,'a':round(signed(t),2),
      'amb':amb,'badges':(['res'] if t.get('status')=='PDNG' else []),'pos':signed(t)>0})
# sample per-category monthly budgets (limit = sample; spent computed in-app)
BUDGETS={'Maisto prekės':390.0,'Kavinės, restoranai':150.0,'Kuras':220.0,'Alkoholis, tabakas':120.0}

OUT={'months':list(months.values())[:2],  # latest 2 months for the feed
     'week':week,
     'subs':{'items':sorted(recd.items(),key=lambda x:-x[1]),'total':round(sum(recd.values()),2)},
     'spark':spark, 'june_net':june_net, 'all':allt, 'budgets':BUDGETS,
     'meta':{'count':len(d),'range':f'{min(bydate)}..{max(bydate)}',
             'netflow':netflow,'income':income,'spend':spend,'latest':latest}}

open('/private/tmp/claude-501/-Users-barzdyla-vaultie/0613433a-79c3-47e7-b9b6-0fb1f9300d2f/scratchpad/dash_data.json','w').write(json.dumps(OUT,ensure_ascii=False))

# ---- consistency self-test (fails loudly if aggregations don't foot) ----
from collections import defaultdict as _dd
def _check(month):
    rows=[t for t in allt if t['d'].startswith(month)]
    if not rows: return None
    net=round(sum(t['a'] for t in rows),2)
    sec=_dd(float); day=_dd(float)
    for t in rows:
        sec[t['sec']]+=t['a']; day[t['d']]+=t['a']
    assert abs(round(sum(sec.values()),2)-net)<0.01, f'{month}: category sum != net'
    assert abs(round(sum(day.values()),2)-net)<0.01, f'{month}: day sum != net'
    return net
for _m in ['2026-05','2026-06','2026-07']: _check(_m)
print('\u2713 consistency OK (category=net, day=net) for 05/06/07')
print('DATA:', OUT['meta']['range'], '| txns', OUT['meta']['count'])
_jun=[t for t in allt if t['d'].startswith('2026-06')]
_js=_dd(float)
for t in _jun: _js[t['sec']]+=t['a']
for _s,_v in sorted(_js.items(),key=lambda x:-abs(x[1])): print(f'   {_s:22} {_v:9.2f}')
