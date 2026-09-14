#!/usr/bin/env python3
"""N-way comparison of persona-db API evidence packages.

Usage: compare-nway.py [dir1 dir2 dir3 dir4 ...]
Defaults to the four rounds: v4.9.2 / v5.2 / v5.3.1 / v5.4
"""
import json, glob, os, sys, csv, hashlib, itertools

HOME = '/Users/kstsai/Documents'
DIRS = sys.argv[1:] or [
    f'{HOME}/round1-v4.9.2-nodeA',
    f'{HOME}/round2-v5.2-nodeB',
    f'{HOME}/round3-v5.3.1-nodeA',
    f'{HOME}/round4-v5.4-nodeB',
    f'{HOME}/round5-v5.6-nodeB-frozenrunner',
    f'{HOME}/round6-v5.6-nodeB-upstreamrunner',
    f'{HOME}/round7-v5.6-nodeA-upstreamrunner',
]
CASES = ['01_kangshimei','02_tesla','03_fashion','04_role_fangzhong',
         '05_role_banker','06_aesthetic','07_debt','08_boss']
NEWDIMS = ['aesthetic_procedure','debt_status','employment_status']
TAGS = 'ABCDEFGH'

def ver(d):
    p=os.path.join(d,'raw','00_status.body')
    if not os.path.exists(p): return '?'
    for line in open(p,encoding='utf-8'):
        if 'Version' in line: return line.split()[-1]
    return '?'

def host(d): return os.path.basename(d.rstrip('/'))

def load(d,c):
    p=os.path.join(d,'json',c+'.json')
    try: return json.load(open(p,encoding='utf-8'))
    except Exception: return None

def ok(r):
    """True only for a successful candidates response (not an error body)."""
    return isinstance(r,dict) and 'total_matched' in r

def errcode(d,c):
    """Return the HTTP status + error code for a failed case, else None."""
    m=meta(d,c); code=m.get('http_code')
    if code in (None,'200'): return None
    r=load(d,c)
    ec=None
    if isinstance(r,dict):
        ec=(r.get('detail') or {}).get('code') if isinstance(r.get('detail'),dict) else None
        if ec is None and isinstance(r.get('error'),dict): ec=r['error'].get('code')
    return f'HTTP {code}' + (f' {ec}' if ec else '')

def meta(d,c):
    p=os.path.join(d,'meta',c+'.meta'); m={}
    if os.path.exists(p):
        for line in open(p,encoding='utf-8'):
            if ':' in line:
                k,v=line.split(':',1); m[k.strip()]=v.strip()
    return m

def dims(d):
    for f in sorted(glob.glob(os.path.join(d,'supplemental','detail_*.json'))):
        try: return set(json.load(open(f,encoding='utf-8'))['persona']['dimensions'].keys())
        except Exception: pass
    return set()

def oapi(d):
    p=os.path.join(d,'raw','openapi.json')
    if not os.path.exists(p): return None
    return json.load(open(p,encoding='utf-8'))

labs=[f'{ver(d)} @ {host(d)}' for d in DIRS]
W=30
print('='*(24+W*len(DIRS)))
for i,l in enumerate(labs): print(f'  {TAGS[i]} = {l}')
print('='*(24+W*len(DIRS)))

print('\n=== persona schema dimensions ===')
for l,d in zip(labs,DIRS): print(f'  {l:46s} {len(dims(d))} dims')
base=dims(DIRS[0])
for i,d in enumerate(DIRS[1:],1):
    add=sorted(dims(d)-base); rem=sorted(base-dims(d))
    print(f'  A vs {TAGS[i]}: +{add or "[]"}  -{rem or "[]"}')

print('\n=== OpenAPI contract ===')
hashes=[]
for l,d in zip(labs,DIRS):
    p=os.path.join(d,'raw','openapi.json')
    h=hashlib.sha256(open(p,'rb').read()).hexdigest() if os.path.exists(p) else '(missing)'
    hashes.append(h)
    print(f'  {l:46s} {len(open(p,"rb").read()) if os.path.exists(p) else 0:6d} B  {h[:16]}')
print('  distinct contracts:', len(set(hashes)))

print('\n=== NEW contract fields present? (response top-level / broadening / scoring) ===')
def find_oapi(d, path):
    o=oapi(d)
    if not o: return None
    cur=o
    for k in path:
        if not isinstance(cur,dict) or k not in cur: return None
        cur=cur[k]
    return cur
for lab_path,label in [
    (['components','schemas','CandidatesResponse','properties'],'top-level props'),
    (['components','schemas','CandidatesResponse','properties','broadening_attempts','items','properties'],'broadening_attempts item props'),
    (['components','schemas','CandidatesResponse','properties','scoring_basis','properties'],'scoring_basis props'),
]:
    print(f'  --- {label} ---')
    for l,d in zip(labs,DIRS):
        v=find_oapi(d,lab_path)
        print(f'    {l:44s} {sorted(v.keys()) if isinstance(v,dict) else "(n/a)"}')

print('\n=== per-case: total_matched / returned / top_score / latency ===')
hdr=f'{"case":20s} ' + ' '.join(f'{t:>{W}s}' for t in TAGS[:len(DIRS)])
print(hdr); print('-'*len(hdr))
rows=[]
for c in CASES:
    cells=[]; rec={'case':c}
    for i,d in enumerate(DIRS):
        r=load(d,c)
        if not ok(r):
            e=errcode(d,c)
            cells.append(f'{(e or "(missing)"):>{W}s}'); rec[f'{TAGS[i]}_ERROR']=e or 'missing'; continue
        m=meta(d,c); sec=float(m.get('time_total_sec',0) or 0)
        pool=r.get('pool_exhausted')
        flag='!' if pool else ' '
        cells.append(f'{r["total_matched"]:>6d} {len(r["persona_ids"]):>2d}{flag} {r["summary"][0]["score"]:>7.4f} {sec:>5.0f}s')
        t=TAGS[i]
        rec[f'{t}_matched']=r['total_matched']; rec[f'{t}_returned']=len(r['persona_ids'])
        rec[f'{t}_ids']=' '.join(map(str,r['persona_ids'])); rec[f'{t}_top']=r['summary'][0]['score']
        rec[f'{t}_sec']=sec; rec[f'{t}_pool_exhausted']=pool
    print(f'{c:20s} ' + ' '.join(cells)); rows.append(rec)
print('  (within each cell: total_matched / n_returned / top_score / latency ; "!" = pool_exhausted true)')

print('\n=== pool_exhausted / returned field (v5.4 telemetry) ===')
for l,d in zip(labs,DIRS):
    vals=[]
    for c in CASES:
        r=load(d,c)
        if not ok(r): continue
        if 'pool_exhausted' in r or 'returned' in r:
            vals.append(f'{c[:2]}:pool={r.get("pool_exhausted")},ret={r.get("returned")}')
    print(f'  {l:46s} {vals if vals else "(fields absent)"}')

print('\n=== broadening loop telemetry (no_op / overshoot / filters_changed) ===')
for l,d in zip(labs,DIRS):
    have=[]
    for c in CASES:
        r=load(d,c)
        if not ok(r): continue
        for x in r.get('broadening_attempts',[]):
            for k in ('no_op','overshoot','filters_changed'):
                if k in x: have.append(k); break
    ks=sorted(set(have))
    print(f'  {l:46s} {ks if ks else "(absent — legacy shape)"}')

print('\n=== scoring_basis fields ===')
for l,d in zip(labs,DIRS):
    r=load(d,'07_debt')
    print(f'  {l:46s} {sorted(r["scoring_basis"].keys()) if ok(r) else "(n/a)"}')

print('\n=== top-k set overlap (pairwise across all versions) ===')
pairs=list(itertools.combinations(range(len(DIRS)),2))
print(f'{"case":20s} ' + ' '.join(f'{TAGS[a]}∩{TAGS[b]}' for a,b in pairs))
for c in CASES:
    rs=[load(d,c) for d in DIRS]
    sets=[set(r['persona_ids']) if ok(r) else None for r in rs]
    out=[]
    for a,b in pairs:
        if sets[a] is None or sets[b] is None: out.append('n/a')
        else: out.append(f'{len(sets[a]&sets[b])}/{max(len(sets[a]),len(sets[b]))}')
    print(f'{c:20s} ' + ' '.join(f'{x:>7s}' for x in out))

print('\n=== NEW dimensions applied as FILTERS ===')
for c in CASES:
    line=f'  {c:20s} '
    for d in DIRS:
        r=load(d,c)
        if not ok(r):
            line+=f'{(errcode(d,c) or "(missing)"):>28s}'; continue
        got=[f'{k}={"/".join(v)}' for k,v in r['applied_filters'].items() if k in NEWDIMS]
        line+=f'{(("; ".join(got)) or "—"):>28s}'
    print(line)

print('\n=== employment_status ever applied? ===')
for l,d in zip(labs,DIRS):
    hits=[c[:2] for c in CASES if ok(load(d,c)) and 'employment_status' in (load(d,c)['applied_filters'] or {})]
    print(f'  {l:46s} {hits or "NEVER (0/8)"}')

print('\n=== income saturation (income=">8萬") ===')
for l,d in zip(labs,DIRS):
    p=[]
    for c in CASES:
        r=load(d,c)
        if not ok(r): p.append(f'{c[:2]}:ERR'); continue
        p.append(f'{c[:2]}:{sum(1 for s in r["summary"] if s.get("income")==">8萬")}/{len(r["summary"])}')
    print(f'  {l:46s} ' + '  '.join(p))

print('\n=== broadening inert (before==after) vs declared no_op ===')
for l,d in zip(labs,DIRS):
    t=i=declared=0
    for c in CASES:
        r=load(d,c)
        if not ok(r): continue
        for x in r.get('broadening_attempts',[]):
            t+=1; i+= x.get('match_count_before')==x.get('match_count_after')
            declared+= bool(x.get('no_op'))
    print(f'  {l:46s} inert={i}/{t}' + (f'  declared no_op={declared}' if declared else ''))

print('\n=== scoring_basis.dims_counted consistency (mismatch count) ===')
for l,d in zip(labs,DIRS):
    out=[]; tin=0
    for c in CASES:
        r=load(d,c)
        if not ok(r): continue
        dm=r['scoring_basis']['dims_counted']
        rr=[(s['score'],'|'.join(str(s.get(k,'n/a')) for k in dm)) for s in r['summary']]
        ties=sum(1 for i in range(len(rr)) for j in range(i+1,len(rr)) if rr[i][0]==rr[j][0])
        bad=sum(1 for i in range(len(rr)) for j in range(i+1,len(rr)) if (rr[i][0]==rr[j][0])!=(rr[i][1]==rr[j][1]))
        if ties: tin+=1
        out.append(f'{c[:2]}:{bad}')
    print(f'  {l:46s} ' + ' '.join(out) + f'   (cases with ties = {tin}/8)')

out=os.path.join(DIRS[-1],'version-comparison-nway.csv')
keys=[]
for r in rows:
    for k in r:
        if k not in keys: keys.append(k)
with open(out,'w',newline='',encoding='utf-8-sig') as fh:
    w=csv.DictWriter(fh,fieldnames=keys); w.writeheader(); w.writerows(rows)
print(f'\nwrote {out}')
