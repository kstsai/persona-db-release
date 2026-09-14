# NODE-B persona-db **v5.4** API 實測 — 證據包（第四輪，四版對照）

**結論摘要**：8/9 成功（**1 次 HTTP 503 `FILTER_FAILED`，四輪首見**）。v5.4 新增 `pool_exhausted`/`returned`/`no_op`/`overshoot`/`score_scale` 等**可觀測性欄位**，精準對應前三輪報告的發現；`debt_status` 精度與案例 06 召回同時改善。但 503 回應**違反自身宣告的 schema**，且可重現性較 v5.3.1 退步。
**完整分析**：見 **`ANALYSIS.md`**。

> **節點確認**：`NODE-B` (`NODE-B`)，node ID `NODE-B-NODEID`（與第二輪 v5.2 相同 → 就地升級 v5.2 → v5.4）。

---

## 四輪證據包位置

| 版本 | 節點 | 目錄 |
|------|------|------|
| v4.9.2 | NODE-A (NODE-A) | `../personadb-NODE-A-api-verify/` |
| v5.2 | NODE-B (NODE-B) | `../personadb-dh1-api-verify/` |
| v5.3.1 | NODE-A (NODE-A) | `../personadb-NODE-A-v531-api-verify/` |
| **v5.4** | **NODE-B (NODE-B)** | **本目錄** |

四輪 `run-test.sh` **sha256 完全相同**（`ffc7b106…`）。

---

## 目錄結構

```
personadb-dh1-v54-api-verify/
├── ANALYSIS.md                    ← 【主報告】四版對照 + 逐案例 + 8 項發現
├── README.md                      ← 本檔
├── run-test.sh                    ← runner（四輪同一份 sha256）
├── compare-nway.py                ← ★ N 版自動對照（現為四版 A/B/C/D）
├── run.log                        ← 完整執行 stdout
│
├── raw/                           ← 【原始證據】逐位元組 HTTP response body
│   ├── 00_status.body             ←   v5.4, 790 bytes
│   ├── 01_kangshimei.body         … 08_boss.body
│   ├── 02_tesla.body              ←   ★ 503 FILTER_FAILED 原始回應（206 bytes）
│   └── openapi.json               ←   10131 bytes（第三種契約）
├── json/                          ← pretty-print 版
│                                    ⚠️ 00_status.json 為 0 bytes（text/plain，預期行為）
│                                    ⚠️ 02_tesla.json 為 503 error body（非 candidates 回應）
├── headers/                       ← 每案例完整 headers（含 503 的 Service Unavailable）
├── meta/                          ← http_code / 耗時 / bytes / curl 參數
│   ├── instance-provenance.txt
│   ├── original-test-persona-db-api.sh
│   └── script-provenance.txt      ←   四輪 runner sha256 對照
│
├── repeat/                        ← 重現性探測（case 01 發 3 次：r1 200 / r2 逾時(無檔案) / r3 200）
│                                    ⚠️ r2 因 300s 客戶端逾時而未產生檔案 → 目錄僅 2 個檔案，
│                                       共 3 個有效觀測（suite + r1 + r3）。逾時本身即證據。
├── probe/                         ← ★ pool_exhausted 定向探針（top_k=100 → matched 12）
│   └── pool_exhausted_topk100.json
├── supplemental/                  ← /personadb/detail 樣本（維度字典 8 個）
│
├── summary-per-case.csv           ← 逐案例彙總（含 503 該列，欄位 error_code/error_message）
├── summary-per-persona.csv        ← 逐 persona 明細（7 成功案例；含新維度欄位）
├── summary-all-cases.json         ← 8 案例合併（含 503 body）
└── version-comparison-nway.csv    ← ★ 四版逐案例對照
```

---

## 複驗步驟

### 1. 確認四輪可比對

```bash
cd /Users/kstsai/Documents/personadb-dh1-v54-api-verify
cat meta/script-provenance.txt      # 四輪 runner sha256 應完全相同
cat meta/instance-provenance.txt    # 確認 node ID 與第二輪相同（就地升級）
```

### 2. 確認 v5.4 契約是新的（第三種）

```bash
for d in ../personadb-NODE-A-api-verify ../personadb-dh1-api-verify \
         ../personadb-NODE-A-v531-api-verify .; do
  printf "%-42s %6d B  %s\n" "$(basename $d)" "$(wc -c < $d/raw/openapi.json)" \
    "$(shasum -a 256 $d/raw/openapi.json | cut -c1-16)"
done
# v5.2 與 v5.3.1 應同一個 hash；v5.4 應不同
```

### 3. 複驗核心斷言

```bash
# (a) 契約一致性（7 個成功案例；02 為 503 應跳過）
for f in json/0[1-8]*.json; do
  jq -e 'has("total_matched")' "$f" >/dev/null 2>&1 || { echo "$(basename $f .json): (error response)"; continue; }
  jq -r '"\(input_filename|split("/")[-1]): aligned=\(([.persona_ids[]|tostring]) == ([.summary[].id|sub("TW-P-";"")|tonumber|tostring])) monotonic=\([.summary[].score] as $s | [range(1;$s|length)|$s[.] <= $s[.-1]] | all) returned_ok=\(.returned == (.summary|length) and .returned == (.persona_ids|length))"' "$f"
done
# 全部應為 aligned=true monotonic=true returned_ok=true

# (b) ★ 503 原始證據（四輪首見）
cat raw/02_tesla.body | jq .
cat headers/02_tesla.headers          # HTTP/1.1 503 Service Unavailable

# (c) ★ 503 違反宣告 schema：宣告 ErrorResponse(required "error")，實際是 "detail"
jq -c '.components.schemas.ErrorResponse.required' raw/openapi.json   # ["error"]
jq -r 'has("error")' raw/02_tesla.body                                # false
jq -r 'has("detail")' raw/02_tesla.body                               # true

# (d) ★ 新欄位存在性（v5.4 才有）
jq -r 'keys|join(", ")' json/07_debt.json
# 應含 returned, pool_exhausted（前 3 版皆無）

# (e) ★ v5.4 scoring_basis 新欄位（回應我上輪「分數不可跨版本比較」的發現）
jq '.scoring_basis' json/07_debt.json
# 應含 weight_version="v5.4", score_scale="relative-within-version", score_schema=1
for d in ../personadb-NODE-A-api-verify ../personadb-dh1-api-verify ../personadb-NODE-A-v531-api-verify; do
  printf "%-42s %s\n" "$(basename $d)" "$(jq -c '.scoring_basis|keys' $d/json/07_debt.json)"
done
# 前三版應只有 4 個 key

# (f) ★ pool_exhausted 語意（定向探針：top_k=100 → matched 12 → true）
jq -r '"matched=\(.total_matched) returned=\(.returned) pool_exhausted=\(.pool_exhausted) (top_k was 100)"' \
   probe/pool_exhausted_topk100.json
# 應為 matched=12 returned=12 pool_exhausted=true

# (g) ★ no_op 標記是否準確（人工判定 vs 機器標記，應相等）
python3 - <<'PY'
import json,glob
for f in sorted(glob.glob('json/0[1-8]*.json')):
    d=json.load(open(f,encoding='utf-8'))
    if 'total_matched' not in d: continue
    ba=d['broadening_attempts']
    if not ba: continue
    inert=sum(1 for x in ba if x['match_count_before']==x['match_count_after'])
    decl=sum(1 for x in ba if x.get('no_op'))
    print(f"{f.split('/')[-1][:-5]:22s} loops={len(ba)} inert={inert} declared_no_op={decl} {'OK' if inert==decl else 'MISMATCH'}")
PY
# 應全部 OK（v5.4 合計 3 vs 3）

# (h) ★ overshoot（v5.4 新增，前三版無）
jq -r '.broadening_attempts[] | select(.overshoot==true) | "  loop \(.loop): \(.match_count_before)→\(.match_count_after)"' json/03_fashion.json

# (i) ★ debt_status 精度恢復（v5.3.1 有 4/10 無債務；v5.4 應 0/10）
echo "v5.4  : $(jq -r '[.summary[].debt_status]|group_by(.)|map("\(.[0]):\(length)")|join("  ")' json/07_debt.json)"
echo "v5.3.1: $(jq -r '[.summary[].debt_status]|group_by(.)|map("\(.[0]):\(length)")|join("  ")' ../personadb-NODE-A-v531-api-verify/json/07_debt.json)"

# (j) ★ 案例 06 由 5 筆恢復到 10 筆
echo "v5.4  : matched=$(jq -r .total_matched json/06_aesthetic.json) returned=$(jq -r .returned json/06_aesthetic.json)"
echo "v5.3.1: matched=$(jq -r .total_matched ../personadb-NODE-A-v531-api-verify/json/06_aesthetic.json) returned=$(jq -r .returned ../personadb-NODE-A-v531-api-verify/json/06_aesthetic.json)"

# (k) ★ employment_status 四輪皆未套用
for d in ../personadb-NODE-A-api-verify ../personadb-dh1-api-verify \
         ../personadb-NODE-A-v531-api-verify .; do
  printf "%-42s " "$(basename $d)"
  n=0; for f in $d/json/0[1-8]*.json; do
    jq -e 'has("total_matched")' "$f" >/dev/null 2>&1 || continue
    [ -n "$(jq -r '.applied_filters.employment_status // empty' $f)" ] && n=$((n+1))
  done; echo "applied in $n/8"
done

# (l) ★ 四版完整對照（一次跑完）
python3 compare-nway.py
```

### 4. 重跑整套（⚠️ 約 28 分鐘；結果不會相同，且**可能遇到 503**）

```bash
cd /Users/kstsai/Documents/personadb-dh1-v54-api-verify
OUT=/tmp/v54-rerun BASE_URL=http://NODE-B:8000 bash run-test.sh
```

> v5.4 的 `total_matched` 變異約 4.5×（v5.3.1 為 1.3×），且 3 次 case-01 取樣中有 1 次 300s 逾時。**建議保留本包作 baseline。**

---

## 執行環境

| 項目 | 值 |
|------|-----|
| 目標 | `NODE-B` = tailscale `NODE-B`（node ID `NODE-B-NODEID`；節點內部 HostName 為 `NODE-B-host`） |
| 連線 | tailscale 直連 `[public-ip]:21845`（非 relay） |
| 服務 | uvicorn / Persona DB **v5.4**，1069 personas（1.72 MB） |
| LLM 後端 | `deepseek-v4-flash` → `https://api.deepseek.com` |
| 其他 | Python 3.11.15；Name diversity 172 (16.1%) max 16×；32 Python files |
| 時間 | 2026-09-12 11:39 – 12:07 UTC（約 28 分鐘） |

### 四版環境對照

| | v4.9.2 | v5.2 | v5.3.1 | **v5.4** |
|---|---|---|---|---|
| 節點 | NODE-A | NODE-B | NODE-A | **NODE-B** |
| 契約 sha256(16) | `8ac54b95228d85fc` | `8b869ae266992056` | `8b869ae266992056` | **`30a228782154bdce`** |
| openapi bytes | 9298 | 9706 | 9706 | **10131** |
| top-level keys | 10 | 10 | 10 | **12** |
| `scoring_basis` keys | 4 | 4 | 4 | **7** |
| candidates 平均延遲 | 144.1s | 203.5s | 157.5s | **195.7s** |
| HTTP 200 率 | 9/9 | 9/9 | 9/9 | **8/9**（1×503） |

## 已知偏離原腳本之處

**請求參數、順序、斷言邏輯 100% 不變**（runner sha256 四輪相同）。僅：
1. `BASE_URL` / `OUT` 指向本次目標
2. 新增證據落盤（`raw/` `headers/` `meta/`）
3. Role QA diff check 由 `python3` 讀 `/tmp` 改為 `jq` 讀 `json/`（等效）
4. **新增**（非原腳本，報告中已標示）：`repeat/` 重現性探測、`probe/` pool_exhausted 定向探針、`supplemental/` 維度查證、`compare-nway.py`
