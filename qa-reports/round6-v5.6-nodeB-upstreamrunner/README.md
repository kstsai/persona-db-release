# NODE-B persona-db **v5.6** API 實測 — 第六輪（**upstream runner**）

**結論摘要**：10/10 HTTP 200（零錯誤）。本輪**改用現行上游 runner**（223 行，取代前五輪的凍結版 90 行），
目的為**結案 issue #51**：實測確認 **`employment_status` 運作正常**（業主語意正確套用、顧客語意正確不套用）
—— 前五輪的「0/8 未解問題」是**量測工件**。同時以負向測試驗收第三輪發現的**錯誤回應契約不符已修復**。
**完整分析**：見 **`ANALYSIS.md`**。

> ⚠️ **本輪與前五輪不可直接整體比較**：runner 已更換（`10e888d9…` ≠ `ffc7b106…`）。
> 但案例 1–8 的 **query 與參數完全相同**（已機械比對），故該 8 案例仍可比。

---

## 六輪證據包位置

| # | 版本 | 節點 | runner | 目錄 |
|:-:|:---|:---|:---|:---|
| 1 | v4.9.2 | `NODE-A` | 凍結 `33749d4e`(90行) | `../round1-v4.9.2-nodeA/` |
| 2 | v5.2 | `NODE-B` | 同上 | `../round2-v5.2-nodeB/` |
| 3 | v5.3.1 | `NODE-A` | 同上 | `../round3-v5.3.1-nodeA/` |
| 4 | v5.4 | `NODE-B` | 同上 | `../round4-v5.4-nodeB/` |
| 5 | v5.6 | `NODE-B` | 同上 | `../round5-v5.6-nodeB-frozenrunner/` |
| **6** | **v5.6** | **`NODE-B`** | **upstream `9a29a8ef`(223行)** | **本目錄** |

> 代號對照見 `../README.md`（本 repo 為 public，故以代號標示）。

---

## 目錄結構

```
round6-v5.6-nodeB-upstreamrunner/
├── ANALYSIS.md                       ← 【主報告】
├── README.md                         ← 本檔
├── run-test.sh                       ← 本輪 runner（由 upstream 改寫，請求參數未變）
├── compare-nway.py                   ← N 版對照工具
├── run.log                           ← 完整 stdout（含 11 條斷言輸出）
│
├── raw/                              ← 逐位元組 response body + openapi.json
├── json/                             ← pretty-print 版
├── headers/                          ← 完整 HTTP response headers
├── meta/                             ← http_code / 耗時 / bytes / curl 參數
│   ├── original-upstream-9a29a8ef.sh ← ★ 本輪所用上游原版（證據）
│   ├── script-provenance.txt         ←   upstream sha + runner sha + 改動紀律
│   └── instance-provenance.txt
├── extra/                            ← ★ 斷言輸出（上游斷言的落盤證據）
│   ├── assertions-34-37.txt
│   ├── assertions-47-49.txt
│   ├── assert47-invalid-opmode.json  ←   負向測試的原始回應
│   └── assert50-na.txt               ←   #50 未執行的明確記錄
└── supplemental/                     ← /personadb/detail 樣本（維度字典）
```

---

## 複驗步驟

### 1. 確認儀器與上游

```bash
cd <repo>/qa-reports/round6-v5.6-nodeB-upstreamrunner
cat meta/script-provenance.txt
shasum -a 256 meta/original-upstream-9a29a8ef.sh   # 應為 9a29a8ef…
shasum -a 256 run-test.sh                          # 應為 10e888d9…
```

### 2. ★ 證明請求參數與順序未被改動（Step 1 紀律）

```bash
diff <(grep -o 'data-urlencode "[^"]*"' meta/original-upstream-9a29a8ef.sh) \
     <(grep -o 'data-urlencode "[^"]*"' run-test.sh) && echo "✓ 完全相同且順序一致"
```

### 3. ★ 結案 issue #51 的那兩條斷言

```bash
cat extra/assertions-34-37.txt | head -2
# 應為：
#   #34 業主 query employment_status=['雇主', '自營作業者'] → ✅
#   #34 顧客 query employment_status=None → ✅ 未套用（語意正確）

# 直接看原始證據
jq -r '.applied_filters.employment_status' json/09_owner.json   # ["雇主","自營作業者"]
jq -r '.applied_filters.employment_status // "None(正確未套用)"' json/08_boss.json
```

### 4. ★ 負向測試：錯誤回應契約（第三輪發現的缺陷是否已修）

```bash
cat extra/assert47-invalid-opmode.json | jq .
# 應為 {"status":"error","error":{"code":"INVALID_OPMODE",…}}，且**無** "detail"
jq -r '.body|has("error"), has("detail")' extra/assert47-invalid-opmode.json
# → true / false   （注意：本檔結構為 {"status":400,"body":{...}}，error 在 .body 內）
```

### 5. 其餘斷言

```bash
cat extra/assertions-34-37.txt     # #35/#36/#37/#42/#43/#44
cat extra/assertions-47-49.txt     # #47/#48/#49
cat extra/assert50-na.txt          # #50 = N/A（遠端無 host 權限）
```

### 6. 逐案例完整性

```bash
for f in json/0[1-9]*.json; do
  jq -r '"\(input_filename|split("/")[-1]): matched=\(.total_matched) returned=\(.returned) inv=\(.returned == (.summary|length)) pool=\(.pool_exhausted)"' "$f"
done
# inv 應全部 true（returned == len(summary) 不變式）
```

### 7. 六輪對照

```bash
python3 compare-nway.py ../round1-v4.9.2-nodeA ../round2-v5.2-nodeB \
  ../round3-v5.3.1-nodeA ../round4-v5.4-nodeB \
  ../round5-v5.6-nodeB-frozenrunner .
```

### 8. 重跑（⚠️ 需連得到受測節點，約 15 分鐘；結果不會相同）

```bash
OUT=/tmp/r6 BASE_URL=http://<node>:8000 bash run-test.sh   # 上游原版需 host 權限才能跑 #50
```

---

## 執行環境

| 項目 | 值 |
|:---|:---|
| 目標 | `NODE-B`（代號；實際節點見內部私有 repo）|
| 服務 | uvicorn / Persona DB **v5.6**，1069 personas（1.72 MB）|
| 契約 | `aafe647f46ee8abe`（12332 B）—— **與第五輪完全相同** |
| LLM 後端 | `deepseek-v4-flash` → `https://api.deepseek.com` |
| 時間 | 2026-09-14 01:41 – 01:55 UTC |

## 已知偏離上游腳本之處

見 `ANALYSIS.md` §7。摘要：base URL 參數化、證據落盤、斷言輸出路徑、Role QA 改用 `jq`、
**#50 不執行（N/A）**。**請求參數／順序／斷言邏輯 100% 未變**（§複驗步驟 2 可驗）。

## 誠實聲明

- **本輪是為結案我自己造成的誤報而跑**（issue #51）。前五輪把「測試集覆蓋缺口」寫成
  「產品五輪未解問題」，並在公開 repo 重複五輪 —— 詳見 `../CORRECTIONS.md` 修正③。
- **#50 未執行**，明確標 N/A；**未執行 ≠ 通過**。
- 本輪**未做重現性探針**（目的為驗收斷言）。變異幅度可從 ANALYSIS §3 的
  「同版本 E↔F 對照」觀察（案例 03 差異 5×）。
- 本目錄節點資訊已去識別化（`NODE-B` / `[public-ip]` / `[tailnet]`）；代號對照不在本 repo。
