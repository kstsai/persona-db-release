> 產品文件（來源：kstsai/linkEazyCenter wiki `entities/persona-db.md`，更新 2026-09-16）
> 進度看板：GitHub issues（kstsai/persona-db）為 ground truth。


# Persona DB — 台灣人口加權合成人設資料庫

> 1069 筆，25 個維度 key（filterable 19 / 計分 18），23 條 QA 規則。DGBAS 主計總處真實資料驅動，全自動生成 + 驗證 + 部署。

> 📊 進度追蹤：見 Persona-DB 進度看板（GitHub issues 對照）。

## 系統概覽

| 項目 | 數值 |
|------|:---:|
| 總筆數 | 1069 |
| 維度 | 25 keys（filterable 19 / 計分 18） |
| QA 規則 | 23（ALL PASS） |
| 生成種子 | 42（可重現） |
| 縣市覆蓋 | 22/22 |
| 性別比 | 男 49.7% / 女 50.3% |
| Repos | `kstsai/persona-db`（source）+ `kstsai/persona-db-release`（delivery） |
| API | FastAPI `/personadb/candidates`（LLM 分析→篩選人設） |
| 版本 | **v5.14**（`VERSION` / `RELEASE-VERSION` / `dim_weights._meta.version` 三者一致，由 `check_dim_weights.py` 守門） |
| 部署 | **nodeB**（原 lzc-dh1）= **v5.14**（SOP 已驗；`--restart unless-stopped` 已生效）；**nodeA**（原 lzcdh5）= **v5.13**（升版由 kstsai 執行）（Docker containers；nodeA 另含 hermes 容器） |
| 主體判準（v5.12 #65 / v5.13 #67） | **機械化＋優先序**（只看題目原文）：① 明確業主標記 → `owner`；② 消費端名詞 → `customer`；③ 否則 `""`（不設限）；結果進**禁用集**並對外揭露 `subject`／`subject_basis`；**覆蓋率 2/9 → 7/9** |
| 禁用集 | `FORBIDDEN_BY_SUBJECT = {"customer": {"employment_status"}}` —— **套用前剝除**、抑制兜底表該條目、**不得進保護集**（優先序 **`forbidden > protected`**） |
| 核心維度保護集 | **六來源聯集**（凍結於請求開始，v5.14 起）：domain 關鍵字／分析 `reasoning` 必要性宣告（詞界比對）／分析 `core_dims` 結構化宣告／模型每輪 `protected_dims`（單調累積）／protect-only 語意表；**來源④有上限**（`max(1, min(3, 已套用維度數//2))`，實測值由 `declared_protected_cap` 揭露）；**全部已套用維度受保護 → `protection_saturated`**（停手不稀釋）；**來源⑥ `overshoot_restore`**（v5.14：移除維度致 ≥3× 過衝 → 還原該維度並納入保護集） |
| 放寬語意 | 移除維度＝可被 veto；**移除致 ≥3× 過衝 → 還原**；值集放寬＝合法並留**幅度**痕跡（`widened_deltas`） |
| veto 條件 | **移除維度，或值集不再是原值集超集（縮小／替換）** → 還原該輪；**值集放寬（嚴格超集）＝合法**，僅記入 `widened_dims` 留痕（v5.11.1 回退了「雙向凍結」） |
| 運維 | `LOG_LEVEL`（預設 `INFO`，非法值回退）；容器 `--log-opt max-size=10m --max-file=3`（log rotation）＋ `--restart unless-stopped`（v5.11） |
| per-request token 預算 | analysis 12000（重試 18000）+ 放寬 ≤3×8000 → `TOKEN_BUDGET` **40000** |

## 22 維度

> **維度計數校正（v5.3.1 實測，2026-09-12）**：per-persona dimension keys = **25**（下表 22 個編號維度 + `city_price_tier` / `city_income_tier` 等由 residence 推導的城市屬性）；**filterable**（`persona_matcher.valid_dims`）= **19**；**計分**（`dim_weights.json` = `SCORED_DIMS`）= **18**（`politics` / `media_diet` filterable 但刻意不計分）。

| # | 維度 | 值域 | 資料源 |
|:-:|:----|:-----|:-------|
| 1 | 年齡 | 8 級距 | 內政部戶政司 |
| 2 | 性別 | 男/女 | 內政部 |
| 3 | 區域 | 6 區 | 內政部 |
| 4 | 教育 | 4 級 | DGBAS 人力資源 |
| 5 | 職業 | 12 類 | DGBAS 人力資源 |
| 6 | 個人收入 | 4 級 | DGBAS 薪資中位數 |
| 7 | 政治傾向 | 4 類 | — |
| 8 | 媒體習慣 | 4 類 | — |
| 9 | 家庭口數 | 1-5+ | DGBAS |
| 10 | 家庭可支配所得 | 6-tier | DGBAS 家庭收支 |
| 11 | 興趣嗜好 | 12 類 | — |
| 12 | 婚姻狀況 | 4 類 | — |
| 13 | 戶籍地 | 22 縣市 | 內政部 |
| 14 | 物價分級 | 5 級 | DGBAS 消費支出 |
| 15 | 家戶所得分級 | 5 級 | DGBAS |
| 16 | 居住支出 | 5-tier | DGBAS 家庭收支 |
| 17 | 居住負擔率 | 低/中/高 | 計算值 |
| 18 | 通勤方式 | 5 選項 | 交通部 2024 |
| 19 | 服飾消費 | 5-tier | DGBAS 衣著支出 |
| 20 | 醫美療程經歷 | 無/有 | ISAPS Global Survey 2024（甲方提供） |
| 21 | 債務背貸狀態 | 無/有房貸/有信貸或卡債/多重 | JCIC 聯徵中心（2026-03/04） |
| 22 | 從業身分 | 受僱/雇主/自營作業者/無酬家屬/不適用 | DGBAS 人力資源（表48） |

## 演進歷程（v3.7→v4.4.3 馬拉松）

| 版本 | 變更 | 日期 |
|:----|:-----|:-----|
| v3.8 | family_income 6-tier 重構：百萬→>8萬, 3-7萬→3-5萬+5-7萬 | 07/29 |
| v3.9 | 新增失業選項、修復「老伴走了」重複 | 07/29 |
| v4.0 | housing_cost + housing_burden（dim 16-17） | 07/29 |
| v4.1 | commute_mode（dim 18） | 07/29 |
| v4.2 | clothing_spend（dim 19） | 07/29 |
| v4.3.2 | Filter relaxation（0 交集自動放寬） | 08/05 |
| v4.4 | Relevance scoring（dim_weights + score_persona） | 08/05 |
| v4.4.1 | LLM_ANALYSIS_MODEL=pro（filters 品質提升） | 08/05 |
| v4.4.2 | TARGET_MIN=20 + residence 引導 | 08/05 |
| v4.4.3 | Coherence R-A/R-B/C（單人+無收入矛盾修正） | 08/05 |
| v4.5.3 | （中間版本，詳見 interactive-llm-db-loop） | 08/12 |
| v4.6 | query-score（互動式 query 評分） | 08/12 |
| v4.7 | interactive loop + role 參數 | 08/12 |
| v4.7.1 | 修正 | 08/12 |
| v4.8 | 資料 coherence 大修（10 個系統性 bug #15-23） | 08/13 |
| v4.8.1 | role 分化（房仲/銀行產出不同結果） | 08/13 |
| v4.8.2 | broadening loop max_tokens 修復 | 08/13 |
| v4.9.0 | LLM Retry 防火牆 4 層落地（#24），省 40%+ token | 08/14 |
| v4.9.1 | broadening overshoot fix（#25）+ deploy env 鏈根治（#26） | 08/14 |
| v4.9.2 | coherence 三連修（#27 房貸套小孩 / #28 R-01 缺 fi / #29 未成年高服飾） | 08/19 |
| v4.9.3 | R-03/R-08 ordering 修復（#30：fam1_fi_cap 在規則之前） | 08/27 |
| v5.0 | dimension 20 醫美療程經歷（in-place annotation + L2 filterable）+ #31 regen 確定性修復 | 09/02 |
| v5.1 | dimension 21 債務背貸狀態（JCIC 聯徵資料，A3 混合：房貸 derive + 消費債 annotate + L2 filterable） | 09/03 |
| v5.2 | dimension 22 從業身分（occupation 自營退役 + full regen，issue #32） | 09/09 |
| v5.3 | **bug fix ×6**：#33 filter 值型別 500、#34 `employment_status` 未套用、#35 新維度 rarity 0 靜默不計分、#36 `aesthetic_procedure` 語意誤套、#37 broadening no-op 空轉、#41 **權重表自 v4.3.2 未重建**（latent） | 09/12 |
| v5.3.1 | 交付包納入 `concepts/` 設計知識（14 頁 + README）；`references/` 仍排除（內部 review 紀錄） | 09/12 |
| **v5.4** | #42 稀有維度放寬護欄（rescue-only + 核心性排除 + 強制理由 + `broadening_attempts[].overshoot`）；#43 `returned` / `pool_exhausted`；#44 `scoring_basis.weight_version` / `score_scale` / `score_schema` | 09/12 |
| **v5.5** | #47 **錯誤契約統一**（400/404/422/500/503 全為 `{status:error,error:{code,message,details}}`，不再回 FastAPI `detail` 包裝）；#46 解析失敗記 raw response + 重試帶變化 + `retryable`；#48 `BroadeningAttempt` / `ScoringBasis` 型別化；#49 `opMode` 預設值修正（省略不再 400） | 09/12 |
| **v5.6** | #50 `finish_reason` 從 `call_llm` 傳到消費層（解析失敗 log 可一句話分辨「截斷 vs 格式問題」）；`content` 非空但被截斷在來源即告警 | 09/13 |
| **v5.7** | #53 `summary` 補齊 7 個可篩維度（`sex`/`region`/`education`/`marriage`/`hobby`/`politics`/`media_diet` → `valid_dims ⊆ summary`）；#54 `housing_cost` prompt 指示使用但 `valid_dims` 缺、靜默丟棄修正 | 09/14 |
| **v5.8** | #56 **放寬策略改善**（逐維度約束分析 `dim_constraint_report()` + 核心維度排除 + 連續 2 輪空轉即停 + `broadening_stop_reason`）；#55 失敗 log 帶例外型別；analysis 基礎預算 8000 → **12000**（重試 18000）、`TOKEN_BUDGET` 32000 → 40000 | 09/14 |
| **v5.9** | #57 **核心維度保護機制**（保護集四來源 + 硬性 veto + `protected_dims`/`protected_veto` 揭露）；#58 `matched=0` 不再回 `status='ok'`（→ `too_strict`）；#59 503 分兩型態、`no_op` 與「刻意拒絕」分離 | 09/14–15 |
| **v5.10** | #60 root logger 設定（`LOG_LEVEL`，修「app INFO 在生產被靜默丟棄」）+ log rotation；#61 protect-only 語意表（**第五來源**，`電動車`/`汽車` → `commute_mode`）；#45 `usage_suggestion` 補選擇準則 | 09/15 |
| **v5.11** | #62 **空值清單正規化**（`[]` ＝「未指定」⇒ 丟棄，修「排除全部」的靜默語意反轉）；#63(a) `broadening_attempts[].widened_dims` **值集放寬留痕**；#56 停止原因白名單改由 OpenAPI **動態取得**（出貨腳本曾因硬編白名單誤報）；infra：`persona-db-api` 加 `--restart unless-stopped` | 09/15 |
| **v5.11.1** | **回退**：受保護維度「雙向凍結」→ 回到「移除／縮小才 veto」（值集放寬＝合法但留痕，醫美 `matched` 14→3 的代價）；**回退** #64 的 prompt 改動 → 轉 known-limitation（must-not-use 回歸）。兩項皆由**我方自己的驗收條件**抓回 | 09/15 |
| **v5.12** | **#65 主體判準機械化**（顧客 vs 業主）：`_subject_from_questions()` 只看題目原文判「題目的標的」＋ `FORBIDDEN_BY_SUBJECT` ＋ 優先序 **`forbidden > protected`**；回應新增 **`subject`／`warnings`**；`Subject gate`／`Normalize filters` 留痕；出貨斷言新增 **S/T 不變式**與**同質化矩陣** | 09/15 |
| **v5.14** | **#69** `broadening_attempts[].widened_deltas`（放寬**幅度**：`{dim,before,after,added}`）；**#70 A** **過衝回饋**（移除維度致 **≥3× 過衝** → 還原該輪 + 保護集**來源⑥** `overshoot_restore` + warning）+ **#70 B** 自選維度優先序提示（餵回提示、不進保護集）；**#71 A** `_normalize_filters()` 留痕移入**函式本體**、**#71 B** 回應揭露 `declared_protected_cap` | 09/16 |
| **v5.13** | **#66** 保護集來源④**上限**（`max(1, min(3, 已套用維度數//2))`）＋回應揭露 **`protected_dims_sources`**＋**覆蓋警示**＋新停止原因 **`protection_saturated`**（全部維度受保護 → 不呼叫 LLM、不稀釋）；**#67** 主體判準**優先序擴充**（9 案例可判定率 **2/9 → 7/9**）＋揭露 **`subject_basis`** | 09/16 |
| — | （安全）出貨 tarball 排除清單補 `.env`／`.env.*`／`*.env`；repo `.env` 停止追蹤並刪除；外洩 key 已撤銷（見 出貨產物必掃密鑰） | 09/16 |

## API 品質演進（v4.3.2→v4.4.3）

| 能力 | 說明 |
|:-----|:-----|
| Filter relaxation | 交集為空時自動放寬，避免 total_matched=0 |
| Relevance scoring | log-frequency × 跨維度正規化，依相關性排序 |
| Pro model analysis | LLM_ANALYSIS_MODEL=deepseek-v4-pro，filters 品質大幅提升 |
| TARGET_MIN=20 | 門檻制 relaxation，確保最少候選人數 |
| Domain reinforcement | 消費型 query 自動補 clothing_spend filter |
| Coherence rules | 單人+無收入 → fi 壓低、不養車、不高治裝 |

## v4.8.x 資料驗證閉環（2026-08-13）

首次完整跑 資料驗證閉環，揪出 **10 個系統性 bug**：

| Issue | Bug | fixes |
|:-----|:----|:-----:|
| #16 | family_income 低於個人 income | 118 |
| #17 | 退休/家管 + 職場敘述 | 239 |
| #15 | hh_income_tier 語意誤導（城市≠個人） | 改名 |
| #18 | fam=1 家庭收入高於個人 | 32 |
| #19 | 高學歷+專業+<3萬 | 15 |
| #20 | BG 貸款矛盾 + 住家裡免房租 vs 住房成本 | 40 |
| #21 | 12-18歲 + 汽車 | 14 |
| #22 | 未婚 + 含飴弄孫/小孩費 | 21 |
| #23 | 苗栗縣 region 北部→中部 | 23 |

### 欄位改名（#15 完整修法）

```
hh_income_tier → city_income_tier
price_tier     → city_price_tier
```

語意 self-evident（城市等級），並從 `valid_dims` 移除（residence 可推導，不當可篩維度）。

### role 分化（v4.8.1，issue #13）

`role` 參數原本只做到「有加參數」，沒做到「真有分化」— 房仲/銀行對「房貸優惠」產出相同 filters。修法：`ROLE_GUIDANCE` dict 給具體維度指引，驗證：房仲 age=[25-44] top=小光 vs 銀行 age=[35-54] top=雅芳。

### broadening loop 修復（v4.8.2）

房仲 query 卡在 total=3（broadening 靜默失敗）。根因：pro model 是 reasoning-heavy，`max_tokens=2000` 被 reasoning 吃光 → 空 content。修法：pro 給 8000。驗證：total 3→28。

## v4.9.0 LLM Retry 防火牆（2026-08-14）

RFC（issue #24）從審批走到**實作 + release v4.9.0**，4 層全落地（詳見 LLM Retry 防火牆）：

- **L1 一次到位**：pro 直接 8000、flash 關 thinking + 2000
- **L2 精準 retry**：只在 `finish_reason=length` 截斷才 retry 1 次 +50%，砍掉 doubling
- **L3 免費提取**：content 空先挖 `reasoning_content`（已付費白拿）
- **L4 硬預算+熔斷**：per-request ≤32000 token + circuit breaker（3 連敗 → 60s 冷卻）

**效益：** 正常 query 16K → 8K token（-50%）、嚴格 query 40K → 32K 上限，預期省 40%+。

**D6 regression 教訓：** BROADEN_PROMPT 有效值清單漏 4 維度（region/education/housing_burden/housing_cost），broadening 誤刪 housing_burden — LLM verify 抓到後補齊。證明 資料驗證閉環 的價值。

## v4.9.1 — pre-release SOP 抓到 2 個 hotfix（2026-08-14）

v4.9.0 落地後跑 pre-release SOP，**LLM verify 在 lzcdh5 抓到 2 個問題**，修掉後 release v4.9.1：

1. **#26 deploy env 鏈**（詳見 Deploy Env 鏈）：stale `~/.env` 蓋過 `pocDemo.env` → `LLM_ANALYSIS_MODEL` 空白 → analysis fallback 到 flash（漏消費維度，TESLA 只數 3 維度 vs pro 8-10）。根治：undeploy 清 `~/.env` + deploy script LLM config 只從 pocDemo.env 讀。
2. **#25 broadening overshoot**：broadening 一次移除多維度 → total 暴增（房仲 4→97）。修：每 loop 只動 1 維度（server.py cap + BROADEN_PROMPT 指令），房仲 total 97→39。

另遇 402（DeepSeek api key 餘額不足，甲方測試用 key）→ 儲值重跑全綠。issue sync 完成（persona-db ↔ persona-db-release，#1-26 全關）。

## v4.9.2 — coherence 三連修（#27/#28/#29，2026-08-19）

起因：kstsai 在 role_5xx.json 看到 TW-P-0134 vs TW-P-0158「像同一人設」→ 追出 3 個 coherence bug（設計坑詳見 Coherence Rule 設計）：

1. **#27 「房貸早就還完了」套到小孩/學生/租客**（170 筆）：`HOUSING_BURDEN_LOW` 的房貸片段隱含自有住宅，卻隨機套到所有 burden=低 的人。修：非屋主（0-24 歲/學生/無收入/租屋）改用「住家裡不用付房租」/「房租不貴」。驗證 0-18 歲 46→0、學生 56→0、租客矛盾 13→0。
2. **#28 R-01 未考慮 family_income**：housing_burden 高是**比值**不是「窮」——高所得「高房貸+高消費」是合理組合。修：R-01 只對低所得（<1萬/1-3萬）開火 + 移到 burden 重算後。驗證低所得殘留 0。
3. **#29 未成年高服飾**（22 筆）：19/22 是高所得（佔比合理，kstsai 確認後不修），但 fs=3 漏洞（R-06/R-07 合併補） + 5 筆 >5000 語意瑕疵要修。0-18 歲 clothing cap 1500~3000（>5000 是成人語意）。驗證低所得高服飾 0、0-18 高服飾 0。

**QA**：lzcdh5 fresh deploy — 5 domains 全綠 + Role QA DIFFERENT（1062 vs 382）+ #27/#29 spot-check 0 殘留。release v4.9.2 後不需再進版。

## v4.9.3 — R-03/R-08 ordering bug（issue #30，2026-08-27）

v4.9.2 contradiction-hunt 首跑抓到的 10 筆殘留（R-03×3 + R-08×7）確認是 **ordering bug**（跟 #28/#29 同類）：

- `fam1_fi_cap`（L1109）把 fs=1 的 family_income cap 到「1-3萬」，但排在 R-03（L1060）/R-08（L1073）**之後** → 這些 persona 檢查時 fi 還是 3-5萬（不觸發）、cap 完才落 1-3萬 → 重新落入低所得矛盾
- **修法**：R-03/R-08 純搬移到 `fam1_fi_cap` 之後（與 R-06/R-07 並列），condition 不變、不改機率分布
- **驗證**：R-03 3→0、R-08 7→0；#27/#28/#29 無回歸；QA 23 規則 ALL PASS；lzcdh1 pre-release SOP + LLM verify 全綠 → 定版

**通用教訓（第三次踩同坑）**：任何會改 `family_income` 的步驟（adjust/floor/cap）都必須在依賴其最終值的 coherence rule **之前**。設計坑詳見 Coherence Rule 設計。

## v5.0 — dimension 20 醫美療程經歷 + regen SOP（2026-09-02）

新增 dimension 20「醫美療程經歷」（二元：無/有），用**甲方提供的 ISAPS Global Survey 2024**（p24 Chinese Taipei）資料升級：

- **原始資料**: persona-db repo `isaps-global-survey-2024.pdf`（commit 04e5ee6 起，repo 根目錄）

- **語意**：過去 12 個月有進行至少一次醫美療程（注射或手術型）。台灣年療程 658,320（手術 257,480 / 非手術 400,840）→ 全年齡年盛行率 ~2.8%（procedures ≠ patients，是上界）
- **實作路線 = in-place annotation（非 full regen）**：`_annotate_aesthetic.py` 在 v4.9.3 基礎上加標記（segment quota 制：rate × eligible 取整 + seed 42 確定性），不重抽 — 16/1069「有」（1.50%）；0-18 與無收入硬性排除
- **Segment rates（甲方確認）**：女19-24 2% / 女25-44 6% / 女45-64 3% / 女65+ 0.5% / 男 0.5%
- **API**：L2 filterable — 醫美 query → `applied_filters` 含 `aesthetic_procedure:[有]`，LLM 自發使用（case 6 驗證 top 全「有」、1-5 無回歸）
- **#31 regen 確定性修復**：`pick_hobbies` 排序非確定性 bug → `sorted(chosen)`；驗證時資料被覆寫（`/tmp/gen_fixed.py` 沒帶 PERSONA_OUTPUT），v5.0 base 採納 sorted 版（可被現行 code 重現）。隱藏變更：14 筆科技業次要 hobby 內容改變（occ 調整保留、良性）
- **regen SOP 文件化**：docs/regen-sop.md（dryrun → determinism gate（同 code 兩次跑 0 差異）→ regen → QA）+ qa_validate 支援傳檔
- **小 segment 限制**：女19-24（20 eligible × 2% = 0.4 → quota 0）無法表示 2%

**核心教訓**：新增維度不一定要 full regen — in-place annotation 保住 persona 身份穩定（甲方認識的丹尼爾還是丹尼爾）+ QA 只驗新維度 + 可稽核（v4.9.3 + annotation script v1 + seed X）。兩路線決策框架詳見 In-place Annotation。

## v5.1 — dimension 21 債務背貸狀態 + JCIC 資料教訓（2026-09-03）

新增 dimension 21「債務背貸狀態」（4 tiers：無 / 有房貸 / 有信貸或卡債 / 房貸+消費債多重），用 **JCIC 聯徵中心個人授信統計**（2026-03/04）資料升級：

- **資料源**：信貸借款人 188 萬 by 年齡×性別、房貸 226 萬、房貸×信貸交叉（房貸族 18.7% 也有信貸）
- **原始資料**: persona-db repo `sources/jcic/`（11 CSV + README fid 對應表，commit ce969c1）— 下載頁 https://www.jcic.org.tw/main_ch/download_page.aspx?uid=213&pid=190
- **實作 = A3 混合**：房貸 tier **derive**（BG 短語顯性化，不重抽）+ 消費債 tier **annotate**（JCIC rates，seed 42）→ 無 961 / 有房貸 39 / 有信貸或卡債 60 / 多重 9
- **API**：L2 filterable（債務整合 query → `debt_status:[有房貸, 房貸+消費債]`，LLM 自發使用）
- **JCIC 資料教訓**：檔案實際是 CSV；「人數」by 年齡×性別 可靠可算盛行率（優於 ISAPS 療程數）；人均金額不可靠（大額拉高）；基數=信用系統參與者
- **已知限制**：persona 房貸盛行率 5.8% < JCIC 11.6%（A3 接受，不動既有欄位）

> 📌 **原始參考資料位置（dimension 20/21 共通）**: persona-db repo（private）— ISAPS: `isaps-global-survey-2024.pdf`；JCIC: `sources/jcic/`。wiki 不另存原始檔。


## v5.2 — dimension 22 從業身分 + issue #32（2026-09-09）

kstsai 逐筆審查發現 occupation=自營只有 4/1069（0.37%）→ 查證根因是**職業 vs 從業身分概念錯位**（詳見 職業 vs 從業身分）：

- **修法（X3+Y1+R1）**：新增獨立 employment_status 維度（不改 occupation 比率）+ occupation=自營 退役 + full regen（dim 20/21 annotation 重跑補回）
- **資料源**：DGBAS 113 年報 表48（就業者教育程度與年齡—按從業身分分，性別×5年帶，驗證誤差 <2 千人）→ rates 存 persona-db repo `references/employment-status-dgbas-2024.md`（wiki 不另存）
- **實作**：OCC_PROB 7 cells 移除自營（mass 分製造/服務/其他）+ EMP_STATUS_PROB 原生指派 + 收入連動（無酬家屬=無薪、雇主 >8萬 55%、自營兩極化）
- **結果**：受僱 467 / 自營 53 / 雇主 20 / 無酬 11 / 不適用 518 → 雇主+自營 = **13.2% 就業者**（vs 舊 0.37%，DGBAS ~15%）；occupation=自營 0；QA 23 rules + dim22 專屬規則 ALL PASS
- **API**：L2 filterable — 攤商/老闆 query → `employment_status:[自營作業者, 雇主]`（lzcdh1 case 8，LLM 自發使用）
- **表52 鐵證**：主管/經理人員 83% 是**受僱的專業經理人** — 職業「主管」≠ 老闆（同時錯兩邊的映射陷阱）
- **已知限制**：無酬家屬 2.0% < DGBAS 4%（55-64 女多為家管非就業 — 職業模型限制）

## v5.3 — 六項修復與三個可靠性教訓（2026-09-12）

**背景**：從檢查 lzcdh5 API 狀況（v4.9.2）出發 → 讀 dsh agent 的 lzc-dh1-1（v5.2）跨版本驗證報告 → 開 8 張 issue（5 bug + 3 known-limitation #38-40）→ 修 6 張 → lzcdh5 fresh-install QA 通過。

| # | 症狀 | 修法 |
|:--|:----|:----|
| #33 | LLM 回 `family_size: [3,4]`（int）→ `.strip()` → **500** | `_coerce_filter_value()`：純量 coerce、非純量丟棄 |
| #34 | `employment_status` 8/8 案例未套用 | prompt must-use 指引（**業主本人 vs 顧客**）+ domain_filters 補「業主/自營」+ 測試案例語意校正 |
| #35 | 新維度不在權重表 → rarity **靜默乘 0**（能篩選、不影響排序） | `SCORED_DIMS` 15→18、fallback `0.0`→`1.0`、`dims_counted` 由實際計分集合 `scored_dims()` 產生 |
| #36 | `aesthetic_procedure` 誤套藥妝語境 → matched **62 → 1** | prompt 負面約束 + 移除「美容」對應 + 稀有維度（<5%）放寬提示（只提示不硬刪） |
| #37 | broadening 空轉率 17%→41% | no-op 偵測提前中止 + `no_op`/`filters_changed` 欄位 + 禁止數量預測 |
| #41 | `dim_weights.json` 自 **v4.3.2** 未重建 → v4.4~v5.2 排序用舊分布 | 重跑 + `scripts/check_dim_weights.py` + **`do-release.sh` Step 0e gate** |

**驗證**：程式級 30/30（決定性）· 本機 e2e 6/6 HTTP 200（0 次 500）· **lzcdh5 fresh-install QA 9/9 案例 200、0 traceback、Role QA DIFFERENT、資料 QA 23 rules ✅**

### 三個可複用教訓

1. **LLM JSON 純量型別不可信** —— 同族第三次（#14 / #42 D6 / #33）→ 型別與衍生產物安全
2. **derived artifact 要機械化新鮮度檢查，文件提醒無效** —— 權重表 stale 潛伏 8 個版本，服務零異狀（#41）→ Dim Weights
3. **新維度「可用」≠「用對語境」** —— 稀有維度誤套會讓候選池崩塌；測試案例語意要對準要驗的維度（#34/#36）→ 維度語意適用性

### 行為變更（v5.3 起）

- 權重表由 v4.3.2 分布更新為現行分布（12/15 既有維度值改變，例 `family_size=1` 0.7259→2.0）＋ 新維度正式計分 → **同一 query 的 top-k 與 score 與 v5.2 不同**；longitudinal 比較以 v5.3 為新基準。
- `scoring_basis.dims_counted` 現在列出**所有實際計分維度**（含 `dim_importance`-only）；`broadening_attempts[]` 多 `no_op`/`filters_changed` 欄位。
- **v5.14 起**：移除維度造成 **≥3× 過衝**的輪次會被**還原**（該維度進保護集來源⑥）→ 這類請求 `returned` 可能變少但語意更貼題；未達門檻的正常放寬不受影響（有反向測試）。

### 部署 / 交付現況（2026-09-16）

| 項目 | 狀態 |
|:----|:----|
| lzcdh5（nodeA） | **v5.13**（第九～十三輪驗證在此執行；v5.14 升版由 kstsai 執行） |
| lzc-dh1（nodeB，lzc-dh1-1） | **v5.14**（SOP 已驗；`--restart unless-stopped` 已生效） |
| 交付包 | v5.3.1 起含 `concepts/`（設計知識）；`references/` 仍為內部；**v5.13 起打包排除 `.env` 變體並機械掃描密鑰**（出貨產物必掃密鑰） |
| QA host 慣例 | 由 kstsai 指定進版的那台跑 SOP，**另一台保留 baseline** |

## v5.9 → v5.11.1 — 核心維度保護機制與驗證閉環（2026-09-15）

第九輪驗證把第八輪的離群現象收斂成一條**產品缺陷**：放寬步驟會移除「分析步驟自己說必須用」的維度（5/9 案例），最尖銳的一例是**同一案例相鄰兩輪自我矛盾**（案例 07 債務整合：loop1「`debt_status` 為核心、不可放寬」→ loop2「移除、非核心」，8 → 58 並首度 `overshoot`）。根因是「核心維度保護」**只是 prompt 提示、判定只靠一張關鍵字表**，而 v5.8 剛好把「移除各維度後的倍率」這個數學槓桿交給了模型 → 模型拿它去移除語意核心。

- **v5.9（#57）＝提示升為機制**：保護集**凍結於請求開始**、五來源聯集、任一輪移除或縮小受保護維度即**還原該輪**（純新增值＝合法放寬），並在回應揭露 `protected_dims`/`protected_veto`/`vetoed_dims`。機制頁見 核心維度保護機制
- **#58 / #59**：`matched=0` 不再回 `status='ok'`（→ `too_strict`）；503 分「呼叫失敗／產不出 filter」兩型態，`no_op` 與「刻意拒絕」分離
- **v5.10（#60 / #61 / #45）**：root logger（`LOG_LEVEL`）修「app 的 INFO 在生產被靜默丟棄」；protect-only 語意表補上 `commute_mode`（連續 5 次被放寬的電動車動機維度，只保護、不補 filter）；`usage_suggestion` 補選擇準則
- **實測（同節點同 runner）**：空轉率 60% → 12% → **7%**；總延遲 2072s → 907s → **766s**；不變式 `protected_dims ∩ relaxed_dims = ∅` 全案通過；**部署環境實際觸發 veto**（案例 05 銀行房貸題：模型想移除受保護的 `family_income` → 還原）；代價是部分題目回傳數更少（`matched` 36 → 8，`returned=5` 仍滿足 `top_k`）

**方法論產出**：斷言設計：寫不變式（6 個版本連續 6 次「新增斷言第一次在部署環境執行就抓到自己的瑕疵」）與 log 證據的盲點（`grep` 回 0 不是「沒發生」）。

### 第十輪 → v5.11 / v5.11.1：驗證方指出的三個缺口，與我方驗收抓回的兩項迴歸

第十輪（dsh，v5.10，nodeA）是**系列首次零瑕疵**：**42 ✅ / 0 ⚠️ / 0 ❌ / 0 N/A**，「自述必要卻被放寬」**9/9 為 0**（第九輪 5/9）→ 保護機制在另一台節點被獨立驗證有效（硬 veto 路徑由**定向探針**逼出）。報告同時指出三個新缺口，我方**逐條獨立複驗**（源碼 + 實測 + 自有資料頻率）後開 #62/#63/#64：

- **#62 空值清單**：`applied_filters` 的 `[]` 語意是**排除全部**（實測 `age=[]` → 0 人 vs 未指定 → 129 人），由放寬路徑帶進來（分析路徑會丟棄空清單、放寬路徑不會）→ v5.11 在所有 LLM 產出的 filters 被套用**前**統一正規化（空值清單陷阱）
- **#63(a) 值集放寬不留痕**：`['女'] → ['女','男']` 這類稀釋長期不收錄、不受 veto 管，我方資料中**至少 15 輪**屬此型 → v5.11 記入 `widened_dims`（值集放寬）
- **#63(b) / #64 的修法在驗收中被否決**：受保護維度「雙向凍結」讓醫美題 `matched` **14 → 3**（保護集被模型撐到 5 維時封死放寬空間）；#64 的兩版 prompt 各有一邊不達標（保護集暴增 / must-not-use 回歸）→ **v5.11.1 回退兩者**，`#64` 依 ticket fallback 轉 known-limitation

**這一輪最重要的產出是閉環本身**：第十輪的建議促使我方建立了原本沒有的驗收條件（**保護集不得暴增**、**must-not-use 不得回歸**），而這兩個條件隨後抓到了**我方自己**的兩項迴歸。護欄來源④的單調累積無上限仍是未解觀察（保護集失控）；長驗證工作的執行紀律（不要在同一 turn 串長 wait）見 長 turn idle watchdog。

## v5.12 — 主體判準機械化（語意反轉修復，2026-09-15）

第十一輪的斷言通過率是系列最高（**44 ✅ / 1 ️**），但那**唯一一個 ⚠️ 是質性最嚴重的一類**：`#34` 顧客語意題（「小吃攤老闆的目標客群」）被讀成**業主本人**，回傳 10 筆全是僱主、`>8萬`，**與 B2B 業主題名單重疊 9/10**（其他配對僅 3–5）。這是**整題語意方向反了**，不是數值偏差。

**根因鏈（我方複驗）**：題目 → 分析吐出 `domain = 餐飲／夜市攤商經營` → 命中兜底表 `"攤商" → employment_status`（**比對的是 LLM 自由產生的字串**，程式註解中「案例 08 不會觸發」的假設已失效）→ 同一來源讓該維度進保護集 → **錯誤被鎖死**。重現率 **2/10**，由 domain 措辭控的**雙峰**。

- **v5.12（#65）**：主體判準**機械化** —— 只看題目原文判「題目的標的」（`customer`/`owner`/`""`），結果成為**禁用集**（顧客語意 → 剝除 `employment_status`、抑制兜底表該條目），優先序 **`forbidden > protected`**；回應揭露 `subject`／`warnings`，並留 `Subject gate`／`Normalize filters` 兩行 log
- **驗證**：單元 10 套件全綠（主體判定 11 案例含 3 反例）；真 LLM e2e 同題 **k=6 → 反轉 0/6**（其中一次實際觸發剝除，≈17% 與 2/10 基準一致）、業主題 must-use 不回歸；nodeB SOP 9 案例 0  / 0 traceback、同質化矩陣無 ≥8/10 配對
- **方法論產出**：關鍵字兜底陷阱（護欄不能比對 LLM 自由產生的字串）、主體判準機械化（判「題目的標的」不判「題目提到誰」）、名單同質化（語意反轉的指紋指標：語意不同的兩題回傳幾乎同一批人 ⇒ 有一題被理解錯了，已納入出貨斷言）
- **判讀紀律**：⚠️ 的**數量**不是品質指標 —— 1 個語意反轉 ⚠️ 比 13 個數值 ⚠️ 更重要，要按「錯了會造成什麼後果」排序
- **另開 #66**：保護集來源④（模型每輪宣告）單調累積無上限 → 樣本數崩落且無警示（v5.13 修）

## v5.13 — 護欄的上限與飽和、機械判準優先序（2026-09-16）

第十二輪（dsh，v5.12，nodeA）**53 ✅ / 0 ⚠️ / 0 ❌ / 1 ℹ️**：v5.12 的主體護欄在**不同節點、不同操作者**手上 **4/4 成立**（案例 08 `subject='customer'`、未套 `employment_status`、名單為中低消費力消費者），第十一輪的語意反轉未再現。這一輪的收穫多在**流程面**：報告抓出我方兩條出貨斷言的瑕疵（形式過嚴＋**涵蓋不足**，見 自製斷言瑕疵），而 v5.13 把 #66／#67 補上。

- **#66 護欄上限與揭露（A + C 都做）**：保護集來源④（模型每輪宣告）加上上限 `max(1, min(3, 已套用維度數//2))`；回應揭露 `protected_dims_sources`（**來源拆解**，回答「是哪個來源讓保護集變大」）＋覆蓋警示；全部已套用維度都被保護時發新停止原因 **`protection_saturated`**，**不呼叫 LLM、不稀釋** → 見 護欄的上限與飽和
- **#67 主體判準優先序**：明確業主標記 > 消費端名詞 > 不設限（覆蓋 **2/9 → 7/9**）＋揭露 `subject_basis`；教訓＝機械化時**「優先序」比樣式廣度更關鍵**，同一組樣式換個判斷順序就從救火變制造火警 → 見 機械判準的優先序
- **安全事件（#68 已結案）**：出貨時首次掃出真實外洩 —— `pack-persona-db-release.sh` 打包整個工作樹、排除清單沒有 `.env`，**public repo 歷史中 46 個 tarball 有 45 個含 `.env`**（v1.0 起）。該 key 是**孤兒憑證**（無 agent／節點使用）→ 撤銷即結案（HTTP 401 驗證）；修法與五條鐵則見 出貨產物必掃密鑰
- **判讀紀律（累積）**：⚠️ 的**數量**不是品質指標；斷言輸出必須附**掃描涵蓋數**（否則「通過」可能只是「沒掃到」）；`subject` 這類語意欄位要看**分布**（雙峰 2:2）而非單次；**「未行使」要明說**（第十二輪把「`warnings` 除路徑本輪未觸發」列為限制，而不是當作「已驗證有效」）
- 評語：**「自述與實作一致 ≠ 語意正確」** —— 一致性檢查對「一致地錯」無效，只有案例級 must-not-use 斷言能抓

## v5.14 — 放寬幅度、過衝回饋、可稽核性（2026-09-16）

第十三輪（dsh，v5.13，nodeA）**57 ✅ / 0 ⚠️ / 0  / 1 ℹ️**：v5.13 的兩個新機制被**逼到真實運作**驗證通過 —— `#66 A` 上限在案例 05 **真的裁掉**模型宣告的保護維度（3 → 2）、`#66 C` `protection_saturated` 由定向探針逼出 2 次、`warnings` 首次有內容（6 筆）、`subject` 覆蓋 8/9。**唯一的 ℹ️ 是斷言自己的問題**，不是產品。

- **自製斷言瑕疵第 10 例（斷言範圍與空轉）**：veto 區塊**只掃 4/9 案例** → ① 斷言輸出「本輪未觸發 veto」**與事實相反**（案例 05 確有 veto 與 rollback）② K/L/M 三條 ✅ 是**空轉**（掃描範圍內沒有事件，不具檢定效力）。我方**系統性盤點**（子集範圍還用在 `#53`／`#56`／`#57`／`#58`／`#62`／`#63`／`#65` **共 7 處**）→ 全改掃 9/9 ＋ 輸出印「掃描 N/M」＋ **空轉防護** → 見 斷言的掃描範圍與空轉
- **#70 A 過衝回饋**：移除維度造成 **≥3× 過衝**（時尚題 `matched` 5.8×）→ **還原該輪**＋該維度進保護集（來源⑥）＋warning＋attempt 標記；單元雙向驗證（正向 89×／反向 2.5× 不還原）→ 見 過衝回饋（與 護欄的上限與飽和 互補：一個治「放寬過頭」、一個治「護欄過嚴」）
- **#69 揭露的層次**：放寬的可稽核性從「有沒有放寬」（`widened_dims`）進到「**鬆了多少**」（`widened_deltas` `{dim,before,after,added}`）→ 見 揭露的層次
- **#71 留痕的位置**：外部驗證者**第三次**重複提出同一誤判（`_normalize_filters` 無 log）—— 事實是留痕寫在**呼叫點**。修法＝把留痕**移進函式本體**、呼叫點移除重複訊息、單元測試改為直接呼叫該函式 → 見 留痕的位置決定它會不會被看見
- **誠實界線**：過衝還原在**部署層尚未自然行使**（SOP 0 筆）；以原素材再跑 2 次（`matched` 22／95）**5.8× 未再現** → 不宣稱「已消失」，只說機制就位且欄位可觀測

## LLM 模型決策

- **analysis model = deepseek-v4-pro**（reasoning，85-90s/題，需 8000 tokens，5/5 合法 JSON，主動補消費維度）
- **flash**（deepseek-v4-flash）也是 reasoning model，加 `thinking={"type":"disabled"}` 才 3s/題但漏消費維度，當備援
- 詳見 LLM Retry 防火牆

## API 契約要點（給消費者）

- **錯誤回應**：所有錯誤碼統一 `{"status":"error","error":{"code","message","details"}}`；瞬時失敗（`FILTER_FAILED`）帶 `retryable: true`。**不要解析 FastAPI 的 `detail`**
- **回傳數**：`returned == len(summary) == len(persona_ids)`，**可小於 `top_k`**（`pool_exhausted: true` 表示池子比要求的小；系統拒絕為湊數放寬核心維度）
- **分數**：`score` 僅供**版本內相對排序**（`score_scale: "relative-within-version"`）；`weight_version` 可偵測尺度換版；`score_schema` 為分數定義版號（與資料版號脫鉤）
- **`opMode` 可省略**，預設 `僅篩選`
- **可篩維度可見（v5.7）**：`summary[].sex/region/education/marriage/hobby/politics/media_diet`（`valid_dims ⊆ summary`），消費端可從回應驗證 filter 生效
- **`broadening_stop_reason`（v5.8）**：放寬停止原因（`target_reached` / `no_op_limit` / `loop_limit` / `budget_limit` / `llm_*`）；`loop_limit` + `total_matched < top_k` ⇒ 池子真的小；**`protected_veto`（v5.9）＝放寬被核心維度擋下**，有兩條路徑（硬性 veto／模型自行拒絕），不應視為「放寬失敗」
- **`protected_dims`（v5.9）**：本請求受保護的核心維度（凍結於請求開始）—— 消費者能看穿「為何名單比預期小」；`broadening_attempts[].protected_veto` / `vetoed_dims` 為違規嘗試的稽核紀錄
- **`status`（v5.9）**：有符合樣本 → `ok`；**`total_matched == 0` → `too_strict`**（不再依賴輪數）
- **`llm_analysis.usage_suggestion.mode`（v5.10）**：依題意判斷（決策者立場→模擬詢問／族群態度→問卷答題者／兼具→兩者皆可）；v5.3.1 起曾 8/8 常數
- **`applied_filters`（v5.11）**：實際套用的篩選條件 —— **值清單保證非空**。空清單的語意是「排除全部」（`age=[]` → 0 人 vs 未指定 → 129 人），已在套用前統一正規化為「未指定」而丟棄 → 見 空值清單陷阱
- **`broadening_attempts[].widened_dims`（v5.11）**：該輪**值集被放寬**（嚴格超集）的維度，**稽核用、不併入 `relaxed_dims`**（併入會與不變式 `protected_dims ∩ relaxed_dims = ∅` 衝突）→ 見 值集放寬
- **`broadening_stop_reason`（v5.11 註記）**：enum **以 OpenAPI 為準，消費端不要硬編白名單**（我方出貨腳本曾因硬編白名單在新增值後誤報）
- **`subject`（v5.12）**：主體判定 `customer` / `owner` / `""`（不設限）—— 下游可辨識本次詮釋方向；同一輪新增 **`warnings`**（語意護欄告警，例：禁用維度已依顧客語意剝除）
- **`applied_filters`（v5.12）**：當主體為**顧客**時**保證不含 `employment_status`**（該維度問的是從業身分，屬業主語意）
- **`subject_basis`（v5.13）**：主體判定的**依據**（命中的原文片段）—— 揭露「憑什麼這樣判」，下游可自行覆核
- **`protected_dims_sources`（v5.13）**：`protected_dims` 的**來源拆解**（五來源各貢獻了哪些維度）
- **`protection_saturated`（v5.13）**：`broadening_stop_reason` 新 enum 值 —— 保護集已覆蓋全部已套用維度，系統**停手不稀釋**（不呼叫 LLM）
- **`warnings`（v5.13 追加兩類）**：模型宣告超上限、保護集覆蓋過半已套用維度
- **`broadening_attempts[].widened_deltas`（v5.14）**：值集放寬的**幅度**（`{dim,before,after,added}`；口徑＝嚴格超集，與 `widened_dims` 一致）→ 見 揭露的層次
- **`broadening_attempts[].overshoot_restore`／`restored_dims`（v5.14）**：該輪是否因移除維度造成過衝而被**還原**，以及被還原並納入保護集（來源⑥）的維度 → 見 過衝回饋
- **`declared_protected_cap`（v5.14）**：本請求實際套用的來源④累積上限（讓「半數規則」可在部署層稽核）
- **`protected_dims_sources`（v5.14 擴充）**：來源拆解由五鍵 → **六鍵**（新增 `overshoot_restore`）

## 未解項（追蹤用）

| issue | 類型 | 內容 |
|:---|:---|:---|
| #38 | known-limitation | 端點不可重現（filter 層同版本內即變動，見 抽樣變異 vs 版本效應） |
| #39 | known-limitation | 延遲偏高；四個成分與可解/不可控區分見 LLM pipeline 延遲解剖 |
| #40 | known-limitation | 候選池頭部集中（第 8 輪：跨案例重複 top-3 persona **19%**） |
| #45 | bug（低） | `usage_suggestion` 失去區辨力 → v5.10 補選擇準則後 5 案例出現 2 種值 |
| （新觀察） | 未開票 | TESLA 案例連續三輪放寬 `commute_mode`（語意核心）→ 語意判準與約束數學衝突（見 broadening 約束維度分析） |
| （殘留） | 未開票 | **未被五來源選中的語意核心仍可能被放寬** → 需下一輪證據再開票補表（見 核心維度保護機制） |
| **#64** | **known-limitation**（enhancement） | 部分**顧客語意題**（案例 08 小吃攤）`protected_dims` 為空 → 該類題若需放寬則無維度受保護。**修法已嘗試並回退**（兩版 prompt 各有一邊不達標：一版保護集暴增、一版 must-not-use 回歸），目前**無實際受害案例**（v5.12 後該題已由 `subject` 禁用集守住語意方向） |
| （已結案） | enhancement | **#66** 保護集來源④單調累積無上限 → **v5.13 修畢**（上限＋`protected_dims_sources` 揭露＋覆蓋警示＋`protection_saturated`） |
| （觀察中） | — | **`overshoot_restore` 的自然發生率**：機制在單元層雙向驗證（正向 89×／反向 2.5×），但部署層尚未自然行使（SOP 0 筆）→ 後續輪次統計 |
| （已結案） | security | **#68** 出貨 tarball 含 `.env`（public repo 46 個 tarball 中 45 個含）→ 排除清單修正＋停止追蹤＋刪檔＋重打包驗證；**孤兒憑證已撤銷**（HTTP 401 驗證） |
| （觀察） | 未開票 | **保護集來源④（模型每輪宣告）單調累積無上限／無檢核** → 過度保護時樣本數崩落（醫美 `matched` 14→3）；需跨輪證據（見 保護集失控） |
| （已結案） | infra | `persona-db-api` 容器缺 `--restart`（僅 hermes 容器有）→ v5.11 已加 `--restart unless-stopped`；nodeA 下一輪部署帶上 |

> 已關閉：#1–#37、#41–#44、#46–#71（含 v5.4–v5.14 全部修復）；**open：`#38 #39 #40 #64`**（全為 known-limitation）。

## 部署環境

- **lzc-dh1**（100.100.112.108）：deploy host，跑 Pre-release SOP — **nodeB，目前 v5.14**（2026-09-16 實查，SOP 已驗）
- **lzcdh5**（100.96.79.33）：tailscale 測試 VM — **nodeA，目前 v5.13**（2026-09-16 實查；Docker 部署，另含 hermes 容器；第九～十三輪驗證在此執行）
- QA host 慣例：由 kstsai 指定進版的那台跑完整 SOP，另一台保留 baseline

## QA 系統

23 條規則，全部 deterministic（不依賴 LLM 判斷）。涵蓋：
- 人口分布偏差檢查（年齡/性別/區域 ±0.5% 內）
- 收入 conflight 檢查（高收入個人不可配極低家庭所得）
- 背景故事語意檢查（不得含「或」字、不得已婚+學費敘述等）
- 命名唯一性、縣市覆蓋率

## 關鍵教訓

1. **to-tickets 的 API ticket 要寫 3 層 AC** — models + matcher + LLM prompt，漏一層白做
2. **cap 邏輯先手算再 coding** — housing_cost cap 太緊，全部卡在 <5千
3. **BG 短語與 QA 規則的相容性** — R3 擋「或」字，所有新短語要掃一遍
4. **每次加維度都要測 LLM query** — 確認 LLM 知道怎麼用它來過濾

## 相關頁面

- Persona-DB 部署與交付
- SOP Verification 方法論
- Family Income Tiers — 6-tier 定義
- 維度指派邏輯與資料源
- v4.2 週報摘要
- v3.8 驗證報告
- v4.2 驗證報告
- Relevance Scoring — API 排序演算法
- Dim Weights — 維度權重表
- v4.4 週報摘要
- 馬拉松 worklog
- v3.7→v4.2 session 摘要
- v4.3.2→v4.4.3 session 摘要
- 資料驗證閉環 — 首跑揪出 10 bug
- LLM Retry 防火牆 — issue #24 RFC
- Pre-release SOP — 部署驗證流程
- Deploy Env 鏈 — ~/.env vs pocDemo.env 的坑（issue #26）
- Coherence Rule 設計 — 比值 vs 絕對值 + 規則順序（#28/#29 歸納）
- In-place Annotation — 新增維度兩路線（full regen vs in-place），dim 20 決策教訓（v5.0）
- v4.8.x 週報摘要
- v4.8.x session 摘要
- v4.9.1 週報摘要
- v4.9.1 session 摘要
- v5.0 release 摘要
- v5.1 release 摘要
- 職業 vs 從業身分 — occupation≠employment status（issue #32 根因）
- v5.2 release 摘要
- 型別與衍生產物安全 — LLM JSON 純量型別不可信 + derived artifact 新鮮度（#33/#35/#41）
- 維度語意適用性 — 新維度「可用 ≠ 用對語境」（#34/#36）
- v5.3 release 摘要
- persona-db QA 報告系列 — 跨版本實測報告 + 判讀修正制度（v4.9.2→v5.6 七輪）
- v5.4→v5.6 API 驗證 digest — 驗證與驗證的驗證（三條誤報查明 + 雙向品質迴路）
- 用症狀歸因的陷阱 — 任何「對方有問題」的結論，先證明你的量測看得到那個問題
- 覆蓋缺口 vs 產品缺陷 — 「測試集測不到」≠「產品沒做」（employment_status 0/8）
- 抽樣變異 vs 版本效應 — 同版本同 query 變異 5×，N=1 跨版比較無統計意義
- 第八輪 + v5.8 摘要 — 空轉率 60%→12%、延遲 34.5 分→15.1 分
- broadening 約束維度分析 — 不告訴模型誰是真正的限制，等於讓它瞎猜（空轉 60%）
- LLM pipeline 延遲解剖 — 把「慢」拆成四個成分的可複用取證流程
- 預算算術的隱性耦合 — 改單次預算 → 所有加總上限跟著變（靜默降輪次）
- 核心維度保護機制 — 提示不是保護：五來源保護集 + 硬性 veto + 可稽核欄位
- 斷言設計：寫不變式 — 寫狀態不變式不寫預期序列；斷言自給自足
- log 證據的盲點 — 用 log 當證據前先驗證該訊息真的會輸出
- 第九輪 + v5.9/v5.10 摘要 — 空轉率 7%、延遲 766s、生產環境實際觸發 veto
- 空值清單陷阱 — `[]` ＝排除全部；同一份資料的多條路徑正規化必須共用
- 值集放寬 — 變更有可見的（移除）與不可見的（值域調整）；對稀釋的處置是揭露而非禁止
- 保護集失控 — 護欄來源自己會長大（單調累積 + prompt 敏感）；改 prompt 就是改護欄
- 長 turn idle watchdog — harness 的「活著」＝有新的 turn 週期，不是有程序在跑
- 第十輪 + v5.11/v5.11.1 摘要 — 首次 42/42 全清；三個缺口 → 兩修一回退
- 主體判準機械化 — 判題目的標的、不判題目提到誰；`forbidden > protected`
- 關鍵字兜底陷阱 — 確定性關鍵字表比對 LLM 產生的字串＝有效性取決於沒人保證的措辭假設
- 名單同質化 — 語意不同的兩題回傳同一批人＝有一題被理解錯（已納入出貨斷言）
- 第十一輪 + v5.12 摘要 — 44✅/1⚠️，唯一 ️ 是語意反轉；v5.12 機械化主體判準
- 護欄的上限與飽和 — 只會變嚴的護欄最後只能回答「無」；上限＋來源揭露＋飽和即停
- 機械判準的優先序 — 「寧可漏擋，不要誤擋」；優先序比樣式廣度更關鍵
- 自製斷言瑕疵 — 九個實例五種形態；斷言要附掃描涵蓋數
- 出貨產物必掃密鑰 — 自動打包不會判斷什麼不該出去；撤銷優先於輪替
- 第十二輪 + v5.13 摘要 — 53✅/0⚠️；主體護欄 4/4、護欄上限、產物掃密鑰
- 斷言的掃描範圍與空轉 — 「通過」與「沒看」必須可區分；無事件時要明示不具檢定效力
- 過衝回饋 — 「多而失焦」不如「少而正確」：移除維度致 ≥3× 過衝即還原
- 揭露的層次 — 可稽核性不是「有沒有一個欄位」，而是它能回答到第幾層問題
- 留痕的位置決定它會不會被看見 — 函式本體 > 呼叫點；重複出現的誤判是設計訊號
- 第十三輪 + v5.14 摘要 — 57✅/1ℹ️；機制被逼到真實運作、斷言範圍系統性修正
