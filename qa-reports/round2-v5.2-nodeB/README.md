# NODE-B persona-db **v5.2** API 實測 — 證據包

**結論摘要**：9/9 請求 HTTP 200。v5.2 **新增 3 個 persona 維度**（`aesthetic_procedure`/`debt_status`/`employment_status`）並實際投入篩選；收入桶飽和大幅改善。但端點仍不可重現（同查詢 `total_matched` 1↔62）、`employment_status` 從未被套用。
**完整分析**：見 **`ANALYSIS.md`**。**對照組**：`../round1-v4.9.2-nodeA/`（v4.9.2）。

> ⚠️ **與 NODE-A 的關鍵差異**：v5.2 多了 3 個維度，`summary[]` 由 14 欄增至 17 欄。若你的 consumer 做嚴格 schema 驗證，會在此失敗（top-level key 不變，屬相容性新增）。

---

## 目錄結構

```
round2-v5.2-nodeB/
├── ANALYSIS.md                    ← 【主報告】逐案例分析 + 7 項跨版本對照發現
├── README.md                      ← 本檔（證據地圖 + 複驗步驟）
├── run-test.sh                    ← 實際執行的 runner（sha256 與 NODE-A run 完全相同）
├── compare-versions.py            ← v4.9.2 ⟷ v5.2 自動對照工具
├── run.log                        ← 完整執行 stdout（含每案例標籤 + 完整 response body）
│
├── raw/                           ← 【原始證據】逐位元組 HTTP response body
│   ├── 00_status.body             ←   /personadb/status（text/plain，790 bytes）
│   ├── 01_kangshimei.body         … 08_boss.body（application/json）
│   └── openapi.json               ←   /openapi.json（API 契約，9706 bytes）
├── json/                          ← 同上 body 的 pretty-print 版（jq .）
│                                    ⚠️ 00_status.json 為 0 bytes + meta/00_status.jqerr 存在
│                                       屬**預期行為**（status 回傳 text/plain，非 JSON）
├── headers/                       ← 每案例完整 HTTP response headers
├── meta/                          ← 每案例 http_code / 耗時 / bytes / curl 參數 + provenance
│   ├── instance-provenance.txt    ←   tailscale 節點資訊（含 NODE-B vs NODE-A）
│   ├── original-test-persona-db-api.sh  ← 上游原始腳本存檔
│   └── script-provenance.txt      ←   （見下方「雜湊」）
│
├── repeat/                        ← 【關鍵證據】重現性探測（同一查詢 case 01 ×4）
│   ├── case01_r1.json             ←   matched=1, aesthetic_procedure=["有"]
│   ├── case01_r2.json             ←   matched=1, aesthetic_procedure=["有"]
│   └── r3-timeout.txt             ←   r3 HTTP 000（300s 客戶端逾時）證據
│
├── supplemental/                  ← 補充查證（非原腳本範圍，用於維度字典/性別）
│   └── detail_*.json              ←   /personadb/detail 樣本（17 個：8 個維度字典抽樣 + 案例 06 的 10 位）
│
├── summary-per-case.csv           ← 逐案例彙總表（UTF-8 BOM，Excel 可開）
├── summary-per-persona.csv        ← 逐 persona 明細（8 案例 × top_k = 56 列）
├── summary-all-cases.json         ← 8 案例完整回應合併
└── version-comparison.csv         ← v4.9.2 ⟷ v5.2 逐案例對照
```

---

## 複驗步驟

### 1. 確認證據未被竄改／確認兩版可對照

```bash
cd /Users/kstsai/Documents/round2-v5.2-nodeB
shasum -a 256 run-test.sh meta/original-test-persona-db-api.sh
# runner 應為 ffc7b10642f72f4120a43b77848ed722c6cf865c23b3267a3eb87bd48c74695d
#   ← 與 NODE-A 那次執行「完全相同」，確保是同一份測試
# 上游腳本應為 33749d4e5218f3860f15f4296c5fc5ea90f0fa93f441bc4eba9faf2274dad2e3
```

### 2. 抽驗單一案例（不重跑整套，避免 27 分鐘）

```bash
cat raw/07_debt.body | jq .      # 原始 body（位元組級證據）
cat meta/07_debt.meta            # HTTP code / 耗時 / bytes / curl 參數
cat headers/07_debt.headers      # response headers
```

### 3. 複驗核心斷言

```bash
# (a) 契約一致性：top_k 遵守 + persona_ids 對齊 summary.id（8/8 應為 true）
for f in json/0[1-8]*.json; do
  jq -r '([.persona_ids|length] == [(.summary|length)]) and
         (([.persona_ids[]|tostring]) == ([.summary[].id|sub("TW-P-";"")|tonumber|tostring]))' "$f"
done

# (b) 分數單調遞減（8/8 應為 true）
for f in json/0[1-8]*.json; do
  jq -r '[.summary[].score] as $s | [range(1;$s|length)|$s[.] <= $s[.-1]] | all' "$f"
done

# (c) ★ v5.2 新增 3 維度：summary[] 應為 17 欄（v4.9.2 為 14 欄）
echo "v5.2  : $(jq -r '.summary[0]|keys|length' json/01_kangshimei.json) 欄"
echo "v4.9.2: $(jq -r '.summary[0]|keys|length' ../round1-v4.9.2-nodeA/json/01_kangshimei.json) 欄"

# (d) ★ 新維度是否被「套用為篩選」（vs 僅出現在 summary 欄位）
for f in json/0[1-8]*.json; do
  printf "%-22s %s\n" "$(basename $f .json)" \
    "$(jq -r '[.applied_filters|to_entries[]|select(.key|test("aesthetic_procedure|debt_status|employment_status"))|"\(.key)=\(.value|join("/"))"]|join("  ")' $f)"
done
# 預期：04/05/07 出現 debt_status, 06 出現 aesthetic_procedure,
#       ★ 08（標籤宣稱測 employment_status）應為「空」← 這就是 §3.1 的發現

# (e) ★ employment_status 從未被套用（8/8 應無輸出）
for f in json/0[1-8]*.json; do jq -r '.applied_filters.employment_status // empty' $f; done
echo "(無輸出 = 證實從未套用)"

# (f) ★ 案例 06 醫美：應 10/10 aesthetic_procedure=有
jq -r '[.summary[].aesthetic_procedure]|group_by(.)|map("\(.[0]):\(length)")|join("  ")' json/06_aesthetic.json
# (g) ★ 案例 07 債務整合：應 10/10 符合 debt_status 篩選
jq -r '.applied_filters.debt_status, ([.summary[].debt_status]|group_by(.)|map("\(.[0]):\(length)")|join("  "))' json/07_debt.json

# (h) ★ 收入桶飽和對照（v5.2 vs v4.9.2）
for d in . ../round1-v4.9.2-nodeA; do
  echo "--- $d ---"
  for f in $d/json/0[1-8]*.json; do
    printf "%s %s/%s  " "$(basename $f .json | cut -c1-2)" \
      "$(jq '[.summary[]|select(.income==">8萬")]|length' $f)" "$(jq '.summary|length' $f)"
  done; echo
done

# (i) ★ 重現性（同一查詢 4 次觀測）
python3 - <<'PY'
import json
for k,p in [('suite_run','json/01_kangshimei.json'),
            ('repeat_r1','repeat/case01_r1.json'),
            ('repeat_r2','repeat/case01_r2.json')]:
    d=json.load(open(p,encoding='utf-8'))
    print(f"{k:10s} matched={d['total_matched']:3d} ids={d['persona_ids']} top={d['summary'][0]['score']} aes={d['applied_filters'].get('aesthetic_procedure','NOT APPLIED')}")
PY
cat repeat/r3-timeout.txt          # 第 4 次為 300s 逾時

# (j) ★ broadening 空轉率
python3 - <<'PY'
import json,glob
t=i=0
for f in sorted(glob.glob('json/0[1-8]*.json')):
    for x in json.load(open(f,encoding='utf-8'))['broadening_attempts']:
        t+=1; i+= x['match_count_before']==x['match_count_after']
print(f"空轉 {i}/{t} = {100*i/t:.0f}%")
PY

# (k) 跨版本自動對照（一次跑完所有對照）
python3 compare-versions.py
```

### 4. 重跑整套（⚠️ 約 27 分鐘，且結果**不會**相同 — 見 §5.2）

```bash
cd /Users/kstsai/Documents/round2-v5.2-nodeB
OUT=/tmp/dh1-rerun BASE_URL=http://NODE-B:8000 bash run-test.sh
```

> **重要**：v5.2 的不可重現性比 v4.9.2 更嚴重（同查詢 `total_matched` 1↔62）。重跑請保留本包 `summary-per-case.csv` 作 baseline。

---

## 執行環境（本次）

| 項目 | 值 |
|------|-----|
| 目標 | `NODE-B` = tailscale `NODE-B`，`NODE-B.[tailnet]` |
| **節點內部 HostName** | **`NODE-B-host`**（與 tailnet 名 `NODE-B` 不同 —— 用 `HostName` 查 `tailscale status --json` 會查不到，須用 `DNSName`） |
| 連線 | tailscale 直連 `[public-ip]:21888`（非 relay），`Online: true` |
| 服務 | uvicorn / Persona DB **v5.2**，1069 personas（persona 檔 1.72 MB） |
| LLM 後端 | `deepseek-v4-flash` → `https://api.deepseek.com` |
| 其他 | Python 3.11.15；Name diversity 172 unique (16.1%)，max repeat 16×；32 Python files |
| 時間 | 2026-09-12 02:53 – 03:17 UTC（≈24 分鐘） |

**v4.9.2 (NODE-A) vs v5.2 (NODE-B) 環境對照**

| | NODE-A | NODE-B |
|---|---|---|
| Version | v4.9.2 | **v5.2** |
| persona 檔大小 | 1.60 MB | **1.72 MB** |
| persona 維度數 | 22 | **25** |
| `summary[]` 欄數 | 14 | **17** |
| Name diversity | 171 (16.0%), max 15× | 172 (16.1%), max 16× |
| Python | 3.11.16 | 3.11.15 |
| Supporting Artifices | 30 | 32 |
| candidates 平均延遲 | 144.1s | **203.5s** |
| 公網 IP | `[public-ip]` | `[public-ip]`（**同一 NAT**） |

## 已知偏離原腳本之處

**請求參數、順序、斷言邏輯 100% 不變**（runner sha256 與 NODE-A run 相同）。僅三處：
1. Base URL `localhost:8000` → `NODE-B:8000`（遠端執行）
2. 新增逐案例證據落盤（`raw/` `headers/` `meta/`）
3. Role QA diff check 由 `python3` 讀 `/tmp` 改為 `jq` 讀 `json/`（等效，避免 `/tmp` 依賴）

另新增 `repeat/`（重現性探測）、`supplemental/`（維度字典查證）、`compare-versions.py` —— 這些**不屬於原腳本**，是為分析而加的，已在報告中標示。
