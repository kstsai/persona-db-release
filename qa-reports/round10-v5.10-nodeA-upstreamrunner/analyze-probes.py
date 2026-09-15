#!/usr/bin/env python3
"""探針分析：§6.8 重現性（同 query 3 次）+ §6.9 定向探針（逼出主套件未涵蓋的分支）。"""
import json
import pathlib

P = pathlib.Path("probe")


def load(name):
    f = P / f"{name}.body"
    if not f.exists():
        return None
    try:
        return json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        return {"_raw": f.read_text(encoding="utf-8")[:200]}


def meta(name, key):
    f = P / f"{name}.meta"
    if not f.exists():
        return ""
    for line in f.read_text(encoding="utf-8").split("\n"):
        if line.startswith(f"{key}="):
            return line.split("=", 1)[1]
    return ""


def summarize(tag, d):
    if not d or "total_matched" not in d:
        return (f"  {tag:22s} http={meta(tag,'http_code')} "
                f"{float(meta(tag,'time_total') or 0):7.1f}s  ← 非成功回應："
                f"{(d or {}).get('error', {}).get('code') if isinstance(d, dict) else '?'}")
    ba = d.get("broadening_attempts") or []
    af = d.get("applied_filters") or {}
    return (f"  {tag:22s} http=200 {float(meta(tag,'time_total')):7.1f}s  "
            f"matched={d.get('total_matched'):4d} ret={d.get('returned'):3d} "
            f"pe={str(d.get('pool_exhausted')):5s} loops={len(ba)} "
            f"no_op={sum(1 for b in ba if b.get('no_op'))} "
            f"ovs={sum(1 for b in ba if b.get('overshoot'))} "
            f"stop={d.get('broadening_stop_reason')!r}\n"
            f"    {'':22s} relaxed={d.get('relaxed_dims')} applied={json.dumps(af, ensure_ascii=False)}")


print("=" * 100)
print("§6.8 重現性探針 —— 同一 query、同一參數、重複 3 次（與主套件同一題）")
print("=" * 100)
print("\n[case06 醫美] 主套件基準：matched=16 ret=10 loops=3 no_op=1 stop='no_op_limit' relaxed=['income','age'] applied={'aesthetic_procedure':['有']}")
for i in (1, 2, 3):
    d = load(f"r06_aesthetic_{i}")
    print(summarize(f"r06_aesthetic_{i}", d))

print("\n[case09 業主] 主套件基準：matched=61 ret=10 loops=0 stop='target_reached' relaxed=[] applied={age, employment_status}")
for i in (1, 2, 3):
    d = load(f"r09_owner_{i}")
    print(summarize(f"r09_owner_{i}", d))

print()
print("=" * 100)
print("§6.9 定向探針 —— 逼出主套件未涵蓋的分支")
print("=" * 100)
print("\n主套件涵蓋：stop_reason 只有 {target_reached, no_op_limit}；pool_exhausted 全是 False；HTTP 只有 200/400")
print()
for t in ("t1_narrow_topk10", "t2_narrow_topk100", "t3_broad_topk3"):
    d = load(t)
    print(summarize(t, d))


def cmp_key(d):
    if not d or "total_matched" not in d:
        return None
    return (d.get("total_matched"), d.get("broadening_stop_reason"),
            tuple(sorted(d.get("relaxed_dims") or [])),
            json.dumps(d.get("applied_filters") or {}, sort_keys=True, ensure_ascii=False))


print()
print("=" * 100)
print("§6.8 判定：3 次是否可重現？")
print("=" * 100)
for base, keys in (("case06 醫美", ["r06_aesthetic_1", "r06_aesthetic_2", "r06_aesthetic_3"]),
                   ("case09 業主", ["r09_owner_1", "r09_owner_2", "r09_owner_3"])):
    ks = [cmp_key(load(k)) for k in keys]
    same = len(set(ks)) == 1
    print(f"\n  {base}: {'✅ 三次完全一致' if same else f'❌ 三次不一致（{len(set(ks))} 種結果）'}")
    for k, v in zip(keys, ks):
        print(f"    {k:20s} matched={v[0]:4d} stop={v[1]!r} relaxed={v[2]}")
        print(f"    {'':20s} applied={v[3]}")
