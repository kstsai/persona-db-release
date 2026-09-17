# `NODE-A` persona-db **v5.6**（Docker 部署）API 實測 — 第七輪

**結論摘要**：10/10 HTTP 200。**語意正確性 9/9**；`#34` 雙向驗證通過（業主套 `employment_status=['雇主']`、顧客不套）；
計分宣告**經正向實驗驗證為誠實**（居住地/城市層級不同、分數完全相同）。值得注意：頭部集中 25%、broadening 空轉 31%。
**完整分析**：見 **`ANALYSIS.md`**。

> ## 本輪範圍（依 kstsai 指示）
> - ❌ **不做 api-version 跨版本比對**
> - ✅ **純 API response 結果分析**
>
> 因此本包**不含**跨版本對照；契約資訊僅用於確認回應結構。

---

## 受測環境

| 項目 | 值 |
|:---|:---|
| 節點 | `NODE-A`（Docker 部署：`upDockerVerHermes` compose，`hermes` + `persona-db-api` 容器）|
| 版本 | **v5.6**（`/personadb/status` 與 `RELEASE-VERSION` 一致）|
| API 契約 | `aafe647f46ee8abe`（12332 B）|
| LLM 後端 | `deepseek-v4-flash` |
| 執行時間 | 2026-09-14 02:25 – 02:53 UTC |

---

## 儀器

| 項目 | 值 |
|:---|:---|
| 上游腳本 | sha256 `9a29a8ef3bc553a334b1865c792d4f0f17e60ce15f93a46fe9f8ac9b684edbd8`（223 行）|
| 本輪 runner | sha256 `10e888d9ad575401363e70b61ffbf37d46da1ff90b6b9696853add6ed306e196` |
| 請求參數 | **100% 未改**（§複驗步驟 2 可驗）|

---

## 目錄結構

```
round7-v5.6-nodeA-upstreamrunner/
├── ANALYSIS.md                        ← 【主報告】response 結果分析
├── README.md                          ← 本檔
├── run-test.sh                        ← runner（由上游改寫）
├── run.log                            ← 完整 stdout（含 14 條斷言輸出）
├── raw/                               ← 逐位元組 response body + openapi.json
├── json/                              ← pretty-print 版
├── headers/                           ← 完整 HTTP response headers
├── meta/                              ← http_code / 耗時 / bytes / curl 參數
│   ├── original-upstream-9a29a8ef.sh  ← 上游原版（證據）
│   └── scope-and-provenance.txt       ← 本輪範圍 + 儀器
├── extra/                             ← 斷言輸出落盤
│   ├── assertions-34-37.txt           ← #34/#35/#36/#37 + v5.4 斷言
│   ├── assertions-47-49.txt           ← #47/#48/#49
│   ├── assert47-invalid-opmode.json   ← 負向測試原始回應
│   └── assert50-na.txt                ← #50 未執行的明確記錄
├── probe/                             ← 居住地計分假設的**否證**實驗（top_k=30）
│   └── fangzhong_topk30.json
├── supplemental/                      ← /personadb/detail 樣本
└── summary-per-case.csv / summary-per-persona.csv / summary-all-cases.json
```

---

## 複驗步驟

### 1. 儀器與上游

```bash
cd <repo>/qa-reports/round7-v5.6-nodeA-upstreamrunner   # 或本目錄
shasum -a 256 meta/original-upstream-9a29a8ef.sh   # 9a29a8ef…
shasum -a 256 run-test.sh                          # 10e888d9…
```

### 2. 證明請求參數與順序未被改動

```bash
diff <(grep -o 'data-urlencode "[^"]*"' meta/original-upstream-9a29a8ef.sh) \
     <(grep -o 'data-urlencode "[^"]*"' run-test.sh) && echo "✓ 完全相同且順序一致"
```

### 3. ★ 語意正確性（本輪核心）

```bash
# #34 雙向：業主必套、顧客不套
head -2 extra/assertions-34-37.txt
jq -c '.applied_filters.employment_status' json/09_owner.json          # ["雇主"]
jq -r '.applied_filters.employment_status // "None(正確未套用)"' json/08_boss.json

# 回傳 10/10 皆雇主
jq -r '[.summary[].employment_status]|unique|join(",")' json/09_owner.json

# #36：藥妝不套、醫美套
jq -r '.applied_filters.aesthetic_procedure // "None(正確未套用)"' json/01_kangshimei.json
jq -c '.applied_filters.aesthetic_procedure' json/06_aesthetic.json

# 角色差異（房仲 vs 銀行 的 debt_status 方向相反）
jq -c '.applied_filters.debt_status' json/04_role_fangzhong.json       # ["無"]
jq -c '.applied_filters.debt_status' json/05_role_banker.json          # ["有房貸"]
```

### 4. ★ 計分宣告誠實性（含正向實驗）

```bash
python3 - <<'PY'
import json,collections
d=json.load(open('probe/fangzhong_topk30.json',encoding='utf-8'))
dm=d['scoring_basis']['dims_counted']
g=collections.defaultdict(list)
for s in d['summary']:
    g['|'.join(str(s.get(k,'n/a')) for k in dm)].append(s)
for v,rows in g.items():
    if len(rows)<2: continue
    print(f"向量 {v}")
    for r in rows: print(f"   {r['id']} {r['residence']} tier={r.get('city_price_tier')} → {r['score']}")
    print("  ⇒", "分數相同 ✅（居住地不參與計分）" if len({r['score'] for r in rows})==1 else "分數不同 ⚠️")
PY
# 預期：tier=高 vs tier=低 的 persona 得到**完全相同**的分數
```

### 5. 斷言全貌

```bash
cat extra/assertions-34-37.txt    # 含 #42 的 ⚠️ 說明（斷言絕對門檻問題）
cat extra/assertions-47-49.txt    # #47 負向測試 / #48 / #49
cat extra/assert50-na.txt         # #50 = N/A
```

### 6. 逐案例不變式

```bash
for f in json/0[1-9]*.json; do
  jq -r '"\(input_filename|split("/")[-1]): matched=\(.total_matched) returned=\(.returned) inv=\(.returned == (.summary|length)) pool=\(.pool_exhausted) mono=\([.summary[].score] as $s | [range(1;$s|length)|$s[.] <= $s[.-1]] | all)"' "$f"
done
# inv / mono 應全部 true
```

### 7. 重跑（⚠️ 需連得到受測節點，約 30 分鐘）

```bash
OUT=/tmp/r7 BASE_URL=http://<node>:8000 bash run-test.sh
```

> ⚠️ 重跑結果必然不同 —— 本輪已實測**同一輪內、同一 query** 的 filter 與匹配數就會變（見 `ANALYSIS.md` §4.4）。

---

## 誠實聲明

- **單次執行**：各案例的單筆數值不可視為穩定值；本輪未做重現性探針（依指示聚焦 response 分析）。
- **`#50` 未執行**（遠端無 host 權限），明確標 N/A；**未執行 ≠ 通過**。
- **§3.4 的檢定僅涵蓋 `summary` 曝露的 7 個維度** —— `sex`/`marriage`/`education`/`hobby`
  可出現在 `dims_counted` 卻不在 `summary`，故無法從回應驗證（見 `ANALYSIS.md` §4.5）。
- **一條假設被自己的探針推翻**：案例 4 的 top-3 全在低房價層級，一度像是「居住地影響計分」；
  以 `top_k=30` 取更大池子後**否證**（不同 tier 分數完全相同）。若沒做該探針，就會誤報一條不存在的缺陷。
- 本目錄節點資訊以代號呈現（`NODE-A` / `[private-net]`）；代號對照不在本 repo。
