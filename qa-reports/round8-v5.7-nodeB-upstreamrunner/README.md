# `NODE-B` persona-db **v5.7** API 實測 — 第八輪

**結論摘要**：10/10 HTTP 200。**上游斷言 13/13 全數通過**；語意正確性 9/9；
**`summary` 擴充至 24 欄使回應成為「自證的」**（可直接從回傳列驗證每個 `applied_filter`，本輪 9 項查核全過）。
需注意：**broadening 空轉率 60%**、案例 4 三輪放寬全無效、案例 2 首次觸發 `overshoot`。
**完整分析**：見 **`ANALYSIS.md`**。

> ## 本輪範圍（依 kstsai 指示）
> - ❌ **不與前版本比對**
> - ✅ **LLM Verify QA**：契約 + 斷言 + API response 結果分析

---

## 受測環境

| 項目 | 值 |
|:---|:---|
| 節點 | `NODE-B`（node ID 與 v5.2 / v5.4 / v5.6 三輪相同 ⇒ **第 4 次就地升級**）|
| 版本 | **v5.7**（`/personadb/status`）|
| Personas | 1069（1.72 MB）|
| API 契約 | `cb5b08084daea8af`（13053 B）；`PersonaSummary` **24 欄** |
| 執行時間 | 2026-09-14 06:36 – 07:10 UTC（34.5 分鐘）|

> ⚠️ **版本落差**：repo `upDockerVerHermes/RELEASE-VERSION` = **v5.6**，但服務自報 **v5.7**。
> 上游 `#50` 正是檢查此事，惟該項需 host 權限 → **本輪 N/A**。

---

## 儀器

| 項目 | 值 |
|:---|:---|
| 上游腳本 | sha256 `5c1ca7165049f449745f43813edc01190fa25d171fa8f2228ceef71010bcf537`（**227 行**）|
| 本輪 runner | sha256 `473d6e5525da45d2795c51eab1b8b512ccef89377ce45b26a5597b33a03e4bfd` |
| 請求參數 | **100% 未改**（§複驗步驟 2 可驗）|
| 與前一版上游差異 | **僅** `#42` 斷言改比例式（issue #52 修復），已同步且逐字相同 |

---

## 目錄結構

```
round8-v5.7-nodeB-upstreamrunner/
├── ANALYSIS.md                         ← 【主報告】
├── README.md                           ← 本檔
├── run-test.sh                         ← runner（由上游改寫）
├── run.log                             ← 完整 stdout（含 14 條斷言輸出）
├── raw/                                ← 逐位元組 response body + openapi.json
├── json/                               ← pretty-print 版
├── headers/                            ← 完整 HTTP response headers
├── meta/                               ← http_code / 耗時 / bytes / curl 參數
│   ├── original-upstream-5c1ca716.sh   ← 上游原版（證據）
│   └── scope-and-provenance.txt        ← 本輪範圍 + 儀器 + 版本落差記錄
├── extra/                              ← 斷言輸出落盤
│   ├── assertions-34-37.txt
│   ├── assertions-47-49.txt
│   ├── assert47-invalid-opmode.json    ← 負向測試原始回應
│   └── assert50-na.txt                 ← #50 未執行的明確記錄
├── supplemental/                        ← /personadb/detail 樣本
└── summary-per-case.csv / summary-per-persona.csv / summary-all-cases.json
```

---

## 複驗步驟

### 1. 儀器與上游

```bash
cd <repo>/qa-reports/round8-v5.7-nodeB-upstreamrunner
shasum -a 256 meta/original-upstream-5c1ca716.sh   # 5c1ca716…
shasum -a 256 run-test.sh                          # 473d6e55…
```

### 2. 證明請求參數與順序未被改動

```bash
diff <(grep -o 'data-urlencode "[^"]*"' meta/original-upstream-5c1ca716.sh) \
     <(grep -o 'data-urlencode "[^"]*"' run-test.sh) && echo "✓ 完全相同且順序一致"
```

### 3. ★ 上游斷言 13/13

```bash
cat extra/assertions-34-37.txt    # #34/#35/#36/#37 + v5.4(#42/#43/#44)
cat extra/assertions-47-49.txt    # #47 負向測試 / #48 / #49
cat extra/assert50-na.txt         # #50 = N/A
# 應全為 ✅（除 #50 N/A）
```

### 4. ★ 回應「自證性」查核（24 欄 summary 帶來的新能力）

```bash
python3 - <<'PY'
import json,glob,collections
for f in sorted(glob.glob('json/0[1-9]*.json')):
    d=json.load(open(f,encoding='utf-8'))
    if 'total_matched' not in d: continue
    af=d['applied_filters']
    for k in ('sex','marriage','education','employment_status','debt_status','aesthetic_procedure'):
        if k not in af: continue
        got=collections.Counter(str(s.get(k)) for s in d['summary'])
        ok=all(g in set(af[k]) for g in got)
        print(f"{f.split('/')[-1][:-5]:20s} {k}={'/'.join(af[k])} → {dict(got)} {'✓' if ok else '✗'}")
PY
# 每個 applied_filter 都應在回傳列中被滿足（✓）
```

### 5. ★ 計分宣告誠實性（區分碰撞 vs 低報）

```bash
python3 - <<'PY'
import json,glob,os
for f in sorted(glob.glob('json/0[1-9]*.json')):
    d=json.load(open(f,encoding='utf-8'))
    if 'total_matched' not in d: continue
    dm=d['scoring_basis']['dims_counted']
    rows=[(s['score'],'|'.join(str(s.get(k,'n/a')) for k in dm)) for s in d['summary']]
    a=b=0
    for i in range(len(rows)):
        for j in range(i+1,len(rows)):
            ss=rows[i][0]==rows[j][0]; sv=rows[i][1]==rows[j][1]
            if ss and not sv: a+=1
            if sv and not ss: b+=1
    print(f"{os.path.basename(f)[:-5]:20s} (a)碰撞={a}  (b)低報={b}")
PY
# (b) 應全為 0
```

### 6. Broadening 行為（含案例 4 的三輪空轉、案例 2 的 overshoot）

```bash
python3 - <<'PY'
import json,glob,os
for f in sorted(glob.glob('json/0[1-9]*.json')):
    d=json.load(open(f,encoding='utf-8'))
    if 'total_matched' not in d: continue
    ba=d['broadening_attempts']
    seq=' → '.join(f"{x['match_count_before']}→{x['match_count_after']}" for x in ba) or '0 輪'
    print(f"{os.path.basename(f)[:-5]:20s} {seq}  no_op={sum(1 for x in ba if x.get('no_op'))} overshoot={sum(1 for x in ba if x.get('overshoot'))}")
PY
```

### 7. 重跑（⚠️ 需連得到受測節點；本輪實測 34.5 分鐘）

```bash
OUT=/tmp/r8 BASE_URL=http://<node>:8000 bash run-test.sh
```

---

## 誠實聲明

- **單次執行**：各案例單筆數值不可視為穩定值（已知同輪同 query 會變異）；本輪未做重現性探針。
- **`#50` 未執行** → 因此 §0 的「`RELEASE-VERSION` v5.6 vs 服務 v5.7」落差**無法判定**；
  **未執行 ≠ 通過**。
- **案例 6 延遲 588.9s 離群未歸因** —— 未取得伺服器端證據前不得推論伺服器端問題。
- **不與前版本比對**（依指示）；本報告不含跨版本對照。
- 本目錄節點資訊以代號呈現（`NODE-B` / `[tailnet]`）；代號對照不在本 repo。
