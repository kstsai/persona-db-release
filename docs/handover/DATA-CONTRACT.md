# DATA CONTRACT — Persona DB 資料與 API 契約

> **權威來源**：`tw-persona-db-rfc.md`（規格）＋ `concepts/`（設計知識）＋ `sources/*/README.md`（資料來源）。
> 本檔是**操作摘要**：動手前先讀這裡，細節回查上述三處。

---

## 1. 人設資料集（dataset）

| 項目 | 值 |
|:--|:--|
| 檔案 | `tw_persona_1069.json`（現行 1069 位；擴充時可換名，但需同步 API 讀取設定） |
| 每人設必要欄位 | `id`（`TW-P-XXXX`）、`name`、`type`、`input_dimensions`、`prompt_prefix`、`reference_pre_prompt` |
| 設計原則 | 姓名／地點／校名皆**虛構**（`note` 欄位須聲明） |
| 雙 prompt | `prompt_prefix`＝沉浸式角色代入（給 LLM 扮演）；`reference_pre_prompt`＝結構化輪廓（供查閱） |

## 2. 維度（現行 22）

| 分層 | 維度 |
|:--|:--|
| **通用底層 1–13** | 年齡／性別／區域／教育／職業／個人收入／政治傾向／媒體習慣／家庭口數／家庭可支配所得／興趣嗜好／婚姻狀況／戶籍地 |
| **派生 14–19** | 物價分級／家戶所得分級／居住支出／居住負擔率／通勤方式／服飾消費 |
| **外部資料新增 20–22** | 醫美療程經歷（ISAPS 2024）／債務背貸狀態（JCIC）／從業身分（DGBAS 報表48） |

**可見性契約**（由 `scripts/check_response_schema.py` 把關）：**計分 18 ⊆ 可篩 20 ⊆ 可見 21**（計分維度必須同時可篩、可篩必須同時可見）
—— 新增維度時必須同步更新這三層清單，否則會出現「prompt 指示使用但被靜默丟棄」的缺陷（歷史事故 #54）。

## 3. 一致性規則（Coherence Rules）

依 RFC §Coherence Rules 實作，例：年齡 ↔ 婚姻 ↔ 家庭口數 ↔ 職業／教育 ↔ 收入的合理組合；
未成年不貼政治標籤；居住支出 **≤ 家庭可支配所得 50%**；居住負擔率由 `housing_cost / family_income` 計算。
驗證工具：`scripts/persona_contradiction_check.py`、`scripts/contradiction_hunt/`、`scripts/persona_review*.py`。

## 4. 權重表（scoring）

| 項目 | 值 |
|:--|:--|
| 檔案 | `dim_weights.json`（由 `scripts/gen_dim_weights.py` 產生） |
| 必要欄位 | `weight_version`（＝版本號）、資料年度、每維度每級距的權重 |
| 計分維度 | 18 個（`gen_dim_weights.py` 內的可計分清單；**新增維度要一起改**，否則 fallback 1.0） |
| 分數語意 | relative-within-version（**跨版本分數不可比**；`score_schema` 有變就要 bump） |

## 5. 資料來源對照（`sources/`）

| 維度 | 來源 | 年度 | 備註 |
|:--|:--|:--|:--|
| 家庭可支配所得／消費／居住／服飾 | 主計總處 **家庭收支調查** | 113 年 | 金額口徑＝**稅後、尚未扣消費支出** |
| 就業／從業身分 | 主計總處 **人力資源調查**（報表48） | 113 年 | 性別 × 年齡 |
| 通勤 | 交通部 | 2024 | |
| 醫美 | ISAPS Global Survey（p24 Chinese Taipei） | 2024 | 甲方提供 |
| 債務 | **JCIC 聯徵中心**個人授信統計 | 各期 | ⚠️ **人數比例可靠、金額不要引用**（歷史教訓） |

> ⚠️ **口徑陷阱**：`個人收入` 與 `家庭可支配所得` 是**兩個不同欄位**，不可互換；
> 金額類外部統計若口徑不同，**寧可不用**，也不要換算後硬套（會產生看似合理但錯的分布）。

## 6. API 契約（v5.18 現行）

| 端點 | 參數 | 回傳重點 |
|:--|:--|:--|
| `GET /personadb/candidates` | `questions`（多題用 `|`）、`top_k`(1–100)、`opMode`(僅篩選/篩選+模擬/模擬詢問)、`role` | `total_matched`／`summary[]`／`persona_ids[]`／`returned`／`pool_exhausted`／`llm_analysis.reasoning`／`protected_dims`（含 `protected_dims_sources` 六鍵）／`warnings`／`broadening_attempts[]`（含 `parse_error`、`overshoot_ratio`）／`stop_reason`／`subject`／`subject_basis`／`llm_calls` |
| `GET /personadb/detail` | `persona_id` | 完整人設（`dimensions`／`prompt_prefix`／`reference_pre_prompt`）；**不呼叫 LLM、毫秒級** |
| `GET /personadb/status` | — | 版本、人設筆數、LLM 可用性 |
| `GET /docs` | — | Swagger UI（**已內建操作重點與 1–5 分鐘提醒**） |

**契約變更規則**：改動 `api/*.py` 的欄位／語意 → **必須** ① bump 版號 ② 更新 `upDockerVerHermes/test-persona-db-api.sh` 斷言
③ 在 `RELEASE-<ver>.md` 的「相容性」段落寫明（純新增欄位 vs 行為變更）。

## 7. 擴充點（要加東西時改哪裡）

| 要加什麼 | 動到的檔案 |
|:--|:--|
| 新維度 | RFC §維度設計＋`sources/`（來源）＋`gen_dim_weights.py`（可計分清單）＋`check_response_schema.py`（可見/可篩）＋`api/models.py`（若有欄位揭露）＋斷言 |
| 新資料集（重建） | `tw_persona_1069.json`＋`dim_weights.json`＋`RELEASE-*.md`（方法與來源） |
| 新 coherence rule | RFC §Coherence Rules＋`scripts/persona_contradiction_check.py`＋驗證報告 |
| 新 API 欄位 | `api/models.py`＋`api/server.py`＋`check_response_schema.py`＋出貨斷言＋`docs/` |
