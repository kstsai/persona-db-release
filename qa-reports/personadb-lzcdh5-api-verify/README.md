# lzcdh5 persona-db API 實測 — 證據包

**結論摘要**：9/9 請求 HTTP 200。`role` 參數驗證通過；但發現 7 項問題（收入桶飽和、端點不可重現、宣稱維度不存在等）。
**完整分析**：見 **`ANALYSIS.md`**。

---

## 目錄結構

```
personadb-lzcdh5-api-verify/
├── ANALYSIS.md                    ← 【主報告】逐案例分析 + 7 項跨案例發現
├── README.md                      ← 本檔（證據地圖 + 複驗步驟）
├── run-test.sh                    ← 實際執行的 runner（原腳本改作遠端執行版）
├── run.log                        ← 完整執行 stdout（含每案例 echo 標籤 + 完整 response body）
│
├── raw/                           ← 【原始證據】逐位元組的 HTTP response body
│   ├── 00_status.body             ←   /personadb/status（text/plain，792 bytes）
│   ├── 01_kangshimei.body         … 08_boss.body（application/json）
│   └── openapi.json               ←   /openapi.json（API 契約，9298 bytes）
├── json/                          ← 同上 body 的 pretty-print 版（jq .）
│                                    ⚠️ 00_status.json 為 0 bytes 且 meta/00_status.jqerr
│                                       存在，屬**預期行為**：status 端點回傳 text/plain
│                                       非 JSON，jq 解析失敗。有效證據在 raw/00_status.body。
├── headers/                       ← 每案例完整 HTTP response headers
├── meta/                          ← 每案例 http_code / 耗時 / bytes / curl 參數 + 執行環境 provenance
│   ├── NN_*.meta / NN_*.w         ←   逐案例 metadata
│   ├── run-partial-foreground.log ←   Run A（逾時中斷的那次）完整 stdout
│   ├── original-test-persona-db-api.sh  ← 上游原始腳本存檔
│   ├── script-provenance.txt      ←   上下游腳本 + runner 的 sha256
│   └── instance-provenance.txt    ←   tailscale 節點資訊
│
├── runA/                          ← 【關鍵證據】Run A 的 body（被 Run B 覆蓋前的完整保留）
│   ├── 01_kangshimei.{body,json}  … 03_fashion.{body,json}
│   └── requests.txt               ←   Run A 的請求與耗時行
│
├── supplemental/                  ← 補充查證（非原腳本範圍，用於 §4.3/§3-案例6）
│   ├── detail_*.json              ←   /personadb/detail 樣本（維度字典 + 性別）
│
├── summary-per-case.csv           ← 逐案例彙總表（Excel 可開，UTF-8 BOM）
├── summary-per-persona.csv        ← 逐 persona 明細（8 案例 × top_k = 66 列）
├── summary-all-cases.json         ← 8 案例完整回應合併為單一 JSON
└── determinism-comparison.csv     ← Run A vs Run B 重現性對照（§4.2 證據）
```

---

## 複驗步驟

### 1. 確認證據未被竄改

```bash
cd /Users/kstsai/Documents/personadb-lzcdh5-api-verify
cat meta/script-provenance.txt          # 比對上游腳本 sha256
shasum -a 256 run-test.sh               # 應為 ffc7b106…74695d
```

### 2. 抽驗單一案例（不重跑整套，避免 20 分鐘）

```bash
# 原始 body（位元組級證據）
cat raw/07_debt.body | jq .

# 該次呼叫的 HTTP 結果與耗時
cat meta/07_debt.meta

# response headers
cat headers/07_debt.headers
```

### 3. 複驗關鍵斷言

```bash
# (a) top_k 精確遵守 + persona_ids 對齊 summary.id（8/8 應為 true）
for f in json/0[1-8]*.json; do
  jq -r '([.persona_ids|length] == [(.summary|length)]) and
         (([.persona_ids[]|tostring]) == ([.summary[].id|sub("TW-P-";"")|tonumber|tostring]))' "$f"
done

# (b) 分數單調遞減（8/8 應為 true）
for f in json/0[1-8]*.json; do
  jq -r '[.summary[].score] as $s | [range(1;$s|length)|$s[.] <= $s[.-1]] | all' "$f"
done

# (c) Role 差異化（§3 案例 4/5）：應印出 DIFFERENT，且交集為 0
jq -r '.persona_ids[0]' json/04_role_fangzhong.json
jq -r '.persona_ids[0]' json/05_role_banker.json
comm -12 <(jq -r '.persona_ids|sort[]' json/04_role_fangzhong.json) \
         <(jq -r '.persona_ids|sort[]' json/05_role_banker.json) | wc -l   # → 0

# (d) 宣稱維度不存在（§4.3）：應無輸出
grep -l -e aesthetic_procedure -e debt_status -e employment_status raw/*.body json/*.json

# (e) 收入桶飽和（§4.1）
for f in json/0[1-8]*.json; do
  printf "%s %s/%s\n" "$(basename $f .json)" \
    "$(jq '[.summary[]|select(.income==">8萬")]|length' $f)" "$(jq '.summary|length' $f)"
done

# (f) 重現性（§4.2）：Run A vs Run B，案例 1/2 交集應為 0
cat determinism-comparison.csv

# (g) 計分維度低報（§4.4）：案例 08 應報 25 組反例
#     （完整指令見 ANALYSIS.md §4.4 所述方法；此處示範最直接的單筆反例）
jq -r '.scoring_basis.dims_counted as $d |
  .summary[] | select(.id=="TW-P-0181" or .id=="TW-P-0149") |
  "\(.id) score=\(.score) age=\(.age) occ=\(.occupation) inc=\(.income) | undeclared faminc=\(.family_income)"' \
  json/08_boss.json
```

### 4. 重跑整套（⚠️ 約 20 分鐘，且結果**不會**與本包相同 — 見 §4.2）

```bash
cd /Users/kstsai/Documents/personadb-lzcdh5-api-verify
# 建議另開目錄，避免覆蓋本證據包
OUT=/tmp/lzcdh5-rerun bash run-test.sh
```

> **重要**：重跑結果**必然不同**（LLM 每次重新合成篩選維度）。若要比較，請保留本包的 `summary-per-case.csv` 作為 baseline，並用 `determinism-comparison.csv` 的方法做交集比對。

---

## 執行環境（本次）

| 項目 | 值 |
|------|-----|
| 執行者 | DSH agent（macOS 14/x） |
| 目標 | `lzcdh5` = tailscale `100.96.79.33`，`lzcdh5.tail6cb434.ts.net` |
| 連線 | tailscale 直連 `1.169.214.22:52036`（非 relay），`Online: true` |
| 服務 | uvicorn / Persona DB **v4.9.2**，1069 personas |
| LLM 後端 | `deepseek-v4-flash` → `https://api.deepseek.com` |
| 時間 | 2026-09-12 02:25:5x – 02:45:07 UTC（≈19.4 分鐘） |
| 上游腳本 | `kstsai/persona-db-release` @ `upDockerVerHermes/test-persona-db-api.sh`<br>sha256 `33749d4e5218f3860f15f4296c5fc5ea90f0fa93f441bc4eba9faf2274dad2e3` |

## 已知偏離原腳本之處

**請求參數、順序、斷言邏輯 100% 不變**。僅三處調整：
1. Base URL `localhost:8000` → `100.96.79.33:8000`（遠端執行）
2. 新增逐案例證據落盤（`raw/` `headers/` `meta/`）
3. Role QA diff check 由 `python3` 讀 `/tmp` 改為 `jq` 讀 `json/`（等效，避免 `/tmp` 依賴）

詳見 `ANALYSIS.md` §7。
