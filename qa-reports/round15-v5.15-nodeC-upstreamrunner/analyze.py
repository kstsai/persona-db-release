#!/usr/bin/env python3
"""round9（v5.8 / NODE-A）回應分析：§6.1–§6.5 的機械部分。

不做跨版本比對（skill v2.0.0）。所有輸出都可由 raw/*.body 複驗。
用法：python3 analyze.py            （讀 raw/，寫出報告片段）
"""
import collections
import glob
import json
import os
import pathlib
import sys

RAW = pathlib.Path("raw")
CASE_ORDER = ["00_status", "01_kangshimei", "02_tesla", "03_fashion", "04_role_fangzhong",
              "05_role_banker", "06_aesthetic", "07_debt", "08_boss", "09_owner"]

# summary 曝露的維度（PersonaSummary 24 欄）→ 可用於 §6.2 自證
VERIFIABLE = ["sex", "region", "education", "marriage", "hobby", "politics", "media_diet",
              "aesthetic_procedure", "debt_status", "employment_status", "housing_cost",
              "commute_mode", "city_price_tier", "housing_burden"]


def load(cid):
    if cid == "00_status":
        return None          # /personadb/status 是 text/plain 端點（791 bytes），非 JSON 契約
    p = RAW / f"{cid}.body"
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"  ⚠️  {cid}: 無法解析（{e}）")
        return None


def hr(t):
    print()
    print("=" * 78)
    print(t)
    print("=" * 78)


def main():
    cases = {}
    for cid in CASE_ORDER:
        d = load(cid)
        if d is not None:
            cases[cid] = d

    ok_cases = [c for c, d in cases.items() if "total_matched" in d]
    print(f"載入 {len(cases)} 個案例，其中候選查詢 {len(ok_cases)} 個：{ok_cases}")

    # ── 總表 ───────────────────────────────────────────────────────────
    hr("§2 執行摘要（機械抽出）")
    hdr = f"{'case':20s} {'matched':>8s} {'ret':>4s} {'sum':>4s} {'pe':>5s} {'loops':>6s} {'noop':>5s} {'ovs':>4s}  stop_reason        protected_dims"
    print(hdr)
    print("-" * len(hdr))
    for cid in ok_cases:
        d = cases[cid]
        ba = d.get("broadening_attempts") or []
        print(f"{cid:20s} {d.get('total_matched', -1):8d} {d.get('returned', -1):4d} "
              f"{len(d.get('summary') or []):4d} {str(d.get('pool_exhausted')):>5s} {len(ba):6d} "
              f"{sum(1 for b in ba if b.get('no_op')):5d} {sum(1 for b in ba if b.get('overshoot')):4d}  "
              f"{str(d.get('broadening_stop_reason')):18s} {d.get('protected_dims')}")

    # ── §6.1 語意正確性：把 LLM 自述與實際 filter 並列 ─────────────────
    hr("§6.1 語意正確性 —— applied_filters vs LLM reasoning（人工判讀用）")
    for cid in ok_cases:
        d = cases[cid]
        af = d.get("applied_filters") or {}
        la = d.get("llm_analysis") or {}
        print(f"\n── {cid} ──")
        print(f"  domain      : {la.get('domain')!r}")
        print(f"  applied     : {json.dumps(af, ensure_ascii=False)}")
        print(f"  relaxed_dims: {d.get('relaxed_dims')}")
        r = (la.get("reasoning") or "").strip().replace("\n", " ")
        print(f"  reasoning   : {r[:600]}")

    # ── §6.2 自證性 ───────────────────────────────────────────────────
    hr("§6.2 自證性 —— 每個 applied_filter 都必須在回傳列中被滿足")
    gaps = {}
    for cid in ok_cases:
        d = cases[cid]
        af = d.get("applied_filters") or {}
        rows = d.get("summary") or []
        if not rows:
            print(f"  {cid:20s} 無 summary → 無法自證")
            continue
        for k, want in af.items():
            if k not in VERIFIABLE:
                gaps.setdefault(k, []).append(f"{cid}:不在 summary 曝露欄位")
                continue
            got = collections.Counter(
                (tuple(sorted(str(x) for x in (r.get(k) or []))) if isinstance(r.get(k), list)
                 else str(r.get(k))) for r in rows)
            want_s = [str(x) for x in (want if isinstance(want, list) else [want])]
            if k == "hobby":
                oks = all(set(want_s) & set(r.get("hobby") or []) for r in rows)
            else:
                oks = all(g in set(want_s) for g in got)
            print(f"  {'✓' if oks else '✗'} {cid:20s} {k}={want_s} → {dict(got)}")
            if not oks:
                gaps.setdefault(k, []).append(f"{cid}:回傳含值域外的值")
    print("\n  §6.2 可驗證性缺口（applied/dims_counted 有、但 summary 沒有 → 無法從回應驗證）：")
    dc_all = set()
    for cid in ok_cases:
        dc_all |= set((cases[cid].get("scoring_basis") or {}).get("dims_counted") or [])
    dc_all |= set()
    for cid in ok_cases:
        dc_all |= set((cases[cid].get("applied_filters") or {}).keys())
    row_keys = set()
    for cid in ok_cases:
        for r in (cases[cid].get("summary") or [])[:1]:
            row_keys |= set(r.keys())
    missing = sorted(dc_all - row_keys)
    print(f"    dims 出現在 filter/dims_counted 但不在 summary：{missing if missing else '（無）'}")
    print(f"    summary 曝露欄位（{len(row_keys)}）：{sorted(row_keys)}")

    # ── §6.3 計分宣告誠實性 ───────────────────────────────────────────
    hr("§6.3 計分宣告誠實性 —— (a) 同分不同向量=碰撞 vs (b) 同向量不同分=低報")
    print(f"  {'case':20s} {'rows':>4s} {'同分對':>7s} {'(a)碰撞':>8s} {'(b)低報':>8s}  判定")
    tot_a = tot_b = tot_probative = 0
    for cid in ok_cases:
        d = cases[cid]
        rows = d.get("summary") or []
        sb = d.get("scoring_basis") or {}
        dm = sb.get("dims_counted")
        if not rows or not dm:
            print(f"  {cid:20s} {len(rows):4d} {'—':>7s} {'—':>8s} {'—':>8s}  空轉（無 scoring_basis.dims_counted）")
            continue
        vecs = [tuple(str(r.get(k, "n/a")) for k in dm) for r in rows]
        scores = [r.get("score") for r in rows]
        a = b = npair = 0
        for i in range(len(rows)):
            for j in range(i + 1, len(rows)):
                same_s = scores[i] == scores[j]
                same_v = vecs[i] == vecs[j]
                if same_s or same_v:
                    npair += 1
                if same_s and not same_v:
                    a += 1
                if same_v and not same_s:
                    b += 1
        tot_a += a
        tot_b += b
        tot_probative += npair
        verdict = "空轉（無同分/同向量對）" if npair == 0 else ("✅ 無低報" if b == 0 else f"❌ 低報 {b} 對")
        print(f"  {cid:20s} {len(rows):4d} {npair:7d} {a:8d} {b:8d}  {verdict}")
    print(f"\n  合計：具檢定效力的配對 {tot_probative}；(a) 碰撞 {tot_a}；(b) 低報 {tot_b}")
    print(f"  dims_counted 用於向量（各案例宣告不同，逐案取用）")

    # ── §6.4 broadening ───────────────────────────────────────────────
    hr("§6.4 broadening 行為 —— no_op / overshoot / 挑錯維度")
    for cid in ok_cases:
        d = cases[cid]
        ba = d.get("broadening_attempts") or []
        if not ba:
            print(f"  {cid:20s} 未進入放寬迴圈（stop_reason={d.get('broadening_stop_reason')!r}）")
            continue
        print(f"  {cid:20s} stop_reason={d.get('broadening_stop_reason')!r} "
              f"no_op={sum(1 for b in ba if b.get('no_op'))}/{len(ba)}")
        for b in ba:
            veto = ""
            if b.get("protected_veto"):
                veto = f" ⛔protected_veto vetoed={b.get('vetoed_dims')}"
            if b.get("widened_dims"):
                veto += f" ↔widened={b.get('widened_dims')}"
            print(f"      loop{b.get('loop')}: {b.get('match_count_before')}→{b.get('match_count_after')} "
                  f"no_op={b.get('no_op')} overshoot={b.get('overshoot')} "
                  f"changed={b.get('filters_changed')}{veto} change={str(b.get('change'))[:150]!r}")

    # ── §6.5 頭部集中 ─────────────────────────────────────────────────
    hr("§6.5 頭部集中 —— 同一批 persona 是否跨題重複")
    seen = collections.defaultdict(list)
    for cid in ok_cases:
        for r in (cases[cid].get("summary") or []):
            seen[r.get("id")].append(cid)
    dup = {k: v for k, v in seen.items() if len(v) > 1}
    print(f"  出現在 ≥2 個案例的 persona：{len(dup)} / {len(seen)}")
    for k, v in sorted(dup.items(), key=lambda kv: -len(kv[1]))[:15]:
        print(f"    {k}: {len(v)} 次 → {v}")
    names = collections.Counter(r.get("name") for cid in ok_cases
                                for r in (cases[cid].get("summary") or []))
    print(f"\n  重複出現的名字 top5：{names.most_common(5)}")

    # ── §6.6 核心維度保護（v5.9+ 的 #57/#59）─────────────────────────
    hr("§6.6 核心維度保護 —— protected_dims / protected_veto（upstream 的 #57/#59）")
    tot_veto = 0
    for cid in ok_cases:
        d = cases[cid]
        pd_ = d.get("protected_dims") or []
        rd = d.get("relaxed_dims") or []
        ba = d.get("broadening_attempts") or []
        viol = sorted(set(pd_) & set(rd))
        vetos = [b for b in ba if b.get("protected_veto")]
        tot_veto += len(vetos)
        print(f"  {cid:20s} protected={pd_}")
        print(f"  {'':20s}   relaxed={rd}  stop={d.get('broadening_stop_reason')!r}  "
              f"{'❌ 保護維度被放寬：' + str(viol) if viol else '✅ 保護集未被放寬'}")
        wide = sorted({d for b in ba for d in (b.get("widened_dims") or [])})
        if wide:
            print(f"  {'':20s}   ↔ widened_dims（值集放寬留痕 #63）: {wide}")
        for b in vetos:
            print(f"  {'':20s}   ⛔ loop{b.get('loop')} vetoed={b.get('vetoed_dims')} "
                  f"（rollback: no_op={b.get('no_op')} changed={b.get('filters_changed')} "
                  f"{b.get('match_count_before')}→{b.get('match_count_after')}）")
    print(f"\n  全輪 veto 次數：{tot_veto}")
    print(f"  未受任何保護的案例：{[c for c in ok_cases if not (cases[c].get('protected_dims') or [])] or '（無）'}")

    hr("done")


if __name__ == "__main__":
    sys.exit(main())
