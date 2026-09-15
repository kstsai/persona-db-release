#!/usr/bin/env python3
"""延伸自證檢查（超出 upstream 斷言範圍的那些）—— round10 v5.10

沿用第九輪的 A–I 檢查，並針對 v5.9/v5.10 的新機制（#57 核心維度保護 / #58 status / #59 enum）
加上 upstream **沒有**驗的不變式：

  A. returned == len(summary)                       （upstream #43 只驗案例 06）
  B. pool_exhausted == (total_matched < top_k)      （upstream 未驗）
  C. total_matched >= returned
  D. applied_filters ⊆ dims_counted                 （upstream #35 只驗 4 案例）
  E. relaxed_dims ∩ applied_filters == ∅
  F. loop 編號連續、match_count 單調不減
  G. no_op 旗標 == (after == before)                ★ upstream 未驗
  H. overshoot 旗標 == (after > 2×TARGET_MIN)       ★ upstream 未驗
  I. 每輪最多移除 1 維度（#25 cap）
  J. protected_dims ∩ relaxed_dims == ∅（#57 核心不變式；獨立重算）
  K. **vetoed_dims ⊆ protected_dims**               ★ upstream 未驗
  L. protected_veto 的 attempt 必須有非空 vetoed_dims ★ upstream 只做條件式檢查
  M. **veto 必須是一次 rollback**：no_op=True、filters_changed=False、
     match_count_after == match_count_before                              ★ upstream 未驗
  N. stop_reason=='protected_veto' 必須有憑據（硬 veto 或被動拒絕）
  O. #58 status 語意：matched==0 ⇔ status != 'ok'
  P. 回應出的 stop_reason 皆在 OpenAPI enum 內（#59）
"""
import json
import pathlib
import sys

TARGET_MIN = 20
TOP_K = {"01_kangshimei": 3, "02_tesla": 3, "03_fashion": 10, "04_role_fangzhong": 5,
         "05_role_banker": 5, "06_aesthetic": 10, "07_debt": 10, "08_boss": 10, "09_owner": 10}
RAW = pathlib.Path("raw")
fails = []


def rec(ck, ok, msg):
    print(f"  {'✅' if ok else '❌'} [{ck}] {msg}")
    if not ok:
        fails.append(f"[{ck}] {msg}")


def main():
    enum = None
    oa = RAW / "openapi.json"
    if oa.exists():
        spec = json.loads(oa.read_text(encoding="utf-8"))
        enum = spec["components"]["schemas"]["CandidatesResponse"]["properties"][
            "broadening_stop_reason"].get("enum")
    sr_seen = set()

    for cid, top_k in TOP_K.items():
        p = RAW / f"{cid}.body"
        if not p.exists():
            continue
        d = json.loads(p.read_text(encoding="utf-8"))
        rows = d.get("summary") or []
        ba = d.get("broadening_attempts") or []
        af = d.get("applied_filters") or {}
        dc = (d.get("scoring_basis") or {}).get("dims_counted") or []
        rd = d.get("relaxed_dims") or []
        pd_ = d.get("protected_dims") or []
        tm, ret, pe = d.get("total_matched"), d.get("returned"), d.get("pool_exhausted")
        sr = d.get("broadening_stop_reason")
        sr_seen.add(sr)

        print(f"\n── {cid} (top_k={top_k}) ──  protected={pd_}")
        rec("A", ret == len(rows), f"returned={ret} len(summary)={len(rows)}")
        rec("B", pe == (tm < top_k), f"pool_exhausted={pe} vs (matched={tm} < top_k={top_k})={tm < top_k}")
        rec("C", tm >= ret, f"total_matched={tm} >= returned={ret}")
        rec("D", not (set(af) - set(dc)), f"applied_filters ⊆ dims_counted（漏={sorted(set(af) - set(dc)) or '無'}）")
        rec("E", not (set(rd) & set(af)), f"relaxed ∩ applied = {sorted(set(rd) & set(af)) or '∅'}")
        seq = [f"{b.get('match_count_before')}→{b.get('match_count_after')}" for b in ba]
        rec("F", all(b.get("loop") == i + 1 for i, b in enumerate(ba))
                 and all(b.get("match_count_after", 0) >= b.get("match_count_before", 0) for b in ba),
            f"{len(ba)} 輪：編號連續且不減 ({seq})")
        for b in ba:
            be, aft = b.get("match_count_before", 0), b.get("match_count_after", 0)
            rec("G", bool(b.get("no_op")) == (aft == be),
                f"loop{b.get('loop')} no_op={b.get('no_op')} 而 {be}→{aft}")
            rec("H", bool(b.get("overshoot")) == (aft > 2 * TARGET_MIN),
                f"loop{b.get('loop')} overshoot={b.get('overshoot')} 而 after={aft}")
            if b.get("protected_veto"):
                vd = b.get("vetoed_dims") or []
                rec("L", bool(vd), f"loop{b.get('loop')} protected_veto=True ⇒ vetoed_dims={vd}（須非空）")
                rec("K", set(vd) <= set(pd_), f"loop{b.get('loop')} vetoed_dims={vd} ⊆ protected_dims={pd_}")
                rec("M", b.get("no_op") is True and b.get("filters_changed") is False and aft == be,
                    f"loop{b.get('loop')} veto 是 rollback（no_op={b.get('no_op')} "
                    f"filters_changed={b.get('filters_changed')} {be}→{aft}）")
        rec("I", len(rd) <= max(1, len(ba)) if ba else len(rd) == 0,
            f"relaxed={len(rd)} 維 ≤ loop={len(ba)}（#25）")
        rec("J", not (set(pd_) & set(rd)),
            f"protected ∩ relaxed = {sorted(set(pd_) & set(rd)) or '∅'}（#57 核心不變式）")
        if sr == "protected_veto":
            p1 = any(b.get("protected_veto") and b.get("vetoed_dims") for b in ba)
            p2 = bool(ba) and bool(ba[-1].get("no_op")) and not ba[-1].get("filters_changed")
            rec("N", p1 or p2, f"stop_reason=protected_veto 有憑據（硬veto={p1} 被動拒絕={p2}）")
        rec("O", ((tm or 0) == 0) == (d.get("status") != "ok"),
            f"#58 status={d.get('status')!r} matched={tm}（matched==0 ⇔ status!=ok）")

    if enum is not None:
        bad = sorted(v for v in sr_seen if v not in enum)
        rec("P", not bad, f"回應出的 stop_reason 皆在 OpenAPI enum 內（非 enum={bad or '無'}）；"
                          f"本輪出現={sorted(sr_seen)}")
        unreach = [v for v in ("", "budget_limit") if v in enum]
        print(f"  ℹ️  [Q] enum 仍宣告 {unreach} —— 依部署碼常數/分類順序，這兩個值不可達"
              f"（源碼層推論，非回應可觀測）")

    print()
    print("=" * 72)
    if fails:
        print(f"❌ 有 {len(fails)} 項不一致：")
        for f in fails:
            print(f"   {f}")
    else:
        print("✅ 全部延伸自證檢查通過（含 #57 核心維度保護的四項額外不變式 K/L/M/N）")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
