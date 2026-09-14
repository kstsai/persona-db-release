#!/usr/bin/env python3
"""延伸自證檢查（超出 upstream 斷言範圍的那些）。

upstream 的斷言只檢查「欄位在不在」「值合不合法」；這裡檢查「欄位之間自相矛盾嗎」：
  A. returned == len(summary)                    （upstream #43 只驗案例 06）
  B. pool_exhausted == (total_matched < top_k)   （upstream 未驗；且主套件全是 False）
  C. total_matched >= returned
  D. applied_filters ⊆ dims_counted              （upstream #35 只驗 4 案例）
  E. relaxed_dims ∩ applied_filters == ∅         （放寬掉的維度不該還在 filter 裡）
  F. loop 編號連續、match_count 單調不減
  G. no_op 旗標 == (after == before)             ★ upstream 完全沒驗：旗標是否與數字一致
  H. overshoot 旗標 == (after > 2×TARGET_MIN)    ★ 同上
  I. 每輪最多移除 1 維度（#25 cap）→ relaxed_dims 數 ≤ loop 數
"""
import json
import pathlib
import sys

TARGET_MIN = 20
TOP_K = {"01_kangshimei": 3, "02_tesla": 3, "03_fashion": 10, "04_role_fangzhong": 5,
         "05_role_banker": 5, "06_aesthetic": 10, "07_debt": 10, "08_boss": 10, "09_owner": 10}

RAW = pathlib.Path("raw")
fails = []
warns = []


def rec(ck, ok, msg):
    tag = "✅" if ok else "❌"
    print(f"  {tag} [{ck}] {msg}")
    if not ok:
        fails.append(f"[{ck}] {msg}")


def main():
    for cid, top_k in TOP_K.items():
        p = RAW / f"{cid}.body"
        if not p.exists():
            continue
        d = json.loads(p.read_text(encoding="utf-8"))
        rows = d.get("summary") or []
        ba = d.get("broadening_attempts") or []
        af = d.get("applied_filters") or {}
        sb = d.get("scoring_basis") or {}
        dc = sb.get("dims_counted") or []
        rd = d.get("relaxed_dims") or []
        tm = d.get("total_matched")
        ret = d.get("returned")
        pe = d.get("pool_exhausted")

        print(f"\n── {cid} (top_k={top_k}) ──")
        rec("A", ret == len(rows), f"returned={ret} len(summary)={len(rows)}")
        rec("B", pe == (tm < top_k),
            f"pool_exhausted={pe} vs (total_matched={tm} < top_k={top_k}) = {tm < top_k}")
        rec("C", tm >= ret, f"total_matched={tm} >= returned={ret}")
        missing = sorted(set(af) - set(dc))
        rec("D", not missing, f"applied_filters ⊆ dims_counted（漏列={missing or '無'}）")
        both = sorted(set(rd) & set(af))
        rec("E", not both, f"relaxed_dims ∩ applied_filters = {both or '∅'}（relaxed={rd}）")
        seq = [f"{b.get('match_count_before')}→{b.get('match_count_after')}" for b in ba]
        rec("F", all(b.get("loop") == i + 1 for i, b in enumerate(ba))
                 and all(b.get("match_count_after", 0) >= b.get("match_count_before", 0) for b in ba),
            f"{len(ba)} 輪：編號連續且樣本數不減 ({seq})")
        for b in ba:
            before, after = b.get("match_count_before", 0), b.get("match_count_after", 0)
            rec("G", bool(b.get("no_op")) == (after == before),
                f"loop{b.get('loop')} no_op={b.get('no_op')} 而 {before}→{after}"
                f"（應為 {after == before}）")
            rec("H", bool(b.get("overshoot")) == (after > 2 * TARGET_MIN),
                f"loop{b.get('loop')} overshoot={b.get('overshoot')} 而 after={after}"
                f"（>2×{TARGET_MIN}={2 * TARGET_MIN} → 應為 {after > 2 * TARGET_MIN}）")
        rec("I", len(rd) <= max(1, len(ba)) if ba else len(rd) == 0,
            f"relaxed_dims={len(rd)} 維 ≤ loop 數={len(ba)}（#25 每輪最多移除 1）")

    print()
    print("=" * 70)
    if fails:
        print(f"❌ 有 {len(fails)} 項不一致：")
        for f in fails:
            print(f"   {f}")
    else:
        print("✅ 全部延伸自證檢查通過（旗標與數字一致、內外欄位無矛盾）")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
