# NODE-B persona-db **v5.6** API 實測 — 證據包（第五輪，五版對照）

**結論摘要**：9/9 HTTP 200（零錯誤）。v5.6 **契約型別化**（落實 v5.4 報告的建議）、**延遲全系列最快 98.2s**、**收入桶飽和降至五輪最低 2/8**（非清零）。但 `employment_status` **連續五輪從未被套用**，且重現性探針出現一次 **75.00s 硬切、無 HTTP 回應**的 transient 異常。
**完整分析**：見 **`ANALYSIS.md`**。

---

## 五輪證據包位置

| 版本 | 節點 | 目錄 |
|:---|:---|:---|
| v4.9.2 | NODE-A | `../round1-v4.9.2-nodeA/` |
| v5.2 | NODE-B | `../round2-v5.2-nodeB/` |
| v5.3.1 | NODE-A | `../round3-v5.3.1-nodeA/` |
| v5.4 | NODE-B | `../round4-v5.4-nodeB/` |
| **v5.6** | **NODE-B** | **本目錄** |

五輪 `run-test.sh` **sha256 完全相同**（`ffc7b106…`）。

---

## 目錄結構

```
round5-v5.6-nodeB-frozenrunner/
├── ANALYSIS.md                    ← 【主報告】五版對照 + 逐案例 + 9 項發現
├── README.md                      ← 本檔
├── run-test.sh                    ← runner（五輪同一份 sha256）
├── compare-nway.py                ← N 版自動對照（現為五版 A–E）
├── run.log                        ← 完整執行 stdout
│
├── raw/                           ← 【原始證據】逐位元組 HTTP response body
│   ├── 00_status.body             ←   v5.6, 790 bytes
│   ├── 01_kangshimei.body         … 08_boss.body
│   └── openapi.json               ←   12332 bytes（第四種契約，+2 型別化 schema）
├── json/                          ← pretty-print 版
│                                    ⚠️ 00_status.json 為 0 bytes（text/plain，預期行為）
├── headers/                       ← 每案例完整 HTTP response headers
├── meta/                          ← http_code / 耗時 / bytes / curl 參數
│   ├── instance-provenance.txt    ←   私有 mesh VPN 節點 + node ID + 歷輪對照
│   ├── original-test-persona-db-api.sh
│   └── script-provenance.txt
│
├── repeat/                        ← 【關鍵證據】重現性探針
│   ├── case01_r{1,2,3}.json       ←   第二次嘗試成功（81.7s / 33.7s / 127.1s）
│   └── PROBE_FAILURE_round1.txt   ←   ★ 第一次嘗試 3/3 失敗：75.00s 硬切、http=000
│
├── probe/                         ← 端點異常診斷
│   └── outage_r{1,2}.json         ←   故障窗口後重試成功（45.4s / 95.2s）
│
├── supplemental/                  ← /personadb/detail 樣本（維度字典 8 個）
│
├── summary-per-case.csv           ← 逐案例彙總（UTF-8 BOM）
├── summary-per-persona.csv        ← 逐 persona 明細（8 案例 = 56 列）
└── summary-all-cases.json         ← 8 案例完整回應合併
```

---

## 複驗步驟

### 1. 確認五輪可比對

```bash
cd /Users/kstsai/Documents/round5-v5.6-nodeB-frozenrunner
cat meta/script-provenance.txt      # 五輪 runner sha256 應完全相同
cat meta/instance-provenance.txt    # 確認 node ID 與 v5.2/v5.4 相同（就地升級）
```

### 2. 確認 v5.6 契約是新的（第四種）

```bash
for d in ../round1-v4.9.2-nodeA ../round2-v5.2-nodeB \
         ../round3-v5.3.1-nodeA ../round4-v5.4-nodeB .; do
  printf "%-42s %6d B  %s\n" "$(basename $d)" "$(wc -c < $d/raw/openapi.json)" \
    "$(shasum -a 256 $d/raw/openapi.json | cut -c1-16)"
done
# v5.2 與 v5.3.1 應同 hash；v5.4、v5.6 各自不同 → 共 4 種契約
```

### 3. 複驗核心斷言

```bash
# (a) 契約一致性 + returned 不變式（8/8 應全 true）
for f in json/0[1-8]*.json; do
  jq -r '([.persona_ids[]|tostring]) == ([.summary[].id|sub("TW-P-";"")|tonumber|tostring])
         and ([.summary[].score] as $s | [range(1;$s|length)|$s[.] <= $s[.-1]] | all)
         and (.returned == (.summary|length) and .returned == (.persona_ids|length))' "$f"
done

# (b) ★ 型別化：v5.6 應有 BroadeningAttempt 與 ScoringBasis
jq -r '.components.schemas | keys[]' raw/openapi.json | grep -E "BroadeningAttempt|ScoringBasis"
jq -r '.components.schemas.CandidatesResponse.properties.broadening_attempts.items."$ref"' raw/openapi.json
# 應為 "#/components/schemas/BroadeningAttempt"（v5.4 時是 free-form object）

# (c) ★ overshoot 首次有可判定定義
jq -r '.components.schemas.BroadeningAttempt.properties.overshoot.description' raw/openapi.json

# (d) ★ score_scale 明示不可跨版本比較
jq -r '.components.schemas.ScoringBasis.properties.score_scale.description' raw/openapi.json

# (e) ★ opMode 預設值變更（v5.4 為「兩者皆可」）
jq -r '.paths["/personadb/candidates"].get.parameters[] | select(.name=="opMode") | .schema.default' raw/openapi.json
for d in ../round4-v5.4-nodeB .; do
  printf "  %-42s %s\n" "$(basename $d)" "$(jq -r '.paths["/personadb/candidates"].get.parameters[]|select(.name=="opMode")|.schema.default' $d/raw/openapi.json)"
done

# (f) ★ 探針失敗證據（75s 硬切、無 HTTP 回應）
cat repeat/PROBE_FAILURE_round1.txt
cat probe/outage_r1.json | jq -r '"  重試成功: matched=\(.total_matched) returned=\(.returned)"'

# (g) ★ employment_status 五輪皆未套用
for d in ../round1-v4.9.2-nodeA ../round2-v5.2-nodeB \
         ../round3-v5.3.1-nodeA ../round4-v5.4-nodeB .; do
  printf "%-42s " "$(basename $d)"
  n=0; for f in $d/json/0[1-8]*.json; do
    jq -e 'has("total_matched")' "$f" >/dev/null 2>&1 || continue
    [ -n "$(jq -r '.applied_filters.employment_status // empty' $f)" ] && n=$((n+1))
  done; echo "applied in $n/8"
done

# (h) ★ 收入桶飽和：五輪趨勢 7/8 → 3/8 → 5/8 → 3/7 → 2/8（v5.6 最低，但未清零）
for d in ../round1-v4.9.2-nodeA ../round2-v5.2-nodeB \
         ../round3-v5.3.1-nodeA ../round4-v5.4-nodeB .; do
  printf "%-42s " "$(basename $d)"
  full=0
  for f in $d/json/0[1-8]*.json; do
    jq -e 'has("total_matched")' "$f" >/dev/null 2>&1 || continue
    hi=$(jq '[.summary[]|select(.income==">8萬")]|length' $f); tot=$(jq '.summary|length' $f)
    [ "$hi" = "$tot" ] && full=$((full+1))
  done; echo "完全飽和 $full/8"
done

# (i) ★ no_op 標記準確度（人工判定 vs 機器宣告應相等）
python3 - <<'PY'
import json,glob
for f in sorted(glob.glob('json/0[1-8]*.json')):
    d=json.load(open(f,encoding='utf-8'))
    if 'total_matched' not in d: continue
    ba=d['broadening_attempts']
    if not ba: continue
    inert=sum(1 for x in ba if x['match_count_before']==x['match_count_after'])
    decl=sum(1 for x in ba if x.get('no_op'))
    print(f"{f.split('/')[-1][:-5]:22s} loops={len(ba)} inert={inert} declared={decl} {'OK' if inert==decl else 'MISMATCH'}")
PY

# (j) ★ 重現性（v5.6 應 13..57）
python3 - <<'PY'
import json,glob,os
for lab,d in (('v5.6','.'),('v5.4','../round4-v5.4-nodeB'),('v5.3.1','../round3-v5.3.1-nodeA'),('v5.2','../round2-v5.2-nodeB')):
    ms=[]
    p=os.path.join(d,'json','01_kangshimei.json')
    try:
        r=json.load(open(p,encoding='utf-8'))
        if 'total_matched' in r: ms.append(('suite',r))
    except Exception: pass
    for f in sorted(glob.glob(os.path.join(d,'repeat','case01_r*.json'))):
        if os.path.getsize(f)>0:
            try:
                r=json.load(open(f,encoding='utf-8'))
                if 'total_matched' in r: ms.append((os.path.basename(f)[:-5],r))
            except Exception: pass
    if ms:
        vals=[v['total_matched'] for _,v in ms]
        print(f"{lab:8s} matched={vals} range={min(vals)}..{max(vals)} ({max(vals)/max(min(vals),1):.1f}x)")
PY

# (k) 五版完整對照（一次跑完）
python3 compare-nway.py
```

### 4. 重跑整套（⚠️ 約 13–30 分鐘；結果不會相同，且**可能遇到 75s 硬切**）

```bash
cd /Users/kstsai/Documents/round5-v5.6-nodeB-frozenrunner
OUT=/tmp/v56-rerun BASE_URL=http://NODE-B:8000 bash run-test.sh
```

> v5.6 的 `total_matched` 變異約 4.4×。**建議保留本包作 baseline。**
> 若遇 `http=000` 且耗時恰為 **75.00s** → 那是本輪記錄過的 transient 異常，**等幾分鐘重試**（見 `repeat/PROBE_FAILURE_round1.txt`）。

---

## 執行環境

| 項目 | 值 |
|:---|:---|
| 目標 | `NODE-B` = 私有 mesh VPN `NODE-B`（node ID `NODE-B-NODEID`；節點內部 HostName 為 `NODE-B-host`） |
| 連線 | 直連 `[public-ip]:23251`（非 relay） |
| 服務 | uvicorn / Persona DB **v5.6**，1069 personas（1.72 MB） |
| LLM 後端 | `deepseek-v4-flash` → `https://api.deepseek.com` |
| 其他 | Python 3.11.15；Name diversity 172 (16.1%) max 16×；32 Python files |
| 時間 | 2026-09-13 23:41 – 23:54 UTC（主套件） |

### 五版環境對照

| | v4.9.2 | v5.2 | v5.3.1 | v5.4 | **v5.6** |
|:---|:---|:---|:---|:---|:---|
| 節點 | NODE-A | NODE-B | NODE-A | NODE-B | **NODE-B** |
| 契約 sha256(16) | `8ac54b95…` | `8b869ae2…` | `8b869ae2…` | `30a22878…` | **`aafe647f…`** |
| openapi bytes | 9298 | 9706 | 9706 | 10131 | **12332** |
| top-level keys | 10 | 10 | 10 | 12 | **12** |
| 平均延遲 | 144.1s | 203.5s | 157.5s | 195.7s | **98.2s** |
| HTTP 200 率 | 9/9 | 9/9 | 9/9 | 8/9（1×503） | **9/9** |

## 已知偏離原腳本之處

**請求參數、順序、斷言邏輯 100% 不變**（runner sha256 五輪相同）。僅：
1. `BASE_URL` / `OUT` 指向本次目標
2. 新增證據落盤（`raw/` `headers/` `meta/`）
3. Role QA diff check 由 `python3` 讀 `/tmp` 改為 `jq` 讀 `json/`（等效）
4. **新增**（非原腳本，報告中已標示）：`repeat/` 重現性探針、`probe/` 端點異常診斷、`supplemental/` 維度查證、`compare-nway.py`
