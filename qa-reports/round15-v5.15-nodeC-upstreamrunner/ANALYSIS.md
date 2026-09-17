# Persona DB API 實測分析報告 — v5.15（NODE-C）

> 單版本 API 驗證與回應分析（依 `api-version-sweep` skill v2.8.0）。**本輪不做跨版本比對**。
> 受測節點：**NODE-C**（tailscale `[ts-peer-ip]`，[account]@linux）。執行位置：BANGOO 的 WSL2（遠端）。

---

## 0. 目標與環境

| 項目 | 值 |
|:--|:--|
| 節點 | NODE-C（tailscale `[ts-peer-ip]`，linux；`ubuntu` 帳號，密碼登入） |
| 連線 | tailscale **relay hkg**（非直連）；BANGOO→NODE-C 延遲 ~0.8–3.3s |
| 服務版本 | **v5.15**（`/personadb/status` 自報；1069 personas；LLM deepseek-v4-flash responsive） |
| 執行位置 | BANGOO WSL2 Ubuntu（`BASE_URL=http://[ts-peer-ip]:8000`，遠端） |
| 收集時間(UTC) | 主套件 2026-09-17 **03:27:07Z → 03:52Z**（約 24 分）；探針 03:53:38Z → 04:18:42Z |

**部署保真度（byte 級證明 ✅）**：以 `ssh ubuntu@[ts-peer-ip]`（密碼登入）取得節點存取後驗證：
- 容器 `persona-db-api`（`Up (healthy)`，RestartCount=0，StartedAt 2026-09-17T02:15:42Z ← 早於主套件）mount `/srv/persona-db-data → /app`（bind）。
- 容器 `/app/api/*.py` sha256 **== v5.15 tarball 內 `api/*.py`**（`server.py` = `1ab44330…` 逐檔相同）。
- → **執行中的服務程式碼 == 發佈的 v5.15 產物（byte 級）**。明細見 `extra/deployment-fidelity.txt`。

> **⚠️ 初稿更正**：本報告初稿寫「NODE-C 無 SSH → 部署保真度無法驗證」——**該敘述有誤**。
> 完整 FP 事例（根因、更正、可複用教訓）見 **[FALSE-POSITIVE-NODE-C-ssh.md](FALSE-POSITIVE-NODE-C-ssh.md)**。
> 實情是：a7 起初僅用 Windows 側的 OpenSSH key 試過一次（`Permission denied`），未測 WSL、也未用正確帳號。
> 改用 `ubuntu/ubuntu` 密碼登入後即可存取，部署保真度與 docker 主機層斷言**皆可驗證**。

**⚠️ 打包缺陷（repo 側，非節點）**：v5.15 tarball **內含**的 `RELEASE-VERSION` = **v5.14**（未 bump），
但 tarball 內 `VERSION` = v5.15（server.py 讀 `VERSION` → status 報 v5.15 正確）。
節點上的工作目錄 `RELEASE-VERSION` 則是 v5.15。→ tarball 在 bump 前就打包了。上游 #50 斷言若比對
tarball 內的 `RELEASE-VERSION` 會誤報「stale 映像」。

---

## 1. 儀器

| 項目 | 值 |
|:--|:--|
| upstream sha256 | `e3d83cd2fe394135a099e30620bb2a8f9f7eea49e3f1b19c4760fe0dd43242df`（609 行） |
| runner sha256（執行前即記錄） | **執行時** `9cf5e88bfd8cd5401c88d096991b02b4c279c1a6365b2bc152addb3e3112439f`／561 行；**發布版** `29bc1bfe347dd1a7b1d9e27b9c48f8cee50cb85c12e92b8ecb181e400d302d9b`／563 行 |
| 忠實度 | `data-urlencode` 請求參數與上游 **diff 一致**（機械證明，非肉眼） |
| 契約 | openapi.json sha256 `7546f1e4…`（CandidatesResponse 20 欄、BroadeningAttempt 15 欄、stop_reason enum 11 值） |

**對上游的改動**（全部為「可改」類別；請求參數／順序／斷言邏輯未動，見 §7）：
BASE_URL 指向節點、OUT 自我定位、證據落盤、python 斷言塊 4 處硬編 localhost→`os.environ`、
移除 jq 自動安裝塊、新增 v5.15 #72 斷言、docker 主機層斷言標 N/A。

**執行時行為驗證**：harness 單元測試（stub 網路）驗證 case_run 證據落盤與參數傳遞正確
（`meta/harness-out/`、`meta/harness-wsl/`）。UTF-8 編碼已確認（`url_effective` 顯示 `%E5%BA%B7…`）。

---

## 2. 執行摘要

主套件 **10/10 HTTP 200**（00_status + 01–09）。逐案例：

| case | matched | ret | sum | pe | loops | noop | ovs | stop_reason | protected_dims | 耗時(s) |
|:--|--:|--:|--:|:--|--:|--:|--:|:--|:--|--:|
| 01 康是美 | 47 | 3 | 3 | F | 0 | 0 | 0 | target_reached | clothing_spend | 114 |
| 02 TESLA | 27 | 3 | 3 | F | 2 | 0 | 0 | target_reached | commute_mode,family_income,income | 182 |
| 03 時尚 | 25 | 10 | 10 | F | 1 | 0 | 0 | target_reached | clothing_spend | 159 |
| 04 房仲 | 33 | 5 | 5 | F | 2 | 0 | 0 | target_reached | family_income,housing_burden | 189 |
| 05 銀行 | 8 | 5 | 5 | F | 3 | 1 | 0 | **protected_veto** | debt_status,family_income,housing_burden | 318 |
| 06 醫美 | 16 | 10 | 10 | F | 0 | 0 | 0 | **protection_saturated** | aesthetic_procedure | 86 |
| 07 債務 | 30 | 10 | 10 | F | 3 | 0 | 0 | target_reached | debt_status | 291 |
| 08 小吃攤 | 64 | 10 | 10 | F | 0 | 0 | 0 | target_reached | （無） | 73 |
| 09 業主 | 61 | 10 | 10 | F | 0 | 0 | 0 | target_reached | employment_status | 48 |

- 本輪出現的停止原因：`target_reached`（7）、`protected_veto`（1，案例 05）、`protection_saturated`（1，案例 06）。
- **案例 06 直接觸發 `protection_saturated`（#66 C 分支）**、**案例 05 直接觸發硬 `protected_veto`（#57）** —— 兩個「必然觸發」分支都在主套件內被行使，無需定向探針補。
- 全輪 **0 次 overshoot**、**0 次 `overshoot_restore`**（#70 A 分支本輪未行使 → 空轉，見 §4.4）。

---

## 3. 斷言結果

**59 ✅ / 0 ❌ / 0 ⚠️ / 1 ℹ️**（`extra/assertions.txt` + 補跑的 docker 主機層斷言）。延伸自證檢查
（`verify-extended.py`，A–AF）**210 ✅ / 0 ❌**。

> 初稿把 #50/#55/#60 標為 N/A（誤以為無節點存取）。取得 `ubuntu` SSH 存取後**補跑**：
> - **#50 部署版本一致性 → ✅**：`docker exec cat /app/VERSION` = v5.15 == 節點 `RELEASE-VERSION`；
>   `finish_reason={fr}` 診斷碼存在。
> - **#55 例外型別診斷碼 → ✅**：`LLM call failed [` 存在於映像內 `llm.py`。
> - **#60 root logger → ✅（實質）**：log 檔內 `Protected dims` × 15、`Broadening loop` × 51。
>   （`docker logs` CLI 只吐 90/3077 行 → false 0，見 §4.6。）

重點斷言：
- **#34** 業主 query 套 `employment_status=['雇主','自營作業者']` ✅；顧客 query 未套 ✅
- **#36** 藥妝零售未套 `aesthetic_procedure` ✅；醫美套 `['有']` ✅
- **#42** 債務 `debt_status` 保留、符合率 10/10 ✅
- **#47** 400 錯誤形狀正確（`INVALID_OPMODE`、無 `detail`）✅
- **#57** 保護維度未被放寬 ✅；veto 事件 1 筆，K/L/M 不變式 ✅
- **#61** TESLA `commute_mode` 受保護未放寬 ✅
- **#65** subject 7/9 非空；顧客/業主語意護欄正確 ✅
- **#72** `llm_calls` 全部揭露且 ≥ 1+attempts（掃描 9/9）✅
- **#69** `widened_deltas` 口徑一致（5 筆）✅

---

## 4. API response 分析

### 4.1 語意正確性 —— 逐案例 filter vs 題意

全部 9 案例的 `applied_filters` 與題意對應正確，`reasoning` 與實際 filter 一致：

| case | 題意 | 該套的維度 | 不該套的 | 判定 |
|:--|:--|:--|:--|:--|
| 01 康是美 | 藥妝零售顧客 | 消費/居住維度 | `aesthetic_procedure`、`employment_status` | ✅ 未誤套 |
| 02 TESLA | 電動車高消費 | income/commute | — | ✅ |
| 03 時尚 | 服飾消費 | clothing_spend/hobby | — | ✅ |
| 04 房仲 | 房貸（買方） | housing_burden/family_income | — | ✅ |
| 05 銀行 | 房貸（轉貸戶） | `debt_status` | — | ✅ |
| 06 醫美 | 醫美顧客 | `aesthetic_procedure` | `employment_status` | ✅ 正確套用 |
| 07 債務 | 債務整合 | `debt_status` | — | ✅ |
| 08 小吃攤 | 顧客語意 | 消費/生活型態 | `employment_status` | ✅ 未誤套 |
| 09 業主 | 業主本人 | `employment_status` | — | ✅ 正確套用 |

> 案例 01 reasoning 明示「不使用 employment_status 與 aesthetic_procedure」；案例 06 reasoning 明示
> 「主體是顧客非業主本人，因此不使用 employment_status」—— 自述意圖與實作一致。

### 4.2 自證性 —— 用回傳列驗證 applied_filters

**全部 applied_filters 都在回傳列中被滿足**（analyze.py §6.2 逐維度 ✓）。**無可驗證性缺口**：
summary 曝露全部 24 欄，`applied_filters`/`dims_counted` 的維度皆可從回應驗證。

### 4.3 計分宣告誠實性

具檢定效力的配對 **10** 對：(a) 同分不同向量（碰撞）**3** 對（全在案例 09，合法）；(b) 同向量不同分（低報）**0** 對。
→ **無低報**。案例 01–06 無同分/同向量對 → 空轉（不具檢定效力），已如實標示。

### 4.4 Broadening 行為

- **案例 05（銀行）**：3 輪，loop3 為**硬 `protected_veto`**（嘗試移除 `family_income` → 被拒，rollback 8→8，
  `no_op=True`、`filters_changed=False`）。這是本輪唯一 veto 事件，K/L/M 不變式全過。
- **案例 07（債務）**：3 輪全為值集放寬（`age`、`income`、`family_income`），9→30（3.3×），無 overshoot。
- **案例 02/03/04**：各 1–2 輪移除非核心維度（occupation/age、income、housing_cost/family_size），皆達 target。
- **全輪 0 次 overshoot、0 次 `overshoot_restore`** → #70 A 分支**空轉**（本輪無事件；機制由單元測試雙向驗證，
  自然發生率觀察中）。無 no_op 空轉（案例 05 的 no_op 是 veto 的 rollback，非空轉）。

### 4.5 頭部集中

56 個回傳 persona 中 **7 個跨題重複**。`TW-P-0234`、`TW-P-0473`、`TW-P-0331` 各出現 3 次。
案例 05（銀行）與 07（債務）重疊最多（0234/0473/0331/0388/0811）—— 兩者同為房貸/債務語意，重疊**語意上合理**。
`TW-P-0234` 另跨 02（TESLA）—— 高收入+有房貸，跨「高消費」與「房貸」題，屬合理輪廓。

### 4.6 其他觀察

- **#72 新欄位**：`llm_calls` 全部揭露（1–4 次），且 ≥ 1+attempts；`broadening_attempts` 每筆含
  `parse_error`/`error_type`（本輪全為 `false`/`""`，無失敗輪）。✅
- **#66 A 保護集上限**：`declared_protected_cap` 全部揭露，`len(model_declared) ≤ cap` ✅。
- **#60 `docker logs` 讀取異常（工具工件，非 app 缺陷）**：`docker logs persona-db-api | grep -c "Protected dims"`
  = **0**，看似 #60 失敗。但**實為量測工具失效**：
  - `docker logs` 穩定只輸出 **90 行**（run1/run2/`--tail all` 皆 90）；容器 log 檔（json-file）實際 **3077 行**、最後時間戳 05:18:50Z。
  - raw log 檔內：`Protected dims` × **15**、`Broadening loop` × **51**、`candidates` × **20**（含主套件 03:27–03:52Z 的請求）。
  - 根因：log 檔在 offset **11586 有一塊 NUL(0x00) 位元組區塊**（容器 09-17T02:15Z 重啟造成的 sparse hole），
    docker 的 json-file reader 讀到 NUL 即停 → `docker logs` 只吐 NUL 之前的 90 行。
  - → **#60 實質通過**（root logger 修正生效，app INFO 行確實進 log）；上游 #60 斷言用 `docker logs`
    取樣，在此節點會因 log 檔的 NUL hole 而**誤報 0**。此為 §6.7 歸因紀律的實例：先確認量測看得到標的，再下結論。
- **tarball `RELEASE-VERSION` 未 bump**（tarball 內 v5.14，節點工作目錄 v5.15）→ 打包缺陷（見 §0）。

### 4.7 探針結果（§6.8 重現性 + §6.9 定向）

**§6.8 重現性（LLM 非確定性）**：

| 探針 | r1 | r2 | r3 | 觀察 |
|:--|--:|--:|--:|:--|
| r08 小吃攤 matched | 126 | 172 | 74 | 2.3× 變異；`subject=customer`、`employment_status` 未套 **3/3 一致** |
| r06 醫美 matched | 16 | 14 | 12 | 1.3× 變異；`aesthetic_procedure=['有']` **3/3 一致**；但 r3 保護集多出 `sex`、stop 變 `protected_veto`（r1/r2 為 `loop_limit`） |

> 主體護欄（#65）與核心維度（aesthetic_procedure）在重現性探針下**穩定**；但 `total_matched` 與
> 保護集組成隨 LLM 抽樣變異（r06 r3 保護集含 `sex`）。這印證 §6.8 的「LLM-backed 不可重現」—— 單次
> 數值不可歸因，機制性結論（護欄/核心維度）才可靠。

**§6.9 定向探針**（題目原文見 `README.md`；皆為刻意設計，非業務案例、非缺陷主張）：

| 探針 | 目標分支 | 結果 |
|:--|:--|:--|
| t1 不可滿足查詢 | `pool_exhausted`（#66 哨兵） | ✅ `pe=True`（matched=5 < top_k=10）。**但 matched≠0**：本輪 LLM 未對「遊艇/私人飛機」過度設限（round14 同題 matched=0）→ 分支仍被行使，但「不可滿足」的強度依抽樣 |
| t2 時尚（case03 原參數） | `overshoot_restore`（#70 A） | ❌ **未達標**：matched=245 但無 broadening（初始即 ≥20 → 直接 target_reached）→ 分支未行使 |
| t3 收窄醫美 | `protection_saturated`（#66 C） | ✅ **觸發**：matched=1、`applied ⊆ protected`、stop=`protection_saturated` |
| t4 TESLA top_k=20 | #61 `commute_mode` 保護 | ✅ `commute_mode` 在 protected、不在 relaxed |

> **#70 A `overshoot_restore` 本輪仍空轉**（主套件 0 事件 + t2 未達標）。機制由單元測試雙向驗證
> （正向 89×／反向 2.5×），自然發生率觀察中。t2 用 case03 原參數，但本輪該題初始即達標，未進入放寬迴圈。

---

## 5. 驗證限制 / 未涵蓋範圍

- ~~部署保真度無法驗證~~ → **已驗證 ✅**（取得 `ubuntu` SSH 存取後，容器 `api/*.py` == v5.15 tarball，byte 級；見 §0）。
- ~~docker 主機層斷言 N/A~~ → **已補跑 ✅**（#50/#55/#60；見 §3）。
- **`docker logs` CLI 輸出被截斷（工具工件）**：容器 log 檔的 NUL hole 使 `docker logs` 只吐 90/3077 行 →
  凡依賴 `docker logs` 取樣的檢查（含上游 #60）在此節點不可靠，須直接讀 log 檔（需 sudo）。見 §4.6。
- **連線走 relay**：延遲較高（~0.8–3.3s），但以 LLM 呼叫為主（48–318s/案例），網路延遲影響可忽略。
- **單次執行**：LLM-backed 非確定性 → 重現性探針見 §4.7。
- **#70 A `overshoot_restore` 本輪未行使**：主套件無 overshoot 事件 + t2 探針未達標 → 該分支空轉（見 §4.4/§4.7）。

---

## 6. 結論

**正面（證據級）**：
- **部署保真度已驗證**：容器 `api/*.py` sha256 == v5.15 tarball（byte 級）→ 受測的就是發佈產物（§0）。
- 語意正確性全過：9/9 案例 filter 與題意對應正確，無誤套/漏套（§4.1）。
- 自證性全過：所有 applied_filters 在回傳列被滿足，無可驗證性缺口（§4.2）。
- 計分無低報：10 對具檢定效力，0 低報（§4.3）。
- 保護機制運作：案例 05 硬 `protected_veto`、案例 06 `protection_saturated` 都在主套件內被行使，K/L/M 不變式全過（§4.4/§4.6）。
- #72 新欄位正確：`llm_calls` 揭露且 ≥ 1+attempts，失敗輪欄位齊備（§4.6）。
- docker 主機層斷言補跑全過：#50 部署版本一致、#55 例外型別診斷碼、#60 root logger 生效（§3/§4.6）。
- 定向探針：t3 `protection_saturated`、t4 `commute_mode` 保護皆確認（§4.7）。

**需注意**：
- **tarball 內 `RELEASE-VERSION` 未 bump（v5.14，節點工作目錄為 v5.15）** —— 打包缺陷，會讓上游 #50 斷言誤報 stale 映像。建議修（證據級，repo 側）。
- **`docker logs` 在此節點會截斷**（log 檔 NUL hole）→ 依賴 `docker logs` 取樣的檢查會誤報（例：#60 得 false 0）。建議相關斷言改讀 log 檔，或先處理 NUL hole。

**空轉（不具檢定效力，已如實標示）**：
- #70 A `overshoot_restore` 本輪 0 事件（主套件 + t2 探針皆未行使，§4.4/§4.7）。
- 計分檢定僅 10 對具效力（案例 01–06 空轉，§4.3）。
- t1 `pool_exhausted` 雖觸發（pe=True），但 matched=5≠0 —— 本輪 LLM 未對不可滿足維度過度設限，哨兵強度依抽樣（§4.7）。

---

## 7. 相對於原腳本的改動

見 `meta/script-provenance.txt`。摘要：BASE_URL 指向節點、OUT 自我定位、證據落盤、
python 斷言塊 4 處硬編 localhost→`os.environ`、移除 jq 自動安裝塊、新增 v5.15 #72 斷言、
docker 主機層斷言標 N/A。**請求參數／順序／斷言邏輯未動**（`data-urlencode` diff 一致）。
