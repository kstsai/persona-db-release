#!/usr/bin/env python3
"""Compare two persona-db API evidence packages (e.g. v4.9.2 @ lzcdh5 vs v5.2 @ lzc-dh1-1)."""
import json, glob, os, sys, csv

A_DIR = sys.argv[1] if len(sys.argv) > 1 else '/Users/kstsai/Documents/personadb-lzcdh5-api-verify'
B_DIR = sys.argv[2] if len(sys.argv) > 2 else '/Users/kstsai/Documents/personadb-dh1-api-verify'
A_LAB = os.path.basename(A_DIR.rstrip('/'))
B_LAB = os.path.basename(B_DIR.rstrip('/'))

CASES = ['01_kangshimei','02_tesla','03_fashion','04_role_fangzhong',
         '05_role_banker','06_aesthetic','07_debt','08_boss']

def load(d, c):
    p = os.path.join(d, 'json', c + '.json')
    return json.load(open(p, encoding='utf-8')) if os.path.exists(p) else None

def meta(d, c):
    p = os.path.join(d, 'meta', c + '.meta')
    m = {}
    if os.path.exists(p):
        for line in open(p, encoding='utf-8'):
            if ':' in line:
                k, v = line.split(':', 1); m[k.strip()] = v.strip()
    return m

def ver(d):
    p = os.path.join(d, 'raw', '00_status.body')
    if not os.path.exists(p): return '(unknown)'
    for line in open(p, encoding='utf-8'):
        if 'Version' in line: return line.split()[-1]
    return '(unknown)'

print('=' * 100)
print(f'A = {A_LAB}  (Version {ver(A_DIR)})')
print(f'B = {B_LAB}  (Version {ver(B_DIR)})')
print('=' * 100)

# ---- dimension sets ----
def dimset(d):
    fs = glob.glob(os.path.join(d, 'supplemental', 'detail_*.json'))
    for f in fs:
        try:
            return set(json.load(open(f, encoding='utf-8'))['persona']['dimensions'].keys())
        except Exception:
            continue
    return set()
da, db = dimset(A_DIR), dimset(B_DIR)
print(f'\n=== persona schema dimensions ===')
print(f'  A ({A_LAB}): {len(da)} dims')
print(f'  B ({B_LAB}): {len(db)} dims')
print(f'  only in B (NEW)  : {sorted(db - da) or "(none)"}')
print(f'  only in A (GONE) : {sorted(da - db) or "(none)"}')

# ---- the 3 target dimensions ----
TARGETS = ['aesthetic_procedure', 'debt_status', 'employment_status']
print(f'\n=== target dimensions present in schema? ===')
for t in TARGETS:
    print(f'  {t:22s}  A={"YES" if t in da else "NO ":3s}  B={"YES" if t in db else "NO"}')

# ---- per-case ----
rows = []
print(f'\n=== per-case comparison ===')
hdr = f'{"case":20s} {"A_match":>8s} {"B_match":>8s} {"A_ids":>4s} {"B_ids":>4s} {"ovl":>4s} {"A_top":>8s} {"B_top":>8s}'
print(hdr); print('-' * len(hdr))
for c in CASES:
    a, b = load(A_DIR, c), load(B_DIR, c)
    if not a or not b:
        print(f'{c:20s}  (missing)'); continue
    ai, bi = a['persona_ids'], b['persona_ids']
    ovl = len(set(ai) & set(bi))
    print(f'{c:20s} {a["total_matched"]:8d} {b["total_matched"]:8d} {len(ai):4d} {len(bi):4d} {ovl:4d} '
          f'{a["summary"][0]["score"]:8.4f} {b["summary"][0]["score"]:8.4f}')
    rows.append(dict(case=c,
        A_version=ver(A_DIR), B_version=ver(B_DIR),
        A_total_matched=a['total_matched'], B_total_matched=b['total_matched'],
        A_ids=' '.join(map(str, ai)), B_ids=' '.join(map(str, bi)), overlap=ovl,
        A_top_score=a['summary'][0]['score'], B_top_score=b['summary'][0]['score'],
        A_domain=a['llm_analysis']['domain'], B_domain=b['llm_analysis']['domain'],
        A_applied_filter_keys='|'.join(sorted(a['applied_filters'])),
        B_applied_filter_keys='|'.join(sorted(b['applied_filters'])),
        A_scoring_dims='|'.join(a['scoring_basis']['dims_counted']),
        B_scoring_dims='|'.join(b['scoring_basis']['dims_counted']),
        A_relaxed='|'.join(a['relaxed_dims']), B_relaxed='|'.join(b['relaxed_dims']),
        A_broaden_loops=len(a['broadening_attempts']), B_broaden_loops=len(b['broadening_attempts']),
        A_sec=meta(A_DIR, c).get('time_total_sec', ''), B_sec=meta(B_DIR, c).get('time_total_sec', '')))

# ---- usage of the 3 target dims anywhere in B responses ----
print(f'\n=== do the 3 target dims actually get USED by the API? (string search in raw bodies) ===')
for lab, d in ((A_LAB, A_DIR), (B_LAB, B_DIR)):
    print(f'  --- {lab} ({ver(d)}) ---')
    for t in TARGETS:
        hits = []
        for c in CASES:
            p = os.path.join(d, 'raw', c + '.body')
            if os.path.exists(p) and t in open(p, encoding='utf-8', errors='replace').read():
                hits.append(c)
        print(f'    {t:22s} -> {hits if hits else "NOT FOUND in any response"}')

# ---- income saturation ----
print(f'\n=== income saturation (share of returned personas with income=">8萬") ===')
for lab, d in ((A_LAB, A_DIR), (B_LAB, B_DIR)):
    parts = []
    for c in CASES:
        r = load(d, c)
        if not r: continue
        n = len(r['summary']); hi = sum(1 for s in r['summary'] if s.get('income') == '>8萬')
        parts.append(f'{c.split("_")[0]}:{hi}/{n}')
    print(f'  {lab:32s} {"  ".join(parts)}')

# ---- sex filter behaviour on female-skewed categories (cases 01, 06) ----
print(f'\n=== sex filter on female-skewed categories ===')
for lab, d in ((A_LAB, A_DIR), (B_LAB, B_DIR)):
    for c in ('01_kangshimei', '06_aesthetic'):
        r = load(d, c)
        if not r: continue
        print(f'  {lab:32s} {c:18s} applied_filters.sex = {r["applied_filters"].get("sex", "NONE")}')

with open(os.path.join(B_DIR, 'version-comparison.csv'), 'w', newline='', encoding='utf-8-sig') as fh:
    if rows:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
        print(f'\nwrote {os.path.join(B_DIR, "version-comparison.csv")}')
