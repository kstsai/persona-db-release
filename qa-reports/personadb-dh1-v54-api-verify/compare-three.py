#!/usr/bin/env python3
"""Three-way comparison of persona-db API evidence packages.

Usage: compare-three.py <A_dir> <B_dir> <C_dir>
Default: v4.9.2 (NODE-A) / v5.2 (NODE-B) / v5.3.1 (NODE-A upgraded)
"""
import json, glob, os, sys, csv

DIRS = sys.argv[1:4] if len(sys.argv) >= 4 else [
    '/Users/kstsai/Documents/personadb-NODE-A-api-verify',
    '/Users/kstsai/Documents/personadb-dh1-api-verify',
    '/Users/kstsai/Documents/personadb-NODE-A-v531-api-verify',
]
CASES = ['01_kangshimei','02_tesla','03_fashion','04_role_fangzhong',
         '05_role_banker','06_aesthetic','07_debt','08_boss']
NEWDIMS = ['aesthetic_procedure','debt_status','employment_status']

def ver(d):
    p = os.path.join(d,'raw','00_status.body')
    if not os.path.exists(p): return '?'
    for line in open(p,encoding='utf-8'):
        if 'Version' in line: return line.split()[-1]
    return '?'

def load(d,c):
    p = os.path.join(d,'json',c+'.json')
    return json.load(open(p,encoding='utf-8')) if os.path.exists(p) else None

def meta(d,c):
    p = os.path.join(d,'meta',c+'.meta'); m={}
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

labs=[f"{ver(d)} @ {os.path.basename(d.rstrip('/'))}" for d in DIRS]
print('='*110)
for i,l in enumerate(labs): print(f'  {"ABC"[i]} = {l}')
print('='*110)

print('\n=== persona schema dimensions ===')
for l,d in zip(labs,DIRS): print(f'  {l:48s} {len(dims(d))} dims')
print(f'  A vs B: new in B = {sorted(dims(DIRS[1])-dims(DIRS[0])) or "(none)"}')
print(f'  B vs C: new in C = {sorted(dims(DIRS[2])-dims(DIRS[1])) or "(none)"}')
print(f'  B vs C: gone in C = {sorted(dims(DIRS[1])-dims(DIRS[2])) or "(none)"}')

print('\n=== OpenAPI contract hash ===')
import hashlib
for l,d in zip(labs,DIRS):
    p=os.path.join(d,'raw','openapi.json')
    h=hashlib.sha256(open(p,'rb').read()).hexdigest()[:16] if os.path.exists(p) else '(missing)'
    print(f'  {l:48s} {h}')

print('\n=== per-case: total_matched / returned / top_score / latency ===')
hdr=f'{"case":20s} ' + ' '.join(f'{x:>26s}' for x in 'ABC')
print(hdr); print('-'*len(hdr))
rows=[]
for c in CASES:
    cells=[]
    rec={'case':c}
    for i,(l,d) in enumerate(zip(labs,DIRS)):
        r=load(d,c)
        if not r: cells.append(f'{"(missing)":>26s}'); continue
        m=meta(d,c)
        sec=float(m.get('time_total_sec',0) or 0)
        cells.append(f'{r["total_matched"]:>7d} {len(r["persona_ids"]):>3d} {r["summary"][0]["score"]:>7.4f} {sec:>6.0f}s')
        rec[f'{chr(65+i)}_matched']=r['total_matched']; rec[f'{chr(65+i)}_ids']=' '.join(map(str,r['persona_ids']))
        rec[f'{chr(65+i)}_top']=r['summary'][0]['score']; rec[f'{chr(65+i)}_sec']=sec
    print(f'{c:20s} ' + ' '.join(cells)); rows.append(rec)
print('  (columns within each = total_matched / n_returned / top_score / latency)')

print('\n=== top-k set overlap (pairwise) ===')
for c in CASES:
    sets=[set(load(d,c)['persona_ids']) if load(d,c) else set() for d in DIRS]
    o=[len(sets[0]&sets[1]),len(sets[0]&sets[2]),len(sets[1]&sets[2])]
    n=[len(s) for s in sets]
    print(f'  {c:20s} A∩B={o[0]}/{max(n[0],n[1])}  A∩C={o[1]}/{max(n[0],n[2])}  B∩C={o[2]}/{max(n[1],n[2])}')

print('\n=== NEW dimensions applied as FILTERS ===')
for c in CASES:
    line=f'  {c:20s} '
    for d in DIRS:
        r=load(d,c)
        if not r: line+=f'{"(missing)":>30s}'; continue
        got=[f'{k}={"/".join(v)}' for k,v in r['applied_filters'].items() if k in NEWDIMS]
        line+=f'{(("; ".join(got)) or "—"):>30s}'
    print(line)

print('\n=== employment_status ever applied? ===')
for l,d in zip(labs,DIRS):
    hits=[c for c in CASES if load(d,c) and 'employment_status' in load(d,c)['applied_filters']]
    print(f'  {l:48s} {hits or "NEVER (0/8)"}')

print('\n=== income saturation (share income=">8萬") ===')
for l,d in zip(labs,DIRS):
    p=[]
    for c in CASES:
        r=load(d,c)
        if not r: continue
        p.append(f'{c[:2]}:{sum(1 for s in r["summary"] if s.get("income")==">8萬")}/{len(r["summary"])}')
    print(f'  {l:48s} ' + '  '.join(p))

print('\n=== broadening inert loops ===')
for l,d in zip(labs,DIRS):
    t=i=0
    for c in CASES:
        r=load(d,c)
        if not r: continue
        for x in r['broadening_attempts']:
            t+=1; i+= x['match_count_before']==x['match_count_after']
    print(f'  {l:48s} {i}/{t}' + (f' = {100*i/t:.0f}%' if t else ''))

print('\n=== scoring_basis.dims_counted completeness (mismatch count) ===')
for l,d in zip(labs,DIRS):
    out=[]
    for c in CASES:
        r=load(d,c)
        if not r: continue
        dm=r['scoring_basis']['dims_counted']
        rr=[(s['score'],'|'.join(str(s.get(k,'n/a')) for k in dm)) for s in r['summary']]
        bad=sum(1 for i in range(len(rr)) for j in range(i+1,len(rr))
                if (rr[i][0]==rr[j][0])!=(rr[i][1]==rr[j][1]))
        out.append(f'{c[:2]}:{bad}')
    print(f'  {l:48s} ' + ' '.join(out))

print('\n=== new-dim value distributions in summary[] rows ===')
for l,d in zip(labs,DIRS):
    print(f'  --- {l} ---')
    for nd in NEWDIMS:
        vals={}
        for c in CASES:
            r=load(d,c)
            if not r: continue
            for s in r['summary']:
                if nd in s: vals[s[nd]]=vals.get(s[nd],0)+1
        print(f'    {nd:22s} {vals if vals else "(field absent)"}')

with open(os.path.join(DIRS[2],'version-comparison-3way.csv'),'w',newline='',encoding='utf-8-sig') as fh:
    w=csv.DictWriter(fh,fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
print(f'\nwrote {os.path.join(DIRS[2],"version-comparison-3way.csv")}')
