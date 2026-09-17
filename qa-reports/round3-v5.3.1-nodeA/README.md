# NODE-A persona-db **v5.3.1** API 實測 — 證據包（第三輪，三版對照）

**結論摘要**：9/9 請求 HTTP 200。v5.3.1 是**修正版** —— `dims_counted` 計分宣告不一致由 **33 → 11 → 0**、可重現性變異由 **62× 收斂到 1.3×**、broadening 空轉率 **41% → 10%**。但 `employment_status` **連續三版從未被套用**。
**完整分析**：見 **`ANALYSIS.md`**。

> ⚠️ **目標節點澄清**：任務指定的 `NODE-A-1` **不存在**於 私有網路；既有的 `NODE-A` (`NODE-A`) 已被**就地升級** v4.9.2 → v5.3.1（同 node ID `NODE-A-NODEID`）。因版本精確相符，本次以該節點為目標。詳見 `ANALYSIS.md` §0。

---

## 三輪證據包位置

| 版本 | 節點 | 目錄 |
|------|------|------|
| v4.9.2 | NODE-A (NODE-A) | `../round1-v4.9.2-nodeA/` |
| v5.2 | NODE-B (NODE-B) | `../round2-v5.2-nodeB/` |
| **v5.3.1** | **NODE-A (NODE-A)** | **本目錄** |

三輪的 `run-test.sh` **sha256 完全相同**（`ffc7b106…`），確保測試本身零差異。

---

## 目錄結構

```
round3-v5.3.1-nodeA/
├── ANALYSIS.md                    ← 【主報告】三版對照 + 逐案例 + 9 項發現
├── README.md                      ← 本檔
├── run-test.sh                    ← runner（sha256 與前兩輪相同）
├── compare-three.py               ← 三版自動對照工具（A/B/C）
├── compare-versions.py            ← 兩版對照工具（沿用）
├── run.log                        ← 完整執行 stdout
│
├── raw/                           ← 【原始證據】逐位元組 HTTP response body
│   ├── 00_status.body             ←   /personadb/status（text/plain，792 bytes）
│   ├── 01_kangshimei.body         … 08_boss.body
│   └── openapi.json               ←   9706 bytes（sha256 與 v5.2 完全相同）
├── json/                          ← pretty-print 版
│                                    ⚠️ 00_status.json 為 0 bytes + meta/00_status.jqerr
│                                       屬**預期行為**（status 回傳 text/plain）
├── headers/                       ← 每案例完整 HTTP response headers
├── meta/                          ← 每案例 http_code / 耗時 / bytes / curl 參數
│   ├── instance-provenance.txt    ←   私有 mesh VPN 節點 +「NODE-A-1 不存在」證據
│   ├── original-test-persona-db-api.sh
│   └── script-provenance.txt      ←   三輪 runner sha256 對照
│
├── repeat/                        ← 【關鍵證據】重現性探測（case 01 ×3，全部成功）
│   └── case01_r{1,2,3}.json       ←   matched = 22 / 27 / 29（對照 v5.2 曾為 1 / 1 / 逾時）
│
├── supplemental/                  ← /personadb/detail 樣本（維度字典查證）
│
├── summary-per-case.csv           ← 逐案例彙總（UTF-8 BOM）
├── summary-per-persona.csv        ← 逐 persona 明細（8 案例 = 51 列；案例 06 僅回傳 5）
├── summary-all-cases.json         ← 8 案例完整回應合併
└── version-comparison-3way.csv    ← ★ 三版逐案例對照
```

---

## 複驗步驟

### 1. 確認三輪可比對

```bash
cd /Users/kstsai/Documents/round3-v5.3.1-nodeA
cat meta/script-provenance.txt        # 三輪 runner sha256 應完全相同
cat meta/instance-provenance.txt      # 確認 NODE-A-1 不存在、NODE-A = v5.3.1
```

### 2. 確認 v5.2 與 v5.3.1 的契約完全相同（這是判讀前提）

```bash
sha256sum raw/openapi.json ../round2-v5.2-nodeB/raw/openapi.json
# 兩者應相同 → 契約未變 → 版本差異只能來自行為或 LLM 雜訊
diff <(cat raw/00_status.body) <(cat ../round2-v5.2-nodeB/raw/00_status.body)
# 應只差 Version 與 Python 版號
```

### 3. 複驗核心斷言

```bash
# (a) 契約一致性（8/8 應為 true）
for f in json/0[1-8]*.json; do
  jq -r '([.persona_ids|length] == [(.summary|length)]) and
         (([.persona_ids[]|tostring]) == ([.summary[].id|sub("TW-P-";"")|tonumber|tostring]))' "$f"
done
for f in json/0[1-8]*.json; do
  jq -r '[.summary[].score] as $s | [range(1;$s|length)|$s[.] <= $s[.-1]] | all' "$f"
done

# (b) ★ 案例 06 回傳數 < top_k（新契約風險）
jq -r '"matched=\(.total_matched) returned=\(.persona_ids|length) (top_k requested=10)"' json/06_aesthetic.json
# 應為 matched=5 returned=5

# (c) ★ dims_counted 一致性檢定（v5.3.1 應全部 0，且 5 個案例具檢定效力）
python3 - <<'PY'
import json,glob,os
for f in sorted(glob.glob('json/0[1-8]*.json')):
    d=json.load(open(f,encoding='utf-8')); dm=d['scoring_basis']['dims_counted']
    rows=[(s['score'],'|'.join(str(s.get(k,'n/a')) for k in dm)) for s in d['summary']]
    ties=sum(1 for i in range(len(rows)) for j in range(i+1,len(rows)) if rows[i][0]==rows[j][0])
    bad=sum(1 for i in range(len(rows)) for j in range(i+1,len(rows)) if (rows[i][0]==rows[j][0])!=(rows[i][1]==rows[j][1]))
    print(f"{os.path.basename(f)[:-5]:22s} ties={ties:2d} mismatches={bad:2d}  {'INFORMATIVE' if ties else 'vacuous'}")
PY

# (d) ★ 案例 07：debt_status 是否作為計分訊號（排名應乾淨分層）
jq -r '.summary | to_entries[] | "  rank \(.key+1): \(.value.score)  \(.value.debt_status)"' json/07_debt.json
# rank 1-6 應全為有債務，rank 7-10 應全為「無」，中間有分數斷層

# (e) ★ employment_status 三版皆未套用
for f in json/0[1-8]*.json; do jq -r '.applied_filters.employment_status // empty' $f; done
echo "(無輸出 = 證實未套用)"
for d in ../round1-v4.9.2-nodeA ../round2-v5.2-nodeB .; do
  printf "%-42s " "$(basename $d)"
  n=0; for f in $d/json/0[1-8]*.json; do [ -n "$(jq -r '.applied_filters.employment_status // empty' $f)" ] && n=$((n+1)); done
  echo "applied in $n/8 cases"
done

# (f) ★ 重現性（v5.3.1 應 22-29；對照 v5.2 的 1-62）
python3 - <<'PY'
import json,glob,os
for lab,d in (('v5.3.1','.'),('v5.2','../round2-v5.2-nodeB')):
    ms=[]
    p=os.path.join(d,'json','01_kangshimei.json')
    if os.path.exists(p): ms.append(('suite',json.load(open(p,encoding='utf-8'))))
    for f in sorted(glob.glob(os.path.join(d,'repeat','case01_r*.json'))):
        if os.path.getsize(f)>0: ms.append((os.path.basename(f)[:-5],json.load(open(f,encoding='utf-8'))))
    vals=[v['total_matched'] for _,v in ms]
    print(f"{lab:8s} matched={vals}  range={min(vals)}..{max(vals)}  ({len(vals)} obs)")
PY
cat ../round2-v5.2-nodeB/repeat/r3-timeout.txt   # v5.2 的第 4 次為 300s 逾時

# (g) ★ broadening 空轉率（v5.3.1 應 1/10）
python3 - <<'PY'
import json,glob
t=i=0
for f in sorted(glob.glob('json/0[1-8]*.json')):
    for x in json.load(open(f,encoding='utf-8'))['broadening_attempts']:
        t+=1; i+= x['match_count_before']==x['match_count_after']
print(f"空轉 {i}/{t}")
PY

# (h) ★ 三版完整對照（一次跑完）
python3 compare-three.py
```

### 4. 重跑整套（⚠️ 約 21 分鐘，結果**不會**完全相同 — 見 §5.2）

```bash
cd /Users/kstsai/Documents/round3-v5.3.1-nodeA
OUT=/tmp/v531-rerun BASE_URL=http://NODE-A:8000 bash run-test.sh
```

> v5.3.1 的樣本數變異已收斂到 1.3×（v5.2 為 62×），但**最終 top-k persona 集合仍會不同**（6 組配對中 5 組重疊 0/3）。本包仍應保留作 baseline。

---

## 執行環境

| 項目 | 值 |
|------|-----|
| 目標 | `NODE-A` = 私有 mesh VPN `NODE-A`，`NODE-A.[private-net]`（node ID `NODE-A-NODEID`） |
| 連線 | **DERP relay `hkg`**（`CurAddr` 空；v4.9.2 那輪為直連 —— 可能影響延遲比較） |
| 服務 | uvicorn / Persona DB **v5.3.1**，1069 personas（1.72 MB） |
| LLM 後端 | `deepseek-v4-flash` → `https://api.deepseek.com` |
| 其他 | Python 3.11.16；Name diversity 172 (16.1%) max 16×；32 Python files |
| 時間 | 2026-09-12 04:51 – 05:15 UTC（≈24 分鐘） |

### 三版環境對照

| | v4.9.2 | v5.2 | **v5.3.1** |
|---|---|---|---|
| 節點 | NODE-A | NODE-B | **NODE-A**（就地升級） |
| OpenAPI sha256 | `8ac54b95228d85fc` | `8b869ae266992056` | **`8b869ae266992056`**（= v5.2） |
| persona 維度 | 22 | 25 | **25** |
| `summary[]` 欄數 | 14 | 17 | **17** |
| candidates 平均延遲 | 144.1s | 203.5s | **157.5s** |
| 連線方式 | 直連 | 直連 | **DERP relay hkg** |

## 已知偏離原腳本之處

**請求參數、順序、斷言邏輯 100% 不變**（runner sha256 三輪相同）。僅：
1. `BASE_URL` / `OUT` 指向本次目標
2. 新增證據落盤（`raw/` `headers/` `meta/`）
3. Role QA diff check 由 `python3` 讀 `/tmp` 改為 `jq` 讀 `json/`（等效）
4. **新增**（非原腳本，為分析而加，報告中已標示）：`repeat/` 重現性探測、`supplemental/` 維度查證、`compare-*.py`
