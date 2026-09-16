# round13 — Persona DB v5.13 / NODE-A / upstream runner

**單版本 API 驗證與回應分析**（依 `api-version-sweep` skill **v2.5.0**）。
**本輪不做跨版本比對** —— 只分析 v5.13 這個版本的回應。

- 主報告：**[ANALYSIS.md](ANALYSIS.md)** ← 先讀這個
- 執行時間：主套件 2026-09-16 **00:45:48Z → 00:59:07Z**（13 分 19 秒）；探針 **00:59:39Z → 01:2x**
- 結果總覽：主套件 **10/10 HTTP 200**、斷言 **57 ✅ / 0 ⚠️ / 0 ❌ / 1 ℹ️**；探針 **10/10 HTTP 200**

---

## 探針題目原文（供查核；skill v2.4.0 規定必須寫出原文）

| 探針 | 題目原文 | 為什麼要這樣設計 |
|:--|:--|:--|
| **`t1`** | `questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主` | **超出 schema、必然不可滿足**：Persona DB 的 24 個欄位沒有「遊艇」也沒有「私人飛機」，所以必然逼出 `matched=0` / `pool_exhausted=true`（主套件碰不到的分支）。自第九輪起重複作為**回歸哨兵** |
| **`t2`** | `questions=想找做過醫美療程的45歲單身女性` | **收窄到讓保護集飽和**：醫美題的保護集通常只有 `aesthetic_procedure`；把查詢收窄同時減少模型想套的維度，就能讓「已套用維度 ⊆ 保護集」成立 → 逼出 v5.13 新增的 `protection_saturated`（#66 C） |
| `t3` | `questions=TESLA的目標客戶`（`top_k=20`） | 放大主套件案例 2 的 `top_k`，驗 #61 的 `commute_mode` 保護 |
| `t4` | `questions=房貸優惠方案` + `role=銀行業者`（`top_k=20`） | 放大主套件案例 5 的 `top_k`，誘發值集放寬與 veto |

> ⚠️ **兩者都是探針，不是業務案例，也不是產品缺陷主張**（「夜市小吃攤的老闆不會真的想找擁有遊艇的人」）。
> **限制**：人造查詢驗的是**分支機制**，不是真實流量 —— `matched=0` 在真實使用者身上可能由不同機制產生。
> `r08`／`r06` 用的是主套件 case08／case06 的**完全相同參數**（`questions`／`role`／`top_k`／`opMode` 順序一致）。

---

## 目錄地圖

| 路徑 | 內容 |
|:--|:--|
| `ANALYSIS.md` | 主報告（§0 環境 / §1 儀器 / §2 執行摘要 / §3 斷言 / §4 回應分析 / §5 限制 / §6 結論 / §7 改動聲明） |
| `raw/` `headers/` `meta/` `json/` | 逐位元組 body、headers、量測欄位＋實際 curl 指令、body 副本 |
| `meta/original-upstream-3d7b1de2.sh` | **原版腳本逐字留存**（sha256 `3d7b1de2…`，529 行） |
| `run-test.sh` | 本輪 runner（sha256 `928bd09cfdb7408b…`，519 行；**執行前即記錄**） |
| `meta/script-provenance.txt` | 環境、部署保真度、儀器 sha、忠實度證明、跨輪防護 |
| `meta/make-runner.py` | 由原版機械組出 runner；**`OUT` 自我定位**（`dirname $0`） |
| `meta/verify-instrument.py` | 儀器忠實度證明（可指定要比對的 runner 檔） |
| `meta/test-runner-harness.sh` | runner/probe **執行時行為**單元測試（stub `curl`、11 項） |
| `extra/assertions.txt` | 斷言輸出（57 ✅ / 0 ⚠️ / 0 ❌） |
| `extra/server-log-window.txt` | 主套件窗口的**伺服器端** log（含 `Subject gate`、overshoot、veto 告警） |
| `probe/` | §6.8 重現性（case08／case06 各 3 次）+ §6.9 定向（t1–t4）+ `run-probe.sh` |
| `analyze.py` / `verify-extended.py`（A–AB）/ `make-summaries.py` | 分析與檢查腳本 |

---

## 複驗指令（每一條都已實跑過）

### 1. 儀器忠實度
```bash
python3 meta/verify-instrument.py
```

### 2. runner/probe 的執行時行為（不連網）
```bash
bash meta/test-runner-harness.sh
```

### 3. §6.1–§6.6 回應分析（含 subject_basis / protected_dims_sources / warnings）
```bash
python3 analyze.py
```

### 4. 延伸自證檢查（A–AB；含 upstream 未驗的 Y/Z/AA/AB）
```bash
python3 verify-extended.py
```

### 5. §6.8 重現性：case08 的主體護欄（含新增的判定依據）
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
print("case08（小吃攤老闆的目標客群 = 顧客語意）主套件 + 3 次重跑：")
for tag, p in [("主套件","raw/08_boss.body")] + [(f"探針 r{i}", f"probe/r08_boss_{i}.body") for i in (1,2,3)]:
    d = L(p)
    print(f"  {tag:8s} subject={str(d.get('subject')):9s} matched={d['total_matched']:4d} "
          f"emp={(d['applied_filters'] or {}).get('employment_status')}")
    print(f"  {'':8s} basis={d.get('subject_basis')!r}")
PY
```

### 6. §6.8 重現性 + §6.9：`protection_saturated`（v5.13 新分支）
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
for tag, p in [("主套件","raw/06_aesthetic.body")] + [(f"r{i}", f"probe/r06_aesthetic_{i}.body") for i in (1,2,3)] + \
              [("t2(設計探針)","probe/t2_aesthetic_narrow.body")]:
    d = L(p)
    af, pd_ = set(d["applied_filters"] or {}), set(d["protected_dims"] or [])
    sat = d["broadening_stop_reason"] == "protection_saturated"
    print(f"  {tag:14s} matched={d['total_matched']:3d} stop={d['broadening_stop_reason']!r:24s} "
          f"protected={sorted(pd_)}" + ("  ← 飽和：applied ⊆ protected ✅" if sat and af <= pd_ else ""))
PY
```

### 7. §6.9 定向探針全覽（含 t1 的 veto）
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
for t in ("t1_narrow_topk10","t2_aesthetic_narrow","t3_tesla_topk20","t4_banker_topk20"):
    d = L(f"probe/{t}.body")
    print(f"{t:22s} matched={d['total_matched']:3d} status={d['status']!r} pe={d['pool_exhausted']} "
          f"stop={d['broadening_stop_reason']!r}")
    for b in d["broadening_attempts"]:
        if b.get("protected_veto"):
            print(f"    ⛔ veto loop{b['loop']}: vetoed={b['vetoed_dims']} "
                  f"{b['match_count_before']}→{b['match_count_after']}")
PY
```

### 8. veto 斷言的涵蓋問題（本輪的 ⚠️）
```bash
# 斷言說「本輪未觸發 veto」—— 但 05 確實觸發了：
grep -n "veto" extra/assertions.txt
python3 -c "
import json,pathlib
d=json.loads(pathlib.Path('raw/05_role_banker.body').read_text(encoding='utf-8'))
print('  05_role_banker stop=', d['broadening_stop_reason'], ' protected=', d['protected_dims'])
for b in d['broadening_attempts']:
    print('   loop%d veto=%s vetoed=%s no_op=%s changed=%s %d→%d' % (b['loop'], b.get('protected_veto'), b.get('vetoed_dims'), b['no_op'], b['filters_changed'], b['match_count_before'], b['match_count_after']))
"
# 而 #57 的掃描集只有 4 個案例：
grep -n '_cases = ' ../round13-v5.13-nodeA-upstreamrunner/meta/original-upstream-3d7b1de2.sh 2>/dev/null || \
  grep -n '_cases = ' meta/original-upstream-3d7b1de2.sh
```

### 9. 伺服器端交叉核對
```bash
grep "Subject gate" extra/server-log-window.txt          # 主體判定（含 basis）
grep -E "overshoot|受保護維度被變更|protection_saturated|已達上限" extra/server-log-window.txt
printf "Protected dims=%s  錯誤/例外=%s\n" "$(grep -c 'Protected dims' extra/server-log-window.txt)" "$(grep -cE 'Traceback|Exception|ERROR' extra/server-log-window.txt)"
```

---

## 一句話總結

**v5.13 把第十二輪的兩條建議（S/T 的形式＋涵蓋、斷言要報掃描案例數）都修好了**，
並新增了主體判定依據（`subject_basis`，覆蓋從 2/9 擴到 **8/9**）、保護集來源拆解（`protected_dims_sources`）
與保護集上限（`#66 A`）—— 本輪驗證它們都有效，而且 **`warnings` 從「從未被行使」變成有內容**（6 筆）。

**新增的 `protection_saturated` 我用設計過的定向探針逼出來了**（`t2` 在 `loop 1`，覆蓋 4/4），
並以定義不變式確認「已套用維度 ⊆ 保護集」。

**但要注意**：`#57` 的 **veto 區塊仍只掃 4/9 案例** —— 本輪唯一的 veto（案例 05）不在其中，
所以斷言印出「本輪未觸發 veto」，**與事實相反**，而 K/L/M 三條 ✅ 是**空轉**；
我在全 9 案例重算才確認產品行為正確。另外案例 03 出現一次 **5.8× overshoot**（移除 `hobby`），
且同一題的 `matched` 變異仍大（案例 08：82↔291）。
