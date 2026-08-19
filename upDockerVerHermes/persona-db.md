> 產品文件（來源：kstsai/linkEazyCenter wiki `entities/persona-db.md`，更新 2026-08-19）
> 進度看板：GitHub issues（kstsai/persona-db）為 ground truth。


# Persona DB — 台灣人口加權合成人設資料庫

> 1069 筆，19 維度，23 條 QA 規則。DGBAS 主計總處真實資料驅動，全自動生成 + 驗證 + 部署。

> 📊 進度追蹤：見 Persona-DB 進度看板（GitHub issues 對照）。

## 系統概覽

| 項目 | 數值 |
|------|:---:|
| 總筆數 | 1069 |
| 維度 | 19 |
| QA 規則 | 23（ALL PASS） |
| 生成種子 | 42（可重現） |
| 縣市覆蓋 | 22/22 |
| 性別比 | 男 49.7% / 女 50.3% |
| Repos | `kstsai/persona-db`（source）+ `kstsai/persona-db-release`（delivery） |
| API | FastAPI `/personadb/candidates`（LLM 分析→篩選人設） |
| 部署 | lzcdh5 / lzc-dh1（Docker containers） |

## 19 維度

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

## LLM 模型決策

- **analysis model = deepseek-v4-pro**（reasoning，85-90s/題，需 8000 tokens，5/5 合法 JSON，主動補消費維度）
- **flash**（deepseek-v4-flash）也是 reasoning model，加 `thinking={"type":"disabled"}` 才 3s/題但漏消費維度，當備援
- 詳見 LLM Retry 防火牆

## 部署環境

- **lzcdh1**（100.100.112.108）：deploy host，跑 Pre-release SOP
- **lzcdh5**（100.96.79.33）：tailscale 測試 VM

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
- v4.8.x 週報摘要
- v4.8.x session 摘要
- v4.9.1 週報摘要
- v4.9.1 session 摘要
