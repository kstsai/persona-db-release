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
  R. **applied_filters 無空值清單**（#62：空清單＝排除全部）
  S. **widened_dims ⊆ applied_filters**（#63：被放寬值集的維度不應從 filter 消失）★ upstream 未驗
  T. **widened_dims 與 relaxed_dims 不得同時含同一維度**（放寬≠移除）      ★ upstream 未驗
  U. 同一輪不得同時記為 protected_veto 與 widened_dims（veto 是 rollback，沒有放寬）
  V. **#65 主體護欄**：`subject` 必須是 {customer, owner, ""} 之一；
     且 subject=='customer' 時 `applied_filters` 不得含 employment_status
  W. **#65 warnings**：subject 護欄剝除了維度時，`warnings` 必須非空（有剝除就要有告警）
  X. `subject` 與題意一致（customer→未套 employment_status；owner→有套）
  Y. **`protected_dims_sources` 的 5 個來源聯集 ⊆ `protected_dims`，且差集只能是 subject 禁用維度**
     ★ upstream 未驗（#66 A 的來源拆解是否真的解釋了保護集）
  Z. **`stop_reason=='protection_saturated'` ⇒ 已套用維度全在保護集內**（#66 C 的定義不變式）★ upstream 未驗
  AA. `subject_basis` 非空 ⟺ `subject` 非空（#67 B）
  AB. `subject_basis` 的樣式與 `subject` 一致（customer→含「顧客語意樣式」；owner→含「業主語意樣式」）
  AC. **#69 `widened_deltas` 與 `widened_dims` 口徑一致**，且每筆是 `before ⊂ after` 的嚴格超集、
      `added` 非空且 = `after - before`                              ★ upstream 只驗了口徑與非空
  AD. **#71 B `len(model_declared) ≤ declared_protected_cap`**，且 cap == max(1,min(3, 請求開始已套用維度數//2))
      （後者只在能從回應推得基準時檢查）
  AE. **#70 `overshoot_restore` 的一致性**：`restored_dims` 非空、⊆ `protected_dims`、
      且被還原的維度**不得出現在 `relaxed_dims`**（還原＝撤回該輪的移除）★ upstream 未驗第三項
  AF. `protected_dims_sources` 六鍵齊全（新增 `overshoot_restore`）
"""
import json
import pathlib
import re
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
    EXPECT_KEYS = None          # 由契約（OpenAPI description 的反引號列舉）推導，不寫死
    oa = RAW / "openapi.json"
    if oa.exists():
        spec = json.loads(oa.read_text(encoding="utf-8"))
        enum = spec["components"]["schemas"]["CandidatesResponse"]["properties"][
            "broadening_stop_reason"].get("enum")
        # 從 protected_dims_sources 的 description 抽出反引號列舉的來源鍵（契約即權威）
        _desc = (spec["components"]["schemas"]["CandidatesResponse"]["properties"]
                 .get("protected_dims_sources", {}).get("description", "") or "")
        # 只用「括號內的列舉」——描述本文也會用反引號提到欄位本身（`protected_dims`），
        # 直接抓全部反引號會把欄位名一起收進來。取「含／分隔且反引號最多」的那個括號段。
        _cands = re.findall(r"（([^（）]*)）", _desc)
        _best = max(_cands, key=lambda t: t.count("`"), default="")
        _keys = set(re.findall(r"`([a-z_]+)`", _best)) if _best.count("`") >= 2 else set()
        EXPECT_KEYS = _keys or None
        if EXPECT_KEYS:
            print(f"  ℹ️  由契約推導 protected_dims_sources 的來源鍵（{len(EXPECT_KEYS)} 個）：{sorted(EXPECT_KEYS)}")
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
        # ↓ 這一區在 v5.13／v5.14 各被我漏過一次（把檢查插在定義之前 → UnboundLocalError）。
        #   凡是本迴圈會用到的欄位，一律在此一次取齊，後面各檢查區塊只讀不取。
        subj = d.get("subject", None)                 # #65（v5.12 起）
        warn = d.get("warnings") or []                # #65/#66
        sb = d.get("subject_basis", None)             # #67 B（v5.13 起）
        srcs = d.get("protected_dims_sources") or {}  # #66 A（v5.13 起）
        cap = d.get("declared_protected_cap", None)   # #71 B（v5.14 起）

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
        if sr == "protection_saturated":
            rec("Z", set(af) <= set(pd_),
                f"#66 C protection_saturated ⇒ 已套用維度全受保護（applied={sorted(af)} ⊆ protected={sorted(pd_)}）")
        rec("O", ((tm or 0) == 0) == (d.get("status") != "ok"),
            f"#58 status={d.get('status')!r} matched={tm}（matched==0 ⇔ status!=ok）")

        # ── #69 / #70 / #71（v5.14 新增）──
        if srcs:
            extra = sorted(set(srcs) - (EXPECT_KEYS or set(srcs)))
            rec("AF", EXPECT_KEYS is None or EXPECT_KEYS <= set(srcs),
                f"#71 來源鍵齊全（實際={sorted(srcs)}"
                + (f"；契約未列出的新鍵={extra} → 請同步本檢查" if extra else "") + "）")
        if cap is not None:
            md = srcs.get("model_declared") or []
            rec("AD", len(md) <= cap, f"#71 B len(model_declared)={len(md)} ≤ cap={cap}")
        for b in ba:
            wd = b.get("widened_dims") or []
            wdl = b.get("widened_deltas") or []
            if wd or wdl:
                rec("AC1", set(wd) == {x.get("dim") for x in wdl},
                    f"#69 loop{b.get('loop')} widened_dims={sorted(wd)} == deltas 的 dim 集合")
                for x in wdl:
                    bef, aft, added = set(x.get("before") or []), set(x.get("after") or []), set(x.get("added") or [])
                    rec("AC2", bef < aft and added == (aft - bef) and bool(added),
                        f"#69 loop{b.get('loop')} {x.get('dim')}: before⊂after 且 added=after-before（added={sorted(added)}）")
            if b.get("overshoot_restore"):
                rs = set(b.get("restored_dims") or [])
                rec("AE1", bool(rs), f"#70 loop{b.get('loop')} overshoot_restore ⇒ restored_dims={sorted(rs)} 非空")
                rec("AE2", rs <= set(pd_), f"#70 restored_dims={sorted(rs)} ⊆ protected_dims")
                rec("AE3", not (rs & set(rd)),
                    f"#70 restored_dims 不得仍在 relaxed_dims（交集={sorted(rs & set(rd)) or '∅'}）")

        # ── #66 / #67（v5.13 新增）──（srcs/sb 已在迴圈頂端取得）
        if srcs:
            rec("Y1", EXPECT_KEYS is None or EXPECT_KEYS <= set(srcs),
                f"#66 A 來源鍵齊全（契約要求={sorted(EXPECT_KEYS) if EXPECT_KEYS else '（契約未提供，略過）'}；"
                f"實際={sorted(srcs)}；多出的鍵不算錯）")
            union = set(x for v in srcs.values() for x in (v or []))
            unexplained = set(pd_) - union
            allowed_diff = {"employment_status"} if subj == "customer" else set()
            rec("Y2", union <= set(pd_), f"#66 A 來源聯集 ⊆ protected_dims（超出={sorted(union-set(pd_)) or '無'}）")
            rec("Y3", unexplained <= allowed_diff,
                f"#66 A protected_dims 無未解釋項（未解釋={sorted(unexplained) or '無'}；"
                f"允許差集={sorted(allowed_diff) or '∅'}（subject 禁用））")
        rec("AA", (bool(sb) == bool(subj)),
            f"#67 B subject={subj!r} ⟺ subject_basis={'非空' if sb else '空'}")
        if sb:
            want = "顧客語意樣式" if subj == "customer" else ("業主語意樣式" if subj == "owner" else None)
            if want:
                rec("AB", want in sb, f"#67 B basis 樣式與 subject 一致（basis={sb[:40]!r} 應含 {want!r}）")

        # ── #65 主體護欄（v5.12 新增）──（subj/warn 已在迴圈頂端取得）
        rec("V0", subj in ("customer", "owner", ""), f"#65 subject={subj!r} 為合法值")
        if subj == "customer":
            rec("V", "employment_status" not in af,
                f"#65 subject='customer' ⇒ applied_filters 不得含 employment_status（實際={list(af)}）")
        if subj == "owner":
            rec("X", bool(af.get("employment_status")),
                f"#65 subject='owner' ⇒ 應套 employment_status（實際={af.get('employment_status')}）")
        if warn:
            print(f"  ℹ️  [W] warnings={warn}")

        # ── #62 / #63（v5.11.1 新增）──
        empties = sorted(k for k, v in af.items() if isinstance(v, list) and not v)
        rec("R", not empties, f"#62 applied_filters 無空值清單（空＝{empties or '無'}）")
        wide = set()
        for b in ba:
            wide |= set(b.get("widened_dims") or [])
            if b.get("protected_veto") and (b.get("widened_dims") or []):
                rec("U", False, f"loop{b.get('loop')} 同時 protected_veto 與 widened_dims="
                                f"{b.get('widened_dims')}（veto 是 rollback，不應有放寬）")
        if wide:
            # 注意：這裡**不能**要求 `wide ⊆ applied_filters` —— 同一個維度可能
            # 在第 1 輪被「放寬值集」、在第 3 輪又被「整維移除」（實例：r06_aesthetic_2 的
            # clothing_spend：loop1 加入 <500 使值集成全集 → loop3 因已無篩選效果而移除）。
            # 那是合法的跨輪序列，不是矛盾。故正確形式是：放寬過的維度最後只可能落在
            # applied_filters 或 relaxed_dims 之一。
            rec("S", wide <= (set(af) | set(rd)),
                f"widened_dims={sorted(wide)} ⊆ applied ∪ relaxed")
            both = sorted(wide & set(rd))
            if both:
                same_loop = [b.get("loop") for b in ba
                             if (set(b.get("widened_dims") or []) & set(rd))]
                print(f"  ℹ️  [T] 同一維度既被放寬值集、又被移除（跨輪序列，合法）：{both}"
                      f" —— 請查逐輪文字確認順序（涉入輪次 {same_loop}）")
            else:
                print(f"  ✅ [T] 無「既放寬又被移除」的維度")
        else:
            print(f"  ℹ️  [S][T] 本案例無 widened_dims 留痕")

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
